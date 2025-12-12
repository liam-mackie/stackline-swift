import AppKit
import Foundation

/// Main entry point for Stackline
/// Supports multiple run modes:
/// - Default: Launch as menu bar app
/// - --daemon: Run in background without UI
/// - handle-signal <event>: Handle Yabai signal (called by Yabai)

let arguments = CommandLine.arguments

@MainActor
func parseArguments() {
    guard arguments.count > 1 else {
        runApp()
        return
    }

    let firstArg = arguments[1]

    // Ignore system arguments (e.g., -NSDocumentRevisionsDebugMode from Xcode)
    if firstArg.hasPrefix("-NS") || firstArg.hasPrefix("-Apple") {
        runApp()
        return
    }

    switch firstArg {
    case "handle-signal":
        guard arguments.count > 2 else {
            print("Usage: stackline handle-signal <event> [window_id|space_id]")
            exit(1)
        }
        let signalName = arguments[2]
        let contextId = arguments.count > 3 ? Int(arguments[3]) : nil

        // Debug: log to file what we received
        let debugMsg = "handle-signal: args=\(arguments) signalName=\(signalName) contextId=\(String(describing: contextId))\n"
        if let data = debugMsg.data(using: .utf8) {
            FileManager.default.createFile(atPath: "/tmp/stackline-signal.log", contents: nil)
            if let handle = FileHandle(forWritingAtPath: "/tmp/stackline-signal.log") {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }

        YabaiEventListener.postEvent(signalName, contextId: contextId)
        exit(0)

    case "--daemon":
        runDaemon()

    case "--help", "-h":
        printUsage()
        exit(0)

    case "--version", "-v":
        print("Stackline 1.0.0")
        exit(0)

    default:
        // Ignore unknown flags that look like system arguments
        if firstArg.hasPrefix("-") {
            runApp()
        } else {
            print("Unknown argument: \(firstArg)")
            printUsage()
            exit(1)
        }
    }
}

MainActor.assumeIsolated {
    parseArguments()
}

@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    app.setActivationPolicy(.accessory)
    app.run()
}

func runDaemon() {
    let semaphore = DispatchSemaphore(value: 0)

    Task { @MainActor in
        let container = DependencyContainer.shared
        do {
            try await container.initialize()
            container.loggingService.info("Daemon started", category: .app)
        } catch {
            container.loggingService.error("Daemon failed to start: \(error)", category: .app)
            exit(1)
        }
    }

    signal(SIGINT) { _ in
        Task { @MainActor in
            await DependencyContainer.shared.shutdown()
            exit(0)
        }
    }

    signal(SIGTERM) { _ in
        Task { @MainActor in
            await DependencyContainer.shared.shutdown()
            exit(0)
        }
    }

    semaphore.wait()
}

func printUsage() {
    print("""
    Stackline - Window Stack Indicator for macOS

    Usage:
      stackline                  Launch as menu bar application
      stackline --daemon         Run in background without UI
      stackline handle-signal <event>  Handle Yabai signal
      stackline --help           Show this help message
      stackline --version        Show version

    Events:
      window_focused, window_moved, window_resized,
      window_created, window_destroyed, space_changed
    """)
}
