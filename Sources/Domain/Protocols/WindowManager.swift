/// What Stackline needs to know about changes in the window manager.
enum WindowManagerEvent: Sendable, Equatable {
    /// The window manager is reachable and reporting events.
    case connected
    /// The window manager went away. Nothing is known about windows until `.connected`.
    case disconnected
    /// `window` received focus.
    case windowFocused(WindowIdentifier)
    /// Windows were created, destroyed, moved, resized, shown or hidden.
    case windowsChanged
    /// Displays were added, removed or rearranged, or the system woke up. Window frames keep
    /// changing for a while afterwards as the window manager re-tiles.
    case displaysChanged
}

enum WindowManagerError: Error, Equatable {
    /// The window manager is not running.
    case unavailable
    /// The window manager did not answer in time.
    case timedOut
    /// The window manager refused the request.
    case rejected(String)
    /// The request could not be delivered, or the reply could not be understood.
    case failed(String)
}

protocol WindowManager: Sendable {
    /// Connection changes and window events, in order. Supports a single consumer.
    var events: AsyncStream<WindowManagerEvent> { get }

    /// All windows, with frames in the AppKit coordinate space described by `displays`.
    ///
    /// - Throws: `WindowManagerError`, or `CancellationError`.
    func windows(on displays: DisplayGeometry) async throws -> [ManagedWindow]

    /// Gives `window` focus.
    ///
    /// - Throws: `WindowManagerError`, or `CancellationError`.
    func focus(_ window: WindowIdentifier) async throws
}
