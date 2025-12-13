import Foundation

public struct ManagedSpace: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public let index: Int
    public let displayIndex: Int
    public let label: String?
    public let windowIds: [WindowIdentifier]
    public let isFocused: Bool
    public let isVisible: Bool
    public let isFullscreen: Bool

    public init(
        id: Int,
        index: Int,
        displayIndex: Int,
        label: String?,
        windowIds: [WindowIdentifier],
        isFocused: Bool,
        isVisible: Bool,
        isFullscreen: Bool
    ) {
        self.id = id
        self.index = index
        self.displayIndex = displayIndex
        self.label = label
        self.windowIds = windowIds
        self.isFocused = isFocused
        self.isVisible = isVisible
        self.isFullscreen = isFullscreen
    }
}
