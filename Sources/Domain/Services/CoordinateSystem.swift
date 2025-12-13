import Foundation
import CoreGraphics

/// Protocol for coordinate system operations (enables testing with mock displays)
protocol CoordinateSystemProtocol: Sendable {
    /// Get all display frames from the system
    func getAllDisplayFrames() -> [CGRect]

    /// Check if a window is visible on any screen
    func isWindowOnScreen(_ window: ManagedWindow) -> Bool

    /// Find the display containing the given point
    func displayContaining(point: CGPoint) -> CGRect?

    /// Find the display containing the given rect (by center point)
    func displayContaining(rect: CGRect) -> CGRect?
}

/// Production implementation using Core Graphics
/// All returned coordinates are in AppKit format (bottom-left origin, Y increases upward)
final class CoreGraphicsCoordinateSystem: CoordinateSystemProtocol, @unchecked Sendable {

    /// Height of the main display, used for coordinate conversion
    private var mainDisplayHeight: CGFloat {
        CGDisplayBounds(CGMainDisplayID()).height
    }

    func getAllDisplayFrames() -> [CGRect] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        guard displayCount > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        let screenHeight = mainDisplayHeight

        // Convert from CG coordinates (top-left origin) to AppKit (bottom-left origin)
        return displays.map { displayId in
            let cgBounds = CGDisplayBounds(displayId)
            return CoordinateConversion.toAppKit(cgBounds, screenHeight: screenHeight)
        }
    }

    func isWindowOnScreen(_ window: ManagedWindow) -> Bool {
        let displays = getAllDisplayFrames()
        let windowCenter = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )

        return displays.contains { display in
            display.contains(windowCenter)
        }
    }

    func displayContaining(point: CGPoint) -> CGRect? {
        getAllDisplayFrames().first { $0.contains(point) }
    }

    func displayContaining(rect: CGRect) -> CGRect? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displayContaining(point: center)
    }
}
