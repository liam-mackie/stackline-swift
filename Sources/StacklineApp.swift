import SwiftUI
import AppKit
import Foundation
import Combine
import Darwin
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "app")

// MARK: - Stackline App

struct StacklineApp: App {
    @StateObject private var yabaiInterface: YabaiInterface
    @StateObject private var stackDetector: StackDetector
    @StateObject private var signalListener: YabaiSignalListener
    @StateObject private var configManager = ConfigurationManager()
    @StateObject private var indicatorManager: SimpleIndicatorManager
    @StateObject private var signalManager: SignalManager
    
    @State private var showingMenuBarIcon = true
    @State private var isAppInitialized = false
    @State private var isSingletonValid = false
    @State private var isCheckingSingleton = true
    
    // Main window management
    @State private var showMainWindow = false
    
    // Simple config window management
    @State private var configWindow: NSWindow?
    
    init() {
        let yabai = YabaiInterface()
        let detector = StackDetector(yabaiInterface: yabai)
        let listener = YabaiSignalListener(yabaiInterface: yabai, stackDetector: detector)
        let signalManager = SignalManager(stackDetector: detector, yabaiInterface: yabai)
        
        // Initialize configuration and indicator manager
        let configManager = ConfigurationManager()
        let indicatorManager = SimpleIndicatorManager(configManager: configManager)
        
        _yabaiInterface = StateObject(wrappedValue: yabai)
        _stackDetector = StateObject(wrappedValue: detector)
        _signalListener = StateObject(wrappedValue: listener)
        _configManager = StateObject(wrappedValue: configManager)
        _indicatorManager = StateObject(wrappedValue: indicatorManager)
        _signalManager = StateObject(wrappedValue: signalManager)
        
        logger.info("Stackline app initialized")
    }
    
