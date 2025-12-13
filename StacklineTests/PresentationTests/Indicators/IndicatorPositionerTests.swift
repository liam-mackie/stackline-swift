import XCTest
@testable import Stackline

final class IndicatorPositionerTests: XCTestCase {
    let screenBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let indicatorSize = CGSize(width: 50, height: 24)

    // MARK: - Auto Corner Selection Tests
    // Current implementation only considers horizontal position:
    // - Windows on left side of screen → topLeft
    // - Windows on right side of screen → topRight

    func testAutoCornerSelectsTopLeftForLeftSideWindow() {
        // Window on left side of screen (center X < screen center X)
        let stack = createStack(x: 100, y: 500)
        let corner = IndicatorPositioner.autoSelectCorner(for: stack, screenBounds: screenBounds)
        XCTAssertEqual(corner, .topLeft)
    }

    func testAutoCornerSelectsTopRightForRightSideWindow() {
        // Window on right side of screen (center X >= screen center X)
        let stack = createStack(x: 2000, y: 500)
        let corner = IndicatorPositioner.autoSelectCorner(for: stack, screenBounds: screenBounds)
        XCTAssertEqual(corner, .topRight)
    }

    // MARK: - Position Calculation Tests

    func testPositionTopLeft() {
        let stack = createStack(x: 500, y: 500)
        let position = IndicatorPositioner.position(
            for: stack,
            corner: .topLeft,
            indicatorSize: indicatorSize,
            screenBounds: screenBounds
        )

        XCTAssertEqual(position.x, 500 + IndicatorPositioner.defaultEdgePadding)
        // AppKit: top-left corner means maxY - height - padding
        XCTAssertEqual(position.y, 500 + 600 - indicatorSize.height - IndicatorPositioner.defaultEdgePadding)
    }

    func testPositionTopRight() {
        let stack = createStack(x: 500, y: 500, width: 800, height: 600)
        let position = IndicatorPositioner.position(
            for: stack,
            corner: .topRight,
            indicatorSize: indicatorSize,
            screenBounds: screenBounds
        )

        // AppKit: top-right means maxX - width - padding, maxY - height - padding
        XCTAssertEqual(position.x, 500 + 800 - indicatorSize.width - IndicatorPositioner.defaultEdgePadding)
        XCTAssertEqual(position.y, 500 + 600 - indicatorSize.height - IndicatorPositioner.defaultEdgePadding)
    }

    func testPositionBottomLeft() {
        let stack = createStack(x: 500, y: 500, width: 800, height: 600)
        let position = IndicatorPositioner.position(
            for: stack,
            corner: .bottomLeft,
            indicatorSize: indicatorSize,
            screenBounds: screenBounds
        )

        // AppKit: bottom-left means minX + padding, minY + padding
        XCTAssertEqual(position.x, 500 + IndicatorPositioner.defaultEdgePadding)
        XCTAssertEqual(position.y, 500 + IndicatorPositioner.defaultEdgePadding)
    }

    func testPositionBottomRight() {
        let stack = createStack(x: 500, y: 500, width: 800, height: 600)
        let position = IndicatorPositioner.position(
            for: stack,
            corner: .bottomRight,
            indicatorSize: indicatorSize,
            screenBounds: screenBounds
        )

        // AppKit: bottom-right means maxX - width - padding, minY + padding
        XCTAssertEqual(position.x, 500 + 800 - indicatorSize.width - IndicatorPositioner.defaultEdgePadding)
        XCTAssertEqual(position.y, 500 + IndicatorPositioner.defaultEdgePadding)
    }

    func testPositionClampedToScreenBounds() {
        let stack = createStack(x: -100, y: -100)
        let position = IndicatorPositioner.position(
            for: stack,
            corner: .topLeft,
            indicatorSize: indicatorSize,
            screenBounds: screenBounds
        )

        XCTAssertGreaterThanOrEqual(position.x, screenBounds.minX + IndicatorPositioner.defaultEdgePadding)
        XCTAssertGreaterThanOrEqual(position.y, screenBounds.minY + IndicatorPositioner.defaultEdgePadding)
    }

