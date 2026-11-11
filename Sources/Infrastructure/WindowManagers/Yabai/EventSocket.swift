import Darwin
import Foundation
import Synchronization

/// A Unix-domain socket on which Stackline receives one line of text per connection.
///
/// yabai signal actions write to it (see `YabaiSubscription`). A dead listener makes those
/// writes fail immediately, which is what lets the actions detect that Stackline is gone.
final class EventSocket: Sendable {
    let path: String

    /// The received lines, in arrival order. Finishes when the socket is closed.
    let lines: AsyncStream<String>

    private let source: Mutex<(any DispatchSourceRead)?>

    private static let queue = DispatchQueue(label: "sh.mackie.stackline.event-socket", qos: .userInteractive)

    /// Starts listening at `path`, replacing whatever a previous instance left there.
    ///
    /// The caller must hold the instance lock: an existing socket file is assumed to be stale.
    init(path: String) throws(SocketError) {
        let descriptor = try UnixSocket.open()
        do throws(SocketError) {
            unlink(path)
            try UnixSocket.bind(descriptor, to: path)
            guard chmod(path, 0o600) == 0 else { throw .posix(operation: "chmod", code: errno) }
            guard listen(descriptor, SOMAXCONN) == 0 else { throw .posix(operation: "listen", code: errno) }
            UnixSocket.setNonBlocking(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }

        // Events are only triggers to re-read state, so under pressure the oldest may be dropped.
        let (lines, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(128))

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler {
            while true {
                let connection = accept(descriptor, nil, nil)
                guard connection >= 0 else { break }
                if let line = Self.readLine(from: connection) {
                    continuation.yield(line)
                }
                Darwin.close(connection)
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
            continuation.finish()
        }
        source.resume()

        self.path = path
        self.lines = lines
        self.source = Mutex(source)
    }

    deinit {
        close()
    }

    /// Stops listening and removes the socket file. Safe to call more than once.
    ///
    /// The file is gone by the time this returns; the stream finishes shortly after.
    func close() {
        source.withLock { source in
            guard let listening = source else { return }
            unlink(path)
            listening.cancel()
            source = nil
        }
    }

    /// Reads the first line a client sends. Clients are local and write immediately, so a slow
    /// one is cut off quickly rather than allowed to hold up the events behind it.
    private static func readLine(from connection: Int32) -> String? {
        UnixSocket.setNonBlocking(connection)
        let deadline = ContinuousClock.now + .milliseconds(250)
        let newline = UInt8(ascii: "\n")
        let limit = 256

        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: limit)
        while bytes.count < limit, !bytes.contains(newline) {
            let count = read(connection, &chunk, limit - bytes.count)
            if count > 0 {
                bytes.append(contentsOf: chunk[..<count])
            } else if count == 0 {
                break
            } else if errno == EAGAIN {
                guard (try? UnixSocket.wait(for: POLLIN, on: connection, until: deadline)) != nil else { break }
            } else if errno != EINTR {
                break
            }
        }

        let line = String(decoding: bytes.prefix { $0 != newline }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }
}
