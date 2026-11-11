import XCTest
@testable import Stackline

final class WindowStackTests: XCTestCase {
    private let tile = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testWindowsAreInStackOrder() {
        let stack = WindowStack.make([
            .make(id: 1, frame: tile, stackIndex: 3),
            .make(id: 2, frame: tile, stackIndex: 1),
            .make(id: 3, frame: tile, stackIndex: 2),
        ])

        XCTAssertEqual(stack.windows.map(\.id), [2, 3, 1])
        XCTAssertEqual(stack.index(of: 1), 2)
        XCTAssertNil(stack.index(of: 99))
    }

    func testFrameIsThatOfTheFirstWindowInStackOrder() {
        let narrow = CGRect(x: 100, y: 100, width: 700, height: 600)

        let stack = WindowStack.make([
            .make(id: 1, frame: narrow, stackIndex: 2),
            .make(id: 2, frame: tile, stackIndex: 1),
        ])

        XCTAssertEqual(stack.frame, tile)
    }

    func testIdentityFollowsTheTileNotTheWindows() {
        let before = WindowStack.make([.make(id: 1, frame: tile), .make(id: 2, frame: tile)])
        let after = WindowStack.make([.make(id: 3, frame: tile)])

        XCTAssertEqual(before.id, after.id)
    }

    func testIdentityDiffersAcrossTilesSpacesAndDisplays() {
        let ids = [
            WindowStack.make([.make(id: 1, frame: tile)]),
            WindowStack.make([.make(id: 1, frame: tile.offsetBy(dx: 900, dy: 0))]),
            WindowStack.make([.make(id: 1, frame: tile, space: 2)]),
            WindowStack.make([.make(id: 1, frame: tile, display: 2)]),
        ].map(\.id)

        XCTAssertEqual(Set(ids).count, 4)
    }

    /// Displays left of or below the primary one have negative coordinates.
    func testIdentityDistinguishesTilesEitherSideOfTheOrigin() {
        let left = WindowStack.make([.make(id: 1, frame: CGRect(x: -3, y: -3, width: 800, height: 600))])
        let right = WindowStack.make([.make(id: 2, frame: CGRect(x: 3, y: 3, width: 800, height: 600))])

        XCTAssertNotEqual(left.id, right.id)
    }

    func testTopWindowDefaultsToTheFocusedMember() {
        let windows: [ManagedWindow] = [
            .make(id: 1, frame: tile, stackIndex: 1),
            .make(id: 2, frame: tile, stackIndex: 2, isFocused: true),
        ]

        XCTAssertEqual(WindowStack(windows: windows, screenFrame: .zero).focusedWindowId, 2)
        XCTAssertEqual(WindowStack(windows: windows, screenFrame: .zero, focusedWindowId: 1).focusedWindowId, 1)
    }

    /// Resizing a tile without moving its origin keeps the ID and the windows, but indicators
    /// anchored to its far edges must still move.
    func testStacksDifferingOnlyInSizeAreNotEqual() {
        let wider = CGRect(x: tile.minX, y: tile.minY, width: tile.width + 200, height: tile.height)

        let before = WindowStack.make([.make(id: 1, frame: tile), .make(id: 2, frame: tile)])
        let after = WindowStack.make([.make(id: 1, frame: wider), .make(id: 2, frame: wider)])

        XCTAssertEqual(before.id, after.id)
        XCTAssertNotEqual(before, after)
    }
}
