import XCTest
import Combine
@testable import Stackline

/// Integration tests for the full stack detection flow
@MainActor
final class StackDetectionIntegrationTests: XCTestCase {
    var mockWindowManager: MockWindowManager!
    var mockCoordinateSystem: MockCoordinateSystem!
    var stackDetector: StackDetector!
    var preferences: UserDefaultsPreferences!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        mockWindowManager = MockWindowManager()
        mockCoordinateSystem = MockCoordinateSystem()

        let defaults = CachedUserDefaults(suiteName: "sh.mackie.stackline.integration.\(UUID().uuidString)")
        preferences = UserDefaultsPreferences(defaults: defaults)

        stackDetector = StackDetector(
            windowManager: mockWindowManager,
            coordinateSystem: mockCoordinateSystem
        )

        cancellables = Set<AnyCancellable>()
        try await mockWindowManager.connect()
    }

    override func tearDown() async throws {
        stackDetector.stopMonitoring()
        cancellables = nil
        preferences = nil
        stackDetector = nil
        mockCoordinateSystem = nil
        mockWindowManager = nil
        try await super.tearDown()
    }

    // MARK: - Integration Tests

    func testFullStackDetectionFlow() async throws {
        // Windows at same position form a multi-window stack
        // Window at different position forms a single-window stack
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100)
        let window3 = createWindow(id: 3, stackIndex: 1, x: 500, y: 500)

        await mockWindowManager.setWindows([window1, window2, window3])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 2)

        // Find the multi-window stack
        let multiWindowStack = stacks.first { $0.count == 2 }
        XCTAssertNotNil(multiWindowStack)
        XCTAssertTrue(multiWindowStack!.windows.contains { $0.id == 1 })
        XCTAssertTrue(multiWindowStack!.windows.contains { $0.id == 2 })

        // Find the single-window stack
        let singleWindowStack = stacks.first { $0.count == 1 }
        XCTAssertNotNil(singleWindowStack)
        XCTAssertTrue(singleWindowStack!.windows.contains { $0.id == 3 })
    }

    func testStackDetectionWithMultipleSpaces() async throws {
        let space1Window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100, spaceIndex: 1)
        let space1Window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100, spaceIndex: 1)
        let space2Window1 = createWindow(id: 3, stackIndex: 1, x: 100, y: 100, spaceIndex: 2)
        let space2Window2 = createWindow(id: 4, stackIndex: 2, x: 100, y: 100, spaceIndex: 2)

        await mockWindowManager.setWindows([space1Window1, space1Window2, space2Window1, space2Window2])

        let stacks = try await stackDetector.detectStacks()

        XCTAssertEqual(stacks.count, 2)

        let space1Stack = stacks.first { $0.spaceIndex == 1 }
        let space2Stack = stacks.first { $0.spaceIndex == 2 }

        XCTAssertNotNil(space1Stack)
        XCTAssertNotNil(space2Stack)
        XCTAssertEqual(space1Stack?.count, 2)
        XCTAssertEqual(space2Stack?.count, 2)
    }

    func testCoordinatorWithPreferences() async throws {
        let window1 = createWindow(id: 1, stackIndex: 1, x: 100, y: 100)
        let window2 = createWindow(id: 2, stackIndex: 2, x: 100, y: 100)
        await mockWindowManager.setWindows([window1, window2])

        _ = try await stackDetector.detectStacks()

        let coordinator = IndicatorCoordinator(
            stackDetector: stackDetector,
            windowManager: mockWindowManager,
            preferences: preferences,
            coordinateSystem: mockCoordinateSystem
        )

        XCTAssertNotNil(coordinator)
    }

    // MARK: - Helper Methods

    private func createWindow(
        id: Int,
        stackIndex: Int,
        x: CGFloat,
        y: CGFloat,
        spaceIndex: Int = 1
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: 100 + id,
            applicationName: "TestApp",
            title: "Window \(id)",
            frame: CGRect(x: x, y: y, width: 800, height: 600),
            spaceIndex: spaceIndex,
            displayIndex: 1,
            stackIndex: stackIndex,
            isVisible: true,
            isFocused: stackIndex == 1,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
    }
}
