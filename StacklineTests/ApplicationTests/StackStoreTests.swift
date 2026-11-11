import XCTest
@testable import Stackline

@MainActor
final class StackStoreTests: XCTestCase {
    private var windowManager: FakeWindowManager!
    private var systemEvents: AsyncStream<SystemEvent>.Continuation!
    private var store: StackStore!
    private var running: Task<Void, Never>!

    private let tile = CGRect(x: 100, y: 100, width: 800, height: 600)
    private var otherTile: CGRect { tile.offsetBy(dx: 900, dy: 0) }

    override func setUp() async throws {
        windowManager = FakeWindowManager()
        let (stream, continuation) = AsyncStream.makeStream(of: SystemEvent.self)
        systemEvents = continuation

        store = StackStore(
            windowManager: windowManager,
            systemEvents: stream,
            displays: { .single },
            settleDelays: [.milliseconds(20), .milliseconds(20)]
        )
        running = Task { [store] in await store!.run() }
    }

    override func tearDown() async throws {
        windowManager.releaseQueries()
        running.cancel()
        await running.value
    }

    private func stackedPair(focused: WindowIdentifier? = nil) -> [ManagedWindow] {
        [
            .make(id: 1, frame: tile, stackIndex: 1, isFocused: focused == 1),
            .make(id: 2, frame: tile, stackIndex: 2, isFocused: focused == 2),
        ]
    }

    private func waitForStacks(
        _ expected: [[WindowIdentifier]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let matched = await waitUntil { self.store.stacks.map { $0.windows.map(\.id) } == expected }
        XCTAssertTrue(matched, "Expected stacks \(expected), got \(store.stacks.map { $0.windows.map(\.id) })", file: file, line: line)
    }

    // MARK: - Connection

    func testShowsNothingUntilTheWindowManagerConnects() async {
        windowManager.setWindows(stackedPair())

        windowManager.send(.windowsChanged)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(store.connection, .waiting)
        XCTAssertEqual(store.stacks, [])
        XCTAssertEqual(windowManager.queryCount, 0)
    }

    func testLoadsStacksOnConnecting() async {
        windowManager.setWindows(stackedPair())

        windowManager.send(.connected)

        await waitForStacks([[1, 2]])
        XCTAssertEqual(store.connection, .connected)
    }

    func testClearsStacksWhenTheWindowManagerGoesAwayAndReloadsWhenItReturns() async {
        windowManager.setWindows(stackedPair())
        windowManager.send(.connected)
        await waitForStacks([[1, 2]])

        windowManager.send(.disconnected)
        await waitForStacks([])
        XCTAssertEqual(store.connection, .waiting)

        // After a restart yabai has re-tiled everything: the old stack is gone.
        windowManager.setWindows([.make(id: 1, frame: tile), .make(id: 2, frame: otherTile)])
        windowManager.send(.connected)
        await waitForStacks([[1], [2]])
    }

    func testAResultThatArrivesAfterDisconnectingIsDiscarded() async {
        windowManager.setWindows(stackedPair())
        windowManager.holdQueries()
        windowManager.send(.connected)
        let querying = await waitUntil { self.windowManager.queryCount == 1 }
        XCTAssertTrue(querying)

        windowManager.send(.disconnected)
        let disconnected = await waitUntil { self.store.connection == .waiting }
        XCTAssertTrue(disconnected)
        windowManager.releaseQueries()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(store.stacks, [])
    }

    // MARK: - Refreshing

    func testWindowEventsRefreshTheStacks() async {
        windowManager.setWindows(stackedPair())
        windowManager.send(.connected)
        await waitForStacks([[1, 2]])

        windowManager.setWindows(stackedPair() + [.make(id: 3, frame: tile, stackIndex: 3)])
        windowManager.send(.windowsChanged)

        await waitForStacks([[1, 2, 3]])
    }

    func testABurstOfEventsCostsOneMoreQueryNotOnePerEvent() async {
        windowManager.setWindows(stackedPair())
        windowManager.holdQueries()
        windowManager.send(.connected)
        let querying = await waitUntil { self.windowManager.queryCount == 1 }
        XCTAssertTrue(querying)

        for _ in 0..<50 {
            windowManager.send(.windowsChanged)
        }
        // Give the store time to take in the whole burst while the first query is still out.
        try? await Task.sleep(for: .milliseconds(50))
        windowManager.releaseQueries()

        let settled = await waitUntil { self.windowManager.queryCount == 2 }
        XCTAssertTrue(settled)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(windowManager.queryCount, 2)
    }

    func testKeepsTheLastKnownStacksWhenAQueryFails() async {
        windowManager.setWindows(stackedPair())
        windowManager.send(.connected)
        await waitForStacks([[1, 2]])

        windowManager.setFailure(.timedOut)
        windowManager.send(.windowsChanged)
        let queried = await waitUntil { self.windowManager.queryCount == 2 }
        XCTAssertTrue(queried)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.stacks.map { $0.windows.map(\.id) }, [[1, 2]])

        // …and recovers with the next event.
        windowManager.setFailure(nil)
        windowManager.setWindows([.make(id: 1, frame: tile)])
        windowManager.send(.windowsChanged)
        await waitForStacks([[1]])
    }

