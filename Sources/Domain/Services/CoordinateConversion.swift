import CoreGraphics

/// Coordinate conversion utilities for translating between coordinate systems.
///
/// Stackline uses AppKit coordinates (bottom-left origin, Y increases upward) internally.
/// This matches NSWindow, NSScreen, and other AppKit APIs.
///
/// External systems use different coordinate systems:
/// - Yabai: top-left origin, Y increases downward
/// - CGDisplayBounds: top-left origin, Y increases downward
/// - SwiftUI: top-left origin, Y increases downward
enum CoordinateConversion {

    /// Convert a rect from top-left origin (Yabai/CG) to bottom-left origin (AppKit)
    /// - Parameters:
    ///   - rect: Rectangle in top-left origin coordinates
    ///   - screenHeight: Total height of the coordinate space
    /// - Returns: Rectangle in bottom-left origin coordinates
    static func toAppKit(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Convert a point from top-left origin to bottom-left origin (AppKit)
    /// - Parameters:
    ///   - point: Point in top-left origin coordinates
    ///   - screenHeight: Total height of the coordinate space
    /// - Returns: Point in bottom-left origin coordinates
    static func toAppKit(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    /// Convert a rect from bottom-left origin (AppKit) to top-left origin (SwiftUI)
    /// - Parameters:
    ///   - rect: Rectangle in bottom-left origin coordinates
    ///   - screenHeight: Total height of the coordinate space
    /// - Returns: Rectangle in top-left origin coordinates
    static func toSwiftUI(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Convert a point from bottom-left origin (AppKit) to top-left origin (SwiftUI)
    /// - Parameters:
    ///   - point: Point in bottom-left origin coordinates
    ///   - screenHeight: Total height of the coordinate space
    /// - Returns: Point in top-left origin coordinates
    static func toSwiftUI(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }
}
