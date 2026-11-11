import CoreGraphics

public typealias WindowIdentifier = Int

/// A window as reported by the window manager.
public struct ManagedWindow: Identifiable, Hashable, Sendable {
    public let id: WindowIdentifier
    public let processId: Int
    public let applicationName: String
    /// Frame in AppKit screen coordinates (bottom-left origin, Y increases upward).
    public let frame: CGRect
    public let spaceIndex: Int
    public let displayIndex: Int
    /// Position within the window manager's stack; 0 when the window is not stacked.
    public let stackIndex: Int
    public let isVisible: Bool
    public let isFocused: Bool
    public let isFloating: Bool
    public let isMinimized: Bool
    public let isFullscreen: Bool

    public init(
        id: WindowIdentifier,
        processId: Int,
        applicationName: String,
        frame: CGRect,
        spaceIndex: Int,
        displayIndex: Int,
        stackIndex: Int,
        isVisible: Bool,
        isFocused: Bool,
        isFloating: Bool,
        isMinimized: Bool,
        isFullscreen: Bool
    ) {
        self.id = id
        self.processId = processId
        self.applicationName = applicationName
        self.frame = frame
        self.spaceIndex = spaceIndex
        self.displayIndex = displayIndex
        self.stackIndex = stackIndex
        self.isVisible = isVisible
        self.isFocused = isFocused
        self.isFloating = isFloating
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
    }

    /// A window can be part of a stack if it is a visible, tiled window.
    public var isStackable: Bool {
        isVisible && !isFloating && !isMinimized && !isFullscreen
    }
}
