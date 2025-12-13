import XCTest
@testable import Stackline

final class WindowStackTests: XCTestCase {
    private func makeWindow(
        id: Int,
        stackIndex: Int,
        frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
        spaceIndex: Int = 1,
        isFocused: Bool = false
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: 100,
            applicationName: "TestApp",
            title: "Window \(id)",
            frame: frame,
            spaceIndex: spaceIndex,
            displayIndex: 1,
            stackIndex: stackIndex,
            isVisible: true,
            isFocused: isFocused,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
    }

    func testStackCreation() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.spaceIndex, 1)
        XCTAssertEqual(stack.displayIndex, 1)
    }

    func testStackSortsWindowsByStackIndex() {
        let windows = [
            makeWindow(id: 1, stackIndex: 3),
            makeWindow(id: 2, stackIndex: 1),
            makeWindow(id: 3, stackIndex: 2),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack.windows[0].stackIndex, 1)
        XCTAssertEqual(stack.windows[1].stackIndex, 2)
        XCTAssertEqual(stack.windows[2].stackIndex, 3)
    }

    func testStackIdIsStable() {
        let windows1 = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let windows2 = [
            makeWindow(id: 3, stackIndex: 1),
            makeWindow(id: 4, stackIndex: 2),
        ]

        let stack1 = WindowStack(windows: windows1, displayIndex: 1)
        let stack2 = WindowStack(windows: windows2, displayIndex: 1)

        XCTAssertEqual(stack1.id, stack2.id)
    }

    func testStackIdDiffersForDifferentPositions() {
        let windows1 = [
            makeWindow(id: 1, stackIndex: 1, frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
        ]

        let windows2 = [
            makeWindow(id: 2, stackIndex: 1, frame: CGRect(x: 500, y: 100, width: 800, height: 600)),
        ]

        let stack1 = WindowStack(windows: windows1, displayIndex: 1)
        let stack2 = WindowStack(windows: windows2, displayIndex: 1)

        XCTAssertNotEqual(stack1.id, stack2.id)
    }

    func testStackIdDiffersForDifferentSpaces() {
        let windows1 = [
            makeWindow(id: 1, stackIndex: 1, spaceIndex: 1),
        ]

        let windows2 = [
            makeWindow(id: 2, stackIndex: 1, spaceIndex: 2),
        ]

        let stack1 = WindowStack(windows: windows1, displayIndex: 1)
        let stack2 = WindowStack(windows: windows2, displayIndex: 1)

        XCTAssertNotEqual(stack1.id, stack2.id)
    }

    func testFocusedWindowReturnsFocusedWindow() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1, isFocused: false),
            makeWindow(id: 2, stackIndex: 2, isFocused: true),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack.focusedWindow?.id, 2)
    }

    func testFocusedWindowReturnsTrackedWindow() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1, isFocused: false),
            makeWindow(id: 2, stackIndex: 2, isFocused: false),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1, focusedWindowId: 2)

        XCTAssertEqual(stack.focusedWindow?.id, 2)
    }

    func testFocusedWindowFallsBackToFirstWindow() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1, isFocused: false),
            makeWindow(id: 2, stackIndex: 2, isFocused: false),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack.focusedWindow?.id, 1)
    }

    func testWindowAtIndex() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack.window(at: 0)?.id, 1)
        XCTAssertEqual(stack.window(at: 1)?.id, 2)
        XCTAssertNil(stack.window(at: 2))
        XCTAssertNil(stack.window(at: -1))
    }

    func testIndexOfWindow() {
        let windows = [
            makeWindow(id: 1, stackIndex: 2),
            makeWindow(id: 2, stackIndex: 1),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack.index(of: 2), 0)
        XCTAssertEqual(stack.index(of: 1), 1)
        XCTAssertNil(stack.index(of: 99))
    }

    func testWithFocusedWindow() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let stack = WindowStack(windows: windows, displayIndex: 1)
        let updatedStack = stack.withFocusedWindow(1)

        XCTAssertEqual(updatedStack.focusedWindowId, 1)
        XCTAssertEqual(updatedStack.focusedWindow?.id, 1)
    }

    func testStackEquality() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let stack1 = WindowStack(windows: windows, displayIndex: 1)
        let stack2 = WindowStack(windows: windows, displayIndex: 1)

        XCTAssertEqual(stack1, stack2)
    }

    func testStackInequalityWithDifferentWindows() {
        let windows1 = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let windows2 = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 3, stackIndex: 2),
        ]

        let stack1 = WindowStack(windows: windows1, displayIndex: 1)
        let stack2 = WindowStack(windows: windows2, displayIndex: 1)

        XCTAssertNotEqual(stack1, stack2)
    }

    func testStackInequalityWithDifferentFocusedWindow() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let stack1 = WindowStack(windows: windows, displayIndex: 1, focusedWindowId: 1)
        let stack2 = WindowStack(windows: windows, displayIndex: 1, focusedWindowId: 2)

        XCTAssertNotEqual(stack1, stack2)
    }

    func testStackHashing() {
        let windows = [
            makeWindow(id: 1, stackIndex: 1),
            makeWindow(id: 2, stackIndex: 2),
        ]

        let stack1 = WindowStack(windows: windows, displayIndex: 1)
        let stack2 = WindowStack(windows: windows, displayIndex: 1)

        var set: Set<WindowStack> = []
        set.insert(stack1)
        set.insert(stack2)

        XCTAssertEqual(set.count, 1)
    }
}
