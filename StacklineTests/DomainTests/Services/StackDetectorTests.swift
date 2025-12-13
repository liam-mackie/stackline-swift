import XCTest
@testable import Stackline

@MainActor
final class StackDetectorTests: XCTestCase {
    var mockWindowManager: MockWindowManager!
    var mockCoordinateSystem: MockCoordinateSystem!
    var stackDetector: StackDetector!

    override func setUp() async throws {
        try await super.setUp()
        mockWindowManager = MockWindowManager()
        mockCoordinateSystem = MockCoordinateSystem()
        stackDetector = StackDetector(
            windowManager: mockWindowManager,
            coordinateSystem: mockCoordinateSystem
        )
        try await mockWindowManager.connect()
    }

    override func tearDown() async throws {
        stackDetector.stopMonitoring()
        stackDetector = nil
        mockCoordinateSystem = nil
        mockWindowManager = nil
        try await super.tearDown()
    }

    // MARK: - Basic Detection Tests

    func testDetectStacksWithNoWindows() async throws {
        await mockWindowManager.setWindows([])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertTrue(stacks.isEmpty)
    }

    func testDetectStacksWithSingleWindow() async throws {
        // Single window creates a single-element stack (UI filters via showSingleWindowIndicators)
        let window = createWindow(id: 1, stackIndex: 1)
        await mockWindowManager.setWindows([window])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].count, 1)
    }

    func testDetectStacksWithTwoWindowsAtSamePosition() async throws {
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100)
        await mockWindowManager.setWindows([window1, window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].windows.count, 2)
    }

    func testDetectStacksWithWindowsAtDifferentPositions() async throws {
        // Two windows at different positions form two separate single-element stacks
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 1, x: 500, y: 500)
        await mockWindowManager.setWindows([window1, window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 2)
        XCTAssertTrue(stacks.allSatisfy { $0.count == 1 })
    }

    // MARK: - Position Tolerance Tests

    func testDetectStacksWithWindowsWithinTolerance() async throws {
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 103, y: 102)
        await mockWindowManager.setWindows([window1, window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 1)
    }

    func testDetectStacksWithWindowsOutsideTolerance() async throws {
        // Windows outside tolerance form separate stacks
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 110, y: 100)
        await mockWindowManager.setWindows([window1, window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 2)
        XCTAssertTrue(stacks.allSatisfy { $0.count == 1 })
    }

    // MARK: - Filter Tests

    func testDetectStacksFiltersNonStackableWindows() async throws {
        let stackable1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let stackable2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100)
        // Non-visible windows should be filtered out
        let notVisible = createWindow(id: 3, stackIndex: 3, x: 100, y: 100, isVisible: false)
        await mockWindowManager.setWindows([stackable1, stackable2, notVisible])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].windows.count, 2)
    }

    func testDetectStacksFiltersWindowsOffScreen() async throws {
        // Only on-screen windows form stacks; off-screen windows are filtered
        let onScreen = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let offScreen = createWindow(id: 2, stackIndex: 2, x: 5000, y: 5000)
        await mockWindowManager.setWindows([onScreen, offScreen])

        let stacks = try await stackDetector.detectStacks()

        // Only the on-screen window forms a stack
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].count, 1)
        XCTAssertEqual(stacks[0].windows[0].id, 1)
    }

    // MARK: - Space and Display Grouping Tests

    func testDetectStacksGroupsBySpace() async throws {
        let space1Window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100, spaceIndex: 1)
        let space1Window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100, spaceIndex: 1)
        let space2Window1 = createWindow(id: 3, stackIndex: 1, x: 100, y: 100, spaceIndex: 2)
        let space2Window2 = createWindow(id: 4, stackIndex: 2, x: 100, y: 100, spaceIndex: 2)
        await mockWindowManager.setWindows([space1Window1, space1Window2, space2Window1, space2Window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 2)
        XCTAssertTrue(stacks.allSatisfy { $0.windows.count == 2 })
    }

    func testDetectStacksGroupsByDisplay() async throws {
        let display1Window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100, displayIndex: 1)
        let display1Window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100, displayIndex: 1)
        let display2Window1 = createWindow(id: 3, stackIndex: 1, x: 100, y: 100, displayIndex: 2)
        let display2Window2 = createWindow(id: 4, stackIndex: 2, x: 100, y: 100, displayIndex: 2)
        await mockWindowManager.setWindows([display1Window1, display1Window2, display2Window1, display2Window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 2)
    }

    // MARK: - Focus Tracking Tests

    func testDetectStacksTracksFocusedWindow() async throws {
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100, isFocused: false)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100, isFocused: true)
        await mockWindowManager.setWindows([window1, window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].focusedWindow?.id, 2)
    }

    // MARK: - Stack Lookup Tests

    func testStackContainingWindow() async throws {
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100)
        await mockWindowManager.setWindows([window1, window2])

        _ = try await stackDetector.detectStacks()

        let stack = stackDetector.stack(containing: 1)

        XCTAssertNotNil(stack)
        XCTAssertTrue(stack!.windows.contains { $0.id == 1 })
    }

    func testStackContainingWindowNotFound() async throws {
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100)
        await mockWindowManager.setWindows([window1, window2])

        _ = try await stackDetector.detectStacks()

        let stack = stackDetector.stack(containing: 999)

        XCTAssertNil(stack)
    }

    // MARK: - Helper Methods

    private func createWindow(
        id: Int,
        stackIndex: Int,
        x: CGFloat = 100,
        y: CGFloat = 100,
        width: CGFloat = 800,
        height: CGFloat = 600,
        spaceIndex: Int = 1,
        displayIndex: Int = 1,
        isVisible: Bool = true,
        isFocused: Bool = false,
        isMinimized: Bool = false,
        isRootWindow: Bool = true
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: 100 + id,
            applicationName: "TestApp",
            title: "Window \(id)",
            frame: CGRect(x: x, y: y, width: width, height: height),
            spaceIndex: spaceIndex,
            displayIndex: displayIndex,
            stackIndex: stackIndex,
            isVisible: isVisible,
            isFocused: isFocused,
            isFloating: false,
            isMinimized: isMinimized,
            isFullscreen: false,
            isRootWindow: isRootWindow
        )
    }
}
