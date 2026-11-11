import AppKit

/// Changes the system announces itself, independently of the window manager.
enum SystemEvent: Sendable, Equatable {
    /// Displays were reconfigured, or the machine, its displays or the user session woke up.
    case displaysChanged
    /// A different space became active.
    case spaceChanged
}

enum SystemEvents {
    /// A stream of system events that observes for as long as it is being iterated.
    @MainActor
    static func stream() -> AsyncStream<SystemEvent> {
        let workspace = NSWorkspace.shared.notificationCenter
        let sources: [(center: NotificationCenter, name: Notification.Name, event: SystemEvent)] = [
            (.default, NSApplication.didChangeScreenParametersNotification, .displaysChanged),
            (workspace, NSWorkspace.didWakeNotification, .displaysChanged),
            (workspace, NSWorkspace.screensDidWakeNotification, .displaysChanged),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .displaysChanged),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, .spaceChanged),
        ]

        // Events are only triggers to re-read state, so a burst may collapse.
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let observation = Task {
                await withTaskGroup(of: Void.self) { group in
                    for source in sources {
                        group.addTask {
                            for await _ in source.center.notifications(named: source.name) {
                                continuation.yield(source.event)
                            }
                        }
                    }
                }
            }
            continuation.onTermination = { _ in observation.cancel() }
        }
    }
}
