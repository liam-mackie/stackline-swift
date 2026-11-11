import CoreGraphics

/// A snapshot of the display arrangement.
///
/// Stackline works in AppKit screen coordinates (bottom-left origin, Y increases upward), while
/// window managers and CoreGraphics report top-left-origin coordinates. Converting between the
/// two depends on the height of the primary display, which changes when displays are connected,
/// disconnected or rearranged — so every conversion goes through one snapshot, and a snapshot is
/// only ever combined with window frames queried at the same time.
struct DisplayGeometry: Equatable, Sendable {
    /// Frames of the active displays in AppKit screen coordinates.
    let screens: [CGRect]
    /// Height of the primary display: the pivot between the two coordinate spaces.
    let primaryHeight: CGFloat

    /// No displays, e.g. while the system is reconfiguring them.
    static let none = DisplayGeometry(screens: [], primaryHeight: 0)

    /// Converts a rect from global top-left-origin coordinates to AppKit screen coordinates.
    func appKitRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// The display showing the center of `rect`, which must be in AppKit screen coordinates.
    func screen(containing rect: CGRect) -> CGRect? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screens.first { $0.contains(center) }
    }

    /// The arrangement right now. Safe to call from any thread.
    static func current() -> DisplayGeometry {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return .none }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return .none }

        let pivot = DisplayGeometry(screens: [], primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
        return DisplayGeometry(
            screens: displays.prefix(Int(count)).map { pivot.appKitRect(fromTopLeft: CGDisplayBounds($0)) },
            primaryHeight: pivot.primaryHeight
        )
    }
}
