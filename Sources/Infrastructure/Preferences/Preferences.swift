import Foundation
import Observation

/// The user's settings, persisted in `UserDefaults`.
///
/// Changes are written through immediately and can be observed with the Observation framework.
@MainActor
@Observable
final class Preferences {
    var appearance: AppearancePreferences {
        didSet {
            guard appearance != oldValue else { return }
            save(appearance)
        }
    }

    var positioning: PositioningPreferences {
        didSet {
            guard positioning != oldValue else { return }
            save(positioning)
        }
    }

    var behavior: BehaviorPreferences {
        didSet {
            guard behavior != oldValue else { return }
            save(behavior)
            syncLoginItem()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: (any LoginItem)?

    /// - Parameter loginItem: The system's launch-at-login registration, which is the source of
    ///   truth for `behavior.launchAtStartup`. Pass nil to keep the setting purely local.
    init(defaults: UserDefaults = .standard, loginItem: (any LoginItem)? = nil) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.appearance = Self.loadAppearance(from: defaults)
        self.positioning = Self.loadPositioning(from: defaults)

        var behavior = Self.loadBehavior(from: defaults)
        if let loginItem {
            behavior.launchAtStartup = loginItem.isEnabled
        }
        self.behavior = behavior
    }

    func resetToDefaults() {
        appearance = .default
        positioning = .default
        behavior = .default
    }

    // MARK: - Login item

    private func syncLoginItem() {
        guard let loginItem, loginItem.isEnabled != behavior.launchAtStartup else { return }

        do {
            try loginItem.setEnabled(behavior.launchAtStartup)
        } catch {
            Log.preferences.error("Could not update the login item: \(String(describing: error), privacy: .public)")
        }
        // Show what the system actually did, which is not necessarily what was asked for.
        behavior.launchAtStartup = loginItem.isEnabled
    }

    // MARK: - Loading

    private static func loadAppearance(from defaults: UserDefaults) -> AppearancePreferences {
        let fallback = AppearancePreferences.default

        return AppearancePreferences(
            indicatorStyle: defaults.string(forKey: PreferencesKey.indicatorStyle.rawValue)
                .flatMap(IndicatorStyle.init(rawValue:)) ?? fallback.indicatorStyle,
            cornerRadius: defaults.double(for: .cornerRadius, default: fallback.cornerRadius),
            spacing: defaults.double(for: .spacing, default: fallback.spacing),
            containerPadding: defaults.double(for: .containerPadding, default: fallback.containerPadding),
            borderWidth: defaults.double(for: .borderWidth, default: fallback.borderWidth),
            showContainer: defaults.bool(for: .showContainer, default: fallback.showContainer),
            backgroundColor: defaults.json(for: .backgroundColor) ?? fallback.backgroundColor,
            borderColor: defaults.json(for: .borderColor) ?? fallback.borderColor,
            pillSettings: defaults.json(for: .pillSettings) ?? fallback.pillSettings,
            iconsSettings: defaults.json(for: .iconsSettings) ?? fallback.iconsSettings,
            minimalSettings: defaults.json(for: .minimalSettings) ?? fallback.minimalSettings
        )
    }

    private static func loadPositioning(from defaults: UserDefaults) -> PositioningPreferences {
        let fallback = PositioningPreferences.default

        return PositioningPreferences(
            stickToScreenEdge: defaults.bool(for: .stickToScreenEdge, default: fallback.stickToScreenEdge),
            showSingleWindowIndicators: defaults.bool(for: .showSingleWindowIndicators, default: fallback.showSingleWindowIndicators),
            globalHorizontalOffset: defaults.double(for: .globalHorizontalOffset, default: fallback.globalHorizontalOffset),
            globalVerticalOffset: defaults.double(for: .globalVerticalOffset, default: fallback.globalVerticalOffset),
            layoutSettings: defaults.json(for: .layoutSettings) ?? fallback.layoutSettings
        )
    }

    private static func loadBehavior(from defaults: UserDefaults) -> BehaviorPreferences {
        let fallback = BehaviorPreferences.default

        return BehaviorPreferences(
            showByDefault: defaults.bool(for: .showByDefault, default: fallback.showByDefault),
            clickToFocus: defaults.bool(for: .clickToFocus, default: fallback.clickToFocus),
            launchAtStartup: defaults.bool(for: .launchAtStartup, default: fallback.launchAtStartup)
        )
    }

    // MARK: - Saving

    private func save(_ appearance: AppearancePreferences) {
        defaults.set(appearance.indicatorStyle.rawValue, forKey: PreferencesKey.indicatorStyle.rawValue)
        defaults.set(Double(appearance.cornerRadius), forKey: PreferencesKey.cornerRadius.rawValue)
        defaults.set(Double(appearance.spacing), forKey: PreferencesKey.spacing.rawValue)
        defaults.set(Double(appearance.containerPadding), forKey: PreferencesKey.containerPadding.rawValue)
        defaults.set(Double(appearance.borderWidth), forKey: PreferencesKey.borderWidth.rawValue)
        defaults.set(appearance.showContainer, forKey: PreferencesKey.showContainer.rawValue)
        defaults.setJSON(appearance.backgroundColor, for: .backgroundColor)
        defaults.setJSON(appearance.borderColor, for: .borderColor)
        defaults.setJSON(appearance.pillSettings, for: .pillSettings)
        defaults.setJSON(appearance.iconsSettings, for: .iconsSettings)
        defaults.setJSON(appearance.minimalSettings, for: .minimalSettings)
    }

    private func save(_ positioning: PositioningPreferences) {
        defaults.set(positioning.stickToScreenEdge, forKey: PreferencesKey.stickToScreenEdge.rawValue)
        defaults.set(positioning.showSingleWindowIndicators, forKey: PreferencesKey.showSingleWindowIndicators.rawValue)
        defaults.set(Double(positioning.globalHorizontalOffset), forKey: PreferencesKey.globalHorizontalOffset.rawValue)
        defaults.set(Double(positioning.globalVerticalOffset), forKey: PreferencesKey.globalVerticalOffset.rawValue)
        defaults.setJSON(positioning.layoutSettings, for: .layoutSettings)
    }

    private func save(_ behavior: BehaviorPreferences) {
        defaults.set(behavior.showByDefault, forKey: PreferencesKey.showByDefault.rawValue)
        defaults.set(behavior.clickToFocus, forKey: PreferencesKey.clickToFocus.rawValue)
        defaults.set(behavior.launchAtStartup, forKey: PreferencesKey.launchAtStartup.rawValue)
    }
}

private extension UserDefaults {
    func bool(for key: PreferencesKey, default fallback: Bool) -> Bool {
        object(forKey: key.rawValue) == nil ? fallback : bool(forKey: key.rawValue)
    }

    func double(for key: PreferencesKey, default fallback: Double) -> Double {
        object(forKey: key.rawValue) == nil ? fallback : double(forKey: key.rawValue)
    }

    func json<Value: Decodable>(for key: PreferencesKey) -> Value? {
        data(forKey: key.rawValue).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    func setJSON(_ value: some Encodable, for key: PreferencesKey) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key.rawValue)
    }
}
