import Foundation
import SwiftUI

public enum IndicatorStyle: String, Codable, CaseIterable, Sendable {
    case pill
    case icons
    case minimal
}

public enum IconDirection: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical
}

public enum StackCorner: String, Codable, CaseIterable, Sendable {
    case auto
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

// MARK: - Layout Signature

/// A normalized rectangle representing a stack's position as percentages of screen bounds
public struct NormalizedRect: Hashable, Codable, Sendable, Comparable {
    public let x: Int       // 0-100, percentage of screen width
    public let y: Int       // 0-100, percentage of screen height
    public let width: Int   // 0-100
    public let height: Int  // 0-100

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Create from a frame normalized against screen bounds
    public init(frame: CGRect, screenBounds: CGRect) {
        // Normalize to 0-100 range and quantize to integers
        self.x = Int(((frame.minX - screenBounds.minX) / screenBounds.width * 100).rounded())
        self.y = Int(((frame.minY - screenBounds.minY) / screenBounds.height * 100).rounded())
        self.width = Int((frame.width / screenBounds.width * 100).rounded())
        self.height = Int((frame.height / screenBounds.height * 100).rounded())
    }

    /// Canonical ordering: top-to-bottom (higher Y first in AppKit), then left-to-right
    public static func < (lhs: NormalizedRect, rhs: NormalizedRect) -> Bool {
        // AppKit: higher Y = top of screen, so sort descending by Y for top-first
        if lhs.y != rhs.y {
            return lhs.y > rhs.y
        }
        return lhs.x < rhs.x
    }
}

/// Uniquely identifies a layout based on normalized stack positions
public struct LayoutSignature: Hashable, Codable, Sendable {
    /// Normalized frames, sorted canonically (top-to-bottom, left-to-right)
    public let frames: [NormalizedRect]

    public var stackCount: Int { frames.count }

    public init(frames: [NormalizedRect]) {
        self.frames = frames.sorted()
    }

    /// Compute a layout signature from window stacks and screen bounds
    public static func compute(from stacks: [WindowStack], screenBounds: CGRect) -> LayoutSignature {
        let normalizedFrames = stacks.map { NormalizedRect(frame: $0.frame, screenBounds: screenBounds) }
        return LayoutSignature(frames: normalizedFrames)
    }

    /// Storage key for persisting per-layout preferences
    public var storageKey: String {
        let frameStrings = frames.map { "\($0.x),\($0.y),\($0.width),\($0.height)" }
        return "\(stackCount)|\(frameStrings.joined(separator: ";"))"
    }

    /// Parse a storage key back into a LayoutSignature
    public init?(storageKey: String) {
        let parts = storageKey.split(separator: "|", maxSplits: 1)
        guard parts.count == 2,
              let count = Int(parts[0]) else {
            return nil
        }

        let frameStrings = parts[1].split(separator: ";")
        guard frameStrings.count == count else {
            return nil
        }

        var frames: [NormalizedRect] = []
        for frameStr in frameStrings {
            let values = frameStr.split(separator: ",").compactMap { Int($0) }
            guard values.count == 4 else {
                return nil
            }
            frames.append(NormalizedRect(x: values[0], y: values[1], width: values[2], height: values[3]))
        }

        self.frames = frames.sorted()
    }

    public static let empty = LayoutSignature(frames: [])
}

public struct StackPositionSettings: Equatable, Codable, Sendable {
    public var stackCorner: StackCorner
    public var horizontalOffset: CGFloat
    public var verticalOffset: CGFloat

    public init(
        stackCorner: StackCorner = .auto,
        horizontalOffset: CGFloat = 0,
        verticalOffset: CGFloat = 0
    ) {
        self.stackCorner = stackCorner
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }

    public static let `default` = StackPositionSettings()
}

/// Represents a specific layout pattern that can be identified and remembered
public struct LayoutPattern: Hashable, Codable, Sendable {
    public let signature: LayoutSignature

