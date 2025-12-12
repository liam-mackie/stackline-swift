import AppKit
import Combine
import SwiftUI

/// Manages the lifecycle of indicator windows for all stacks
@MainActor
final class IndicatorCoordinator: PreferencesObserver {
    private let tracer = PerformanceTracer.shared
    private var windows: [String: IndicatorWindow] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let stackDetector: StackDetectorProtocol
    private let windowManager: any WindowManagerProtocol
    private let preferences: any PreferencesProtocol
    private let coordinateSystem: CoordinateSystemProtocol

    init(
        stackDetector: StackDetectorProtocol,
        windowManager: any WindowManagerProtocol,
        preferences: any PreferencesProtocol,
        coordinateSystem: CoordinateSystemProtocol = CoreGraphicsCoordinateSystem()
    ) {
        self.stackDetector = stackDetector
        self.windowManager = windowManager
        self.preferences = preferences
        self.coordinateSystem = coordinateSystem

        setupSubscriptions()
        preferences.addObserver(self)
    }

    nonisolated func preferencesDidChange(_ keyPath: AnyKeyPath) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshAllIndicators()
        }
    }

    private func setupSubscriptions() {
        stackDetector.stacksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stacks in
                self?.updateIndicators(for: stacks)
            }
            .store(in: &cancellables)
    }

    private func refreshAllIndicators() {
        let stacks = stackDetector.detectedStacks
        for stack in stacks {
            updateIndicator(for: stack)
        }
    }

    func start() {
        let stacks = stackDetector.detectedStacks
        updateIndicators(for: stacks)
    }

    func stop() {
        preferences.removeObserver(self)
        removeAllIndicators()
    }

    private func updateIndicators(for stacks: [WindowStack]) {
        let state = tracer.begin("UpdateIndicators", category: .uiUpdate)
        defer { tracer.end("UpdateIndicators", state, "stacks=\(stacks.count)") }

        guard preferences.behavior.showByDefault else {
            removeAllIndicators()
            return
        }

        let visibleStacks = stacks.filter { stack in
            stack.count > 1 || preferences.positioning.showSingleWindowIndicators
        }

        let currentStackIds = Set(visibleStacks.map(\.id))
        let existingStackIds = Set(windows.keys)

        let toRemove = existingStackIds.subtracting(currentStackIds)
        for stackId in toRemove {
            removeIndicator(for: stackId)
        }

        for stack in visibleStacks {
            if windows[stack.id] != nil {
                updateIndicator(for: stack)
            } else {
                createIndicator(for: stack)
            }
        }
    }

    private func createIndicator(for stack: WindowStack) {
        let state = tracer.begin("CreateIndicator", category: .uiUpdate)
        defer { tracer.end("CreateIndicator", state) }

        let appearance = preferences.appearance
        let positioning = preferences.positioning
        let behavior = preferences.behavior
        let allStacks = stackDetector.detectedStacks

        let size = IndicatorSizeCalculator.size(for: stack, appearance: appearance)
        let screenBounds = coordinateSystem.displayContaining(rect: stack.frame) ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let stacksOnSameDisplay = allStacks.filter { $0.displayIndex == stack.displayIndex }
        let layout = IndicatorPositioner.detectLayout(from: stacksOnSameDisplay, screenBounds: screenBounds)
        let stackIndex = IndicatorPositioner.layoutIndex(for: stack, in: stacksOnSameDisplay)
        let positionSettings = positioning.settings(for: stackIndex, in: layout)
        let offsets = positioning.effectiveOffsets(for: stackIndex, in: layout)

        let position = IndicatorPositioner.position(
            for: stack,
            corner: positionSettings.stackCorner,
            indicatorSize: size,
            screenBounds: screenBounds,
            horizontalOffset: offsets.horizontal,
            verticalOffset: offsets.vertical,
            stickToScreenEdge: positioning.stickToScreenEdge
        )

        let window = IndicatorWindow(
            stackId: stack.id,
            contentRect: NSRect(origin: position, size: size),
            clickable: behavior.clickToFocus
        )

        let view = IndicatorView(
            stack: stack,
            style: appearance.indicatorStyle,
            appearance: appearance,
            onWindowClick: behavior.clickToFocus ? makeClickHandler() : nil
        )
        window.setIndicatorView(view)
        window.orderFront(nil)

        windows[stack.id] = window
    }

    private func updateIndicator(for stack: WindowStack) {
        let state = tracer.begin("UpdateIndicator", category: .uiUpdate)
        defer { tracer.end("UpdateIndicator", state) }

        guard let window = windows[stack.id] else { return }

        let appearance = preferences.appearance
        let positioning = preferences.positioning
        let behavior = preferences.behavior
        let allStacks = stackDetector.detectedStacks

        let size = IndicatorSizeCalculator.size(for: stack, appearance: appearance)
        let screenBounds = coordinateSystem.displayContaining(rect: stack.frame) ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)

        let stacksOnSameDisplay = allStacks.filter { $0.displayIndex == stack.displayIndex }
        let layout = IndicatorPositioner.detectLayout(from: stacksOnSameDisplay, screenBounds: screenBounds)
        let stackIndex = IndicatorPositioner.layoutIndex(for: stack, in: stacksOnSameDisplay)
        let positionSettings = positioning.settings(for: stackIndex, in: layout)
        let offsets = positioning.effectiveOffsets(for: stackIndex, in: layout)

        let position = IndicatorPositioner.position(
            for: stack,
            corner: positionSettings.stackCorner,
            indicatorSize: size,
            screenBounds: screenBounds,
            horizontalOffset: offsets.horizontal,
            verticalOffset: offsets.vertical,
            stickToScreenEdge: positioning.stickToScreenEdge
        )

        window.updateSize(size)
        window.updatePosition(position)
        window.setClickable(behavior.clickToFocus)

        let view = IndicatorView(
            stack: stack,
            style: appearance.indicatorStyle,
            appearance: appearance,
            onWindowClick: behavior.clickToFocus ? makeClickHandler() : nil
        )
        window.setIndicatorView(view)
    }

    private func makeClickHandler() -> (WindowIdentifier) -> Void {
        return { [weak self] windowId in
            guard let self = self else { return }
            Task {
                do {
                    try await self.windowManager.focusWindow(windowId)
                } catch {
                    // Focus failed - window may have been closed
                }
            }
        }
    }

    private func removeIndicator(for stackId: String) {
        guard let window = windows.removeValue(forKey: stackId) else { return }
        window.orderOut(nil)
        window.close()
    }

    private func removeAllIndicators() {
        for (_, window) in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}
