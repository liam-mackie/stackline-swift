import AppKit

/// Application delegate managing lifecycle events
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var preferencesWindowController: PreferencesWindowController?
    private let container = DependencyContainer.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()
        setupPreferencesWindow()
        initializeApp()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Use semaphore to wait for async shutdown to complete before process exits
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await container.shutdown()
            semaphore.signal()
        }
        semaphore.wait()
        menuBarController?.teardown()
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (required for standard shortcuts)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Stackline", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Stackline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu (for Cmd-W)
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController(container: container)
        menuBarController?.setup()
    }

    private func setupPreferencesWindow() {
        preferencesWindowController = PreferencesWindowController(
            preferences: container.preferences,
            stackDetector: container.stackDetector
        )
    }

    private func initializeApp() {
        Task {
            do {
                try await container.initialize()
            } catch {
                container.loggingService.error("Failed to initialize: \(error)", category: .app)
                await showInitializationError(error)
            }
        }
    }

    private func showInitializationError(_ error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Stackline Initialization Failed"
        alert.informativeText = "Could not connect to Yabai. Make sure Yabai is installed and running.\n\nError: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Retry")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        } else {
            initializeApp()
        }
    }
}
