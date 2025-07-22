import Foundation
import Combine
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "signal-listener")

class YabaiSignalListener: ObservableObject {
    private let yabaiInterface: YabaiInterface
    private let stackDetector: StackDetector
    
    @Published var isListening: Bool = false
    @Published var lastSignalReceived: String?
    @Published var signalCount: Int = 0
    
    private var pollingTask: Task<Void, Never>?
    private var lastWindowState: [Int: Bool] = [:] // windowId -> isFocused
    private var lastStackCount: Int = 0
    private var lastStackState: [String: Int] = [:] // stackId -> windowCount
    private var lastSignalCheck: Date = Date.distantPast
    private var isSettingUpSignals: Bool = false
    
    private let pollingInterval: TimeInterval = 1.0 // 1 second
    private let signalCheckInterval: TimeInterval = 30.0 // Check signals every 30 seconds
    private let signalIdentifier = "mackie-sh-stackline"
    
    init(yabaiInterface: YabaiInterface, stackDetector: StackDetector) {
        self.yabaiInterface = yabaiInterface
        self.stackDetector = stackDetector
        
        // Listen for distributed notifications from external signals
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification),
            name: Notification.Name("StacklineUpdate"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        logger.debug("YabaiSignalListener initialized")
    }
    
    deinit {
        stopListening()
        DistributedNotificationCenter.default().removeObserver(self)
        
        // Note: Signal cleanup will be handled by app termination handlers
        // Async cleanup in deinit can be problematic, so we rely on app-level cleanup
        logger.debug("YabaiSignalListener deinitialized (signals will be cleaned up by app termination handler)")
    }
    
    // MARK: - Listening Control
    
    func startListening() {
        guard !isListening else { return }
        
        isListening = true
        startPolling()
        
        // Set up yabai signals immediately
        Task {
            await setupYabaiSignals()
        }
        
        logger.info("YabaiSignalListener started with \(self.pollingInterval)s polling interval and \(self.signalCheckInterval)s signal check interval")
    }
    
    func stopListening() {
        guard isListening else { return }
        
        isListening = false
        pollingTask?.cancel()
        pollingTask = nil
        
        logger.info("YabaiSignalListener stopped")
    }
    
    // MARK: - Polling Implementation
    
    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                // Ensure we're still listening before proceeding
                let listening = await MainActor.run { self.isListening }
                guard listening else { break }
                
                await performPeriodicCheck()
                
