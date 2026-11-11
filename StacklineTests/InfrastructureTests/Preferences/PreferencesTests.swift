import XCTest
@testable import Stackline

@MainActor
final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "sh.mackie.stackline.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Persistence

    func testStartsWithDefaults() {
        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.appearance, .default)
        XCTAssertEqual(preferences.positioning, .default)
        XCTAssertEqual(preferences.behavior, .default)
    }

    func testChangesSurviveARelaunch() {
        let preferences = Preferences(defaults: defaults)
        preferences.appearance.indicatorStyle = .minimal
        preferences.appearance.cornerRadius = 12
        preferences.appearance.backgroundColor = CodableColor(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4)
        preferences.appearance.iconsSettings.iconSize = 32
        preferences.positioning.globalHorizontalOffset = -50
        preferences.positioning.showSingleWindowIndicators = false
        preferences.positioning.setSettings(
            StackPositionSettings(stackCorner: .bottomRight, horizontalOffset: 4, verticalOffset: 8),
            for: 1,
            in: LayoutPattern(storageKey: "2|0,0,50,100;50,0,50,100")!
        )
        preferences.behavior.clickToFocus = false

        let relaunched = Preferences(defaults: defaults)

        XCTAssertEqual(relaunched.appearance, preferences.appearance)
        XCTAssertEqual(relaunched.positioning, preferences.positioning)
        XCTAssertEqual(relaunched.behavior, preferences.behavior)
    }

    /// Settings written by Stackline 2.0, byte for byte as found in a real preferences domain.
    func testReadsSettingsWrittenByEarlierVersions() {
        func json(_ text: String) -> Data { Data(text.utf8) }
        defaults.set("icons", forKey: "appearance.indicatorStyle")
        defaults.set(20, forKey: "appearance.cornerRadius")
        defaults.set(false, forKey: "appearance.showContainer")
        defaults.set(json(#"{"green":0,"blue":0,"red":0,"opacity":0.6}"#), forKey: "appearance.backgroundColor")
        defaults.set(
            json(#"{"unfocusedOpacity":0.6,"focusedColor":{"red":1,"blue":1,"opacity":1,"green":1},"iconSize":32,"iconDirection":"vertical"}"#),
            forKey: "appearance.iconsSettings"
        )
        defaults.set(json(#"{"pillHeight":6,"textColor":{"red":1,"blue":1,"opacity":1,"green":1},"pillWidth":40}"#), forKey: "appearance.pillSettings")
        defaults.set(-50.0, forKey: "positioning.globalHorizontalOffset")
        defaults.set(false, forKey: "positioning.showSingleWindowIndicators")
        defaults.set(
            json(#"{"1|2,1,96,96":{"stackSettings":{"0":{"verticalOffset":0,"stackCorner":"topRight","horizontalOffset":12}}}}"#),
            forKey: "positioning.layoutSettings"
        )
        defaults.set(false, forKey: "behavior.clickToFocus")

        let preferences = Preferences(defaults: defaults)

        XCTAssertEqual(preferences.appearance.indicatorStyle, .icons)
        XCTAssertEqual(preferences.appearance.cornerRadius, 20)
        XCTAssertFalse(preferences.appearance.showContainer)
        XCTAssertEqual(preferences.appearance.backgroundColor, CodableColor(red: 0, green: 0, blue: 0, opacity: 0.6))
        XCTAssertEqual(preferences.appearance.iconsSettings.iconSize, 32)
        XCTAssertEqual(preferences.appearance.pillSettings, .default)
        XCTAssertEqual(preferences.positioning.globalHorizontalOffset, -50)
        XCTAssertFalse(preferences.positioning.showSingleWindowIndicators)
        XCTAssertEqual(
            preferences.positioning.settings(for: 0, in: LayoutPattern(storageKey: "1|2,1,96,96")!),
            StackPositionSettings(stackCorner: .topRight, horizontalOffset: 12, verticalOffset: 0)
        )
        XCTAssertFalse(preferences.behavior.clickToFocus)
        // Untouched keys keep their defaults.
        XCTAssertEqual(preferences.appearance.spacing, AppearancePreferences.default.spacing)
        XCTAssertTrue(preferences.behavior.showByDefault)
    }

    func testResetRestoresDefaultsPersistently() {
        let preferences = Preferences(defaults: defaults)
        preferences.appearance.indicatorStyle = .minimal
        preferences.positioning.stickToScreenEdge = false
        preferences.behavior.showByDefault = false

        preferences.resetToDefaults()

        let relaunched = Preferences(defaults: defaults)
        XCTAssertEqual(relaunched.appearance, .default)
        XCTAssertEqual(relaunched.positioning, .default)
        XCTAssertEqual(relaunched.behavior, .default)
    }

    // MARK: - Login item

    func testLaunchAtLoginReflectsTheSystemRegistrationAtLaunch() {
        defaults.set(false, forKey: "behavior.launchAtStartup")
        let loginItem = FakeLoginItem(isEnabled: true)

        let preferences = Preferences(defaults: defaults, loginItem: loginItem)

        XCTAssertTrue(preferences.behavior.launchAtStartup)
        XCTAssertEqual(loginItem.changes, [])
    }

    func testTogglingLaunchAtLoginUpdatesTheSystemRegistration() {
        let loginItem = FakeLoginItem(isEnabled: false)
        let preferences = Preferences(defaults: defaults, loginItem: loginItem)

        preferences.behavior.launchAtStartup = true
        preferences.behavior.launchAtStartup = false

        XCTAssertEqual(loginItem.changes, [true, false])
    }

    func testOtherBehaviorChangesLeaveTheLoginItemAlone() {
        let loginItem = FakeLoginItem(isEnabled: true)
        let preferences = Preferences(defaults: defaults, loginItem: loginItem)

        preferences.behavior.showByDefault.toggle()
        preferences.behavior.clickToFocus.toggle()

        XCTAssertEqual(loginItem.changes, [])
    }

    func testLaunchAtLoginSnapsBackWhenTheSystemRefuses() {
        let loginItem = FakeLoginItem(isEnabled: false)
        loginItem.failure = CocoaError(.featureUnsupported)
        let preferences = Preferences(defaults: defaults, loginItem: loginItem)

        preferences.behavior.launchAtStartup = true

        XCTAssertFalse(preferences.behavior.launchAtStartup)
        XCTAssertFalse(Preferences(defaults: defaults).behavior.launchAtStartup)
    }
}

@MainActor
private final class FakeLoginItem: LoginItem {
    private(set) var isEnabled: Bool
    private(set) var changes: [Bool] = []
    var failure: (any Error)?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        changes.append(enabled)
        if let failure { throw failure }
        isEnabled = enabled
    }
}
