import Foundation
import Combine
import SwiftUI
import ServiceManagement

public final class UserDefaultsPreferences: PreferencesProtocol, ObservableObject, @unchecked Sendable {
    private let defaults: CachedUserDefaults
    private var observers: [WeakObserverBox] = []
    private let observerLock = NSLock()

    @Published public var appearance: AppearancePreferences {
        didSet {
            saveAppearance()
            notifyObservers(\UserDefaultsPreferences.appearance)
        }
    }

    @Published public var positioning: PositioningPreferences {
        didSet {
            savePositioning()
            notifyObservers(\UserDefaultsPreferences.positioning)
        }
    }

    @Published public var behavior: BehaviorPreferences {
        didSet {
            saveBehavior()
            notifyObservers(\UserDefaultsPreferences.behavior)
        }
    }

    public init(defaults: CachedUserDefaults = CachedUserDefaults()) {
        self.defaults = defaults
        self.appearance = Self.loadAppearance(from: defaults)
        self.positioning = Self.loadPositioning(from: defaults)
        self.behavior = Self.loadBehavior(from: defaults)
        syncLoginItemState()
    }

    private func syncLoginItemState() {
        if #available(macOS 13.0, *) {
            let isRegistered = SMAppService.mainApp.status == .enabled
            if behavior.launchAtStartup != isRegistered {
                behavior = BehaviorPreferences(
                    showByDefault: behavior.showByDefault,
                    clickToFocus: behavior.clickToFocus,
                    launchAtStartup: isRegistered
                )
            }
        }
    }

    public func addObserver(_ observer: PreferencesObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }
        observers.removeAll { $0.observer == nil }
        observers.append(WeakObserverBox(observer: observer))
    }

    public func removeObserver(_ observer: PreferencesObserver) {
        observerLock.lock()
        defer { observerLock.unlock() }
        observers.removeAll { $0.observer === observer || $0.observer == nil }
    }

    public func resetToDefaults() {
        appearance = .default
        positioning = .default
        behavior = .default
    }

    private func notifyObservers(_ keyPath: AnyKeyPath) {
        observerLock.lock()
        let currentObservers = observers.compactMap { $0.observer }
        observerLock.unlock()

        nonisolated(unsafe) let capturedKeyPath = keyPath
        DispatchQueue.main.async {
            for observer in currentObservers {
                observer.preferencesDidChange(capturedKeyPath)
            }
        }
    }

    private static func loadAppearance(from defaults: CachedUserDefaults) -> AppearancePreferences {
        let defaultAppearance = AppearancePreferences.default

        return AppearancePreferences(
            indicatorStyle: defaults.string(forKey: PreferencesKey.indicatorStyle.rawValue)
                .flatMap { IndicatorStyle(rawValue: $0) } ?? defaultAppearance.indicatorStyle,
            iconDirection: defaults.string(forKey: PreferencesKey.iconDirection.rawValue)
                .flatMap { IconDirection(rawValue: $0) } ?? defaultAppearance.iconDirection,
            iconSize: CGFloat(defaults.double(forKey: PreferencesKey.iconSize.rawValue, default: defaultAppearance.iconSize)),
            pillHeight: CGFloat(defaults.double(forKey: PreferencesKey.pillHeight.rawValue, default: defaultAppearance.pillHeight)),
            pillWidth: CGFloat(defaults.double(forKey: PreferencesKey.pillWidth.rawValue, default: defaultAppearance.pillWidth)),
            minimalSize: CGFloat(defaults.double(forKey: PreferencesKey.minimalSize.rawValue, default: defaultAppearance.minimalSize)),
            cornerRadius: CGFloat(defaults.double(forKey: PreferencesKey.cornerRadius.rawValue, default: defaultAppearance.cornerRadius)),
            spacing: CGFloat(defaults.double(forKey: PreferencesKey.spacing.rawValue, default: defaultAppearance.spacing)),
            containerPadding: CGFloat(defaults.double(forKey: PreferencesKey.containerPadding.rawValue, default: defaultAppearance.containerPadding)),
            borderWidth: CGFloat(defaults.double(forKey: PreferencesKey.borderWidth.rawValue, default: defaultAppearance.borderWidth)),
            showContainer: defaults.bool(forKey: PreferencesKey.showContainer.rawValue, default: defaultAppearance.showContainer),
            backgroundColor: loadColor(from: defaults, key: .backgroundColor, default: defaultAppearance.backgroundColor),
            borderColor: loadColor(from: defaults, key: .borderColor, default: defaultAppearance.borderColor),
            focusedColor: loadColor(from: defaults, key: .focusedColor, default: defaultAppearance.focusedColor),
            unfocusedColor: loadColor(from: defaults, key: .unfocusedColor, default: defaultAppearance.unfocusedColor)
        )
    }

    private static func loadPositioning(from defaults: CachedUserDefaults) -> PositioningPreferences {
        let defaultPositioning = PositioningPreferences.default

        var layoutSettings: [String: LayoutStackSettings] = [:]
        if let data = defaults.data(forKey: PreferencesKey.layoutSettings.rawValue),
           let decoded = try? JSONDecoder().decode([String: LayoutStackSettings].self, from: data) {
            layoutSettings = decoded
        }

        return PositioningPreferences(
            stickToScreenEdge: defaults.bool(forKey: PreferencesKey.stickToScreenEdge.rawValue, default: defaultPositioning.stickToScreenEdge),
            showSingleWindowIndicators: defaults.bool(forKey: PreferencesKey.showSingleWindowIndicators.rawValue, default: defaultPositioning.showSingleWindowIndicators),
            globalHorizontalOffset: CGFloat(defaults.double(forKey: PreferencesKey.globalHorizontalOffset.rawValue, default: defaultPositioning.globalHorizontalOffset)),
            globalVerticalOffset: CGFloat(defaults.double(forKey: PreferencesKey.globalVerticalOffset.rawValue, default: defaultPositioning.globalVerticalOffset)),
            layoutSettings: layoutSettings
        )
    }

    private static func loadBehavior(from defaults: CachedUserDefaults) -> BehaviorPreferences {
        let defaultBehavior = BehaviorPreferences.default

        return BehaviorPreferences(
            showByDefault: defaults.bool(forKey: PreferencesKey.showByDefault.rawValue, default: defaultBehavior.showByDefault),
            clickToFocus: defaults.bool(forKey: PreferencesKey.clickToFocus.rawValue, default: defaultBehavior.clickToFocus),
            launchAtStartup: defaults.bool(forKey: PreferencesKey.launchAtStartup.rawValue, default: defaultBehavior.launchAtStartup)
        )
    }

    private static func loadColor(from defaults: CachedUserDefaults, key: PreferencesKey, default defaultColor: CodableColor) -> CodableColor {
        guard let data = defaults.data(forKey: key.rawValue),
              let color = try? JSONDecoder().decode(CodableColor.self, from: data) else {
            return defaultColor
        }
        return color
    }

    private func saveAppearance() {
        defaults.setString(appearance.indicatorStyle.rawValue, forKey: PreferencesKey.indicatorStyle.rawValue)
        defaults.setString(appearance.iconDirection.rawValue, forKey: PreferencesKey.iconDirection.rawValue)
        defaults.setDouble(appearance.iconSize, forKey: PreferencesKey.iconSize.rawValue)
        defaults.setDouble(appearance.pillHeight, forKey: PreferencesKey.pillHeight.rawValue)
        defaults.setDouble(appearance.pillWidth, forKey: PreferencesKey.pillWidth.rawValue)
        defaults.setDouble(appearance.minimalSize, forKey: PreferencesKey.minimalSize.rawValue)
        defaults.setDouble(appearance.cornerRadius, forKey: PreferencesKey.cornerRadius.rawValue)
        defaults.setDouble(appearance.spacing, forKey: PreferencesKey.spacing.rawValue)
        defaults.setDouble(appearance.containerPadding, forKey: PreferencesKey.containerPadding.rawValue)
        defaults.setDouble(appearance.borderWidth, forKey: PreferencesKey.borderWidth.rawValue)
        defaults.setBool(appearance.showContainer, forKey: PreferencesKey.showContainer.rawValue)
        saveColor(appearance.backgroundColor, forKey: .backgroundColor)
        saveColor(appearance.borderColor, forKey: .borderColor)
        saveColor(appearance.focusedColor, forKey: .focusedColor)
        saveColor(appearance.unfocusedColor, forKey: .unfocusedColor)
    }

    private func savePositioning() {
        defaults.setBool(positioning.stickToScreenEdge, forKey: PreferencesKey.stickToScreenEdge.rawValue)
        defaults.setBool(positioning.showSingleWindowIndicators, forKey: PreferencesKey.showSingleWindowIndicators.rawValue)
        defaults.setDouble(positioning.globalHorizontalOffset, forKey: PreferencesKey.globalHorizontalOffset.rawValue)
        defaults.setDouble(positioning.globalVerticalOffset, forKey: PreferencesKey.globalVerticalOffset.rawValue)

        if let data = try? JSONEncoder().encode(positioning.layoutSettings) {
            defaults.setData(data, forKey: PreferencesKey.layoutSettings.rawValue)
        }
    }

    private func saveBehavior() {
        defaults.setBool(behavior.showByDefault, forKey: PreferencesKey.showByDefault.rawValue)
        defaults.setBool(behavior.clickToFocus, forKey: PreferencesKey.clickToFocus.rawValue)
        defaults.setBool(behavior.launchAtStartup, forKey: PreferencesKey.launchAtStartup.rawValue)
        updateLoginItem(enabled: behavior.launchAtStartup)
    }

    private func updateLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // SMAppService can throw if already in the desired state
            }
        }
    }

    private func saveColor(_ color: CodableColor, forKey key: PreferencesKey) {
        if let data = try? JSONEncoder().encode(color) {
            defaults.setData(data, forKey: key.rawValue)
        }
    }
}

private final class WeakObserverBox {
    weak var observer: PreferencesObserver?

    init(observer: PreferencesObserver) {
        self.observer = observer
    }
}