    // MARK: - System events

    func testKeepsRefreshingAfterADisplayChangeUntilTheLayoutSettles() async {
        windowManager.setWindows(stackedPair())
        windowManager.send(.connected)
        await waitForStacks([[1, 2]])
        let queriesBefore = windowManager.queryCount

        systemEvents.yield(.displaysChanged)
        // yabai re-tiles a moment later without telling anyone.
        let refreshed = await waitUntil { self.windowManager.queryCount > queriesBefore }
        XCTAssertTrue(refreshed)
        windowManager.setWindows([.make(id: 1, frame: tile), .make(id: 2, frame: otherTile)])

        await waitForStacks([[1], [2]])
        let settled = await waitUntil { self.windowManager.queryCount == queriesBefore + 3 }
        XCTAssertTrue(settled)
    }

    func testWindowManagerDisplayEventsAlsoSettle() async {
        windowManager.setWindows(stackedPair())
        windowManager.send(.connected)
        await waitForStacks([[1, 2]])
        let queriesBefore = windowManager.queryCount

        windowManager.send(.displaysChanged)

        let settled = await waitUntil { self.windowManager.queryCount == queriesBefore + 3 }
        XCTAssertTrue(settled)
    }

    func testSpaceChangeRefreshes() async {
        windowManager.setWindows(stackedPair())
        windowManager.send(.connected)
        await waitForStacks([[1, 2]])

        windowManager.setWindows([.make(id: 5, frame: tile, space: 2), .make(id: 6, frame: tile, space: 2)])
        systemEvents.yield(.spaceChanged)

        await waitForStacks([[5, 6]])
    }

    // MARK: - Top window

    func testRemembersWhichWindowIsOnTopOfAStackThatLostFocus() async {
        windowManager.setWindows(stackedPair(focused: 2) + [.make(id: 9, frame: otherTile)])
        windowManager.send(.connected)
        await waitForStacks([[1, 2], [9]])
        XCTAssertEqual(store.stacks.first?.focusedWindowId, 2)

        windowManager.setWindows(stackedPair() + [.make(id: 9, frame: otherTile, isFocused: true)])
        windowManager.send(.windowFocused(9))

        let moved = await waitUntil { self.store.stacks.last?.focusedWindowId == 9 }
        XCTAssertTrue(moved)
        XCTAssertEqual(store.stacks.first?.focusedWindowId, 2)
    }

    /// Two focus changes in quick succession collapse into one query, which only sees the
    /// second. The first must still be remembered from its event.
    func testFocusEventsAreRememberedEvenWhenTheirRefreshIsCoalescedAway() async {
        windowManager.setWindows(stackedPair(focused: 2) + [.make(id: 9, frame: otherTile)])
        windowManager.send(.connected)
        await waitForStacks([[1, 2], [9]])

        windowManager.holdQueries()
        windowManager.setWindows(stackedPair() + [.make(id: 9, frame: otherTile, isFocused: true)])
        windowManager.send(.windowFocused(1))
        windowManager.send(.windowFocused(9))
        try? await Task.sleep(for: .milliseconds(50))
        windowManager.releaseQueries()

        let updated = await waitUntil { self.store.stacks.first?.focusedWindowId == 1 }
        XCTAssertTrue(updated)
    }

    func testStackKeepsItsTopWindowWhenItMovesToAnotherTile() async {
        windowManager.setWindows(stackedPair(focused: 2) + [.make(id: 9, frame: otherTile)])
        windowManager.send(.connected)
        await waitForStacks([[1, 2], [9]])

        // Focus leaves, then a display change shifts every tile.
        let shifted = tile.offsetBy(dx: 0, dy: 300)
        windowManager.setWindows([
            .make(id: 1, frame: shifted, stackIndex: 1),
            .make(id: 2, frame: shifted, stackIndex: 2),
            .make(id: 9, frame: otherTile.offsetBy(dx: 0, dy: 300), isFocused: true),
        ])
        windowManager.send(.windowsChanged)

        let moved = await waitUntil { self.store.stacks.first?.frame == shifted }
        XCTAssertTrue(moved)
        XCTAssertEqual(store.stacks.first?.focusedWindowId, 2)
    }

    // MARK: - Actions

    func testFocusIsForwardedToTheWindowManager() async {
        store.focus(7)

        let forwarded = await waitUntil { self.windowManager.focusRequests == [7] }
        XCTAssertTrue(forwarded)
    }
}
