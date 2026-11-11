import XCTest
@testable import Stackline

final class YabaiModelsTests: XCTestCase {
    /// One window exactly as yabai v7.1 prints it.
    private let yabaiWindow = #"""
    {
        "id":618,
        "pid":1420,
        "app":"Ghostty",
        "title":"~/g/stackline-swift",
        "scratchpad":"",
        "frame":{
            "x":8.0000,
            "y":33.0000,
            "w":1264.0000,
            "h":799.0000
        },
        "role":"AXWindow",
        "subrole":"AXStandardWindow",
        "root-window":true,
        "display":1,
        "space":2,
        "level":0,
        "sub-level":0,
        "layer":"normal",
        "sub-layer":"normal",
        "opacity":1.0000,
        "split-type":"none",
        "split-child":"none",
        "stack-index":2,
        "can-move":true,
        "can-resize":true,
        "has-focus":true,
        "has-shadow":true,
        "has-parent-zoom":false,
        "has-fullscreen-zoom":false,
        "has-ax-reference":true,
        "is-native-fullscreen":false,
        "is-visible":true,
        "is-minimized":false,
        "is-hidden":false,
        "is-floating":false,
        "is-sticky":false,
        "is-grabbed":false
    }
    """#

    private func decode(_ json: String) throws -> YabaiWindow {
        try JSONDecoder().decode(YabaiWindow.self, from: Data(json.utf8))
    }

    func testMapsAYabaiWindowIntoAppKitCoordinates() throws {
        let displays = DisplayGeometry(screens: [CGRect(x: 0, y: 0, width: 1280, height: 840)], primaryHeight: 840)

        let window = try decode(yabaiWindow).managedWindow(on: displays)

        XCTAssertEqual(window, ManagedWindow(
            id: 618,
            processId: 1420,
            applicationName: "Ghostty",
            frame: CGRect(x: 8, y: 840 - 33 - 799, width: 1264, height: 799),
            spaceIndex: 2,
            displayIndex: 1,
            stackIndex: 2,
            isVisible: true,
            isFocused: true,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false
        ))
    }

    /// Only the fields Stackline uses are required, so other yabai versions keep working.
    func testIgnoresFieldsItDoesNotUse() throws {
        let minimal = #"""
        {"id":1,"pid":2,"app":"A","frame":{"x":0,"y":0,"w":1,"h":1},"display":1,"space":1,
         "stack-index":0,"has-focus":false,"is-visible":true,"is-minimized":false,"is-hidden":false,
         "is-floating":false,"is-native-fullscreen":false,"a-field-from-the-future":[1,2,3]}
        """#

        XCTAssertEqual(try decode(minimal).id, 1)
    }

    func testWindowOfAHiddenApplicationIsNotVisible() throws {
        let hidden = yabaiWindow.replacingOccurrences(of: #""is-hidden":false"#, with: #""is-hidden":true"#)

        let window = try decode(hidden).managedWindow(on: .single)

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isStackable)
    }
}
