import Foundation
import Synchronization
@testable import Stackline

/// An in-process stand-in for the yabai daemon that speaks yabai's wire protocol on a Unix socket.
///
/// The framing is implemented here independently of `YabaiClient`, from yabai's source, so the
/// two only agree if the client really speaks yabai's protocol.
final class FakeYabai: Sendable {
    struct Signal: Equatable, Sendable, Encodable {
        var event: String
        var label: String
        var action: String
    }

    let socketPath: String

    private struct State {
        var listener: (any DispatchSourceRead)?
        var signals: [Signal] = []
        var requests: [[String]] = []
        var windows = Data("[]".utf8)
        var focusFailure: String?
        var isHung = false
        var parkedConnections: [Int32] = []
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "FakeYabai")

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit {
        stop()
    }

    // MARK: - Process lifecycle

    /// "Launches" yabai: it starts answering, with no signals registered.
    func start() throws {
        let descriptor = try UnixSocket.open()
        unlink(socketPath)
        try UnixSocket.bind(descriptor, to: socketPath)
        listen(descriptor, SOMAXCONN)
        UnixSocket.setNonBlocking(descriptor)

        let listener = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        listener.setEventHandler { [self] in
            while true {
                let connection = accept(descriptor, nil, nil)
                guard connection >= 0 else { break }
                serve(connection)
            }
        }
        listener.setCancelHandler { close(descriptor) }
        listener.resume()

        state.withLock { $0.listener = listener }
    }

    /// "Kills" yabai: its socket disappears and everything it had in memory is forgotten.
    func stop() {
        unlink(socketPath)
        let parked = state.withLock { state in
            state.listener?.cancel()
            state.listener = nil
            state.signals = []
            state.isHung = false
            defer { state.parkedConnections = [] }
            return state.parkedConnections
        }
        parked.forEach { close($0) }
    }

    /// Makes yabai accept requests without ever answering them.
    func hang() {
        state.withLock { $0.isHung = true }
    }

    // MARK: - Inspection and setup

    var signals: [Signal] {
        state.withLock { $0.signals }
    }

    var labels: Set<String> {
        Set(signals.map(\.label))
    }

    /// Every request received, as the argument list that followed `yabai -m`.
    var requests: [[String]] {
        state.withLock { $0.requests }
    }

    func addSignal(_ signal: Signal) {
        state.withLock { $0.signals.append(signal) }
    }

    func removeSignal(labelled label: String) {
        state.withLock { $0.signals.removeAll { $0.label == label } }
    }

    /// Sets the reply to `query --windows`.
    func setWindows(_ json: String) {
        state.withLock { $0.windows = Data(json.utf8) }
    }

    /// Makes `window --focus` fail with `message`.
    func rejectFocus(with message: String) {
        state.withLock { $0.focusFailure = message }
    }

    // MARK: - Protocol

    private func serve(_ connection: Int32) {
        var enabled: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
        var patience = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &patience, socklen_t(MemoryLayout<timeval>.size))

        guard let arguments = Self.readRequest(from: connection) else {
            close(connection)
            return
        }

        let reply: Data? = state.withLock { state in
            state.requests.append(arguments)
            if state.isHung {
                state.parkedConnections.append(connection)
                return nil
            }
            return Self.reply(to: arguments, state: &state)
        }
        guard let reply else { return }

        reply.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(connection, bytes.baseAddress! + offset, bytes.count - offset)
                guard written > 0 else { break }
                offset += written
            }
        }
        close(connection)
    }

    /// yabai reads an `int` byte count, then that many bytes of NUL-separated arguments.
    private static func readRequest(from connection: Int32) -> [String]? {
        guard let header = readExactly(4, from: connection) else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard length > 0, let payload = readExactly(Int(length), from: connection) else { return nil }
        return payload.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func readExactly(_ count: Int, from connection: Int32) -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { read(connection, $0.baseAddress! + offset, count - offset) }
            guard received > 0 else { return nil }
            offset += received
        }
        return data
    }

    private static func reply(to arguments: [String], state: inout State) -> Data {
        switch (arguments.first, arguments.dropFirst().first) {
        case ("signal", "--list"):
            return try! JSONEncoder().encode(state.signals)

        case ("signal", "--add"):
            var fields: [String: String] = [:]
            for argument in arguments.dropFirst(2) {
                let pair = argument.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return failure("invalid argument '\(argument)'") }
                fields[pair[0]] = pair[1]
            }
            guard let event = fields["event"], let action = fields["action"] else {
                return failure("signal was specified without event or action")
            }
            let label = fields["label"] ?? ""
            if !label.isEmpty {
                state.signals.removeAll { $0.label == label }
            }
            state.signals.append(Signal(event: event, label: label, action: action))
            return Data()

        case ("signal", "--remove"):
            let label = arguments.dropFirst(2).first ?? ""
            guard state.signals.contains(where: { $0.label == label }) else {
                return failure("signal with label '\(label)' not found.")
            }
            state.signals.removeAll { $0.label == label }
            return Data()

        case ("query", "--windows"):
            return state.windows

        case ("window", "--focus"):
            return state.focusFailure.map(failure) ?? Data()

        default:
            return failure("unknown command")
        }
    }

    /// yabai marks failures with a leading BEL byte.
    private static func failure(_ message: String) -> Data {
        Data([0x07]) + Data("\(message)\n".utf8)
    }
}

/// Stands in for "the yabai process exited", which an in-process fake cannot do for real.
final class ProcessExitTrigger: Sendable {
    private let exits = Mutex(0)

    func fire() {
        exits.withLock { $0 += 1 }
    }

    /// Suspends until the next `fire()`, or until the task is cancelled.
    func wait() async {
        let seen = exits.withLock { $0 }
        while !Task.isCancelled, exits.withLock({ $0 }) == seen {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
