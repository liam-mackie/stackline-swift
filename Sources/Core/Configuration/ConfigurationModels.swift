import SwiftUI
import Foundation
import os

// MARK: - Configuration Models

struct StacklineConfiguration: Codable, Equatable {
    var appearance: AppearanceConfig = AppearanceConfig()
    var positioning: PositioningConfig = PositioningConfig()
    var behavior: BehaviorConfig = BehaviorConfig()
    
    static let `default` = StacklineConfiguration()
}

struct AppearanceConfig: Codable, Equatable {
    var indicatorStyle: IndicatorStyle = .pill
    var iconDirection: IconDirection = .vertical
    var iconSize: CGFloat = 24
    var pillHeight: CGFloat = 6
    var pillWidth: CGFloat = 40
    var minimalSize: CGFloat = 8
    var cornerRadius: CGFloat = 3
    var backgroundColor: CodableColor = CodableColor(.black.opacity(0.7))
    var borderColor: CodableColor = CodableColor(.white.opacity(0.3))
    var focusedColor: CodableColor = CodableColor(.white)
    var unfocusedColor: CodableColor = CodableColor(.gray.opacity(0.7))
    var borderWidth: CGFloat = 1
    var spacing: CGFloat = 2
    var showContainer: Bool = true
}

struct PositioningConfig: Codable, Equatable {
    var stackCorner: StackCornerPosition = .auto
    var edgeOffset: CGFloat = 0
    var cornerOffset: CGFloat = 0
    var stickToScreenEdge: Bool = true
}

struct BehaviorConfig: Codable, Equatable {
    var showByDefault: Bool = true
    var hideWhenNoStacks: Bool = false
    var clickToFocus: Bool = true
    var showOnAllSpaces: Bool = true
    var launchAtStartup: Bool = false
    var showMainWindowAtLaunch: Bool = true
}

enum IndicatorStyle: String, Codable, CaseIterable {
    case pill = "pill"
    case icons = "icons"
    case minimal = "minimal"
    
    var displayName: String {
        switch self {
        case .pill: return "Pill"
        case .icons: return "App Icons"
        case .minimal: return "Minimal"
        }
    }
}

enum IconDirection: String, Codable, CaseIterable {
    case horizontal = "horizontal"
    case vertical = "vertical"
    
    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

enum StackCornerPosition: String, Codable, CaseIterable {
    case auto = "auto"
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto (Smart)"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}