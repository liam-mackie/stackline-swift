import Foundation
import os

/// Listens for Yabai events via distributed notifications
final class YabaiEventListener: @unchecked Sendable {
    private let tracer = PerformanceTracer.shared
    private let notificationCenter: DistributedNotificationCenter
    private let notificationName: String
    private var continuation: AsyncStream<WindowManagerEvent>.Continuation?
    private let queue = DispatchQueue(label: "sh.mackie.stackline.eventlistener")

    init(
        notificationCenter: DistributedNotificationCenter = .default(),
        notificationName: String = "stackline.yabai.signal"
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
    }

    /// Start listening and return an async stream of events
    func startListening() -> AsyncStream<WindowManagerEvent> {
        AsyncStream { continuation in
            self.queue.sync {
                self.continuation = continuation
            }

            self.notificationCenter.addObserver(
                self,
                selector: #selector(self.handleNotification(_:)),
                name: Notification.Name(self.notificationName),
                object: nil
            )

            continuation.onTermination = { [weak self] _ in
                self?.stopListening()
            }
        }
    }

    /// Stop listening for events
    func stopListening() {
        notificationCenter.removeObserver(self)

        queue.sync {
            continuation?.finish()
            continuation = nil
        }
    }

    /// Post an event (called from signal handler process)
    /// Note: DistributedNotificationCenter does NOT pass userInfo between processes,
    /// so we encode the contextId in the object string instead.
    static func postEvent(
        _ signalName: String,
        contextId: Int? = nil,
        notificationName: String = "stackline.yabai.signal"
    ) {
        let object = contextId.map { "\(signalName):\($0)" } ?? signalName
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(notificationName),
            object: object,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @objc private func handleNotification(_ notification: Notification) {
        let state = tracer.begin("SignalReceived", category: .signalHandling)
        defer { tracer.end("SignalReceived", state) }

        guard let objectString = notification.object as? String else {
            tracer.event("SignalError", "object not a string: \(String(describing: notification.object))")
            return
        }

        tracer.event("SignalRaw", "object='\(objectString)'")

        // Parse "window_focused:12345" or just "window_focused"
        let parts = objectString.split(separator: ":", maxSplits: 1)
        let signalName = String(parts[0])
        let contextId = parts.count > 1 ? Int(parts[1]) ?? 0 : 0

        tracer.event("SignalParsed", "signal=\(signalName) parts=\(parts.count) contextId=\(contextId)")

        let event = mapSignalToEvent(signalName, contextId: contextId)

        _ = queue.sync {
            continuation?.yield(event)
        }

        tracer.event("SignalDispatched", "\(signalName) id=\(contextId)")
    }

    private func mapSignalToEvent(_ signalName: String, contextId: Int) -> WindowManagerEvent {
        switch signalName {
        case "window_focused":
            return .windowFocused(contextId)
        case "window_moved":
            return .windowMoved(contextId)
        case "window_resized":
            return .windowResized(contextId)
        case "window_created":
            return .windowCreated(contextId)
        case "window_destroyed":
            return .windowDestroyed(contextId)
        case "space_changed":
            return .spaceChanged(contextId)
        default:
            return .windowFocused(0)
        }
    }
}
