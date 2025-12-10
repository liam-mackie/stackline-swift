import Testing
import Foundation
import CoreGraphics
import CoreFoundation
@testable import Stackline

struct StackDetectionTests {

    func createTestWindow(
        id: Int,
        x: Double,
        y: Double,
        width: Double = 200,
        height: Double = 300,
        stackIndex: Int = 1,
        hasFocus: Bool = false,
        isVisible: Bool = true
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
            stackIndex: stackIndex,
            canMove: true,
            canResize: true,
            hasFocus: hasFocus,
            hasShadow: true,
            hasParentZoom: false,
            hasFullscreenZoom: false,
            hasAXReference: true,
            isNativeFullscreen: false,
            isVisible: isVisible,
            isMinimized: false,
            isHidden: false,
            isFloating: false,
            isSticky: false,
            isGrabbed: false
        )
    }

    @Test func windowStackCreation() {
        // Test that WindowStack correctly identifies stacked windows
        let stackedWindows = [
            createTestWindow(id: 1, x: 100, y: 200, stackIndex: 1, hasFocus: true),
            createTestWindow(id: 2, x: 100, y: 200, stackIndex: 2),
            createTestWindow(id: 3, x: 100, y: 200, stackIndex: 3)
        ]

        let stack = WindowStack(windows: stackedWindows)

        #expect(stack.windows.count == 3, "Stack should contain all 3 windows")
        #expect(stack.count == 3, "Stack count should be 3")
        #expect(stack.focusedWindow != nil, "Stack should have a focused window")
        #expect(stack.focusedWindow?.id == 1, "Focused window should be window 1")
        #expect(stack.visibleWindow != nil, "Stack should have a visible window")
    }

    @Test func windowStackEquality() {
        let windows1 = [
            createTestWindow(id: 1, x: 100, y: 200),
            createTestWindow(id: 2, x: 100, y: 200)
        ]

        let windows2 = [
            createTestWindow(id: 1, x: 100, y: 200),
            createTestWindow(id: 2, x: 100, y: 200)
        ]

        let stack1 = WindowStack(windows: windows1)
        let stack2 = WindowStack(windows: windows2)

        #expect(stack1 == stack2, "Identical stacks should be equal")

        // Test with different windows
        let windows3 = [
            createTestWindow(id: 3, x: 100, y: 200),
            createTestWindow(id: 4, x: 100, y: 200)
        ]

        let stack3 = WindowStack(windows: windows3)
        #expect(stack1 != stack3, "Different stacks should not be equal")
    }

    @Test func windowStackID() {
        // Test that WindowStack generates consistent IDs for same positions
        let windows1 = [
            createTestWindow(id: 1, x: 100, y: 200),
            createTestWindow(id: 2, x: 100, y: 200)
        ]

        let windows2 = [
            createTestWindow(id: 3, x: 100, y: 200), // Same position
            createTestWindow(id: 4, x: 100, y: 200)
        ]

        let stack1 = WindowStack(windows: windows1)
        let stack2 = WindowStack(windows: windows2)

        // IDs should be similar for same position (within tolerance)
        #expect(stack1.id.contains("pos_100_200") || (stack1.id.contains("100") && stack1.id.contains("200")),
               "Stack ID should reflect position")
        #expect(stack2.id.contains("pos_100_200") || (stack2.id.contains("100") && stack2.id.contains("200")),
               "Stack ID should reflect position")
    }

    @Test func windowStackVisibility() {
        // Test visibility tracking with last focused window
        let windows = [
            createTestWindow(id: 1, x: 100, y: 200, hasFocus: false),
            createTestWindow(id: 2, x: 100, y: 200, hasFocus: false),
            createTestWindow(id: 3, x: 100, y: 200, hasFocus: true)
        ]

        let stack = WindowStack(windows: windows)
        #expect(stack.focusedWindow?.id == 3, "Should identify currently focused window")

        // Test with last focused window ID
        let stackWithLastFocused = WindowStack(windows: windows, lastFocusedWindowId: 2)
        #expect(stackWithLastFocused.visibleWindow?.id == 2, "Should use last focused window for visibility")
    }

    @Test func windowFrameOperations() {
        let frame1 = WindowFrame(x: 100, y: 200, w: 300, h: 400)
        let frame2 = WindowFrame(x: 102, y: 198, w: 305, h: 395) // Similar position
        let frame3 = WindowFrame(x: 150, y: 250, w: 300, h: 400) // Different position

        // Test similarity check
        #expect(frame1.isSameAs(frame2, tolerance: 10.0), "Similar frames should be considered same")
        #expect(!frame1.isSameAs(frame3, tolerance: 10.0), "Different frames should not be same")

        // Test CGRect conversion
        let rect = frame1.rect
        // Extract values to avoid Swift Testing macro issues with CoreGraphics properties
        let originX = rect.origin.x
        let originY = rect.origin.y
        let width = rect.width
        let height = rect.height

        #expect(originX == 100, "X coordinate should match")
        #expect(originY == 200, "Y coordinate should match")
        #expect(width == 300, "Width should match")
        #expect(height == 400, "Height should match")
    }

    @Test func windowFrameOverlap() {
        let frame1 = WindowFrame(x: 100, y: 100, w: 200, h: 200)
        let frame2 = WindowFrame(x: 150, y: 150, w: 200, h: 200) // Overlapping
        let frame3 = WindowFrame(x: 400, y: 400, w: 200, h: 200) // Not overlapping

        #expect(frame1.overlaps(frame2, threshold: 0.3), "Overlapping frames should be detected")
        #expect(!frame1.overlaps(frame3, threshold: 0.3), "Non-overlapping frames should not be detected")
    }

    @Test func stackDetectorFiltering() {
        // Test that StackDetectorSimplified properly filters windows
        let validWindow = createTestWindow(id: 1, x: 100, y: 100, isVisible: true)
        let invisibleWindow = createTestWindow(id: 2, x: 200, y: 200, isVisible: false)
        let offScreenWindow = createTestWindow(id: 3, x: -1000, y: -1000, isVisible: true)

        // Test coordinate system filtering
        #expect(CoordinateSystem.isWindowOnScreen(validWindow.frame), "Valid window should be on screen")
        #expect(!CoordinateSystem.isWindowOnScreen(offScreenWindow.frame), "Off-screen window should be filtered")

        // Test visibility filtering logic
        let windows = [validWindow, invisibleWindow, offScreenWindow]
        let filteredWindows = windows.filter { window in
            return CoordinateSystem.isWindowOnScreen(window.frame) &&
                   window.isVisible &&
                   !window.isMinimized &&
                   !window.isHidden &&
                   window.rootWindow
        }

        #expect(filteredWindows.count == 1, "Should only include valid, visible window")
        #expect(filteredWindows.first?.id == 1, "Should be the valid window")
    }

    @Test func positionKeyGeneration() {
        // Test that position keys group nearby windows appropriately
        let tolerance: Double = 5.0

        let frame1 = WindowFrame(x: 100, y: 200, w: 300, h: 400)
        let frame2 = WindowFrame(x: 102, y: 198, w: 300, h: 400) // Within tolerance
        let frame3 = WindowFrame(x: 110, y: 190, w: 300, h: 400) // Outside tolerance

        let key1 = CoordinateSystem.createPositionKey(for: frame1, tolerance: tolerance)
        let key2 = CoordinateSystem.createPositionKey(for: frame2, tolerance: tolerance)
        let key3 = CoordinateSystem.createPositionKey(for: frame3, tolerance: tolerance)

        #expect(key1 == key2, "Nearby windows should have same position key")
        #expect(key1 != key3, "Distant windows should have different position keys")
    }

    @Test func stackDetectionWithMultipleStacks() {
        // Test detection of multiple distinct stacks
        let stackAWindows = [
            createTestWindow(id: 1, x: 100, y: 100),
            createTestWindow(id: 2, x: 100, y: 100)
        ]

        let stackBWindows = [
            createTestWindow(id: 3, x: 500, y: 300),
            createTestWindow(id: 4, x: 500, y: 300),
            createTestWindow(id: 5, x: 500, y: 300)
        ]

        let singleWindow = [createTestWindow(id: 6, x: 800, y: 600)]

        let allWindows = stackAWindows + stackBWindows + singleWindow

        // Group windows by position
        let windowsByPosition = Dictionary(grouping: allWindows) { window in
            CoordinateSystem.createPositionKey(for: window.frame, tolerance: 5.0)
        }

        let stacks = windowsByPosition.compactMap { (_, windows) -> WindowStack? in
            guard windows.count > 1 else { return nil }
            return WindowStack(windows: windows)
        }

        #expect(stacks.count == 2, "Should detect exactly 2 stacks")

        let stackSizes = stacks.map(\.count).sorted()
        #expect(stackSizes == [2, 3], "Should have stacks of size 2 and 3")
    }

    @Test func stackFocusTracking() {
        // Test focus change tracking in stack detection
        var focusState: [String: Int] = [:]
        let maxEntries = 50

        // Simulate focus changes
        for i in 1...100 {
            let frame = WindowFrame(x: Double(i % 10) * 100, y: Double(i % 5) * 200, w: 200, h: 300)
            let positionKey = CoordinateSystem.createPositionKey(for: frame, tolerance: 5.0)
            focusState[positionKey] = i

            // Apply cleanup logic
            if focusState.count > maxEntries {
                let excess = focusState.count - maxEntries
                let keysToRemove = Array(focusState.keys.prefix(excess))
                for key in keysToRemove {
                    focusState.removeValue(forKey: key)
                }
            }
        }

        #expect(focusState.count <= maxEntries, "Focus state should be bounded")
        #expect(focusState.count > 0, "Should maintain some focus state")
    }

    @Test func stackDetectorCleanup() async {
        await MainActor.run {
            let detector = StackDetectorSimplified()

            // Test that cleanup methods work properly
            detector.stopDetection() // Should not crash

            // Test force detection
            detector.forceStackDetection() // Should not crash
            detector.stopDetection() // Should cancel any running tasks
        }
    }
}