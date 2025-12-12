import XCTest
@testable import Stackline

final class CoordinateSystemTests: XCTestCase {

    // MARK: - MockCoordinateSystem Tests

    func testMockDisplayContainsPoint() {
        let mock = MockCoordinateSystem()
        mock.setDisplayFrames([CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        let display = mock.displayContaining(point: CGPoint(x: 100, y: 100))

        XCTAssertNotNil(display)
        XCTAssertEqual(display?.width, 1920)
    }

    func testMockDisplayNotContainsPoint() {
        let mock = MockCoordinateSystem()
        mock.setDisplayFrames([CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        let display = mock.displayContaining(point: CGPoint(x: 3000, y: 100))

        XCTAssertNil(display)
    }

    func testMockDisplayContainsRect() {
        let mock = MockCoordinateSystem()
        mock.setDisplayFrames([CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        let rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        let display = mock.displayContaining(rect: rect)

        XCTAssertNotNil(display)
    }

    func testMockIsWindowOnScreen() {
        let mock = MockCoordinateSystem()
        mock.setDisplayFrames([CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        let window = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Test",
            title: "Test Window",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
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

        XCTAssertTrue(mock.isWindowOnScreen(window))
    }

    func testMockIsWindowOffScreen() {
        let mock = MockCoordinateSystem()
        mock.setDisplayFrames([CGRect(x: 0, y: 0, width: 1920, height: 1080)])

        let window = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Test",
            title: "Test Window",
            frame: CGRect(x: 5000, y: 5000, width: 800, height: 600),
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

        XCTAssertFalse(mock.isWindowOnScreen(window))
    }

    func testMockMultipleDisplays() {
        let mock = MockCoordinateSystem()
        mock.setDisplayFrames([
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        ])

        let frames = mock.getAllDisplayFrames()
        XCTAssertEqual(frames.count, 2)

        let display1 = mock.displayContaining(point: CGPoint(x: 500, y: 500))
        XCTAssertEqual(display1?.width, 1920)

        let display2 = mock.displayContaining(point: CGPoint(x: 2500, y: 500))
        XCTAssertEqual(display2?.width, 2560)
    }
}
