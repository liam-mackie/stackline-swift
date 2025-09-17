import Foundation
import Network
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "socket-server")

// MARK: - Connection Wrapper

class ConnectionWrapper: Hashable {
    let connection: NWConnection
    let id = UUID()

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    static func == (lhs: ConnectionWrapper, rhs: ConnectionWrapper) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Socket Server

final class SocketServer: ObservableObject {
    static let socketPath = "/tmp/stackline.sock"

    private var listener: NWListener?
    private var connections: Set<ConnectionWrapper> = []
    private let queue = DispatchQueue(label: "sh.mackie.stackline.socket", qos: .userInteractive)

    @Published var isListening = false
    @Published var lastMessageReceived: String?

    weak var signalHandler: SignalHandler?

    init() {
        logger.debug("SocketServer initialized")
    }

    func startListening() {
        // Remove existing socket file if it exists
        try? FileManager.default.removeItem(atPath: Self.socketPath)

        // Create Unix domain socket parameters
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)
        parameters.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: parameters)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                self?.handleStateUpdate(state)
            }

            listener?.start(queue: queue)

        } catch {
            logger.error("Failed to start socket listener: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        listener?.cancel()
        listener = nil

        // Close all connections
        for wrapper in connections {
            wrapper.connection.cancel()
        }
        connections.removeAll()

        // Remove socket file
        try? FileManager.default.removeItem(atPath: Self.socketPath)

        Task { @MainActor in
            isListening = false
        }
        logger.info("Socket server stopped")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            Task { @MainActor in
                self.isListening = true
                logger.info("Socket server listening at \(Self.socketPath)")
            }
        case .failed(let error):
            logger.error("Socket listener failed: \(error.localizedDescription)")
            Task { @MainActor in
                self.isListening = false
            }
        case .cancelled:
            Task { @MainActor in
                self.isListening = false
                logger.debug("Socket listener cancelled")
            }
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let wrapper = ConnectionWrapper(connection)
        connections.insert(wrapper)

        connection.stateUpdateHandler = { [weak self, weak wrapper] state in
            switch state {
            case .ready:
                if let wrapper = wrapper {
                    self?.receiveMessage(from: wrapper.connection)
                }
            case .failed(let error):
                logger.error("Connection failed: \(error.localizedDescription)")
                if let wrapper = wrapper {
                    self?.connections.remove(wrapper)
                }
            case .cancelled:
                if let wrapper = wrapper {
                    self?.connections.remove(wrapper)
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                logger.error("Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            if let data = data, !data.isEmpty {
                if let message = String(data: data, encoding: .utf8) {
                    logger.debug("Received message: \(message)")

                    Task { @MainActor [weak self] in
                        self?.lastMessageReceived = message
                        self?.processMessage(message)
                    }
                }
            }

            if isComplete {
                connection.cancel()
            } else {
                // Continue receiving
                self?.receiveMessage(from: connection)
            }
        }
    }

    private func processMessage(_ message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle different message types
        if trimmedMessage.hasPrefix("signal:") {
            let signal = String(trimmedMessage.dropFirst(7))
            // Call the nonisolated protocol method
            signalHandler?.handleSignal(signal)
        } else if trimmedMessage == "ping" {
            logger.debug("Received ping")
        } else {
            // Treat as a signal for backward compatibility
            signalHandler?.handleSignal(trimmedMessage)
        }
    }

    deinit {
        stopListening()
        logger.debug("SocketServer deinitialized")
    }
}

// MARK: - Socket Client

final class SocketClient {
    static let socketPath = "/tmp/stackline.sock"

    static func sendMessage(_ message: String, timeout: TimeInterval = 2.0) -> Bool {
        let queue = DispatchQueue(label: "sh.mackie.stackline.socket.client")
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()

        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .ready:
                // Send the message
                let data = message.data(using: .utf8)!
                connection.send(content: data, completion: NWConnection.SendCompletion.contentProcessed { error in
                    if let error = error {
                        logger.error("Failed to send message: \(error.localizedDescription)")
                        success = false
                    } else {
                        logger.debug("Message sent successfully: \(message)")
                        success = true
                    }
                    connection.cancel()
                    semaphore.signal()
                })

            case .failed(let error):
                logger.error("Connection failed: \(error.localizedDescription)")
                success = false
                semaphore.signal()

            case .cancelled:
                semaphore.signal()

            default:
                break
            }
        }

        connection.start(queue: queue)

        // Wait for completion or timeout
        let result = semaphore.wait(timeout: .now() + timeout)

        if result == .timedOut {
            logger.warning("Socket connection timed out")
            connection.cancel()
            return false
        }

        return success
    }

    static func ping() -> Bool {
        return sendMessage("ping")
    }
}

// MARK: - Signal Handler Protocol

protocol SignalHandler: AnyObject {
    nonisolated func handleSignal(_ signal: String)
}