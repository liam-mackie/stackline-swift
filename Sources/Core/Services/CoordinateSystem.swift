import Foundation
import AppKit
import os

// MARK: - Unified Coordinate System

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "coordinate-system")

enum CoordinateSystem {
    // SwiftUI uses NSScreen coordinates:
    // - Origin at bottom-left of main screen
    // - Y increases upward
    // - Multi-screen handled automatically

    /// Converts from Yabai's Core Graphics coordinates to SwiftUI NSScreen coordinates
    static func fromYabai(_ frame: WindowFrame) -> CGRect {
        // Get main display height for Y conversion
        let mainDisplay = CGDisplayBounds(CGMainDisplayID())
        let screenHeight = mainDisplay.height

        // Convert Core Graphics (top-left origin, Y down) to NSScreen (bottom-left origin, Y up)
        return CGRect(
            x: frame.x,
            y: screenHeight - frame.y - frame.h,
            width: frame.w,
            height: frame.h
        )
    }

    /// Gets the NSScreen that contains the given window frame
    static func screenContaining(_ frame: WindowFrame) -> NSScreen? {
        let screenFrame = fromYabai(frame)

        // Find screen by center point
        let centerX = screenFrame.midX
        let centerY = screenFrame.midY

        for screen in NSScreen.screens {
            if screen.frame.contains(CGPoint(x: centerX, y: centerY)) {
                return screen
            }
        }

        // Fallback to intersection
        for screen in NSScreen.screens {
            if screen.frame.intersects(screenFrame) {
                return screen
            }
        }

        return NSScreen.main
    }

    /// Checks if a window frame is positioned on any display
    static func isWindowOnScreen(_ frame: WindowFrame) -> Bool {
        let rect = CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)

        // Get all displays using Core Graphics (same as yabai)
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        guard result == .success, displayCount > 0 else {
            return false
        }

        var displays = Array<CGDirectDisplayID>(repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard result == .success else {
            return false
        }

        // Check intersection with any display
        for display in displays {
            let bounds = CGDisplayBounds(display)
            if rect.intersects(bounds) {
                return true
            }
        }

        return false
    }

    /// Creates a stable position key for grouping windows into stacks
    static func createPositionKey(for frame: WindowFrame, tolerance: Double = 5.0) -> String {
        // Round to nearest tolerance boundary to create stable clusters
        // Use larger quantization to ensure nearby windows group together
        let quantization = tolerance * 2.0 // Use 2x tolerance for more grouping
        let normalizedX = round(frame.x / quantization) * quantization
        let normalizedY = round(frame.y / quantization) * quantization

        let x = Int(normalizedX)
        let y = Int(normalizedY)

        return "pos_\(x)_\(y)"
    }
}

// MARK: - WindowFrame Extensions

extension WindowFrame {
    /// Convert to SwiftUI-compatible CGRect
    var swiftUIRect: CGRect {
        return CoordinateSystem.fromYabai(self)
    }

    /// Get the screen containing this frame
    var containingScreen: NSScreen? {
        return CoordinateSystem.screenContaining(self)
    }
}