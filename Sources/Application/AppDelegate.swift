import AppKit

/// Owns the app's lifetime: brings the services up at launch and takes them down — once, and in
/// bounded time — however the app is asked to quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var menuBar: MenuBarController?
    private var preferencesWindow: PreferencesWindowController?
    private var terminationSignals: [any DispatchSourceSignal] = []
    private var isStopping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When the app merely hosts the unit tests it must not touch yabai or the user's state.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let services: AppServices
        do {
            services = try AppServices()
        } catch InstanceLock.Failure.alreadyHeld {
            Log.app.notice("Stackline is already running; exiting")
            exit(EXIT_SUCCESS)
        } catch {
            Log.app.fault("Could not start: \(String(describing: error), privacy: .public)")
            presentStartupFailure(error)
            exit(EXIT_FAILURE)
        }
        self.services = services

        let preferencesWindow = PreferencesWindowController(preferences: services.preferences, store: services.store)
        self.preferencesWindow = preferencesWindow
        menuBar = MenuBarController(
            preferences: services.preferences,
            store: services.store,
            showPreferences: { preferencesWindow.show() }
        )

        installMainMenu()
        terminateGracefullyOnSignals()
        services.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let services else { return .terminateNow }

        if !isStopping {
            isStopping = true
            menuBar?.remove()

            let cleanup = services.stop()
            Task.detached {
                await cleanup.value
                onMainRunLoop { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Routes SIGTERM, SIGINT and SIGHUP through the normal quit path, so `kill`, `launchctl` and
    /// Ctrl-C clean up exactly like the Quit menu item does.
    private func terminateGracefullyOnSignals() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            // A dispatch source only sees a signal whose default action is disabled.
            signal(number, SIG_IGN)

            // The handler runs off the main thread, so it must not inherit this type's isolation.
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler { @Sendable [self] in
                onMainRunLoop {
                    guard !self.isStopping else { return }
                    NSApp.terminate(nil)
                }
            }
            source.resume()
            terminationSignals.append(source)
        }
    }

    private func presentStartupFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Stackline could not start"
        alert.informativeText = String(describing: error)
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
    }

    /// An agent app shows no menu bar, but the main menu is still what provides ⌘Q and ⌘W to
    /// the preferences window.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Stackline", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Stackline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu

        NSApp.mainMenu = mainMenu
    }
}

/// Runs `work` on the main thread, called straight from the run loop.
///
/// Terminating has to be driven this way rather than from a main-queue block or a main-actor
/// task. `NSApplication.terminate(_:)` spins a nested run loop until it gets its reply, and a
/// run loop nested inside a main-queue block no longer drains the main queue: started from
/// there, nothing queued for the main thread — the reply included — would ever run.
private func onMainRunLoop(_ work: @escaping @MainActor @Sendable () -> Void) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
        MainActor.assumeIsolated(work)
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
}