    public var stackCount: Int { signature.stackCount }

    public init(signature: LayoutSignature) {
        self.signature = signature
    }

    public var displayName: String {
        if stackCount == 0 {
            return "No Stacks"
        }
        return stackCount == 1 ? "1 Stack" : "\(stackCount) Stacks"
    }

    public var storageKey: String { signature.storageKey }

    public init?(storageKey: String) {
        guard let signature = LayoutSignature(storageKey: storageKey) else {
            return nil
        }
        self.signature = signature
    }

    public static let empty = LayoutPattern(signature: .empty)
}

/// Settings for all stacks within a particular layout pattern
public struct LayoutStackSettings: Equatable, Codable, Sendable {
    /// Settings keyed by stack index within the layout (0, 1, 2, ...)
    public var stackSettings: [Int: StackPositionSettings]

    public init(stackSettings: [Int: StackPositionSettings] = [:]) {
        self.stackSettings = stackSettings
    }

    public func settings(for index: Int) -> StackPositionSettings {
        stackSettings[index] ?? .default
    }

    public mutating func setSettings(_ settings: StackPositionSettings, for index: Int) {
        stackSettings[index] = settings
    }
}

// MARK: - Style-Specific Settings

public struct PillStyleSettings: Equatable, Codable, Sendable {
    public var pillHeight: CGFloat
    public var pillWidth: CGFloat
    public var textColor: CodableColor

    public init(
        pillHeight: CGFloat = 6,
        pillWidth: CGFloat = 40,
        textColor: CodableColor = CodableColor(.white)
    ) {
        self.pillHeight = pillHeight
        self.pillWidth = pillWidth
        self.textColor = textColor
    }

    public static let `default` = PillStyleSettings()
}

public struct IconsStyleSettings: Equatable, Codable, Sendable {
    public var iconDirection: IconDirection
    public var iconSize: CGFloat
    public var unfocusedOpacity: CGFloat
    public var focusedColor: CodableColor

    public init(
        iconDirection: IconDirection = .vertical,
        iconSize: CGFloat = 24,
        unfocusedOpacity: CGFloat = 0.6,
        focusedColor: CodableColor = CodableColor(.white)
    ) {
        self.iconDirection = iconDirection
        self.iconSize = iconSize
        self.unfocusedOpacity = unfocusedOpacity
        self.focusedColor = focusedColor
    }

    public static let `default` = IconsStyleSettings()
}

public struct MinimalStyleSettings: Equatable, Codable, Sendable {
    public var iconDirection: IconDirection
    public var minimalSize: CGFloat
    public var focusedColor: CodableColor
    public var unfocusedColor: CodableColor

    public init(
        iconDirection: IconDirection = .vertical,
        minimalSize: CGFloat = 8,
        focusedColor: CodableColor = CodableColor(.white),
        unfocusedColor: CodableColor = CodableColor(.gray)
    ) {
        self.iconDirection = iconDirection
        self.minimalSize = minimalSize
        self.focusedColor = focusedColor
        self.unfocusedColor = unfocusedColor
    }

    public static let `default` = MinimalStyleSettings()
}

// MARK: - Appearance Preferences

public struct AppearancePreferences: Equatable, Codable, Sendable {
    public var indicatorStyle: IndicatorStyle

    // Shared container settings
    public var cornerRadius: CGFloat
    public var spacing: CGFloat
    public var containerPadding: CGFloat
    public var borderWidth: CGFloat
    public var showContainer: Bool
    public var backgroundColor: CodableColor
    public var borderColor: CodableColor

    // Style-specific settings
    public var pillSettings: PillStyleSettings
    public var iconsSettings: IconsStyleSettings
    public var minimalSettings: MinimalStyleSettings

