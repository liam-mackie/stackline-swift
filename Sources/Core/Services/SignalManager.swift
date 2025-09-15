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
    
    @Published var isRunning: Bool = false
    @Published var lastSignalReceived: String?
    @Published var signalCount: Int = 0
    
    private var signalQueue: Set<String> = []
    private var isProcessingSignals = false
    
    private var distributedNotificationObserver: NSObjectProtocol?

    init(stackDetector: StackDetector, yabaiInterface: YabaiInterface) {
        self.stackDetector = stackDetector
        self.yabaiInterface = yabaiInterface

        // Listen for distributed notifications
        distributedNotificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("StacklineExternalSignal"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleExternalSignalNotification(notification)
            }
        }

        logger.debug("SignalManager initialized")
    }

    deinit {
        if let observer = distributedNotificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        logger.debug("SignalManager deinitialized")
    }
    
    func startSignalHandling() async {
        guard !isRunning else { return }
        
        isRunning = true
        logger.info("SignalManager started (using distributed notifications)")
    }
    
    func stopSignalHandling() async {
        guard isRunning else { return }
        
        isRunning = false
        logger.info("SignalManager stopped")
    }
    
    private func handleExternalSignalNotification(_ notification: Notification) {
        logger.debug("SignalManager: handleExternalSignal called")
        guard let event = notification.object as? String else {
            logger.warning("SignalManager: No event string in notification")
            return
        }

        logger.debug("SignalManager: Processing external signal: \(event)")
        Task { @MainActor [weak self] in
            self?.handleSignal(event)
        }
    }
    
    private func handleSignal(_ event: String) {
        lastSignalReceived = event
        signalCount += 1
        
        logger.debug("SignalManager received signal: \(event) (total count: \(self.signalCount))")
        
        // Add to queue to prevent duplicate processing
        signalQueue.insert(event)
        
        // Process signals without blocking
        Task { [weak self] in
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
            
            // Post notification for other components
            await MainActor.run {
                DistributedNotificationCenter.default().post(
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