import Foundation
import CoreGraphics

public struct WindowStack: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let windows: [ManagedWindow]
    public let frame: CGRect
    public let spaceIndex: Int
    public let displayIndex: Int
    public private(set) var focusedWindowId: WindowIdentifier?

    public init(
        windows: [ManagedWindow],
        displayIndex: Int,
        focusedWindowId: WindowIdentifier? = nil
    ) {
        precondition(!windows.isEmpty, "WindowStack must contain at least one window")

        self.windows = windows.sorted { $0.stackIndex < $1.stackIndex }
        self.frame = windows.first?.frame ?? .zero
        self.spaceIndex = windows.first?.spaceIndex ?? 0
        self.displayIndex = displayIndex
        self.focusedWindowId = focusedWindowId ?? windows.first(where: { $0.isFocused })?.id

        self.id = Self.generateId(
            displayIndex: displayIndex,
            spaceIndex: self.spaceIndex,
            frame: self.frame
        )
    }

    public var count: Int { windows.count }

    public var focusedWindow: ManagedWindow? {
        guard let focusedId = focusedWindowId else {
            return windows.first(where: { $0.isFocused }) ?? windows.first
        }
        return windows.first(where: { $0.id == focusedId })
    }

    public var visibleWindow: ManagedWindow? {
        focusedWindow
    }

    public func window(at index: Int) -> ManagedWindow? {
        guard index >= 0 && index < windows.count else { return nil }
        return windows[index]
    }

    public func index(of windowId: WindowIdentifier) -> Int? {
        windows.firstIndex(where: { $0.id == windowId })
    }

    public func withFocusedWindow(_ windowId: WindowIdentifier) -> WindowStack {
        var copy = self
        copy.focusedWindowId = windowId
        return copy
    }

    private static let positionTolerance: CGFloat = 5.0

    static func generateId(displayIndex: Int, spaceIndex: Int, frame: CGRect) -> String {
        let x = Int(frame.origin.x / positionTolerance) * Int(positionTolerance)
        let y = Int(frame.origin.y / positionTolerance) * Int(positionTolerance)
        return "display_\(displayIndex)_space_\(spaceIndex)_pos_\(x)_\(y)"
    }

    public static func == (lhs: WindowStack, rhs: WindowStack) -> Bool {
        lhs.id == rhs.id &&
        lhs.windows.map(\.id) == rhs.windows.map(\.id) &&
        lhs.focusedWindowId == rhs.focusedWindowId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(windows.map(\.id))
        hasher.combine(focusedWindowId)
    }
}