    var body: some Scene {
        // Main window
        WindowGroup {
            if isCheckingSingleton {
                LoadingView()
                    .onAppear {
                        // Check singleton status after UI is initialized
                        checkSingletonStatus()
                    }
            } else if isSingletonValid {
                ContentView(
                    yabaiInterface: yabaiInterface,
                    stackDetector: stackDetector,
                    signalListener: signalListener,
                    configManager: configManager,
                    indicatorManager: indicatorManager,
                    signalManager: signalManager
                )
                .onAppear {
                    // Check if we should hide the main window at launch
                    if !configManager.config.behavior.showMainWindowAtLaunch {
                        // Hide this window immediately to prevent flashing
                        // Use immediate execution to minimize flash
                        let windows = NSApplication.shared.windows
                        for window in windows {
                            if window.styleMask.contains(.titled) && window.contentView != nil {
                                window.alphaValue = 0.0 // Make invisible first
                                window.orderOut(nil)    // Then hide
                                logger.debug("Hidden main window at launch")
                            }
                        }
                    }
                    
                    if !isAppInitialized {
                        initializeApp()
                    }
                }
            } else {
                SingletonErrorView()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Show Main Window") {
                    openMainWindow()
                }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Stackline") {
                    showAboutPanel()
                }
            }
        }
        
        // Menu bar
        MenuBarExtra("Stackline", systemImage: "rectangle.stack") {
            if isCheckingSingleton {
                Text("Checking for other instances...")
                    .foregroundColor(.secondary)
            } else if isSingletonValid {
                MenuBarView(
                    yabaiInterface: yabaiInterface,
                    stackDetector: stackDetector,
                    signalListener: signalListener,
                    configManager: configManager,
                    indicatorManager: indicatorManager,
                    signalManager: signalManager,
                    onOpenConfig: {
                        openConfigurationWindow()
                    },
                    onOpenMain: {
                        openMainWindow()
                    }
                )
            } else {
                VStack {
                    Text("Another instance is running")
                        .foregroundColor(.secondary)
                    
                    Button("Close This Instance") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
    
    private func checkSingletonStatus() {
        // Try to connect to existing server to check if another instance is running
        Task {
            let isRunning = await checkIfStacklineIsRunning()
            
            await MainActor.run {
                // Update loading state first
                isCheckingSingleton = false
                
                if isRunning {
                    logger.warning("Another instance of Stackline is already running")
                    isSingletonValid = false
                    
                    // Show error and exit after a delay
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
        // Use a lock file approach to check for existing instances
        let lockFilePath = "/tmp/stackline.lock"
        let currentPID = getpid()
        
        do {
            let fileManager = FileManager.default
            
            // First, check if lock file exists and contains a valid PID
            if fileManager.fileExists(atPath: lockFilePath) {
                let lockContent = try String(contentsOfFile: lockFilePath, encoding: .utf8)
                if let existingPID = Int32(lockContent.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // Don't check our own PID (shouldn't happen, but safety check)
                    if existingPID == currentPID {
                        logger.warning("Found our own PID in lock file, removing stale lock")
                        try? fileManager.removeItem(atPath: lockFilePath)
                    } else {
                        // Check if that process is still running
                        let result = kill(existingPID, 0) // Send signal 0 to check if process exists
                        if result == 0 {
                            // Process is still running - another instance exists
                            logger.info("Found running instance with PID: \(existingPID)")
                            return true
                        } else {
                            // Process is dead, remove stale lock file
                            logger.debug("Found stale lock file with PID: \(existingPID), removing")
                            try? fileManager.removeItem(atPath: lockFilePath)
                        }
                    }
                }
            }
            
            // No existing instance found, create lock file with current PID
            logger.debug("Creating lock file with PID: \(currentPID)")
            try String(currentPID).write(toFile: lockFilePath, atomically: true, encoding: .utf8)
            
            return false
        } catch {
            logger.error("Error checking for existing instance: \(error.localizedDescription)")
            return false
        }
    }
    
    private func initializeApp() {
        isAppInitialized = true
        logger.info("Initializing Stackline app")
        
        // Sync launch agent status on startup
        configManager.syncLaunchAgentStatus()
        
        // Window visibility is now handled in the ContentView onAppear method
        
        // Set up cleanup for app termination
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.cleanup()
        }
        
        // Set up signal handlers for graceful shutdown
        setupSignalHandlers()
        
        // Start the signal manager first
        Task {
            await signalManager.startSignalHandling()
            logger.notice("Signal manager started successfully")
        }
        
        // Delay initialization to avoid early crashes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            setupStackDetection()
        }
    }
    
    private func openMainWindow() {
        // Try to bring existing window to front
        if let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }) {
            window.alphaValue = 1.0 // Restore visibility
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            logger.debug("Restored and shown main window")
        } else {
            // Create new window if none exists
            showMainWindow = true
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func cleanup() {
        logger.info("Starting cleanup process")
        
        // Clean up lock file
        let lockFilePath = "/tmp/stackline.lock"
        do {
            try FileManager.default.removeItem(atPath: lockFilePath)
            logger.debug("Removed lock file")
        } catch {
            logger.debug("Could not remove lock file: \(error.localizedDescription)")
        }
        
        // Clean up yabai signals with timeout
        logger.info("Cleaning up yabai signals on app termination...")
        let yabaiInterface = YabaiInterface()
        yabaiInterface.performSignalCleanup(timeout: 20.0)
        logger.info("Cleanup process completed")
    }
    
    private func setupSignalHandlers() {
        // Set up signal handlers for graceful shutdown
        let signalHandler: @convention(c) (Int32) -> Void = { signal in
            logger.info("Received signal \(signal), cleaning up...")
            
            // Use the same cleanup interface as the command line
            let yabaiInterface = YabaiInterface()
            yabaiInterface.performSignalCleanup(timeout: 20.0)
            
            logger.info("Exiting...")
            exit(0)
        }
        
        // Register signal handlers
        signal(SIGTERM, signalHandler)
        signal(SIGINT, signalHandler)
        logger.debug("Signal handlers registered")
    }
    
    private func setupStackDetection() {
        logger.debug("Setting up stack detection")
        
        // Set up stack detection monitoring with fast, responsive updates
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
        
        // Listen for distributed notifications to ensure UI updates
        NotificationCenter.default.addObserver(
            forName: Notification.Name("StacklineUpdate"),
            object: nil,
            queue: .main
        ) { [weak stackDetector] _ in
            stackDetector?.forceStackDetection()
        }
        
        // Listen for external signals (from command line)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("StacklineExternalSignal"),
            object: nil,
            queue: .main
        ) { [weak signalListener] notification in
            if let event = notification.object as? String {
                signalListener?.handleExternalSignal(event)
            }
        }
        
        // Start the signal listener
        signalListener.startListening()
        
        // Initial stack detection
        stackDetector.forceStackDetection()
        
        // Auto-show indicators if configured
        if configManager.config.behavior.showByDefault {
            indicatorManager.isEnabled = true
        }
        
        logger.info("Stack detection setup completed")
    }
    
    @State private var cancellables = Set<AnyCancellable>()
    
    private func showAboutPanel() {
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
    
    private func openConfigurationWindow() {
        // Close existing config window if it exists
        configWindow?.close()
        configWindow = nil
        
        // Create new config window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stackline Configuration"
        window.center()
        window.isReleasedWhenClosed = true
        
        // Create configuration view
        window.contentView = NSHostingView(
            rootView: ConfigurationView(configManager: configManager)
        )
        
        // Store reference
        configWindow = window
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Singleton Error View

struct SingletonErrorView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Stackline Already Running")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Another instance of Stackline is already running.")
                .font(.body)
                .multilineTextAlignment(.center)
            
            Text("This instance will close automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Close Now") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var yabaiInterface: YabaiInterface
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var signalListener: YabaiSignalListener
    @ObservedObject var configManager: ConfigurationManager
    @ObservedObject var indicatorManager: SimpleIndicatorManager
    @ObservedObject var signalManager: SignalManager
    
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainStatusView(
                yabaiInterface: yabaiInterface,
                stackDetector: stackDetector,
                signalListener: signalListener,
                indicatorManager: indicatorManager,
                signalManager: signalManager
            )
            .tabItem {
                Image(systemName: "info.circle")
                Text("Status")
            }
            .tag(0)
            
            StackDetailsView(
                stackDetector: stackDetector,
                yabaiInterface: yabaiInterface
            )
            .tabItem {
                Image(systemName: "rectangle.stack")
                Text("Stacks")
            }
            .tag(1)
            
            ConfigurationMainView(configManager: configManager)
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct MainStatusView: View {
    @ObservedObject var yabaiInterface: YabaiInterface
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var signalListener: YabaiSignalListener
    @ObservedObject var indicatorManager: SimpleIndicatorManager
    @ObservedObject var signalManager: SignalManager
    
    var body: some View {
        VStack(spacing: 20) {
            HeaderView()
            
            StatusView(
                yabaiInterface: yabaiInterface,
                stackDetector: stackDetector,
                signalListener: signalListener,
                indicatorManager: indicatorManager,
                signalManager: signalManager
            )
            
            ControlsView(
                stackDetector: stackDetector,
                indicatorManager: indicatorManager,
                signalManager: signalManager,
                signalListener: signalListener
            )
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - UI Components

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Stackline")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Yabai Stack Indicator")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct StatusView: View {
    @ObservedObject var yabaiInterface: YabaiInterface
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var signalListener: YabaiSignalListener
    @ObservedObject var indicatorManager: SimpleIndicatorManager
    @ObservedObject var signalManager: SignalManager
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                StatusBadge(
                    title: "Yabai Status",
                    status: yabaiInterface.isConnected ? "Connected" : "Disconnected",
                    color: yabaiInterface.isConnected ? .green : .red
                )
                
                StatusBadge(
                    title: "Signal Manager",
                    status: signalManager.isRunning ? "Running" : "Stopped",
                    color: signalManager.isRunning ? .green : .red
                )
            }
            
            GridRow {
                StatusBadge(
                    title: "Signal Listener",
                    status: signalListener.isListening ? "Listening" : "Inactive",
                    color: signalListener.isListening ? .green : .gray
                )
                
                StatusBadge(
                    title: "Signal Count",
                    status: "\(signalManager.signalCount)",
                    color: .blue
                )
            }
            
            GridRow {
                StatusBadge(
                    title: "Stacks",
                    status: "\(stackDetector.detectedStacks.count)",
                    color: .blue
                )
                
                StatusBadge(
                    title: "Indicators",
                    status: indicatorManager.isEnabled ? "Enabled" : "Disabled",
                    color: indicatorManager.isEnabled ? .green : .gray
                )
            }
        }
        .padding()
    }
}

struct StatusBadge: View {
    let title: String
    let status: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 120, maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct ControlsView: View {
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var indicatorManager: SimpleIndicatorManager
    @ObservedObject var signalManager: SignalManager
    @ObservedObject var signalListener: YabaiSignalListener
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {
                    indicatorManager.toggle()
                }) {
                    HStack {
                        Image(systemName: indicatorManager.isEnabled ? "eye.slash" : "eye")
                        Text(indicatorManager.isEnabled ? "Hide Indicators" : "Show Indicators")
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Refresh Stacks") {
                    stackDetector.forceStackDetection()
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                Button("Setup Yabai Signals") {
                    signalListener.setupSignalsManually()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
    }
}

struct StackDetailsView: View {
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var yabaiInterface: YabaiInterface
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section - fixed at top
            HStack {
                Text("Detected Stacks")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(stackDetector.detectedStacks.count) stacks found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Refresh") {
                    stackDetector.forceStackDetection()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.windowBackgroundColor))
            
            // Scrollable content area
            ScrollView {
                LazyVStack(spacing: 16) {
                    if stackDetector.detectedStacks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No stacks detected")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Create stacks in Yabai to see them here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(stackDetector.detectedStacks) { stack in
                            StackDetailCard(stack: stack, yabaiInterface: yabaiInterface)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            stackDetector.forceStackDetection()
        }
    }
}

struct StackDetailCard: View {
    let stack: WindowStack
    @ObservedObject var yabaiInterface: YabaiInterface
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stack \(stack.id)")
                        .font(.headline)
                    
                    HStack {
                        Text("Space \(stack.space)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        
                        Text("Display \(stack.display)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        
                        Text("\(stack.windows.count) windows")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                Button("Focus Stack") {
                    if let firstWindow = stack.windows.first {
                        Task {
                            try? await yabaiInterface.focusWindow(firstWindow.id)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            VStack(spacing: 8) {
                ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stack Index \(window.stackIndex)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(window.app)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(stack.visibleWindow?.id == window.id ? .blue : .primary)
                                
                                if stack.visibleWindow?.id == window.id {
                                    Image(systemName: "eye.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                }
                            }
                            
                            Text(window.title)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button("Focus") {
                            Task {
                                try? await yabaiInterface.focusWindow(window.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(stack.visibleWindow?.id == window.id ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ConfigurationMainView: View {
    @ObservedObject var configManager: ConfigurationManager
    
    var body: some View {
        ConfigurationView(configManager: configManager)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Checking for other instances...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Please wait...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

struct MenuBarView: View {
    @ObservedObject var yabaiInterface: YabaiInterface
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var signalListener: YabaiSignalListener
    @ObservedObject var configManager: ConfigurationManager
    @ObservedObject var indicatorManager: SimpleIndicatorManager
    @ObservedObject var signalManager: SignalManager
    
    let onOpenConfig: () -> Void
    let onOpenMain: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stackline")
                .font(.headline)
                .padding(.bottom, 4)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Stacks:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 90, alignment: .leading)
                    Text("\(stackDetector.detectedStacks.count)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Text("Indicators:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 90, alignment: .leading)
                    Text(indicatorManager.isEnabled ? "Enabled" : "Disabled")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(indicatorManager.isEnabled ? .green : .red)
                }
                
                HStack(spacing: 4) {
                    Text("Signal Manager:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 90, alignment: .leading)
                    Text(signalManager.isRunning ? "Running" : "Stopped")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(signalManager.isRunning ? .green : .red)
                }
                
                HStack(spacing: 4) {
                    Text("Signal Count:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 90, alignment: .leading)
                    Text("\(signalManager.signalCount)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Button("Show Main Window") {
                onOpenMain()
            }
            
            Button(action: {
                indicatorManager.toggle()
            }) {
                HStack {
                    Image(systemName: indicatorManager.isEnabled ? "eye.slash" : "eye")
                    Text(indicatorManager.isEnabled ? "Hide Indicators" : "Show Indicators")
                }
            }
            
            Button("Refresh Stacks") {
                stackDetector.forceStackDetection()
            }
            
            Button("Configuration...") {
                onOpenConfig()
            }
            
            Divider()
            
            Button("Quit Stackline") {
                NSApplication.shared.terminate(NSApp)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
} 
