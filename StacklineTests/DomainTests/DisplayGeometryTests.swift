import XCTest
@testable import Stackline

final class DisplayGeometryTests: XCTestCase {
    /// A 2560x1440 primary display with a 1920x1080 display above it and another to its right.
    private let displays = DisplayGeometry(
        screens: [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 0, y: 1440, width: 1920, height: 1080),
            CGRect(x: 2560, y: 360, width: 1920, height: 1080),
        ],
        primaryHeight: 1440
    )

    func testFlipsAroundThePrimaryDisplayHeight() {
        // 25pt below the top edge of the primary display, e.g. just under the menu bar.
        let converted = displays.appKitRect(fromTopLeft: CGRect(x: 10, y: 25, width: 800, height: 600))

        XCTAssertEqual(converted, CGRect(x: 10, y: 1440 - 25 - 600, width: 800, height: 600))
    }

    func testDisplayAboveThePrimaryHasNegativeTopLeftY() {
        // Top-left coordinates of a window filling the display above the primary one.
        let converted = displays.appKitRect(fromTopLeft: CGRect(x: 0, y: -1080, width: 1920, height: 1080))

        XCTAssertEqual(converted, displays.screens[1])
    }

    func testFindsTheDisplayShowingTheCenterOfARect() {
        // Straddles the primary and right-hand displays, mostly on the latter.
        let straddling = CGRect(x: 2400, y: 500, width: 800, height: 600)

        XCTAssertEqual(displays.screen(containing: straddling), displays.screens[2])
        XCTAssertNil(displays.screen(containing: CGRect(x: 9000, y: 9000, width: 10, height: 10)))
    }
}
