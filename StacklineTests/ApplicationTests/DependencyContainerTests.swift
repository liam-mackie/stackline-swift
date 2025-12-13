import XCTest
@testable import Stackline

@MainActor
final class DependencyContainerTests: XCTestCase {

    func testSharedInstanceExists() {
        let container = DependencyContainer.shared
        XCTAssertNotNil(container)
    }

    func testSharedInstanceIsSingleton() {
        let container1 = DependencyContainer.shared
        let container2 = DependencyContainer.shared
        XCTAssertTrue(container1 === container2)
    }

    func testPreferencesAccessible() {
        let container = DependencyContainer.shared
        let preferences = container.preferences
        XCTAssertNotNil(preferences)
    }

    func testLoggingServiceAccessible() {
        let container = DependencyContainer.shared
        let loggingService = container.loggingService
        XCTAssertNotNil(loggingService)
    }

    func testWindowManagerAccessible() {
        let container = DependencyContainer.shared
        let windowManager = container.windowManager
        XCTAssertNotNil(windowManager)
    }

    func testStackDetectorAccessible() {
        let container = DependencyContainer.shared
        let stackDetector = container.stackDetector
        XCTAssertNotNil(stackDetector)
    }

    func testIndicatorCoordinatorAccessible() {
        let container = DependencyContainer.shared
        let coordinator = container.indicatorCoordinator
        XCTAssertNotNil(coordinator)
    }
}
