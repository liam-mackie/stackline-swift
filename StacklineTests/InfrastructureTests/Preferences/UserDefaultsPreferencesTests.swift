import XCTest
@testable import Stackline

final class UserDefaultsPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: CachedUserDefaults!
    private var preferences: UserDefaultsPreferences!

    override func setUp() {
        super.setUp()
        suiteName = "sh.mackie.stackline.test.\(UUID().uuidString)"
        defaults = CachedUserDefaults(suiteName: suiteName)
        preferences = UserDefaultsPreferences(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        preferences = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultAppearanceValues() {
        XCTAssertEqual(preferences.appearance.indicatorStyle, .pill)
        XCTAssertEqual(preferences.appearance.iconsSettings.iconDirection, .vertical)
        XCTAssertEqual(preferences.appearance.iconsSettings.iconSize, 24)
        XCTAssertEqual(preferences.appearance.pillSettings.pillHeight, 6)
        XCTAssertEqual(preferences.appearance.pillSettings.pillWidth, 40)
        XCTAssertTrue(preferences.appearance.showContainer)
    }

    func testDefaultPositioningValues() {
        XCTAssertTrue(preferences.positioning.stickToScreenEdge)
        XCTAssertTrue(preferences.positioning.showSingleWindowIndicators)
        XCTAssertTrue(preferences.positioning.layoutSettings.isEmpty)
    }

    func testDefaultBehaviorValues() {
        XCTAssertTrue(preferences.behavior.showByDefault)
        XCTAssertTrue(preferences.behavior.clickToFocus)
        XCTAssertFalse(preferences.behavior.launchAtStartup)
    }

    func testAppearanceChangesPersist() {
        preferences.appearance.indicatorStyle = .icons
        preferences.appearance.iconsSettings.iconSize = 32

        let newPreferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertEqual(newPreferences.appearance.indicatorStyle, .icons)
        XCTAssertEqual(newPreferences.appearance.iconsSettings.iconSize, 32)
    }

    func testPositioningChangesPersist() {
        preferences.positioning.stickToScreenEdge = false
        preferences.positioning.showSingleWindowIndicators = false

        let newPreferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertFalse(newPreferences.positioning.stickToScreenEdge)
        XCTAssertFalse(newPreferences.positioning.showSingleWindowIndicators)
    }

    func testBehaviorChangesPersist() {
        preferences.behavior.showByDefault = false
        preferences.behavior.clickToFocus = false

        let newPreferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertFalse(newPreferences.behavior.showByDefault)
        XCTAssertFalse(newPreferences.behavior.clickToFocus)
    }

    func testResetToDefaults() {
        preferences.appearance.indicatorStyle = .minimal
        preferences.positioning.stickToScreenEdge = false
        preferences.behavior.showByDefault = false

        preferences.resetToDefaults()

        XCTAssertEqual(preferences.appearance.indicatorStyle, .pill)
        XCTAssertTrue(preferences.positioning.stickToScreenEdge)
        XCTAssertTrue(preferences.behavior.showByDefault)
    }

    func testObserverNotification() {
        let observer = MockPreferencesObserver()
        preferences.addObserver(observer)

        preferences.appearance.indicatorStyle = .icons

        let expectation = expectation(description: "Observer notified")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(observer.changedKeyPaths.count, 1)
    }

    func testObserverRemoval() {
        let observer = MockPreferencesObserver()
        preferences.addObserver(observer)
        preferences.removeObserver(observer)

        preferences.appearance.indicatorStyle = .icons

        let expectation = expectation(description: "Queue processed")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(observer.changedKeyPaths.count, 0)
    }
}

final class MockPreferencesObserver: PreferencesObserver {
    var changedKeyPaths: [AnyKeyPath] = []

    func preferencesDidChange(_ keyPath: AnyKeyPath) {
        changedKeyPaths.append(keyPath)
    }
}
