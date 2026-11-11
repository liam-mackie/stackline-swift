import XCTest
@testable import Stackline

final class StackBuilderTests: XCTestCase {
    private let displays = DisplayGeometry.single
    private let tile = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func stacks(_ windows: [ManagedWindow], focusHistory: [WindowIdentifier] = []) -> [WindowStack] {
        StackBuilder.stacks(from: windows, on: displays, focusHistory: focusHistory)
    }

    // MARK: - Grouping

    func testWindowsSharingATileFormOneStack() {
        let result = stacks([
            .make(id: 1, frame: tile, stackIndex: 1),
            .make(id: 2, frame: tile, stackIndex: 2),
            .make(id: 3, frame: tile.offsetBy(dx: 900, dy: 0)),
        ])

        XCTAssertEqual(result.map { $0.windows.map(\.id) }, [[1, 2], [3]])
    }

    func testOriginsWithinToleranceShareATile() {
        let result = stacks([
            .make(id: 1, frame: tile),
            .make(id: 2, frame: tile.offsetBy(dx: 5, dy: -5)),
        ])

        XCTAssertEqual(result.count, 1)
    }

    func testOriginsBeyondToleranceAreSeparateTiles() {
        let result = stacks([
            .make(id: 1, frame: tile),
            .make(id: 2, frame: tile.offsetBy(dx: 6, dy: 0)),
        ])

        XCTAssertEqual(result.count, 2)
    }

    func testSamePositionOnDifferentSpacesOrDisplaysIsNotAStack() {
        let result = stacks([
            .make(id: 1, frame: tile, space: 1, display: 1),
            .make(id: 2, frame: tile, space: 2, display: 1),
            .make(id: 3, frame: tile, space: 1, display: 2),
        ])

        XCTAssertEqual(result.count, 3)
    }

    func testOnlyVisibleTiledWindowsAreStacked() {
        let result = stacks([
            .make(id: 1, frame: tile),
            .make(id: 2, frame: tile, isVisible: false),
            .make(id: 3, frame: tile, isFloating: true),
            .make(id: 4, frame: tile, isMinimized: true),
            .make(id: 5, frame: tile, isFullscreen: true),
        ])

        XCTAssertEqual(result.map { $0.windows.map(\.id) }, [[1]])
    }

    func testWindowsOutsideEveryDisplayAreIgnored() {
        let result = stacks([
            .make(id: 1, frame: tile),
            .make(id: 2, frame: tile.offsetBy(dx: 5000, dy: 5000)),
        ])

        XCTAssertEqual(result.map { $0.windows.map(\.id) }, [[1]])
    }

    func testNoDisplaysMeansNoStacks() {
        let result = StackBuilder.stacks(from: [.make(id: 1, frame: tile)], on: .none)

        XCTAssertTrue(result.isEmpty)
    }

    func testStackRecordsTheDisplayItIsOn() {
        let external = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let twoDisplays = DisplayGeometry(screens: displays.screens + [external], primaryHeight: 1440)

        let result = StackBuilder.stacks(
            from: [.make(id: 1, frame: CGRect(x: 2600, y: 100, width: 800, height: 600), display: 2)],
            on: twoDisplays
        )

        XCTAssertEqual(result.first?.screenFrame, external)
    }

    /// yabai lists windows front to back, so the order of its reply changes with every focus
    /// change. That must not change the stacks, or indicators would jump around.
    func testResultDoesNotDependOnInputOrder() {
        let windows: [ManagedWindow] = [
            .make(id: 1, frame: tile, stackIndex: 1),
            .make(id: 2, frame: tile.offsetBy(dx: 4, dy: 0), stackIndex: 2),
            .make(id: 3, frame: tile.offsetBy(dx: -4, dy: 0), stackIndex: 3),
            .make(id: 4, frame: tile.offsetBy(dx: 900, dy: 0)),
        ]

        let expected = stacks(windows)
        XCTAssertEqual(stacks(windows.reversed()), expected)
        XCTAssertEqual(stacks([windows[2], windows[0], windows[3], windows[1]]), expected)
    }

    // MARK: - Top window

    func testFocusedMemberIsOnTop() {
        let result = stacks([
            .make(id: 1, frame: tile, stackIndex: 1),
            .make(id: 2, frame: tile, stackIndex: 2, isFocused: true),
        ])

        XCTAssertEqual(result.first?.focusedWindowId, 2)
    }

    func testUnfocusedStackShowsItsMostRecentlyFocusedMember() {
        let windows: [ManagedWindow] = [
            .make(id: 1, frame: tile, stackIndex: 1),
            .make(id: 2, frame: tile, stackIndex: 2),
            .make(id: 3, frame: tile, stackIndex: 3),
            .make(id: 9, frame: tile.offsetBy(dx: 900, dy: 0), isFocused: true),
        ]

        let result = stacks(windows, focusHistory: [9, 3, 1])

        XCTAssertEqual(result.first { $0.count == 3 }?.focusedWindowId, 3)
    }

    func testTopWindowIsUnknownWithoutFocusOrHistory() {
        let result = stacks([
            .make(id: 1, frame: tile, stackIndex: 1),
            .make(id: 2, frame: tile, stackIndex: 2),
        ], focusHistory: [42])

        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].focusedWindowId)
    }
}
