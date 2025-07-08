import Foundation

// MARK: - Yabai Window Data Models

struct YabaiWindow: Codable, Identifiable, Equatable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let scratchpad: String?
    let frame: WindowFrame
    let role: String
    let subrole: String
    let rootWindow: Bool
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
    let hasShadow: Bool
    let hasParentZoom: Bool
    let hasFullscreenZoom: Bool
    let hasAXReference: Bool
    let isNativeFullscreen: Bool
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let isFloating: Bool
    let isSticky: Bool
    let isGrabbed: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, scratchpad, frame, role, subrole, display, space, level, opacity, layer
        case rootWindow = "root-window"
        case subLevel = "sub-level"
        case subLayer = "sub-layer"
        case splitType = "split-type"
        case splitChild = "split-child"
        case stackIndex = "stack-index"
        case canMove = "can-move"
        case canResize = "can-resize"
        case hasFocus = "has-focus"
        case hasShadow = "has-shadow"
        case hasParentZoom = "has-parent-zoom"
        case hasFullscreenZoom = "has-fullscreen-zoom"
        case hasAXReference = "has-ax-reference"
        case isNativeFullscreen = "is-native-fullscreen"
        case isVisible = "is-visible"
        case isMinimized = "is-minimized"
        case isHidden = "is-hidden"
        case isFloating = "is-floating"
        case isSticky = "is-sticky"
        case isGrabbed = "is-grabbed"
    }
    
    var isFocused: Bool {
        return hasFocus
    }
}

struct WindowFrame: Codable, Equatable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    
    var rect: CGRect {
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    // Check if two frames are effectively the same (allowing for small differences)
    func isSameAs(_ other: WindowFrame, tolerance: Double = 5.0) -> Bool {
        return abs(x - other.x) < tolerance &&
               abs(y - other.y) < tolerance &&
               abs(w - other.w) < tolerance &&
               abs(h - other.h) < tolerance
    }
    
    // Check if two frames overlap significantly
    func overlaps(_ other: WindowFrame, threshold: Double = 0.7) -> Bool {
        let rect1 = self.rect
        let rect2 = other.rect
        let intersection = rect1.intersection(rect2)
        
        let area1 = rect1.width * rect1.height
        let area2 = rect2.width * rect2.height
        let intersectionArea = intersection.width * intersection.height
        
        let overlapRatio1 = intersectionArea / area1
        let overlapRatio2 = intersectionArea / area2
        
        return overlapRatio1 > threshold || overlapRatio2 > threshold
    }
}

// MARK: - Stack Data Models

struct WindowStack: Identifiable, Equatable {
    let id: String
    let windows: [YabaiWindow]
    let frame: WindowFrame
    let space: Int
    let display: Int
    let lastFocusedWindowId: Int? // Track which window was last focused in this stack
    
    var focusedWindow: YabaiWindow? {
        return windows.first { $0.isFocused }
    }
    
    var visibleWindow: YabaiWindow? {
        // Return the window that was last focused in this stack
        // This is the window that should be visible/highlighted
        if let lastFocusedId = lastFocusedWindowId,
           let trackedWindow = windows.first(where: { $0.id == lastFocusedId }) {
            return trackedWindow
        }
        
        // Fallback: if no tracking data, use the currently focused window
        // or the first window with lowest stack index
        return focusedWindow ?? windows.first
    }
    
    var topmostWindow: YabaiWindow? {
        // Deprecated: Use visibleWindow instead
        return visibleWindow
    }
    
    var visibleWindows: [YabaiWindow] {
        return windows.filter { $0.isVisible }
    }
    
    var count: Int {
        return windows.count
    }
    
    init(windows: [YabaiWindow], lastFocusedWindowId: Int? = nil) {
        self.windows = windows
        self.lastFocusedWindowId = lastFocusedWindowId
        
        // Use the frame of the first window as the representative frame
        self.frame = windows.first?.frame ?? WindowFrame(x: 0, y: 0, w: 0, h: 0)
        self.space = windows.first?.space ?? 0
        self.display = windows.first?.display ?? 0
        
        // Create a stable ID based on the stack position and space
        // This should remain consistent as long as the stack is in the same location
        let x = Int(self.frame.x)
        let y = Int(self.frame.y)
        self.id = "stack_\(space)_\(display)_\(x)_\(y)"
    }
    
    static func == (lhs: WindowStack, rhs: WindowStack) -> Bool {
        return lhs.id == rhs.id && 
               lhs.windows.map(\.id) == rhs.windows.map(\.id) &&
               lhs.lastFocusedWindowId == rhs.lastFocusedWindowId
    }
}

// MARK: - Application State

struct AppState {
    var windows: [YabaiWindow] = []
    var stacks: [WindowStack] = []
    var currentSpace: Int = 1
    var currentDisplay: Int = 1
    var isConnectedToYabai: Bool = false
    var lastUpdateTime: Date = Date()
    
    mutating func updateWindows(_ newWindows: [YabaiWindow]) {
        self.windows = newWindows
        self.lastUpdateTime = Date()
    }
    
    mutating func updateStacks(_ newStacks: [WindowStack]) {
        self.stacks = newStacks
    }
}

// MARK: - Yabai Space Data Models

struct YabaiSpace: Codable, Identifiable {
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
    
    var isFocused: Bool {
        return hasFocus
    }
}

// MARK: - Yabai Display Data Models

struct YabaiDisplay: Codable, Identifiable {
    let id: Int
    let index: Int
    let frame: WindowFrame
    let spaces: [Int]
    
    enum CodingKeys: String, CodingKey {
        case id, index, frame, spaces
    }
}

// MARK: - Yabai Signal Data Models

struct YabaiSignal: Codable, Identifiable {
    let index: Int
    let label: String
    let app: String
    let title: String
    let active: String?  // This can be null, so optional String
    let event: String
    let action: String
    
    var id: Int { index }  // Computed property for Identifiable
    
    enum CodingKeys: String, CodingKey {
        case index, label, app, title, active, event, action
    }
} 