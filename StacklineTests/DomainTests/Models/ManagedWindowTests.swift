import XCTest
@testable import Stackline

final class ManagedWindowTests: XCTestCase {
    func testWindowEquality() {
        let window1 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        let window2 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        XCTAssertEqual(window1, window2)
    }

    func testWindowInequality() {
        let window1 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        let window2 = ManagedWindow(
            id: 2,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        XCTAssertNotEqual(window1, window2)
    }

    func testIsStackable_WhenAllConditionsMet() {
        let window = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        XCTAssertTrue(window.isStackable)
    }

    func testIsStackable_FalseWhenNotVisible() {
        let window = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: false,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        XCTAssertFalse(window.isStackable)
    }

    func testIsStackable_TrueWhenVisibleAndInStack() {
        // Windows with stackIndex > 0 that are visible should be stackable
        // regardless of isMinimized or isRootWindow
        let window = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 2,  // Not the root window in stack
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: false
        )

        XCTAssertTrue(window.isStackable)
    }

    func testIsStackable_TrueWhenStackIndexIsZero() {
        // stackIndex doesn't affect isStackable - only visibility, floating, minimized, fullscreen do
        let window = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 0,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        XCTAssertTrue(window.isStackable)
    }

    func testWindowHashing() {
        let window1 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        let window2 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Safari",
            title: "Test",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )

        var set: Set<ManagedWindow> = []
        set.insert(window1)
        set.insert(window2)

        XCTAssertEqual(set.count, 1)
    }
}
