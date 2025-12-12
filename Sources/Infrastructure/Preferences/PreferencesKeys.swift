import Foundation

public enum PreferencesKey: String, CaseIterable {
    case indicatorStyle = "appearance.indicatorStyle"
    case iconDirection = "appearance.iconDirection"
    case iconSize = "appearance.iconSize"
    case pillHeight = "appearance.pillHeight"
    case pillWidth = "appearance.pillWidth"
    case minimalSize = "appearance.minimalSize"
    case cornerRadius = "appearance.cornerRadius"
    case spacing = "appearance.spacing"
    case containerPadding = "appearance.containerPadding"
    case borderWidth = "appearance.borderWidth"
    case showContainer = "appearance.showContainer"
    case backgroundColor = "appearance.backgroundColor"
    case borderColor = "appearance.borderColor"
    case focusedColor = "appearance.focusedColor"
    case unfocusedColor = "appearance.unfocusedColor"

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
