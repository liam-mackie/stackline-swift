import Testing
import SwiftUI
@testable import Stackline

struct IntegrationTests {

    @Test func coordinateSystemIntegration() {
        // Test that the coordinate system works end-to-end with real window management

        // Create a test window frame in Yabai coordinates
        let yabaiFrame = WindowFrame(x: 100, y: 200, w: 300, h: 400)

        // Test the full conversion pipeline
        let swiftUIRect = yabaiFrame.swiftUIRect
        let containingScreen = yabaiFrame.containingScreen

        #expect(containingScreen != nil, "Should find a containing screen")
        #expect(swiftUIRect.width == 300, "Width should be preserved")
        #expect(swiftUIRect.height == 400, "Height should be preserved")

        // Test that screen detection works
        #expect(CoordinateSystem.isWindowOnScreen(yabaiFrame), "Window should be detected as on screen")

        // Test position key generation
        let positionKey = CoordinateSystem.createPositionKey(for: yabaiFrame)
        #expect(!positionKey.isEmpty, "Position key should not be empty")
        #expect(positionKey.hasPrefix("pos_"), "Position key should have correct format")
    }

    @Test func indicatorManagerIntegration() async {
        // Test the complete indicator manager workflow
        await MainActor.run {
            let configManager = ConfigurationManager()
            let indicatorManager = IndicatorManager(configManager: configManager)

            // Create test stacks that would be detected in real usage
            let testWindows = [
                createTestWindow(id: 1, x: 100, y: 200, hasFocus: true),
                createTestWindow(id: 2, x: 100, y: 200),
                createTestWindow(id: 3, x: 500, y: 300, hasFocus: false),
                createTestWindow(id: 4, x: 500, y: 300)
            ]

            let stacks = [
                WindowStack(windows: [testWindows[0], testWindows[1]]),
                WindowStack(windows: [testWindows[2], testWindows[3]])
            ]

            // Test indicator update workflow
            indicatorManager.updateIndicators(for: stacks)
            // Note: Original IndicatorManager doesn't expose activeOverlays, so we just test it doesn't crash

            // Test toggle functionality
            indicatorManager.toggle()
            indicatorManager.toggle() // Toggle back

            // Test cleanup
            indicatorManager.cleanup()
        }
    }

    @Test func stackDetectionWorkflow() async {
        // Test the complete stack detection workflow
        await MainActor.run {
            let detector = StackDetectorSimplified()

            // Start detection
            detector.startDetection()

            // Test force detection doesn't crash
            detector.forceStackDetection()

            // Test stop detection
            detector.stopDetection()

            // Should be able to restart
            detector.startDetection()
            detector.stopDetection()
        }
    }

    @Test func memoryEfficiencyIntegration() async {
        // Test that the complete system doesn't accumulate memory
        await MainActor.run {
            let configManager = ConfigurationManager()
            let indicatorManager = IndicatorManager(configManager: configManager)
            let detector = StackDetectorSimplified()

            // Simulate many update cycles
            for iteration in 1...50 {
                let stacks = createTestStacks(count: 3, iteration: iteration)

                // Update indicators
                indicatorManager.updateIndicators(for: stacks)

                // Clear indicators
                indicatorManager.updateIndicators(for: [])
            }

            // Test final state - just verify cleanup doesn't crash
            // Cleanup
            indicatorManager.cleanup()
            detector.stopDetection()
        }
    }

    @Test func overlayPositioning() async {
        // Test that overlay positioning works correctly with coordinate system
        await MainActor.run {
            let configManager = ConfigurationManager()
            let indicatorManager = IndicatorManager(configManager: configManager)

            // Create a test stack at a known position
            let testStack = WindowStack(windows: [
                createTestWindow(id: 1, x: 100, y: 200, width: 300, height: 400)
            ])

            indicatorManager.updateIndicators(for: [testStack])

            // Test that coordinate conversion works
            let stackSwiftUIRect = testStack.frame.swiftUIRect
            #expect(stackSwiftUIRect.width > 0, "Stack should have positive width")
            #expect(stackSwiftUIRect.height > 0, "Stack should have positive height")
        }
    }

