import SwiftUI
import AppKit
import Foundation
import Combine
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "coordinator")

// MARK: - App Coordinator

@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Dependencies
    
    @Published private(set) var yabaiInterface: YabaiInterface
    @Published private(set) var stackDetector: StackDetector
    @Published private(set) var signalListener: YabaiSignalListener
    @Published private(set) var configManager = ConfigurationManager()
    @Published private(set) var indicatorManager: IndicatorManager
    @Published private(set) var signalManager: SignalManager
    
    // MARK: - State
    
    @Published var isAppInitialized = false
    @Published var isSingletonValid = false
    @Published var isCheckingSingleton = true
    
    // MARK: - Window Management
    
    @Published var showMainWindow = false
    @Published var mainWindowId = "main-window"
    @Published var configWindow: NSWindow?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        let yabai = YabaiInterface()
        let detector = StackDetector()
        let listener = YabaiSignalListener(yabaiInterface: yabai, stackDetector: detector)
        let signalManager = SignalManager(stackDetector: detector, yabaiInterface: yabai)
        
        // Initialize configuration and indicator manager
        let configManager = ConfigurationManager()
        let indicatorManager = IndicatorManager(configManager: configManager)
        
        self.yabaiInterface = yabai
        self.stackDetector = detector
        self.signalListener = listener
        self.configManager = configManager
        self.indicatorManager = indicatorManager
        self.signalManager = signalManager
        
        // Set up observation chains to forward objectWillChange notifications
        setupObservationChains()
        
        logger.info("AppCoordinator initialized")
    }
    
    private func setupObservationChains() {
        // Forward objectWillChange notifications from child objects to this coordinator
        yabaiInterface.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        stackDetector.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        signalListener.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        configManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        indicatorManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        signalManager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    // MARK: - Singleton Management
    
    func checkSingletonStatus() {
        Task {
            let isRunning = await checkIfStacklineIsRunning()
            
            await MainActor.run {
                isCheckingSingleton = false
                
                if isRunning {
                    logger.warning("Another instance of Stackline is already running")
                    isSingletonValid = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    logger.notice("No other instance detected, starting Stackline")
                    isSingletonValid = true
                }
            }
        }
    }
    
    private func checkIfStacklineIsRunning() async -> Bool {
        let lockFilePath = "/tmp/stackline.lock"
        let currentPID = getpid()
        
        do {
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: lockFilePath) {
                let lockContent = try String(contentsOfFile: lockFilePath, encoding: .utf8)
                if let existingPID = Int32(lockContent.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    if existingPID == currentPID {
                        logger.warning("Found our own PID in lock file, removing stale lock")
                        try? fileManager.removeItem(atPath: lockFilePath)
                    } else {
                        let result = kill(existingPID, 0)
                        if result == 0 {
                            logger.info("Found running instance with PID: \(existingPID)")
                            return true
                        } else {
                            logger.debug("Found stale lock file with PID: \(existingPID), removing")
                            try? fileManager.removeItem(atPath: lockFilePath)
                        }
                    }
                }
            }
            
            logger.debug("Creating lock file with PID: \(currentPID)")
            try String(currentPID).write(toFile: lockFilePath, atomically: true, encoding: .utf8)
            
            return false
        } catch {
            logger.error("Error checking for existing instance: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - App Initialization
    
    func initializeApp() {
        guard !isAppInitialized else { return }
        
        isAppInitialized = true
        logger.info("Initializing Stackline app")
        
        // Set initial activation policy based on whether we should show main window at launch
        if configManager.config.behavior.showMainWindowAtLaunch {
            // Show dock icon since main window will be visible
            NSApplication.shared.setActivationPolicy(.regular)
        } else {
            // Start as accessory (no dock icon) - will show dock icon when main window opens
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        
        configManager.syncLaunchAgentStatus()
        
        setupNotifications()
        setupSignalHandlers()
        
        Task {
            await signalManager.startSignalHandling()
            logger.notice("Signal manager started successfully")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupStackDetection()
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.cleanup()
        }
    }
    
    private func setupSignalHandlers() {
        let signalHandler: @convention(c) (Int32) -> Void = { signal in
            logger.info("Received signal \(signal), cleaning up...")
            
            let yabaiInterface = YabaiInterface()
            yabaiInterface.performSignalCleanup(timeout: 20.0)
            
            logger.info("Exiting...")
            exit(0)
        }
        
        signal(SIGTERM, signalHandler)
        signal(SIGINT, signalHandler)
        logger.debug("Signal handlers registered")
    }
    
    private func setupStackDetection() {
        logger.debug("Setting up stack detection")
        
        stackDetector.$detectedStacks
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(10), scheduler: DispatchQueue.main)
            .sink { [weak indicatorManager] newStacks in
                indicatorManager?.updateIndicators(for: newStacks)
            }
            .store(in: &cancellables)
        
        configManager.$config
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak indicatorManager] _ in
                indicatorManager?.refreshAll()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("StacklineUpdate"),
            object: nil,
            queue: .main
        ) { [weak stackDetector] _ in
            Task { @MainActor in
                stackDetector?.forceStackDetection()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("StacklineExternalSignal"),
            object: nil,
            queue: .main
        ) { [weak signalListener] notification in
            if let event = notification.object as? String {
                signalListener?.handleExternalSignal(event)
            }
        }
        
        signalListener.startListening()
        
        Task { @MainActor in
            stackDetector.forceStackDetection()
        }
        
        if configManager.config.behavior.showByDefault {
            indicatorManager.isEnabled = true
        }
        
        logger.info("Stack detection setup completed")
    }
    
    func setupInitialWindowIfNeeded() {
        // If we're showing the main window at launch, set up its close handler
        if configManager.config.behavior.showMainWindowAtLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let mainWindow = NSApplication.shared.windows.first(where: { window in
                    return window.level == .normal && 
                           window.styleMask.contains(.titled) && 
                           window.contentView != nil &&
                           (window.title == "Stackline" || window.title == "") &&
                           !window.title.contains("Configuration")
                }) {
                    self.setupWindowCloseHandler(for: mainWindow)
                    logger.debug("Set up close handler for initial main window")
                }
            }
        }
    }
    
    // MARK: - Window Management
    
    func openMainWindow() {
        // Show dock icon when main window opens
        NSApplication.shared.setActivationPolicy(.regular)
        
        let mainWindow = NSApplication.shared.windows.first { window in
            return window.level == .normal && 
                   window.styleMask.contains(.titled) && 
                   window.contentView != nil &&
                   (window.title == "Stackline" || window.title == "") &&
                   !window.title.contains("Configuration")
        }
        
        if let window = mainWindow {
            setupWindowCloseHandler(for: window)
            window.alphaValue = 1.0
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            logger.debug("Restored and shown main window")
        } else {
            let newId = "main-window-\(UUID().uuidString)"
            mainWindowId = newId
            
            NSApp.activate(ignoringOtherApps: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let newWindow = NSApplication.shared.windows.first(where: { 
                    $0.level == .normal && 
                    $0.styleMask.contains(.titled) && 
                    $0.contentView != nil &&
                    ($0.title == "Stackline" || $0.title == "") &&
                    !$0.title.contains("Configuration")
                }) {
                    self.setupWindowCloseHandler(for: newWindow)
                    newWindow.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    logger.debug("Created and activated new main window")
                } else {
                    logger.warning("Failed to find newly created main window")
                }
            }
        }
    }
    
    private func setupWindowCloseHandler(for window: NSWindow) {
        // Set up notification for when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            // Hide dock icon when main window closes
            NSApplication.shared.setActivationPolicy(.accessory)
            logger.debug("Main window closed, hiding dock icon")
        }
    }
    
    func openConfigurationWindow() {
        configWindow?.close()
        configWindow = nil
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stackline Configuration"
        window.center()
        window.isReleasedWhenClosed = true
        
        window.contentView = NSHostingView(
            rootView: ConfigurationView(configManager: configManager)
        )
        
        configWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showAboutPanel() {
        let aboutPanel = NSAlert()
        aboutPanel.messageText = "Stackline"
        aboutPanel.informativeText = """
        A Yabai stack indicator for macOS

        Displays interactive buttons for stacked windows in Yabai.
        Now with distributed notification support for efficient signal handling.

        Inspired by the original Stackline by Adam Wagner.
        """
        aboutPanel.alertStyle = .informational
        aboutPanel.runModal()
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        logger.info("Starting cleanup process")
        
        let lockFilePath = "/tmp/stackline.lock"
        do {
            try FileManager.default.removeItem(atPath: lockFilePath)
            logger.debug("Removed lock file")
        } catch {
            logger.debug("Could not remove lock file: \(error.localizedDescription)")
        }
        
        logger.info("Cleaning up yabai signals on app termination...")
        let yabaiInterface = YabaiInterface()
        yabaiInterface.performSignalCleanup(timeout: 20.0)
        logger.info("Cleanup process completed")
    }
}