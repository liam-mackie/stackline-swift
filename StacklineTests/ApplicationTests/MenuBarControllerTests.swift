import XCTest
@testable import Stackline

@MainActor
final class MenuBarControllerTests: XCTestCase {

    func testMenuBarControllerInitialization() {
        let controller = MenuBarController(container: DependencyContainer.shared)
        XCTAssertNotNil(controller)
    }
}