    public init(
        indicatorStyle: IndicatorStyle = .pill,
        cornerRadius: CGFloat = 3,
        spacing: CGFloat = 4,
        containerPadding: CGFloat = 0,
        borderWidth: CGFloat = 0,
        showContainer: Bool = true,
        backgroundColor: CodableColor = CodableColor(.black.opacity(0.6)),
        borderColor: CodableColor = CodableColor(.clear),
        pillSettings: PillStyleSettings = .default,
        iconsSettings: IconsStyleSettings = .default,
        minimalSettings: MinimalStyleSettings = .default
    ) {
        self.indicatorStyle = indicatorStyle
        self.cornerRadius = cornerRadius
        self.spacing = spacing
        self.containerPadding = containerPadding
        self.borderWidth = borderWidth
        self.showContainer = showContainer
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.pillSettings = pillSettings
        self.iconsSettings = iconsSettings
        self.minimalSettings = minimalSettings
    }

    public static let `default` = AppearancePreferences()
}

public struct PositioningPreferences: Equatable, Codable, Sendable {
    public var stickToScreenEdge: Bool
    public var showSingleWindowIndicators: Bool
    public var globalHorizontalOffset: CGFloat
    public var globalVerticalOffset: CGFloat
    public var layoutSettings: [String: LayoutStackSettings]

    public init(
        stickToScreenEdge: Bool = true,
        showSingleWindowIndicators: Bool = true,
        globalHorizontalOffset: CGFloat = 0,
        globalVerticalOffset: CGFloat = 0,
        layoutSettings: [String: LayoutStackSettings] = [:]
    ) {
        self.stickToScreenEdge = stickToScreenEdge
        self.showSingleWindowIndicators = showSingleWindowIndicators
        self.globalHorizontalOffset = globalHorizontalOffset
        self.globalVerticalOffset = globalVerticalOffset
        self.layoutSettings = layoutSettings
    }

    public static let `default` = PositioningPreferences()

    /// Get the per-stack adjustment settings (offsets are relative to global)
    public func settings(for stackIndex: Int, in layout: LayoutPattern) -> StackPositionSettings {
        let key = layout.storageKey
        if let layoutConfig = layoutSettings[key] {
            return layoutConfig.settings(for: stackIndex)
        }
        return .default
    }

    /// Compute effective offsets by combining global offset with per-stack adjustment
    public func effectiveOffsets(for stackIndex: Int, in layout: LayoutPattern) -> (horizontal: CGFloat, vertical: CGFloat) {
        let stackSettings = settings(for: stackIndex, in: layout)
        return (
            horizontal: globalHorizontalOffset + stackSettings.horizontalOffset,
            vertical: globalVerticalOffset + stackSettings.verticalOffset
        )
    }

    public mutating func setSettings(_ settings: StackPositionSettings, for stackIndex: Int, in layout: LayoutPattern) {
        let key = layout.storageKey
        var layoutConfig = layoutSettings[key] ?? LayoutStackSettings()
        layoutConfig.setSettings(settings, for: stackIndex)
        layoutSettings[key] = layoutConfig
    }

    public func layoutStackSettings(for layout: LayoutPattern) -> LayoutStackSettings {
        layoutSettings[layout.storageKey] ?? LayoutStackSettings()
    }
}


public struct BehaviorPreferences: Equatable, Codable, Sendable {
    public var showByDefault: Bool
    public var clickToFocus: Bool
    public var launchAtStartup: Bool

    public init(
        showByDefault: Bool = true,
        clickToFocus: Bool = true,
        launchAtStartup: Bool = false
    ) {
        self.showByDefault = showByDefault
        self.clickToFocus = clickToFocus
        self.launchAtStartup = launchAtStartup
    }

    public static let `default` = BehaviorPreferences()
}

public struct CodableColor: Equatable, Codable, Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.black
        self.red = Double(resolved.redComponent)
        self.green = Double(resolved.greenComponent)
        self.blue = Double(resolved.blueComponent)
        self.opacity = Double(resolved.alphaComponent)
    }

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}
