import CoreGraphics

/// Groups windows into stacks. Pure: the same input always yields the same stacks.
enum StackBuilder {
    /// Windows whose origins are within this many points of each other share a tile.
    static let positionTolerance: CGFloat = 5

    /// - Parameters:
    ///   - windows: All windows known to the window manager, with frames in the coordinate space
    ///     of `displays`.
    ///   - displays: The display arrangement the frames were captured with.
    ///   - focusHistory: Recently focused windows, most recent first. A window manager only knows
    ///     the single focused window, so this is what tells which window is on top of the stacks
    ///     that do not have focus.
    static func stacks(
        from windows: [ManagedWindow],
        on displays: DisplayGeometry,
        focusHistory: [WindowIdentifier] = []
    ) -> [WindowStack] {
        var tiles: [(screen: CGRect, windows: [ManagedWindow])] = []

        // Visiting windows in ID order keeps tile membership stable no matter how the window
        // manager orders its reply (yabai lists windows front to back, which changes with focus).
        for window in windows.sorted(by: { $0.id < $1.id }) where window.isStackable {
            guard let screen = displays.screen(containing: window.frame) else { continue }

            if let index = tiles.firstIndex(where: { sharesTile(window, $0.windows[0]) }) {
                tiles[index].windows.append(window)
            } else {
                tiles.append((screen, [window]))
            }
        }

        return tiles
            .map { tile in
                WindowStack(
                    windows: tile.windows,
                    screenFrame: tile.screen,
                    focusedWindowId: topWindow(of: tile.windows, focusHistory: focusHistory)
                )
            }
            .sorted { lhs, rhs in
                (lhs.spaceIndex, lhs.displayIndex, lhs.frame.origin.y, lhs.frame.origin.x)
                    < (rhs.spaceIndex, rhs.displayIndex, rhs.frame.origin.y, rhs.frame.origin.x)
            }
    }

    private static func sharesTile(_ lhs: ManagedWindow, _ rhs: ManagedWindow) -> Bool {
        lhs.spaceIndex == rhs.spaceIndex
            && lhs.displayIndex == rhs.displayIndex
            && abs(lhs.frame.origin.x - rhs.frame.origin.x) <= positionTolerance
            && abs(lhs.frame.origin.y - rhs.frame.origin.y) <= positionTolerance
    }

    private static func topWindow(of windows: [ManagedWindow], focusHistory: [WindowIdentifier]) -> WindowIdentifier? {
        if let focused = windows.first(where: \.isFocused) {
            return focused.id
        }
        return focusHistory.first { id in windows.contains { $0.id == id } }
    }
}
