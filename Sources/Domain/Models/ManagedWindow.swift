import Foundation
import CoreGraphics

public struct ManagedWindow: Identifiable, Equatable, Hashable, Sendable {
    public let id: WindowIdentifier
    public let processId: Int
    public let applicationName: String
    public let title: String
    public let frame: CGRect
    public let spaceIndex: Int
    public let displayIndex: Int
    public let stackIndex: Int
    public let isVisible: Bool
    public let isFocused: Bool
    public let isFloating: Bool
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let isRootWindow: Bool

    public init(
        id: WindowIdentifier,
        processId: Int,
        applicationName: String,
        title: String,
        frame: CGRect,
        spaceIndex: Int,
        displayIndex: Int,
        stackIndex: Int,
        isVisible: Bool,
        isFocused: Bool,
        isFloating: Bool,
        isMinimized: Bool,
        isFullscreen: Bool,
        isRootWindow: Bool
    ) {
        self.id = id
        self.processId = processId
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
        self.spaceIndex = spaceIndex
        self.displayIndex = displayIndex
        self.stackIndex = stackIndex
        self.isVisible = isVisible
        self.isFocused = isFocused
        self.isFloating = isFloating
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isRootWindow = isRootWindow
    }

    /// A window is stackable if it's a visible, managed (non-floating) window
    public var isStackable: Bool {
        isVisible && !isFloating && !isMinimized && !isFullscreen
    }

    /// Creates a copy with the focused state changed
    public func with(isFocused newFocused: Bool) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: processId,
            applicationName: applicationName,
            title: title,
            frame: frame,
            spaceIndex: spaceIndex,
            displayIndex: displayIndex,
            stackIndex: stackIndex,
            isVisible: isVisible,
            isFocused: newFocused,
            isFloating: isFloating,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen,
            isRootWindow: isRootWindow
        )
    }
}
