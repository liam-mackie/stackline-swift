import CoreGraphics

/// One or more windows occupying the same tile on a visible space.
public struct WindowStack: Identifiable, Hashable, Sendable {
    public let id: String
    /// The windows in stack order.
    public let windows: [ManagedWindow]
    /// Frame of the stack in AppKit screen coordinates.
    public let frame: CGRect
    /// Frame of the display the stack is on, in AppKit screen coordinates.
    public let screenFrame: CGRect
    public let spaceIndex: Int
    public let displayIndex: Int
    /// The window shown on top of the stack, if known.
    public let focusedWindowId: WindowIdentifier?

    /// - Parameters:
    ///   - windows: The members of the stack; must not be empty.
    ///   - focusedWindowId: The window on top. Defaults to the member that has focus.
    public init(
        windows: [ManagedWindow],
        screenFrame: CGRect,
        focusedWindowId: WindowIdentifier? = nil
    ) {
        precondition(!windows.isEmpty, "WindowStack must contain at least one window")

        // Ordering by ID as well makes the stack — and the frame and ID derived from its first
        // window — independent of the order the window manager happened to list the windows in.
        let ordered = windows.sorted { ($0.stackIndex, $0.id) < ($1.stackIndex, $1.id) }
        let first = ordered[0]

        self.windows = ordered
        self.frame = first.frame
        self.screenFrame = screenFrame
        self.spaceIndex = first.spaceIndex
        self.displayIndex = first.displayIndex
        self.focusedWindowId = focusedWindowId ?? ordered.first(where: \.isFocused)?.id
        self.id = Self.makeID(displayIndex: first.displayIndex, spaceIndex: first.spaceIndex, frame: first.frame)
    }

    public var count: Int { windows.count }

    public func index(of windowId: WindowIdentifier) -> Int? {
        windows.firstIndex { $0.id == windowId }
    }

    /// Identifies a stack by where it is rather than by what it contains, so an indicator stays
    /// attached to its tile while windows come and go.
    private static func makeID(displayIndex: Int, spaceIndex: Int, frame: CGRect) -> String {
        let tolerance = StackBuilder.positionTolerance
        let x = Int((frame.origin.x / tolerance).rounded(.down) * tolerance)
        let y = Int((frame.origin.y / tolerance).rounded(.down) * tolerance)
        return "display_\(displayIndex)_space_\(spaceIndex)_pos_\(x)_\(y)"
    }
}