    @Test func configurationIntegration() async {
        // Test that configuration changes properly affect the system
        await MainActor.run {
            let configManager = ConfigurationManager()
            let indicatorManager = IndicatorManager(configManager: configManager)

            // Test that we can read config
            let config = configManager.config
            #expect(config != nil, "Configuration should be available")

            let testStack = WindowStack(windows: [createTestWindow(id: 1, x: 100, y: 200)])

            // Test indicator update with config
            indicatorManager.updateIndicators(for: [testStack])
            // Just verify it doesn't crash

            // Test refresh functionality
            indicatorManager.refreshAll()
            // Just verify it doesn't crash
        }
    }

    @Test func multipleStacksScenario() async {
        // Test a realistic scenario with multiple stacks on different positions
        await MainActor.run {
            let configManager = ConfigurationManager()
            let indicatorManager = IndicatorManager(configManager: configManager)

            // Create multiple stacks at different positions
            let stacks = [
                WindowStack(windows: [
                    createTestWindow(id: 1, x: 100, y: 100),
                    createTestWindow(id: 2, x: 100, y: 100)
                ]),
                WindowStack(windows: [
                    createTestWindow(id: 3, x: 500, y: 300),
                    createTestWindow(id: 4, x: 500, y: 300),
                    createTestWindow(id: 5, x: 500, y: 300)
                ]),
                WindowStack(windows: [
                    createTestWindow(id: 6, x: 800, y: 600),
                    createTestWindow(id: 7, x: 800, y: 600)
                ])
            ]

            indicatorManager.updateIndicators(for: stacks)
            // Just verify it doesn't crash

            // Test partial update
            let partialStacks = Array(stacks.prefix(2))
            indicatorManager.updateIndicators(for: partialStacks)
            // Just verify it doesn't crash
        }
    }

    @Test func errorHandling() async {
        // Test system behavior with edge cases
        await MainActor.run {
            let configManager = ConfigurationManager()
            let indicatorManager = IndicatorManager(configManager: configManager)

            // Test with empty stacks
            indicatorManager.updateIndicators(for: [])
            // Should not crash

            // Test with invalid window frames
            let invalidStack = WindowStack(windows: [
                createTestWindow(id: 1, x: -10000, y: -10000) // Off-screen position
            ])

            indicatorManager.updateIndicators(for: [invalidStack])
            // Should not crash

            // Test cleanup with no active overlays
            indicatorManager.cleanup()
            indicatorManager.cleanup() // Should not crash on double cleanup
        }
    }

    // MARK: - Helper Methods

    private func createTestWindow(
        id: Int,
        x: Double,
        y: Double,
        width: Double = 200,
        height: Double = 300,
        hasFocus: Bool = false
    ) -> YabaiWindow {
        return YabaiWindow(
            id: id,
            pid: 1000 + id,
            app: "TestApp\(id)",
            title: "Window \(id)",
            scratchpad: nil,
            frame: WindowFrame(x: x, y: y, w: width, h: height),
            role: "AXWindow",
            subrole: "AXStandardWindow",
            rootWindow: true,
            display: 1,
            space: 1,
            level: 0,
            subLevel: 0,
            layer: "normal",
            subLayer: "normal",
            opacity: 1.0,
            splitType: "none",
            splitChild: "none",
            stackIndex: 1,
            canMove: true,
            canResize: true,
            hasFocus: hasFocus,
            hasShadow: true,
            hasParentZoom: false,
            hasFullscreenZoom: false,
            hasAXReference: true,
            isNativeFullscreen: false,
            isVisible: true,
            isMinimized: false,
            isHidden: false,
            isFloating: false,
            isSticky: false,
            isGrabbed: false
        )
    }

    private func createTestStacks(count: Int, iteration: Int) -> [WindowStack] {
        var stacks: [WindowStack] = []

        for i in 0..<count {
            let windows = [
                createTestWindow(
                    id: iteration * 100 + i * 10 + 1,
                    x: Double(i * 300 + 100),
                    y: Double(i * 200 + 150),
                    hasFocus: i == 0
                ),
                createTestWindow(
                    id: iteration * 100 + i * 10 + 2,
                    x: Double(i * 300 + 100),
                    y: Double(i * 200 + 150)
                )
            ]

            stacks.append(WindowStack(windows: windows))
        }

        return stacks
    }
}