import XCTest
@testable import Stackline

final class YabaiModelsTests: XCTestCase {

    // MARK: - YabaiWindow Tests

    func testYabaiWindowDecoding() throws {
        let json = """
        {
            "id": 123,
            "pid": 456,
            "app": "Safari",
            "title": "Test Page",
            "frame": {"x": 100.0, "y": 200.0, "w": 800.0, "h": 600.0},
            "role": "AXWindow",
            "subrole": "AXStandardWindow",
            "display": 1,
            "space": 2,
            "level": 0,
            "sub-level": 0,
            "layer": "normal",
            "sub-layer": "normal",
            "opacity": 1.0,
            "split-type": "none",
            "split-child": "none",
            "stack-index": 1,
            "can-move": true,
            "can-resize": true,
            "has-focus": true,
            "has-parent-zoom": false,
            "has-shadow": true,
            "has-fullscreen-zoom": false,
            "has-ax-reference": true,
            "is-native-fullscreen": false,
            "is-visible": true,
            "is-minimized": false,
            "is-hidden": false,
            "is-floating": false,
            "is-sticky": false,
            "is-grabbed": false
        }
        """.data(using: .utf8)!

        let window = try JSONDecoder().decode(YabaiWindow.self, from: json)

        XCTAssertEqual(window.id, 123)
        XCTAssertEqual(window.pid, 456)
        XCTAssertEqual(window.app, "Safari")
        XCTAssertEqual(window.title, "Test Page")
        XCTAssertEqual(window.stackIndex, 1)
        XCTAssertTrue(window.hasFocus)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isMinimized)
    }

    func testYabaiWindowToManagedWindow() throws {
        let json = """
        {
            "id": 123,
            "pid": 456,
            "app": "Safari",
            "title": "Test Page",
            "frame": {"x": 100.0, "y": 200.0, "w": 800.0, "h": 600.0},
            "role": "AXWindow",
            "subrole": "AXStandardWindow",
            "display": 1,
            "space": 2,
            "level": 0,
            "sub-level": 0,
            "layer": "normal",
            "sub-layer": "normal",
            "opacity": 1.0,
            "split-type": "none",
            "split-child": "none",
            "stack-index": 1,
            "can-move": true,
            "can-resize": true,
            "has-focus": true,
            "has-parent-zoom": false,
            "has-shadow": true,
            "has-fullscreen-zoom": false,
            "has-ax-reference": true,
            "is-native-fullscreen": false,
            "is-visible": true,
            "is-minimized": false,
            "is-hidden": false,
            "is-floating": false,
            "is-sticky": false,
            "is-grabbed": false
        }
        """.data(using: .utf8)!

        let screenHeight: CGFloat = 1440
        let yabaiWindow = try JSONDecoder().decode(YabaiWindow.self, from: json)
        let managedWindow = yabaiWindow.toManagedWindow(screenHeight: screenHeight)

        XCTAssertEqual(managedWindow.id, 123)
        XCTAssertEqual(managedWindow.processId, 456)
        XCTAssertEqual(managedWindow.applicationName, "Safari")
        XCTAssertEqual(managedWindow.title, "Test Page")
        // Frame is converted from Yabai (top-left origin) to AppKit (bottom-left origin)
        // AppKit Y = screenHeight - yabaiY - height = 1440 - 200 - 600 = 640
        XCTAssertEqual(managedWindow.frame, CGRect(x: 100, y: 640, width: 800, height: 600))
        XCTAssertEqual(managedWindow.spaceIndex, 2)
        XCTAssertEqual(managedWindow.displayIndex, 1)
        XCTAssertEqual(managedWindow.stackIndex, 1)
        XCTAssertTrue(managedWindow.isVisible)
        XCTAssertTrue(managedWindow.isFocused)
        XCTAssertFalse(managedWindow.isFloating)
        XCTAssertFalse(managedWindow.isMinimized)
        XCTAssertFalse(managedWindow.isFullscreen)
        XCTAssertTrue(managedWindow.isRootWindow)
    }

    // MARK: - YabaiSpace Tests

    func testYabaiSpaceDecoding() throws {
        let json = """
        {
            "id": 1,
            "uuid": "ABC123",
            "index": 1,
            "label": "Work",
            "type": "bsp",
            "display": 1,
            "windows": [100, 101, 102],
            "first-window": 100,
            "last-window": 102,
            "has-focus": true,
            "is-visible": true,
            "is-native-fullscreen": false
        }
        """.data(using: .utf8)!

        let space = try JSONDecoder().decode(YabaiSpace.self, from: json)

        XCTAssertEqual(space.id, 1)
        XCTAssertEqual(space.index, 1)
        XCTAssertEqual(space.label, "Work")
        XCTAssertEqual(space.display, 1)
        XCTAssertEqual(space.windows, [100, 101, 102])
        XCTAssertTrue(space.hasFocus)
        XCTAssertTrue(space.isVisible)
    }

    func testYabaiSpaceToManagedSpace() throws {
        let json = """
        {
            "id": 1,
            "uuid": "ABC123",
            "index": 1,
            "label": "Work",
            "type": "bsp",
            "display": 1,
            "windows": [100, 101, 102],
            "first-window": 100,
            "last-window": 102,
            "has-focus": true,
            "is-visible": true,
            "is-native-fullscreen": false
        }
        """.data(using: .utf8)!

        let yabaiSpace = try JSONDecoder().decode(YabaiSpace.self, from: json)
        let managedSpace = yabaiSpace.toManagedSpace()

        XCTAssertEqual(managedSpace.id, 1)
        XCTAssertEqual(managedSpace.index, 1)
        XCTAssertEqual(managedSpace.displayIndex, 1)
        XCTAssertEqual(managedSpace.label, "Work")
        XCTAssertEqual(managedSpace.windowIds, [100, 101, 102])
        XCTAssertTrue(managedSpace.isFocused)
        XCTAssertTrue(managedSpace.isVisible)
        XCTAssertFalse(managedSpace.isFullscreen)
    }

    func testYabaiSpaceEmptyLabelBecomesNil() throws {
        let json = """
        {
            "id": 1,
            "uuid": "ABC123",
            "index": 1,
            "label": "",
            "type": "bsp",
            "display": 1,
            "windows": [],
            "first-window": 0,
            "last-window": 0,
            "has-focus": false,
            "is-visible": false,
            "is-native-fullscreen": false
        }
        """.data(using: .utf8)!

        let yabaiSpace = try JSONDecoder().decode(YabaiSpace.self, from: json)
        let managedSpace = yabaiSpace.toManagedSpace()

        XCTAssertNil(managedSpace.label)
    }

    // MARK: - YabaiDisplay Tests

    func testYabaiDisplayDecoding() throws {
        let json = """
        {
            "id": 1,
            "uuid": "XYZ789",
            "index": 1,
            "label": "Main Display",
            "frame": {"x": 0.0, "y": 0.0, "w": 2560.0, "h": 1440.0},
            "spaces": [1, 2, 3],
            "has-focus": true
        }
        """.data(using: .utf8)!

        let display = try JSONDecoder().decode(YabaiDisplay.self, from: json)

        XCTAssertEqual(display.id, 1)
        XCTAssertEqual(display.index, 1)
        XCTAssertEqual(display.label, "Main Display")
        XCTAssertEqual(display.frame.w, 2560.0)
        XCTAssertEqual(display.frame.h, 1440.0)
        XCTAssertEqual(display.spaces, [1, 2, 3])
        XCTAssertTrue(display.hasFocus)
    }

    func testYabaiDisplayToManagedDisplay() throws {
        let json = """
        {
            "id": 1,
            "uuid": "XYZ789",
            "index": 1,
            "label": "Main Display",
            "frame": {"x": 0.0, "y": 0.0, "w": 2560.0, "h": 1440.0},
            "spaces": [1, 2, 3],
            "has-focus": true
        }
        """.data(using: .utf8)!

        let screenHeight: CGFloat = 1440
        let yabaiDisplay = try JSONDecoder().decode(YabaiDisplay.self, from: json)
        let managedDisplay = yabaiDisplay.toManagedDisplay(screenHeight: screenHeight)

        XCTAssertEqual(managedDisplay.id, 1)
        XCTAssertEqual(managedDisplay.index, 1)
        // Frame converted from top-left to bottom-left origin
        // For a display at origin with same height as screen, Y stays at 0
        XCTAssertEqual(managedDisplay.frame, CGRect(x: 0, y: 0, width: 2560, height: 1440))
        XCTAssertEqual(managedDisplay.spaceIds, [1, 2, 3])
    }

    // MARK: - YabaiFrame Tests

    func testYabaiFrameToCGRect() {
        let frame = YabaiFrame(x: 10.5, y: 20.5, w: 100.0, h: 200.0)
        let cgRect = frame.cgRect

        XCTAssertEqual(cgRect.origin.x, 10.5)
        XCTAssertEqual(cgRect.origin.y, 20.5)
        XCTAssertEqual(cgRect.size.width, 100.0)
        XCTAssertEqual(cgRect.size.height, 200.0)
    }
}
