import Darwin
import Foundation

/// Failure of a POSIX socket operation.
enum SocketError: Error, Equatable, CustomStringConvertible {
    /// The path does not fit in `sockaddr_un.sun_path`.
    case pathTooLong(String)
    /// `operation` failed with `errno == code`.
    case posix(operation: String, code: Int32)
    /// The peer did not become ready before the deadline.
    case timedOut

    var description: String {
        switch self {
        case .pathTooLong(let path):
            "socket path is too long: \(path)"
        case .posix(let operation, let code):
            "\(operation) failed: \(String(cString: strerror(code)))"
        case .timedOut:
            "timed out"
        }
    }

    fileprivate static func last(_ operation: String) -> SocketError {
        .posix(operation: operation, code: errno)
    }
}

/// Thin throwing wrappers over the Unix-domain stream socket calls shared by the yabai client
/// and the event listener. All descriptors are close-on-exec and never raise `SIGPIPE`.
enum UnixSocket {
    /// Creates a Unix-domain stream socket.
    static func open() throws(SocketError) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .last("socket") }

        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        return descriptor
    }

    static func connect(_ descriptor: Int32, to path: String) throws(SocketError) {
        try withAddress(of: path) { address, length throws(SocketError) in
            while Darwin.connect(descriptor, address, length) != 0 {
                guard errno == EINTR else { throw .last("connect") }
            }
        }
    }

    static func bind(_ descriptor: Int32, to path: String) throws(SocketError) {
        try withAddress(of: path) { address, length throws(SocketError) in
            guard Darwin.bind(descriptor, address, length) == 0 else { throw .last("bind") }
        }
    }

    static func setNonBlocking(_ descriptor: Int32) {
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
    }

    /// PID of the process on the other end of a connected socket.
    static func peerProcess(of descriptor: Int32) throws(SocketError) -> pid_t {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0 else {
            throw .last("getsockopt(LOCAL_PEERPID)")
        }
        return pid
    }

    /// Writes all of `data` to a non-blocking descriptor, waiting for buffer space until `deadline`.
    static func write(_ data: Data, to descriptor: Int32, until deadline: ContinuousClock.Instant) throws(SocketError) {
        var remaining = data[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                remaining = remaining.dropFirst(written)
            } else if errno == EAGAIN {
                try wait(for: POLLOUT, on: descriptor, until: deadline)
            } else if errno != EINTR {
                throw .last("write")
            }
        }
    }

    /// Reads from a non-blocking descriptor until the peer closes it, waiting for data until `deadline`.
    static func readToEnd(of descriptor: Int32, until deadline: ContinuousClock.Instant) throws(SocketError) -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &chunk, chunk.count)
            if count > 0 {
                data.append(contentsOf: chunk[..<count])
            } else if count == 0 {
                return data
            } else if errno == EAGAIN {
                try wait(for: POLLIN, on: descriptor, until: deadline)
            } else if errno != EINTR {
                throw .last("read")
            }
        }
    }

    /// Blocks until `descriptor` is ready for `events`; throws `.timedOut` once `deadline` passes.
    static func wait(for events: Int32, on descriptor: Int32, until deadline: ContinuousClock.Instant) throws(SocketError) {
        while true {
            let remaining = deadline - .now
            guard remaining > .zero else { throw .timedOut }

            let (seconds, attoseconds) = remaining.components
            let milliseconds = seconds * 1_000 + attoseconds / 1_000_000_000_000_000 + 1
            var request = pollfd(fd: descriptor, events: Int16(events), revents: 0)

            let ready = poll(&request, 1, Int32(clamping: milliseconds))
            if ready > 0 { return }
            if ready < 0, errno != EINTR { throw .last("poll") }
        }
    }

    private static func withAddress<Result>(
        of path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws(SocketError) -> Result
    ) throws(SocketError) -> Result {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        // `sun_path` must stay NUL-terminated, so the path may use at most capacity - 1 bytes.
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw .pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        return try withUnsafePointer(to: &address) { pointer throws(SocketError) in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound throws(SocketError) in
                try body(rebound, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