    // MARK: - Helper Methods

    private func createStack(x: CGFloat, y: CGFloat, width: CGFloat = 800, height: CGFloat = 600) -> WindowStack {
        let window1 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Test",
            title: "Window 1",
            frame: CGRect(x: x, y: y, width: width, height: height),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: true,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
        let window2 = ManagedWindow(
            id: 2,
            processId: 101,
            applicationName: "Test",
            title: "Window 2",
            frame: CGRect(x: x, y: y, width: width, height: height),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 2,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
        return WindowStack(windows: [window1, window2], displayIndex: 1)
    }
}

final class IndicatorSizeCalculatorTests: XCTestCase {
    let defaultAppearance = AppearancePreferences.default

    func testPillSizeMinimum() {
        let size = IndicatorSizeCalculator.pillSize(windowCount: 1, appearance: defaultAppearance)
        XCTAssertGreaterThanOrEqual(size.width, defaultAppearance.pillSettings.pillWidth)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testPillSizeGrowsWithCount() {
        let size1 = IndicatorSizeCalculator.pillSize(windowCount: 1, appearance: defaultAppearance)
        let size10 = IndicatorSizeCalculator.pillSize(windowCount: 10, appearance: defaultAppearance)
        XCTAssertGreaterThan(size10.width, size1.width)
    }

    func testIconsSizeGrowsWithCount() {
        let size1 = IndicatorSizeCalculator.iconsSize(windowCount: 1, appearance: defaultAppearance)
        let size5 = IndicatorSizeCalculator.iconsSize(windowCount: 5, appearance: defaultAppearance)
        // Icons grow in the direction specified by iconDirection (default is vertical)
        XCTAssertGreaterThan(size5.height, size1.height)
    }

    func testMinimalSizeGrowsWithCount() {
        let size1 = IndicatorSizeCalculator.minimalSize(windowCount: 1, appearance: defaultAppearance)
        let size5 = IndicatorSizeCalculator.minimalSize(windowCount: 5, appearance: defaultAppearance)
        // Minimal dots grow in the direction specified by iconDirection (default is vertical)
        XCTAssertGreaterThan(size5.height, size1.height)
    }

    func testSizeForStackWithStyle() {
        let stack = createStack()

        var pillAppearance = defaultAppearance
        pillAppearance.indicatorStyle = .pill
        let pillSize = IndicatorSizeCalculator.size(for: stack, appearance: pillAppearance)

        var iconsAppearance = defaultAppearance
        iconsAppearance.indicatorStyle = .icons
        let iconsSize = IndicatorSizeCalculator.size(for: stack, appearance: iconsAppearance)

        var minimalAppearance = defaultAppearance
        minimalAppearance.indicatorStyle = .minimal
        let minimalSize = IndicatorSizeCalculator.size(for: stack, appearance: minimalAppearance)

        XCTAssertGreaterThan(pillSize.width, 0)
        XCTAssertGreaterThan(iconsSize.width, 0)
        XCTAssertGreaterThan(minimalSize.width, 0)
    }

    private func createStack() -> WindowStack {
        let window1 = ManagedWindow(
            id: 1,
            processId: 100,
            applicationName: "Test",
            title: "Window 1",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 1,
            isVisible: true,
            isFocused: true,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
        let window2 = ManagedWindow(
            id: 2,
            processId: 101,
            applicationName: "Test",
            title: "Window 2",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            spaceIndex: 1,
            displayIndex: 1,
            stackIndex: 2,
            isVisible: true,
            isFocused: false,
            isFloating: false,
            isMinimized: false,
            isFullscreen: false,
            isRootWindow: true
        )
        return WindowStack(windows: [window1, window2], displayIndex: 1)
    }
}
