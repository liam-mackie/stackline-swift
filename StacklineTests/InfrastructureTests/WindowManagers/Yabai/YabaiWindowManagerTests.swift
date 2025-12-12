import XCTest
@testable import Stackline

final class YabaiWindowManagerTests: XCTestCase {
    var mockExecutor: MockYabaiCommandExecutor!
    var windowManager: YabaiWindowManager!

    override func setUp() {
        super.setUp()
        mockExecutor = MockYabaiCommandExecutor()
        windowManager = YabaiWindowManager(executor: mockExecutor)
    }

    override func tearDown() {
        mockExecutor = nil
        windowManager = nil
        super.tearDown()
    }

    // MARK: - Connection Tests

    func testConnectWhenYabaiAvailable() async throws {
        mockExecutor.available = true

        try await windowManager.connect()

        let connected = await windowManager.isConnected
        XCTAssertTrue(connected)
    }

    func testConnectWhenYabaiUnavailable() async {
        mockExecutor.available = false

        do {
            try await windowManager.connect()
            XCTFail("Expected connection to fail")
        } catch let error as WindowManagerError {
            if case .connectionFailed(let message) = error {
                XCTAssertTrue(message.contains("not running"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDisconnect() async throws {
        mockExecutor.available = true
        try await windowManager.connect()
        let connectedBefore = await windowManager.isConnected
        XCTAssertTrue(connectedBefore)

        await windowManager.disconnect()

        let connectedAfter = await windowManager.isConnected
        XCTAssertFalse(connectedAfter)
    }

    // MARK: - Query Tests

    func testQueryWindowsWhenNotConnected() async {
        do {
            _ = try await windowManager.queryWindows()
            XCTFail("Expected notConnected error")
        } catch let error as WindowManagerError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQueryWindowsReturnsWindows() async throws {
        mockExecutor.available = true
        try await windowManager.connect()

        let yabaiWindows = [createYabaiWindow(id: 1), createYabaiWindow(id: 2)]
        mockExecutor.setQueryResponse(yabaiWindows, for: ["-m", "query", "--windows"])

        let windows = try await windowManager.queryWindows()

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].id, 1)
        XCTAssertEqual(windows[1].id, 2)
    }

    func testQuerySpacesReturnsSpaces() async throws {
        mockExecutor.available = true
        try await windowManager.connect()

        let yabaiSpaces = [createYabaiSpace(id: 1, index: 1), createYabaiSpace(id: 2, index: 2)]
        mockExecutor.setQueryResponse(yabaiSpaces, for: ["-m", "query", "--spaces"])

        let spaces = try await windowManager.querySpaces()

        XCTAssertEqual(spaces.count, 2)
        XCTAssertEqual(spaces[0].index, 1)
        XCTAssertEqual(spaces[1].index, 2)
    }

    func testQueryDisplaysReturnsDisplays() async throws {
        mockExecutor.available = true
        try await windowManager.connect()

        let yabaiDisplays = [createYabaiDisplay(id: 1, index: 1)]
        mockExecutor.setQueryResponse(yabaiDisplays, for: ["-m", "query", "--displays"])

        let displays = try await windowManager.queryDisplays()

        XCTAssertEqual(displays.count, 1)
        XCTAssertEqual(displays[0].index, 1)
    }

    // MARK: - Focus Window Tests

    func testFocusWindowWhenNotConnected() async {
        do {
            try await windowManager.focusWindow(123)
            XCTFail("Expected notConnected error")
        } catch let error as WindowManagerError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFocusWindowSuccess() async throws {
        mockExecutor.available = true
        try await windowManager.connect()

        try await windowManager.focusWindow(123)

        XCTAssertTrue(mockExecutor.executedCommands.contains { $0.contains("--focus") && $0.contains("123") })
    }

    func testFocusWindowNotFound() async throws {
        mockExecutor.available = true
        try await windowManager.connect()
        mockExecutor.errorToThrow = .executionFailed("could not locate window")

        do {
            try await windowManager.focusWindow(999)
            XCTFail("Expected windowNotFound error")
        } catch let error as WindowManagerError {
            if case .windowNotFound(let id) = error {
                XCTAssertEqual(id, 999)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helper Methods

    private func createYabaiWindow(
        id: Int,
        app: String = "TestApp",
        title: String = "Test Window",
        stackIndex: Int = 1,
        hasFocus: Bool = false
    ) -> YabaiWindow {
        YabaiWindow(
            id: id,
            pid: 100 + id,
            app: app,
            title: title,
            frame: YabaiFrame(x: 0, y: 0, w: 800, h: 600),
            role: "AXWindow",
            subrole: "AXStandardWindow",
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
            hasParentZoom: false,
            hasShadow: true,
            hasFullscreenZoom: false,
            hasAxReference: true,
            isNativeFullscreen: false,
            isVisible: true,
            isMinimized: false,
            isHidden: false,
            isFloating: false,
            isSticky: false,
            isGrabbed: false
        )
    }

    private func createYabaiSpace(id: Int, index: Int) -> YabaiSpace {
        YabaiSpace(
            id: id,
            uuid: "uuid-\(id)",
            index: index,
            label: "",
            type: "bsp",
            display: 1,
            windows: [],
            firstWindow: 0,
            lastWindow: 0,
            hasFocus: index == 1,
            isVisible: true,
            isNativeFullscreen: false
        )
    }

    private func createYabaiDisplay(id: Int, index: Int) -> YabaiDisplay {
        YabaiDisplay(
            id: id,
            uuid: "display-\(id)",
            index: index,
            label: "Display \(index)",
            frame: YabaiFrame(x: 0, y: 0, w: 2560, h: 1440),
            spaces: [1, 2],
            hasFocus: true
        )
    }
}
