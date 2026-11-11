import Darwin
import Foundation
import Synchronization

enum YabaiError: Error, Equatable {
    /// yabai is not running: its socket is missing, refuses connections, or went away mid-request.
    case unavailable
    /// yabai accepted the request but did not answer before the deadline.
    case timedOut
    /// yabai answered with a failure message.
    case rejected(String)
    /// The request could not be delivered for a reason other than yabai being down.
    case transport(String)
}

/// Talks to yabai over its Unix-domain socket — the same wire protocol `yabai -m` uses.
///
/// Compared to spawning `yabai -m` this is an order of magnitude faster, cannot dead-lock on pipe
/// buffers, needs no knowledge of where the yabai binary is installed, and reveals the PID of the
/// yabai process that answered.
///
/// One request maps to one connection. Requests are safe to issue concurrently; yabai serialises
/// them on its event loop.
struct YabaiClient: Sendable {
    struct Response: Sendable, Equatable {
        /// PID of the yabai process that answered.
        let pid: pid_t
        let body: Data
    }

    static let defaultTimeout: Duration = .seconds(2)

    /// yabai derives its socket path from `$USER`.
    static var defaultSocketPath: String {
        let user = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        return "/tmp/yabai_\(user).socket"
    }

    let socketPath: String

    init(socketPath: String = YabaiClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    /// Sends `arguments` — what would follow `yabai -m` on the command line — and returns the reply.
    ///
    /// - Throws: `YabaiError`, or `CancellationError` if the calling task is cancelled; cancellation
    ///   aborts an in-flight request immediately.
    func send(_ arguments: [String], timeout: Duration = defaultTimeout) async throws -> Response {
        try await send(arguments, deadline: .now + timeout)
    }

    func send(_ arguments: [String], deadline: ContinuousClock.Instant) async throws -> Response {
        let exchange = Exchange(socketPath: socketPath, request: Self.encode(arguments), deadline: deadline)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    continuation.resume(with: Result { try exchange.run() })
                }
            }
        } onCancel: {
            exchange.cancel()
        }
    }

    // MARK: - Wire format

    private static let failurePrefix: UInt8 = 0x07

    /// A request is a native-endian `int32` byte count followed by the NUL-terminated arguments
    /// and one extra terminating NUL.
    static func encode(_ arguments: [String]) -> Data {
        var payload = Data()
        for argument in arguments {
            payload.append(contentsOf: argument.utf8)
            payload.append(0)
        }
        payload.append(0)

        var message = withUnsafeBytes(of: Int32(payload.count)) { Data($0) }
        message.append(payload)
        return message
    }

    /// A reply is raw output; failures are prefixed with a BEL byte.
    static func decode(_ reply: Data) throws(YabaiError) -> Data {
        guard reply.first == failurePrefix else { return reply }
        let message = String(decoding: reply.dropFirst(), as: UTF8.self)
        throw .rejected(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Transport

    /// Socket I/O blocks, so it runs here rather than on the cooperative thread pool.
    private static let queue = DispatchQueue(
        label: "sh.mackie.stackline.yabai-client",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// One request/response round trip that can be aborted from another thread.
    private final class Exchange: Sendable {
        private struct State {
            var descriptor: Int32?
            var isCancelled = false
        }

        private let socketPath: String
        private let request: Data
        private let deadline: ContinuousClock.Instant
        private let state = Mutex(State())

        init(socketPath: String, request: Data, deadline: ContinuousClock.Instant) {
            self.socketPath = socketPath
            self.request = request
            self.deadline = deadline
        }

        /// Wakes up a blocked `run()`; it then fails with `CancellationError`.
        func cancel() {
            state.withLock { state in
                state.isCancelled = true
                if let descriptor = state.descriptor {
                    shutdown(descriptor, SHUT_RDWR)
                }
            }
        }

        func run() throws -> Response {
            do {
                let descriptor = try UnixSocket.open()
                // Unpublishing and closing under the lock keeps `cancel()` from ever touching a
                // descriptor number that has been closed and reused.
                defer {
                    state.withLock { state in
                        state.descriptor = nil
                        close(descriptor)
                    }
                }
                let isCancelled = state.withLock { state in
                    state.descriptor = descriptor
                    return state.isCancelled
                }
                guard !isCancelled else { throw CancellationError() }

                try UnixSocket.connect(descriptor, to: socketPath)
                let pid = try UnixSocket.peerProcess(of: descriptor)

                UnixSocket.setNonBlocking(descriptor)
                try UnixSocket.write(request, to: descriptor, until: deadline)
                shutdown(descriptor, SHUT_WR)
                let reply = try UnixSocket.readToEnd(of: descriptor, until: deadline)

                // A cancelled exchange looks like an early end-of-stream; don't mistake it for a reply.
                guard !state.withLock(\.isCancelled) else { throw CancellationError() }
                return Response(pid: pid, body: try YabaiClient.decode(reply))
            } catch let error as SocketError {
                guard !state.withLock(\.isCancelled) else { throw CancellationError() }
                throw Self.translate(error)
            }
        }

        private static func translate(_ error: SocketError) -> YabaiError {
            switch error {
            case .timedOut:
                .timedOut
            case .posix(_, ENOENT), .posix(_, ECONNREFUSED), .posix(_, ECONNRESET), .posix(_, EPIPE), .posix(_, ENOTCONN):
                .unavailable
            case .posix, .pathTooLong:
                .transport(error.description)
            }
        }
    }
}
