import Foundation

public struct LegacyConfigMigrator {
    private let fileManager = FileManager.default
    private let defaults: CachedUserDefaults

    public init(defaults: CachedUserDefaults = CachedUserDefaults()) {
        self.defaults = defaults
    }

    public var hasMigrated: Bool {
        defaults.bool(forKey: PreferencesKey.hasMigratedFromJSON.rawValue, default: false)
    }

    public func migrateIfNeeded() {
        guard !hasMigrated else { return }

        if let legacyConfig = loadLegacyConfig() {
            migrate(legacyConfig)
            LoggingService.info("Migrated legacy JSON configuration to UserDefaults", category: .preferences)
        }

        defaults.setBool(true, forKey: PreferencesKey.hasMigratedFromJSON.rawValue)
    }

    private func loadLegacyConfig() -> LegacyConfiguration? {
        let possiblePaths = [
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Stackline/config.json"),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/stackline/config.json")
        ]

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path),
               let data = try? Data(contentsOf: path),
               let config = try? JSONDecoder().decode(LegacyConfiguration.self, from: data) {
                return config
            }
        }

        return nil
    }

    private func migrate(_ config: LegacyConfiguration) {
        if let appearance = config.appearance {
            migrateAppearance(appearance)
        }

        if let positioning = config.positioning {
            migratePositioning(positioning)
        }

        if let behavior = config.behavior {
            migrateBehavior(behavior)
        }
    }

    private func migrateAppearance(_ appearance: LegacyAppearance) {
        if let style = appearance.indicatorStyle {
            defaults.setString(style, forKey: PreferencesKey.indicatorStyle.rawValue)
        }
        if let direction = appearance.iconDirection {
            defaults.setString(direction, forKey: PreferencesKey.iconDirection.rawValue)
        }
        if let size = appearance.iconSize {
            defaults.setDouble(size, forKey: PreferencesKey.iconSize.rawValue)
        }
        if let height = appearance.pillHeight {
            defaults.setDouble(height, forKey: PreferencesKey.pillHeight.rawValue)
        }
        if let width = appearance.pillWidth {
            defaults.setDouble(width, forKey: PreferencesKey.pillWidth.rawValue)
        }
        if let size = appearance.minimalSize {
            defaults.setDouble(size, forKey: PreferencesKey.minimalSize.rawValue)
        }
        if let radius = appearance.cornerRadius {
            defaults.setDouble(radius, forKey: PreferencesKey.cornerRadius.rawValue)
        }
        if let spacing = appearance.spacing {
            defaults.setDouble(spacing, forKey: PreferencesKey.spacing.rawValue)
        }
        if let width = appearance.borderWidth {
            defaults.setDouble(width, forKey: PreferencesKey.borderWidth.rawValue)
        }
        if let show = appearance.showContainer {
            defaults.setBool(show, forKey: PreferencesKey.showContainer.rawValue)
        }
        if let color = appearance.backgroundColor {
            saveColor(color, forKey: .backgroundColor)
        }
        if let color = appearance.borderColor {
            saveColor(color, forKey: .borderColor)
        }
        if let color = appearance.focusedColor {
            saveColor(color, forKey: .focusedColor)
        }
        if let color = appearance.unfocusedColor {
            saveColor(color, forKey: .unfocusedColor)
        }
    }

    private func migratePositioning(_ positioning: LegacyPositioning) {
        if let stick = positioning.stickToScreenEdge {
            defaults.setBool(stick, forKey: PreferencesKey.stickToScreenEdge.rawValue)
        }
    }

    private func migrateBehavior(_ behavior: LegacyBehavior) {
        if let show = behavior.showByDefault {
            defaults.setBool(show, forKey: PreferencesKey.showByDefault.rawValue)
        }
        if let click = behavior.clickToFocus {
            defaults.setBool(click, forKey: PreferencesKey.clickToFocus.rawValue)
        }
        if let launch = behavior.launchAtStartup {
            defaults.setBool(launch, forKey: PreferencesKey.launchAtStartup.rawValue)
        }
    }

    private func saveColor(_ color: LegacyColor, forKey key: PreferencesKey) {
        let codableColor = CodableColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: color.opacity
        )
        if let data = try? JSONEncoder().encode(codableColor) {
            defaults.setData(data, forKey: key.rawValue)
        }
    }
}

struct LegacyConfiguration: Codable {
    let appearance: LegacyAppearance?
    let positioning: LegacyPositioning?
    let behavior: LegacyBehavior?
}

struct LegacyAppearance: Codable {
    let indicatorStyle: String?
    let iconDirection: String?
    let iconSize: Double?
    let pillHeight: Double?
    let pillWidth: Double?
    let minimalSize: Double?
    let cornerRadius: Double?
    let spacing: Double?
    let borderWidth: Double?
    let showContainer: Bool?
    let backgroundColor: LegacyColor?
    let borderColor: LegacyColor?
    let focusedColor: LegacyColor?
    let unfocusedColor: LegacyColor?
}

struct LegacyPositioning: Codable {
    let stackCorner: String?
    let edgeOffset: Double?
    let cornerOffset: Double?
    let stickToScreenEdge: Bool?
}

struct LegacyBehavior: Codable {
    let showByDefault: Bool?
    let hideWhenNoStacks: Bool?
    let clickToFocus: Bool?
    let showOnAllSpaces: Bool?
    let launchAtStartup: Bool?
    let showMainWindowAtLaunch: Bool?
}

struct LegacyColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
}
