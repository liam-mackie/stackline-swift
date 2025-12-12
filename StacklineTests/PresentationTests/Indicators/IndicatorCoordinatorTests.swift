import XCTest
import Combine
@testable import Stackline

@MainActor
final class IndicatorCoordinatorTests: XCTestCase {

    func testCoordinatorInitialization() async throws {
        let mockWindowManager = MockWindowManager()
        let mockCoordinateSystem = MockCoordinateSystem()
        try await mockWindowManager.connect()

        let stackDetector = StackDetector(
            windowManager: mockWindowManager,
            coordinateSystem: mockCoordinateSystem
        )

        let preferences = createMockPreferences()

        let coordinator = IndicatorCoordinator(
            stackDetector: stackDetector,
            windowManager: mockWindowManager,
            preferences: preferences,
            coordinateSystem: mockCoordinateSystem
        )

        XCTAssertNotNil(coordinator)
    }

    private func createMockPreferences() -> UserDefaultsPreferences {
        let defaults = CachedUserDefaults(suiteName: "sh.mackie.stackline.test.\(UUID().uuidString)")
        return UserDefaultsPreferences(defaults: defaults)
    }
}
