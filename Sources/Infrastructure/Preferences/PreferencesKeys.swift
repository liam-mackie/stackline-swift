import Foundation

public enum PreferencesKey: String, CaseIterable {
    // Appearance - shared
    case indicatorStyle = "appearance.indicatorStyle"
    case cornerRadius = "appearance.cornerRadius"
    case spacing = "appearance.spacing"
    case containerPadding = "appearance.containerPadding"
    case borderWidth = "appearance.borderWidth"
    case showContainer = "appearance.showContainer"
    case backgroundColor = "appearance.backgroundColor"
    case borderColor = "appearance.borderColor"

    // Appearance - style-specific (stored as JSON)
    case pillSettings = "appearance.pillSettings"
    case iconsSettings = "appearance.iconsSettings"
    case minimalSettings = "appearance.minimalSettings"

    // Positioning
    case stickToScreenEdge = "positioning.stickToScreenEdge"
    case showSingleWindowIndicators = "positioning.showSingleWindowIndicators"
    case globalHorizontalOffset = "positioning.globalHorizontalOffset"
    case globalVerticalOffset = "positioning.globalVerticalOffset"
    case layoutSettings = "positioning.layoutSettings"

    case showByDefault = "behavior.showByDefault"
    case clickToFocus = "behavior.clickToFocus"
    case launchAtStartup = "behavior.launchAtStartup"

    case hasMigratedFromJSON = "migration.hasMigratedFromJSON"
}
