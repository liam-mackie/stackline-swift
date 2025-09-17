import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "simple-socket")

// MARK: - Simple Socket Server (Alternative Implementation)

/// A simpler socket server using FileHandle and Unix domain sockets
/// This is an alternative to the Network.framework implementation
@MainActor
final class SimpleSocketServer: ObservableObject {
    nonisolated static let socketPath = "/tmp/stackline.sock"

    private var socketFileDescriptor: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private let socketPathCopy = "/tmp/stackline.sock" // Local copy for deinit

    @Published var isListening = false
    @Published var lastMessageReceived: String?

    weak var signalHandler: SignalHandler?

    init() {
        logger.debug("SimpleSocketServer initialized")
    }

    func startListening() {
        guard !isListening else { return }

        // Start the socket setup in background to avoid blocking main thread
        Task { [weak self] in
            guard let self = self else { return }

            // Remove existing socket file if it exists
            try? FileManager.default.removeItem(atPath: Self.socketPath)

            // Create Unix domain socket
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                logger.error("Failed to create socket")
                return
            }

            await MainActor.run {
                self.socketFileDescriptor = fd
            }

            // Set socket to non-blocking mode
            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            // Set socket options
            var reuseOn: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseOn, socklen_t(MemoryLayout<Int32>.size))

            // Bind to socket path
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)

            withUnsafeMutablePointer(to: &address.sun_path.0) { ptr in
                _ = strcpy(ptr, Self.socketPath)
            }

            let bindResult = withUnsafePointer(to: &address) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard bindResult >= 0 else {
                logger.error("Failed to bind socket: \(String(cString: strerror(errno)))")
                close(fd)
                await MainActor.run {
                    self.socketFileDescriptor = -1
                }
                return
            }

            // Start listening
            guard listen(fd, 5) >= 0 else {
                logger.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
                close(fd)
                await MainActor.run {
                    self.socketFileDescriptor = -1
                }
                return
            }

            await MainActor.run {
                self.isListening = true
            }

            logger.info("Socket server listening at \(Self.socketPath)")

            // Start accepting connections in background
            await self.acceptConnections()
        }
    }

    func stopListening() {
        isListening = false
        acceptTask?.cancel()
        acceptTask = nil

        if socketFileDescriptor >= 0 {
            close(socketFileDescriptor)
            socketFileDescriptor = -1
        }

        try? FileManager.default.removeItem(atPath: Self.socketPath)
        logger.info("Socket server stopped")
    }

    private func acceptConnections() async {
        while isListening {
            let fd = socketFileDescriptor
            guard fd >= 0 else { break }

            var clientAddress = sockaddr_un()
            var clientAddressLength = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddress) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(fd, sockaddrPtr, &clientAddressLength)
                }
            }

            if clientSocket < 0 {
                // Non-blocking socket, so EAGAIN/EWOULDBLOCK is normal
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    // No connection available, wait a bit
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    continue
                }

                let stillListening = isListening
                if errno != EINTR && stillListening {
                    logger.error("Accept failed: \(String(cString: strerror(errno)))")
                }
                continue
            }

            // Handle client connection
            Task { [weak self] in
                await self?.handleClient(socket: clientSocket)
            }
        }
    }

    private func handleClient(socket: Int32) async {
        defer {
            close(socket)
        }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }

        let bytesRead = read(socket, buffer, bufferSize - 1)

        if bytesRead > 0 {
            buffer[bytesRead] = 0 // Null terminate
            let message = String(cString: buffer)

            logger.debug("Received message: \(message)")

            await MainActor.run { [weak self] in
                self?.lastMessageReceived = message
                self?.processMessage(message)
            }
        }
    }

    private func processMessage(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle different message types
        if trimmedMessage.hasPrefix("signal:") {
            let signal = String(trimmedMessage.dropFirst(7))
            signalHandler?.handleSignal(signal)
        } else if trimmedMessage == "ping" {
            logger.debug("Received ping")
        } else {
            // Treat as a signal for backward compatibility
            signalHandler?.handleSignal(trimmedMessage)
        }
    }

    deinit {
        // Clean up resources directly since we can't call async methods in deinit
        // Note: Can't modify @MainActor properties from deinit
        acceptTask?.cancel()

        if socketFileDescriptor >= 0 {
            close(socketFileDescriptor)
        }

        // Use the local copy of socket path
        try? FileManager.default.removeItem(atPath: socketPathCopy)
        logger.debug("SimpleSocketServer deinitialized")
    }
}

// MARK: - Simple Socket Client

final class SimpleSocketClient {
    nonisolated static let socketPath = "/tmp/stackline.sock"

    static func sendMessage(_ message: String) -> Bool {
        // Create Unix domain socket
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            logger.error("Failed to create client socket")
            return false
        }

        defer {
            close(socketFD)
        }

        // Connect to server
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        withUnsafeMutablePointer(to: &address.sun_path.0) { ptr in
            _ = strcpy(ptr, socketPath)
        }

        let connectResult = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult >= 0 else {
            logger.error("Failed to connect to socket: \(String(cString: strerror(errno)))")
            return false
        }

        // Send message
        guard let data = message.data(using: .utf8) else {
            logger.error("Failed to encode message")
            return false
        }

        let bytesSent = data.withUnsafeBytes { bytes in
            write(socketFD, bytes.baseAddress, data.count)
        }

        if bytesSent < 0 {
            logger.error("Failed to send message: \(String(cString: strerror(errno)))")
            return false
        }

        logger.debug("Message sent successfully: \(message)")
        return true
    }

    static func ping() -> Bool {
        return sendMessage("ping")
    }
}
