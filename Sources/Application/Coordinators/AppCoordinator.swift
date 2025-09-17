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
    private var notificationObservers: [NSObjectProtocol] = []
    private var windowCloseObservers: [NSObjectProtocol] = []
    private weak var currentMainWindow: NSWindow?
    
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
        // Debounce objectWillChange notifications to reduce updates
        let debounceInterval = 0.1 // 100ms

        yabaiInterface.objectWillChange
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)

        stackDetector.objectWillChange
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)

        signalListener.objectWillChange
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)

        configManager.objectWillChange
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)

        indicatorManager.objectWillChange
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)

        signalManager.objectWillChange
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
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
            logger.notice("Socket-based signal manager started successfully")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupStackDetection()
        }
    }
    
    private func setupNotifications() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cleanup()
            }
        }
        notificationObservers.append(observer)
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
            .sink { [weak self] newStacks in
                self?.indicatorManager.updateIndicators(for: newStacks)
            }
            .store(in: &cancellables)

        configManager.$config
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.indicatorManager.refreshAll()
            }
            .store(in: &cancellables)
        
        // Listen for internal stack update notifications
        let updateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("StacklineUpdate"),
            object: nil,
            queue: .main
        ) { [weak stackDetector] _ in
            Task { @MainActor in
                stackDetector?.forceStackDetection()
            }
        }
        notificationObservers.append(updateObserver)
        
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
        // Store weak reference to the window
        currentMainWindow = window

        // Remove any existing observers
        for observer in windowCloseObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowCloseObservers.removeAll()

        // Set up notification for when window closes
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Hide dock icon when main window closes
                NSApplication.shared.setActivationPolicy(.accessory)
                logger.debug("Main window closed, hiding dock icon")
                self?.currentMainWindow = nil
            }
        }
        windowCloseObservers.append(observer)
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

        // Stop stack detection
        stackDetector.stopDetection()

        // Clean up indicator manager
        indicatorManager.cleanup()

        // Stop signal listener
        signalListener.stopListening()

        // Stop signal manager
        Task { @MainActor in
            await signalManager.stopSignalHandling()
        }

        // Clean up all notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        // Clean up window close observers
        for observer in windowCloseObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowCloseObservers.removeAll()

        // Clear window reference
        currentMainWindow = nil

        // Cancel all Combine subscriptions
        cancellables.removeAll()

        // Clean up temporary files
        let lockFilePath = "/tmp/stackline.lock"
        let socketPath = "/tmp/stackline.sock"

        do {
            try FileManager.default.removeItem(atPath: lockFilePath)
            logger.debug("Removed lock file")
        } catch {
            logger.debug("Could not remove lock file: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.removeItem(atPath: socketPath)
            logger.debug("Removed socket file")
        } catch {
            logger.debug("Could not remove socket file: \(error.localizedDescription)")
        }

        logger.info("Cleaning up yabai signals on app termination...")
        let yabaiInterface = YabaiInterface()
        yabaiInterface.performSignalCleanup(timeout: 20.0)
        logger.info("Cleanup process completed")
    }

    deinit {
        // Clean up all notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }

        // Clean up window close observers
        for observer in windowCloseObservers {
            NotificationCenter.default.removeObserver(observer)
        }

        // Cancel all Combine subscriptions
        cancellables.removeAll()

        // Remove lock file
        let lockFilePath = "/tmp/stackline.lock"
        try? FileManager.default.removeItem(atPath: lockFilePath)

        logger.debug("AppCoordinator deinitialized")
    }
}
