import Foundation
import Combine
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "signal-manager")

// MARK: - Signal Manager

@MainActor
class SignalManager: ObservableObject {
    private let stackDetector: StackDetector
    private let yabaiInterface: YabaiInterface
    private let socketServer = SimpleSocketServer()

    @Published var isRunning: Bool = false
    @Published var lastSignalReceived: String?
    @Published var signalCount: Int = 0

    private var signalQueue: Set<String> = []
    private var isProcessingSignals = false
    private var processTask: Task<Void, Never>?

    init(stackDetector: StackDetector, yabaiInterface: YabaiInterface) {
        self.stackDetector = stackDetector
        self.yabaiInterface = yabaiInterface

        // Set up socket server
        socketServer.signalHandler = self

        logger.debug("SignalManager initialized with socket server")
    }

    deinit {
        // Cancel any ongoing processing task
        processTask?.cancel()
        processTask = nil

        // Note: socketServer cleanup happens in its own deinit
        logger.debug("SignalManager deinitialized")
    }
    
    func startSignalHandling() async {
        guard !isRunning else { return }

        // Start listening is now non-blocking
        socketServer.startListening()
        isRunning = true
        logger.info("SignalManager started (using Unix socket at \(SimpleSocketServer.socketPath))")

        // Give socket a moment to set up
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    func stopSignalHandling() async {
        guard isRunning else { return }

        // Cancel processing task
        processTask?.cancel()
        processTask = nil

        socketServer.stopListening()
        isRunning = false
        logger.info("SignalManager stopped")
    }
    
    private func handleSignalInternal(_ event: String) {
        lastSignalReceived = event
        signalCount += 1

        logger.debug("SignalManager received signal: \(event) (total count: \(self.signalCount))")

        // Add to queue to prevent duplicate processing
        signalQueue.insert(event)

        // Process signals without blocking (cancel previous task)
        processTask?.cancel()
        processTask = Task { [weak self] in
            await self?.processSignalQueue()
        }
    }
    
    private func processSignalQueue() async {
        guard !isProcessingSignals else { return }
        isProcessingSignals = true

        defer {
            isProcessingSignals = false
        }

        // Process all queued signals
        let eventsToProcess = signalQueue
        signalQueue.removeAll()

        if !eventsToProcess.isEmpty {
            logger.debug("Processing \(eventsToProcess.count) signals: \(eventsToProcess)")

            // Trigger stack detection
            await stackDetector.updateStacks()

            // Post notification for internal components (keeping this for now)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("StacklineUpdate"),
                    object: "signal_received"
                )
            }
        }
    }
    
    func getSignalStatus() -> SignalStatus {
        return SignalStatus(
            isRunning: isRunning,
            signalCount: signalCount,
            lastSignalReceived: lastSignalReceived
        )
    }
}

// MARK: - Signal Status

struct SignalStatus {
    let isRunning: Bool
    let signalCount: Int
    let lastSignalReceived: String?
}

// MARK: - SignalHandler Conformance

extension SignalManager: SignalHandler {
    nonisolated func handleSignal(_ signal: String) {
        Task { @MainActor in
            self.handleSignalInternal(signal)
        }
    }
} 