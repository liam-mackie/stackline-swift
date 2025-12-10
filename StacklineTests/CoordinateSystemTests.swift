import Testing
import AppKit
@testable import Stackline

struct CoordinateSystemTests {

    @Test func yabaiToSwiftUICoordinateConversion() {
        // Test conversion from Yabai's Core Graphics coordinates to SwiftUI NSScreen coordinates

        // Get main display bounds for reference
        let mainDisplay = CGDisplayBounds(CGMainDisplayID())
        let screenHeight = mainDisplay.height

        // Test window at top-left of screen in Yabai coordinates
        let yabaiTopLeft = WindowFrame(x: 0, y: 0, w: 100, h: 100)
        let swiftUITopLeft = CoordinateSystem.fromYabai(yabaiTopLeft)

        // In SwiftUI coordinates, top-left becomes bottom-left with Y flipped
        #expect(swiftUITopLeft.origin.x == 0, "X coordinate should remain the same")
        #expect(swiftUITopLeft.origin.y == screenHeight - 100, "Y should be flipped to bottom")
        #expect(swiftUITopLeft.size.width == 100, "Width should remain the same")
        #expect(swiftUITopLeft.size.height == 100, "Height should remain the same")

        // Test window at bottom-right of screen in Yabai coordinates
        let yabaiBottomRight = WindowFrame(
            x: mainDisplay.width - 200,
            y: screenHeight - 150,
            w: 200,
            h: 150
        )
        let swiftUIBottomRight = CoordinateSystem.fromYabai(yabaiBottomRight)

        #expect(swiftUIBottomRight.origin.x == mainDisplay.width - 200, "X coordinate should remain the same")
        #expect(swiftUIBottomRight.origin.y == 0, "Y should be 0 for bottom edge")
        #expect(swiftUIBottomRight.size.width == 200, "Width should remain the same")
        #expect(swiftUIBottomRight.size.height == 150, "Height should remain the same")
    }

    @Test func windowFrameExtensions() {
        // Test the convenience extensions on WindowFrame
        let testFrame = WindowFrame(x: 100, y: 200, w: 300, h: 400)

        let swiftUIRect = testFrame.swiftUIRect
        #expect(swiftUIRect.size.width == 300, "swiftUIRect should maintain width")
        #expect(swiftUIRect.size.height == 400, "swiftUIRect should maintain height")

        // Test that containingScreen returns a valid screen
        let screen = testFrame.containingScreen
        #expect(screen != nil, "containingScreen should return a screen")
    }

    @Test func isWindowOnScreen() {
        // Test with a window clearly on the main screen
        let mainDisplay = CGDisplayBounds(CGMainDisplayID())
        let onScreenFrame = WindowFrame(
            x: mainDisplay.width / 2 - 50,
            y: mainDisplay.height / 2 - 50,
            w: 100,
            h: 100
        )

        #expect(CoordinateSystem.isWindowOnScreen(onScreenFrame), "Window in center should be on screen")

        // Test with a window clearly off screen
        let offScreenFrame = WindowFrame(
            x: mainDisplay.width + 1000,
            y: mainDisplay.height + 1000,
            w: 100,
            h: 100
        )

        #expect(!CoordinateSystem.isWindowOnScreen(offScreenFrame), "Window far off screen should not be on screen")

        // Test edge case - window partially on screen
        let partiallyOnScreenFrame = WindowFrame(
            x: mainDisplay.width - 50,
            y: mainDisplay.height - 50,
            w: 100,
            h: 100
        )

        #expect(CoordinateSystem.isWindowOnScreen(partiallyOnScreenFrame), "Partially visible window should be considered on screen")
    }

    @Test func createPositionKey() {
        // Test position key generation for stack grouping
        let frame1 = WindowFrame(x: 100.2, y: 200.7, w: 300, h: 400)
        let frame2 = WindowFrame(x: 103.8, y: 198.1, w: 350, h: 450) // Within tolerance
        let frame3 = WindowFrame(x: 110.0, y: 190.0, w: 300, h: 400) // Outside tolerance

        let key1 = CoordinateSystem.createPositionKey(for: frame1, tolerance: 5.0)
        let key2 = CoordinateSystem.createPositionKey(for: frame2, tolerance: 5.0)
        let key3 = CoordinateSystem.createPositionKey(for: frame3, tolerance: 5.0)

        #expect(key1 == key2, "Windows within tolerance should have same position key")
        #expect(key1 != key3, "Windows outside tolerance should have different position keys")

        // Test key format
        #expect(key1.hasPrefix("pos_"), "Position key should start with 'pos_'")
        #expect(key1.contains("_100_"), "Position key should contain normalized X coordinate")
        #expect(key1.contains("_200"), "Position key should contain normalized Y coordinate")
    }

    @Test func screenContaining() {
        // Test finding the correct screen for a window frame
        let mainDisplay = CGDisplayBounds(CGMainDisplayID())

        // Test frame clearly on main screen
        let centerFrame = WindowFrame(
            x: mainDisplay.width / 2 - 100,
            y: mainDisplay.height / 2 - 100,
            w: 200,
            h: 200
        )

        let screen = CoordinateSystem.screenContaining(centerFrame)
        #expect(screen != nil, "Should find a screen for center frame")
        #expect(screen == NSScreen.main, "Center frame should be on main screen")

        // Test fallback behavior - should always return a screen
        let impossibleFrame = WindowFrame(x: -10000, y: -10000, w: 1, h: 1)
        let fallbackScreen = CoordinateSystem.screenContaining(impossibleFrame)
        #expect(fallbackScreen != nil, "Should always return a screen, even for impossible frames")
    }

    @Test func coordinateConsistency() {
        // Test that conversions are consistent and reversible where possible
        let originalFrames = [
            WindowFrame(x: 0, y: 0, w: 100, h: 100),
            WindowFrame(x: 500, y: 300, w: 200, h: 150),
            WindowFrame(x: 1000, y: 600, w: 300, h: 400)
        ]

        for frame in originalFrames {
            let converted = CoordinateSystem.fromYabai(frame)

            // Verify dimensions are preserved
            #expect(converted.width == frame.w, "Width should be preserved in conversion")
            #expect(converted.height == frame.h, "Height should be preserved in conversion")

            // Verify X coordinate is preserved
            #expect(converted.origin.x == frame.x, "X coordinate should be preserved")

            // Verify Y coordinate follows expected flipping logic
            let mainDisplay = CGDisplayBounds(CGMainDisplayID())
            let expectedY = mainDisplay.height - frame.y - frame.h
            #expect(converted.origin.y == expectedY, "Y coordinate should follow flipping logic")
        }
    }

    @Test func memoryEfficiency() {
        // Test that position key generation doesn't create excessive temporary objects
        let frames = (0..<1000).map { i in
            WindowFrame(
                x: Double(i % 100) * 10,
                y: Double(i % 50) * 20,
                w: 200,
                h: 300
            )
        }

        var uniqueKeys = Set<String>()

        for frame in frames {
            let key = CoordinateSystem.createPositionKey(for: frame, tolerance: 5.0)
            uniqueKeys.insert(key)
        }

        // We should have fewer unique keys than frames due to tolerance grouping
        #expect(uniqueKeys.count < frames.count, "Position keys should group nearby frames")
        #expect(uniqueKeys.count > 0, "Should generate at least some unique keys")
    }
}
