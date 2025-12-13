import XCTest
@testable import Stackline

final class WindowCacheTests: XCTestCase {
    var cache: WindowCache!

    override func setUp() async throws {
        try await super.setUp()
        cache = WindowCache()
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    // MARK: - Basic Operations

    func testPopulateAndRetrieve() async {
        let windows = [createWindow(id: 1), createWindow(id: 2)]

        await cache.populate(with: windows)
        let retrieved = await cache.allWindows()

        XCTAssertEqual(retrieved.count, 2)
    }

    func testGetSpecificWindow() async {
        let windows = [createWindow(id: 1), createWindow(id: 2)]
        await cache.populate(with: windows)

        let window = await cache.window(for: 1)

        XCTAssertNotNil(window)
        XCTAssertEqual(window?.id, 1)
    }

    func testGetNonExistentWindow() async {
        let windows = [createWindow(id: 1)]
        await cache.populate(with: windows)

        let window = await cache.window(for: 999)

        XCTAssertNil(window)
    }

    // MARK: - Focus Updates

    func testUpdateFocusedWindow() async {
        let windows = [
            createWindow(id: 1, isFocused: true),
            createWindow(id: 2, isFocused: false)
        ]
        await cache.populate(with: windows)

        await cache.updateFocused(windowId: 2)
        let retrieved = await cache.allWindows()

        let window1 = retrieved.first { $0.id == 1 }
        let window2 = retrieved.first { $0.id == 2 }

        XCTAssertFalse(window1?.isFocused ?? true)
        XCTAssertTrue(window2?.isFocused ?? false)
    }

    func testUpdateFocusedClearsOtherFocused() async {
        let windows = [
            createWindow(id: 1, isFocused: true),
            createWindow(id: 2, isFocused: true),
            createWindow(id: 3, isFocused: false)
        ]
        await cache.populate(with: windows)

        await cache.updateFocused(windowId: 3)
        let retrieved = await cache.allWindows()

        let focusedWindows = retrieved.filter { $0.isFocused }
        XCTAssertEqual(focusedWindows.count, 1)
        XCTAssertEqual(focusedWindows.first?.id, 3)
    }

    func testUpdateFocusedWithNonExistentWindow() async {
        let windows = [
            createWindow(id: 1, isFocused: true)
        ]
        await cache.populate(with: windows)

        await cache.updateFocused(windowId: 999)
        let retrieved = await cache.allWindows()

        let window1 = retrieved.first { $0.id == 1 }
        XCTAssertFalse(window1?.isFocused ?? true)
    }

    // MARK: - Remove Operations

    func testRemoveWindow() async {
        let windows = [createWindow(id: 1), createWindow(id: 2)]
        await cache.populate(with: windows)

        await cache.remove(windowId: 1)
        let retrieved = await cache.allWindows()

        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.id, 2)
    }

    func testRemoveNonExistentWindow() async {
        let windows = [createWindow(id: 1)]
        await cache.populate(with: windows)

        await cache.remove(windowId: 999)
        let retrieved = await cache.allWindows()

        XCTAssertEqual(retrieved.count, 1)
    }

    // MARK: - Dirty State

    func testMarkDirty() async {
        let windows = [createWindow(id: 1)]
        await cache.populate(with: windows)

        let beforeDirty = await cache.needsRefresh(maxAge: 100)
        XCTAssertFalse(beforeDirty)

        await cache.markDirty()

        let afterDirty = await cache.needsRefresh(maxAge: 100)
        XCTAssertTrue(afterDirty)
    }

    func testPopulateClearsDirty() async {
        let windows = [createWindow(id: 1)]
        await cache.populate(with: windows)
        await cache.markDirty()

        let isDirty = await cache.needsRefresh(maxAge: 100)
        XCTAssertTrue(isDirty)

        await cache.populate(with: windows)

        let isClean = await cache.needsRefresh(maxAge: 100)
        XCTAssertFalse(isClean)
    }

    // MARK: - Helper Properties

    func testIsEmpty() async {
        let emptyBefore = await cache.isEmpty
        XCTAssertTrue(emptyBefore)

        await cache.populate(with: [createWindow(id: 1)])

        let emptyAfter = await cache.isEmpty
        XCTAssertFalse(emptyAfter)
    }

    func testCount() async {
        let countBefore = await cache.count
        XCTAssertEqual(countBefore, 0)

        await cache.populate(with: [createWindow(id: 1), createWindow(id: 2)])

        let countAfter = await cache.count
        XCTAssertEqual(countAfter, 2)
    }

    // MARK: - Helper Methods

    private func createWindow(id: Int, isFocused: Bool = false) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: 100 + id,
            applicationName: "TestApp",
            title: "Window \(id)",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: isFocused,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
    }
}
