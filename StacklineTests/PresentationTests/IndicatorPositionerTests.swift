import XCTest
@testable import Stackline

final class IndicatorPositionerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let size = CGSize(width: 50, height: 24)

    private func stack(_ frame: CGRect, ids: [Int] = [1, 2]) -> WindowStack {
        WindowStack(windows: ids.map { .make(id: $0, frame: frame, stackIndex: $0) }, screenFrame: screen)
    }

    private func position(
        _ corner: StackCorner,
        frame: CGRect = CGRect(x: 500, y: 500, width: 800, height: 600),
        horizontalOffset: CGFloat = 0,
        verticalOffset: CGFloat = 0,
        stickToScreenEdge: Bool = true
    ) -> CGPoint {
        IndicatorPositioner.position(
            for: stack(frame),
            corner: corner,
            indicatorSize: size,
            screenBounds: screen,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            stickToScreenEdge: stickToScreenEdge
        )
    }

    // MARK: - Corners (AppKit coordinates: the top edge is maxY)

    func testCornersAnchorTheIndicatorInsideTheStackFrame() {
        XCTAssertEqual(position(.topLeft), CGPoint(x: 500, y: 1100 - 24))
        XCTAssertEqual(position(.topRight), CGPoint(x: 1300 - 50, y: 1100 - 24))
        XCTAssertEqual(position(.bottomLeft), CGPoint(x: 500, y: 500))
        XCTAssertEqual(position(.bottomRight), CGPoint(x: 1300 - 50, y: 500))
    }

    func testAutoPicksTheTopCornerOnTheStacksSideOfTheScreen() {
        let left = CGRect(x: 100, y: 500, width: 800, height: 600)
        let right = CGRect(x: 1700, y: 500, width: 800, height: 600)

        XCTAssertEqual(position(.auto, frame: left), position(.topLeft, frame: left))
        XCTAssertEqual(position(.auto, frame: right), position(.topRight, frame: right))
    }

    func testPositiveOffsetsMoveAwayFromTheCorner() {
        XCTAssertEqual(
            position(.topLeft, horizontalOffset: 10, verticalOffset: 20),
            CGPoint(x: 510, y: 1100 - 24 - 20)
        )
        XCTAssertEqual(
            position(.bottomRight, horizontalOffset: 10, verticalOffset: 20),
            CGPoint(x: 1300 - 50 - 10, y: 520)
        )
    }

    func testStickingToTheScreenEdgeKeepsTheIndicatorOnScreen() {
        let pushedOut = position(.topLeft, horizontalOffset: -900, stickToScreenEdge: true)
        let free = position(.topLeft, horizontalOffset: -900, stickToScreenEdge: false)

        XCTAssertEqual(pushedOut.x, 0)
        XCTAssertEqual(free.x, -400)
    }

    // MARK: - Frames from preferences

    func testFrameCombinesGlobalOffsetsWithTheStacksSettingsForItsLayout() {
        let left = stack(CGRect(x: 0, y: 0, width: 1280, height: 1440), ids: [1, 2])
        let right = stack(CGRect(x: 1280, y: 0, width: 1280, height: 1440), ids: [3, 4])
        let stacks = [left, right]
        let layout = IndicatorPositioner.detectLayout(from: stacks, screenBounds: screen)

        var positioning = PositioningPreferences(globalHorizontalOffset: 10, globalVerticalOffset: 5)
        positioning.setSettings(
            StackPositionSettings(stackCorner: .bottomLeft, horizontalOffset: 30, verticalOffset: 0),
            for: IndicatorPositioner.layoutIndex(for: right, in: stacks),
            in: layout
        )
        let appearance = AppearancePreferences.default
        let indicator = IndicatorSizeCalculator.size(for: right, appearance: appearance)

        let configured = IndicatorPositioner.frame(for: right, among: stacks, appearance: appearance, positioning: positioning)
        let untouched = IndicatorPositioner.frame(for: left, among: stacks, appearance: appearance, positioning: positioning)

        XCTAssertEqual(configured, CGRect(origin: CGPoint(x: 1280 + 10 + 30, y: 5), size: indicator))
        // The other stack keeps the default (auto → top-left) corner with only the global offsets.
        XCTAssertEqual(untouched.origin, CGPoint(x: 10, y: 1440 - indicator.height - 5))
    }

    func testSettingsSavedForOneLayoutDoNotApplyToAnother() {
        let left = stack(CGRect(x: 0, y: 0, width: 1280, height: 1440), ids: [1, 2])
        let right = stack(CGRect(x: 1280, y: 0, width: 1280, height: 1440), ids: [3, 4])
        let twoColumns = IndicatorPositioner.detectLayout(from: [left, right], screenBounds: screen)

        var positioning = PositioningPreferences()
        positioning.setSettings(StackPositionSettings(stackCorner: .bottomRight), for: 0, in: twoColumns)
        let appearance = AppearancePreferences.default

        let alone = IndicatorPositioner.frame(for: left, among: [left], appearance: appearance, positioning: positioning)
        let paired = IndicatorPositioner.frame(for: left, among: [left, right], appearance: appearance, positioning: positioning)

        XCTAssertEqual(alone.maxY, 1440)
        XCTAssertEqual(paired.minY, 0)
    }

    // MARK: - Layout identity

    /// Layout keys are persisted in users' preferences, so their format must not drift.
    func testLayoutStorageKeyFormat() {
        let full = stack(CGRect(x: 51, y: 14, width: 2458, height: 1382))

        let layout = IndicatorPositioner.detectLayout(from: [full], screenBounds: screen)

        XCTAssertEqual(layout.storageKey, "1|2,1,96,96")
        XCTAssertEqual(LayoutPattern(storageKey: layout.storageKey), layout)
    }

    // MARK: - Sizes

    func testIndicatorsGrowAlongTheirDirectionWithTheNumberOfWindows() {
        var appearance = AppearancePreferences.default
        appearance.iconsSettings.iconDirection = .horizontal
        appearance.minimalSettings.iconDirection = .vertical

        let icons2 = IndicatorSizeCalculator.iconsSize(windowCount: 2, appearance: appearance)
        let icons5 = IndicatorSizeCalculator.iconsSize(windowCount: 5, appearance: appearance)
        XCTAssertGreaterThan(icons5.width, icons2.width)
        XCTAssertEqual(icons5.height, icons2.height)

        let dots2 = IndicatorSizeCalculator.minimalSize(windowCount: 2, appearance: appearance)
        let dots5 = IndicatorSizeCalculator.minimalSize(windowCount: 5, appearance: appearance)
        XCTAssertGreaterThan(dots5.height, dots2.height)
        XCTAssertEqual(dots5.width, dots2.width)
    }
}
