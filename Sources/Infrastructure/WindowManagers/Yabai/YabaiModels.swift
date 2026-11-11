import CoreGraphics
import Foundation

/// The subset of `yabai -m query --windows` that Stackline relies on.
///
/// Only these keys are decoded, so fields yabai adds, renames or drops elsewhere cannot break
/// stack detection.
struct YabaiWindow: Decodable, Sendable {
    let id: Int
    let pid: Int
    let app: String
    let frame: YabaiFrame
    let display: Int
    let space: Int
    let stackIndex: Int
    let hasFocus: Bool
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let isFloating: Bool
    let isNativeFullscreen: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, frame, display, space
        case stackIndex = "stack-index"
        case hasFocus = "has-focus"
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case isFloating = "is-floating"
        case isNativeFullscreen = "is-native-fullscreen"
    }

    /// Maps to the domain model, converting the frame from yabai's top-left-origin coordinates
    /// into the AppKit coordinate space described by `displays`.
    func managedWindow(on displays: DisplayGeometry) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: pid,
            applicationName: app,
            frame: displays.appKitRect(fromTopLeft: frame.cgRect),
            spaceIndex: space,
            displayIndex: display,
            stackIndex: stackIndex,
            isVisible: isVisible && !isHidden,
            isFocused: hasFocus,
            isFloating: isFloating,
            isMinimized: isMinimized,
            isFullscreen: isNativeFullscreen
        )
    }
}

struct YabaiFrame: Decodable, Sendable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
}

/// An entry of `yabai -m signal --list`.
struct YabaiSignalEntry: Decodable, Sendable {
    let label: String
}
