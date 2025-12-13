import Foundation

/// Yabai-specific JSON models for decoding query responses
/// These are internal to the Yabai adapter and map to domain models

// MARK: - Window Response

struct YabaiWindow: Codable, Sendable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let frame: YabaiFrame
    let role: String
    let subrole: String
    let display: Int
    let space: Int
    let level: Int
    let subLevel: Int
    let layer: String
    let subLayer: String
    let opacity: Double
    let splitType: String
    let splitChild: String
    let stackIndex: Int
    let canMove: Bool
    let canResize: Bool
    let hasFocus: Bool
    let hasParentZoom: Bool
    let hasShadow: Bool
    let hasFullscreenZoom: Bool
    let hasAxReference: Bool
    let isNativeFullscreen: Bool
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let isFloating: Bool
    let isSticky: Bool
    let isGrabbed: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, frame, role, subrole, display, space, level, layer, opacity
        case subLevel = "sub-level"
        case subLayer = "sub-layer"
        case splitType = "split-type"
        case splitChild = "split-child"
        case stackIndex = "stack-index"
        case canMove = "can-move"
        case canResize = "can-resize"
        case hasFocus = "has-focus"
        case hasParentZoom = "has-parent-zoom"
        case hasShadow = "has-shadow"
        case hasFullscreenZoom = "has-fullscreen-zoom"
        case hasAxReference = "has-ax-reference"
        case isNativeFullscreen = "is-native-fullscreen"
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case isFloating = "is-floating"
        case isSticky = "is-sticky"
        case isGrabbed = "is-grabbed"
    }
}

// MARK: - Space Response

struct YabaiSpace: Codable, Sendable {
    let id: Int
    let uuid: String
    let index: Int
    let label: String
    let type: String
    let display: Int
    let windows: [Int]
    let firstWindow: Int
    let lastWindow: Int
    let hasFocus: Bool
    let isVisible: Bool
    let isNativeFullscreen: Bool

    enum CodingKeys: String, CodingKey {
        case id, uuid, index, label, type, display, windows
        case firstWindow = "first-window"
        case lastWindow = "last-window"
        case hasFocus = "has-focus"
        case isVisible = "is-visible"
        case isNativeFullscreen = "is-native-fullscreen"
    }
}

// MARK: - Display Response

struct YabaiDisplay: Codable, Sendable {
    let id: Int
    let uuid: String
    let index: Int
    let label: String
    let frame: YabaiFrame
    let spaces: [Int]
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case id, uuid, index, label, frame, spaces
        case hasFocus = "has-focus"
    }
}

// MARK: - Shared Types

struct YabaiFrame: Codable, Sendable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Domain Model Conversion

extension YabaiWindow {
    /// Convert Yabai window to domain model with coordinate conversion
    /// - Parameter screenHeight: Height of the main display for coordinate conversion
    /// - Returns: ManagedWindow with AppKit coordinates (bottom-left origin)
    func toManagedWindow(screenHeight: CGFloat) -> ManagedWindow {
        // Convert from Yabai (top-left origin) to AppKit (bottom-left origin)
        let appKitFrame = CoordinateConversion.toAppKit(frame.cgRect, screenHeight: screenHeight)

        return ManagedWindow(
            id: id,
            processId: pid,
            applicationName: app,
            title: title,
            frame: appKitFrame,
            spaceIndex: space,
            displayIndex: display,
            stackIndex: stackIndex,
            isVisible: isVisible && !isHidden,
            isFocused: hasFocus,
            isFloating: isFloating,
            isMinimized: isMinimized,
            isFullscreen: isNativeFullscreen,
            isRootWindow: stackIndex == 1 || stackIndex == 0
        )
    }
}

extension YabaiSpace {
    func toManagedSpace() -> ManagedSpace {
        ManagedSpace(
            id: id,
            index: index,
            displayIndex: display,
            label: label.isEmpty ? nil : label,
            windowIds: windows,
            isFocused: hasFocus,
            isVisible: isVisible,
            isFullscreen: isNativeFullscreen
        )
    }
}

extension YabaiDisplay {
    /// Convert Yabai display to domain model with coordinate conversion
    /// - Parameter screenHeight: Height of the main display for coordinate conversion
    /// - Returns: ManagedDisplay with AppKit coordinates (bottom-left origin)
    func toManagedDisplay(screenHeight: CGFloat) -> ManagedDisplay {
        // Convert from Yabai (top-left origin) to AppKit (bottom-left origin)
        let appKitFrame = CoordinateConversion.toAppKit(frame.cgRect, screenHeight: screenHeight)

        return ManagedDisplay(
            id: id,
            index: index,
            frame: appKitFrame,
            spaceIds: spaces
        )
    }
}