                // Use the reduced polling interval (1 second)
                try? await Task.sleep(for: .seconds(pollingInterval))
            }
        }
    }
    
    @MainActor
    private func performPeriodicCheck() async {
        do {
            let windows = try await yabaiInterface.queryWindows()
            let hasChanges = await detectChanges(in: windows)
            
            if hasChanges {
                await stackDetector.updateStacks()
                logger.debug("Periodic check detected changes, updated stacks")
            }
            
            // Check and setup signals if needed (less frequently)
            if shouldCheckSignals() {
                logger.debug("Periodic signal check starting...")
                await setupYabaiSignals()
                markSignalCheck()
            }
            
        } catch {
            logger.error("Error during periodic check: \(error.localizedDescription)")
        }
    }
    
    private func detectChanges(in windows: [YabaiWindow]) async -> Bool {
        var hasChanges = false
        
        // Check for focus changes
        let currentWindowState = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.hasFocus) })
        if currentWindowState != lastWindowState {
            hasChanges = true
            lastWindowState = currentWindowState
            await MainActor.run {
                lastSignalReceived = "window_focus_changed"
                signalCount += 1
            }
        }
        
        // Check for stack changes
        let currentStacks = await stackDetector.detectStacks(in: windows)
        let currentStackState = Dictionary(uniqueKeysWithValues: currentStacks.map { ($0.id, $0.windows.count) })
        
        if currentStackState != lastStackState {
            hasChanges = true
            lastStackState = currentStackState
            await MainActor.run {
                lastSignalReceived = "stack_structure_changed"
                signalCount += 1
            }
        }
        
        return hasChanges
    }
    
    // MARK: - Signal-Based Updates
    
    @objc private func handleDistributedNotification(_ notification: Notification) {
        Task {
            await handleSignalUpdate(notification)
        }
    }
    
    @MainActor
    private func handleSignalUpdate(_ notification: Notification) async {
        guard let source = notification.object as? String else { return }
        
        // Handle external signal updates immediately
        if source == "signal_received" {
            lastSignalReceived = "external_signal"
            signalCount += 1
            
            // Immediate update without waiting for polling
            await stackDetector.updateStacks()
            logger.debug("Immediate update triggered by external signal")
        }
    }
    
    // MARK: - Manual Signal Handling
    
    func simulateSignal(_ event: String) {
        Task {
            await MainActor.run {
                lastSignalReceived = event
                signalCount += 1
            }
            await stackDetector.updateStacks()
        }
    }
    
    func refreshStacks() {
        simulateSignal("manual_refresh")
    }
    
    func setupSignalsManually() {
        Task {
            await setupYabaiSignals()
        }
    }
    
    func handleExternalSignal(_ event: String) {
        Task {
            await MainActor.run {
                lastSignalReceived = event
                signalCount += 1
            }
            
            // Immediate update for external signals
            await stackDetector.updateStacks()
            logger.debug("External signal handled: \(event)")
        }
    }
    
    // MARK: - Signal Setup Management
    
    func setupYabaiSignals() async {
        // Prevent concurrent signal setup
        guard !isSettingUpSignals else {
            logger.debug("Signal setup already in progress, skipping")
            return
        }
        
        isSettingUpSignals = true
        defer { isSettingUpSignals = false }
        
        let currentBinaryPath = getCurrentBinaryPath()
        logger.debug("Checking yabai signals with binary path: \(currentBinaryPath)")
        
        do {
            let signals = try await yabaiInterface.querySignals()
            
            // Find our existing signals
            let ourSignals = signals.filter { signal in
                signal.action.contains(signalIdentifier)
            }
            
            // Define required signals
            let requiredEvents = [
                "window_focused",
                "window_moved", 
                "window_resized",
                "window_destroyed",
                "window_created",
                "space_changed"
            ]
            
            // Check which signals need to be added or updated
            var signalsToAdd: [String] = []
            var signalsToRemove: [YabaiSignal] = []
            
            for event in requiredEvents {
                let expectedAction = "\(currentBinaryPath) handle-signal \(event) # \(signalIdentifier)"
                
                // Find existing signal for this event
                let existingSignal = ourSignals.first { signal in
                    signal.event == event
                }
                
                if let existing = existingSignal {
                    // Check if the action matches the expected one
                    if existing.action != expectedAction {
                        logger.debug("Signal \(event) has outdated action, will update")
                        signalsToRemove.append(existing)
                        signalsToAdd.append(event)
                    }
                    // Don't log when signals are correct to reduce noise
                } else {
                    logger.debug("Signal \(event) is missing, will add")
                    signalsToAdd.append(event)
                }
            }
            
            // Remove outdated signals (in reverse index order)
            if !signalsToRemove.isEmpty {
                logger.info("Removing \(signalsToRemove.count) outdated signals...")
                let sortedSignals = signalsToRemove.sorted { $0.index > $1.index }
                for signal in sortedSignals {
                    do {
                        try await yabaiInterface.removeSignalByIndex(signal.index)
                        logger.debug("Removed outdated signal: \(signal.event) (index \(signal.index))")
                    } catch {
                        logger.error("Failed to remove signal \(signal.event): \(error.localizedDescription)")
                    }
                }
            }
            
            // Add missing signals
            if !signalsToAdd.isEmpty {
                logger.info("Adding \(signalsToAdd.count) missing signals...")
                await addRequiredSignals(binaryPath: currentBinaryPath, events: signalsToAdd)
            }
            
            // Remove any extra signals with our identifier that aren't in required events
            let extraSignals = ourSignals.filter { signal in
                !requiredEvents.contains(signal.event) && !signalsToRemove.contains { $0.index == signal.index }
            }
            
            if !extraSignals.isEmpty {
                logger.info("Removing \(extraSignals.count) extra signals...")
                let sortedExtra = extraSignals.sorted { $0.index > $1.index }
                for signal in sortedExtra {
                    do {
                        try await yabaiInterface.removeSignalByIndex(signal.index)
                        logger.debug("Removed extra signal: \(signal.event) (index \(signal.index))")
                    } catch {
                        logger.error("Failed to remove extra signal \(signal.event): \(error.localizedDescription)")
                    }
                }
            }
            
            if signalsToAdd.isEmpty && signalsToRemove.isEmpty && extraSignals.isEmpty {
                logger.debug("All yabai signals are already correctly configured")
            } else {
                logger.notice("Yabai signals update completed successfully")
            }
            
        } catch {
            logger.warning("Error querying signals, falling back to full setup: \(error.localizedDescription)")
            // Fallback to the old method if we can't query signals
            await removeOldSignals()
            await addRequiredSignals(binaryPath: currentBinaryPath)
        }
    }
    
    private func removeOldSignals() async {
        do {
            let signals = try await yabaiInterface.querySignals()
            
            // Find signals that contain our identifier
            let ourSignals = signals.filter { signal in
                signal.action.contains(signalIdentifier)
            }
            
            logger.debug("Found \(ourSignals.count) existing signals with identifier '\(self.signalIdentifier)'")
            
            // Remove each of our old signals by index (from highest to lowest to avoid index shifting)
            let sortedSignals = ourSignals.sorted { $0.index > $1.index }
            for signal in sortedSignals {
                do {
                    try await yabaiInterface.removeSignalByIndex(signal.index)
                    logger.debug("Removed old signal: \(signal.event) (index \(signal.index))")
                } catch {
                    logger.error("Failed to remove signal \(signal.event) at index \(signal.index): \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Error querying existing signals: \(error.localizedDescription)")
        }
    }
    
    private func addRequiredSignals(binaryPath: String, events: [String]? = nil) async {
        let eventsToAdd = events ?? [
            "window_focused",
            "window_moved", 
            "window_resized",
            "window_destroyed",
            "window_created",
            "space_changed"
        ]
        
        for event in eventsToAdd {
            do {
                // Create action command with our identifier
                let action = "\(binaryPath) handle-signal \(event) # \(signalIdentifier)"
                
                try await yabaiInterface.addSignal(event: event, action: action)
                logger.debug("Added signal: \(event) -> \(action)")
            } catch {
                logger.error("Failed to add signal \(event): \(error.localizedDescription)")
            }
        }
    }
    
    private func getCurrentBinaryPath() -> String {
        // Try to get the current executable path
        if let executablePath = Bundle.main.executablePath {
            return executablePath
        }
        
        // Fallback to command line argument
        if let firstArg = CommandLine.arguments.first {
            // If it's a relative path, make it absolute
            if firstArg.hasPrefix("/") {
                return firstArg
            } else {
                let currentDirectory = FileManager.default.currentDirectoryPath
                return "\(currentDirectory)/\(firstArg)"
            }
        }
        
        // Last resort fallback
        return "stackline"
    }
    
    private func shouldCheckSignals() -> Bool {
        return Date().timeIntervalSince(lastSignalCheck) >= signalCheckInterval
    }
    
    private func markSignalCheck() {
        lastSignalCheck = Date()
    }
    
    // MARK: - Signal Cleanup
    
    func cleanupOurSignals() async {
        logger.info("Cleaning up yabai signals with identifier '\(self.signalIdentifier)'...")
        await removeOldSignals()
        logger.info("Signal cleanup completed")
    }
    
    // MARK: - Utility Methods
    
    func getSignalStats() -> SignalStats {
        return SignalStats(
            isListening: isListening,
            registeredSignals: [], // No yabai signals registered directly
            totalSignalsReceived: signalCount,
            lastSignalReceived: lastSignalReceived,
            lastSignalTime: Date(),
            pollingInterval: pollingInterval
        )
    }
    
    func setPollingInterval(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        
        let wasListening = isListening
        if wasListening {
            stopListening()
        }
        
        // Note: This would require making pollingInterval mutable
        // For now, we'll just log the request
        logger.debug("Polling interval change requested: \(interval)s (currently fixed at \(self.pollingInterval)s)")
        
        if wasListening {
            startListening()
        }
    }
}

// MARK: - Signal Stats

struct SignalStats {
    let isListening: Bool
    let registeredSignals: [String]
    let totalSignalsReceived: Int
    let lastSignalReceived: String?
    let lastSignalTime: Date
    let pollingInterval: TimeInterval
}

// MARK: - Command Line Interface

extension YabaiSignalListener {
    static func handleCommandLineSignal(_ args: [String]) {
        guard args.count >= 2 else {
            logger.error("Usage: stackline signal <event>")
            return
        }
        
        let event = args[1]
        
        // Post a notification that can be picked up by the running app
        DistributedNotificationCenter.default().post(
            name: Notification.Name("StacklineExternalSignal"),
            object: event
        )
        
        logger.info("External signal posted: \(event)")
    }
} 