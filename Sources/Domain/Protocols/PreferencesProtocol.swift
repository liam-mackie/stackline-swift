import Foundation
import Combine
import SwiftUI

public protocol PreferencesObserver: AnyObject {
    func preferencesDidChange(_ keyPath: AnyKeyPath)
}

public protocol PreferencesProtocol: AnyObject, ObservableObject {
    var appearance: AppearancePreferences { get set }
    var positioning: PositioningPreferences { get set }
    var behavior: BehaviorPreferences { get set }

    func addObserver(_ observer: PreferencesObserver)
    func removeObserver(_ observer: PreferencesObserver)
    func resetToDefaults()
}
