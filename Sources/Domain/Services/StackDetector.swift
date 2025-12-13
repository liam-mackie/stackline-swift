import Foundation
import Combine

/// Production implementation of stack detection
@MainActor
final class StackDetector: StackDetectorProtocol, ObservableObject {
    private let tracer = PerformanceTracer.shared
    /// Position tolerance for grouping windows into stacks (in points)
    static let positionTolerance: CGFloat = 5.0

    private let windowManager: any WindowManagerProtocol
    private let coordinateSystem: CoordinateSystemProtocol
    private let windowCache = WindowCache()

    @Published private(set) var detectedStacks: [WindowStack] = []
    private var monitoringTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?

    /// Delay before background refresh verifies optimistic updates
    private let backgroundRefreshDelay: TimeInterval = 0.5

    var stacksPublisher: AnyPublisher<[WindowStack], Never> {
        $detectedStacks.eraseToAnyPublisher()
    }

    init(
        windowManager: any WindowManagerProtocol,
        coordinateSystem: CoordinateSystemProtocol = CoreGraphicsCoordinateSystem()
    ) {
        self.windowManager = windowManager
        self.coordinateSystem = coordinateSystem
    }

    func detectStacks() async throws -> [WindowStack] {
        let overallState = tracer.begin("DetectStacks", category: .stackDetection)
        defer { tracer.end("DetectStacks", overallState, "stacks=\(detectedStacks.count)") }

        let windows = try await windowManager.queryWindows()

        await windowCache.populate(with: windows)

        let stacks = rebuildStacksFromWindows(windows)

        // Only update if stacks actually changed to avoid unnecessary UI updates
        if !stacksAreEquivalent(stacks, detectedStacks) {
            detectedStacks = stacks
        }

        return stacks
    }

    private func stacksAreEquivalent(_ new: [WindowStack], _ old: [WindowStack]) -> Bool {
        guard new.count == old.count else { return false }
        for (newStack, oldStack) in zip(new, old) {
            if newStack.id != oldStack.id { return false }
            if newStack.focusedWindowId != oldStack.focusedWindowId { return false }
            if newStack.windows.map(\.id) != oldStack.windows.map(\.id) { return false }
        }
        return true
    }

    private func rebuildStacksFromWindows(_ windows: [ManagedWindow]) -> [WindowStack] {
        let groupingState = tracer.begin("GroupWindows", category: .stackDetection)
        defer { tracer.end("GroupWindows", groupingState, "windows=\(windows.count)") }

        let previousFocusedWindows = Dictionary(
            uniqueKeysWithValues: detectedStacks.compactMap { stack -> (String, WindowIdentifier)? in
                guard let focusedId = stack.focusedWindowId else { return nil }
                return (stack.id, focusedId)
            }
        )

        return groupWindowsIntoStacks(windows, previousFocusedWindows: previousFocusedWindows)
    }

    func startMonitoring() async {
        monitoringTask?.cancel()

        monitoringTask = Task { [weak self] in
            guard let self = self else { return }

            _ = try? await self.detectStacks()

            for await event in self.windowManager.eventStream() {
                guard !Task.isCancelled else { break }

                let eventState = self.tracer.begin("HandleEvent", category: .stackDetection)

                switch event {
                case .windowFocused(let windowId) where windowId != 0:
                    self.tracer.event("EventPath", "optimistic windowId=\(windowId)")
                    await self.handleOptimisticFocus(windowId: windowId)

                case .windowFocused(let windowId):
                    self.tracer.event("EventPath", "fullQuery windowFocused id=\(windowId)")
                    _ = try? await self.detectStacks()

                case .windowMoved, .windowResized,
                     .windowCreated, .windowDestroyed, .spaceChanged, .displayChanged:
                    self.tracer.event("EventPath", "fullQuery \(event)")
                    _ = try? await self.detectStacks()
                }

                self.tracer.end("HandleEvent", eventState, "\(event)")
            }
        }
    }

    private func handleOptimisticFocus(windowId: WindowIdentifier) async {
        let state = tracer.begin("OptimisticFocus", category: .stackDetection)
        defer { tracer.end("OptimisticFocus", state, "windowId=\(windowId)") }

        await windowCache.updateFocused(windowId: windowId)

        let windows = await windowCache.allWindows()
        let stacks = rebuildStacksFromWindows(windows)
        detectedStacks = stacks

        scheduleBackgroundRefresh()
    }

    private func scheduleBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.backgroundRefreshDelay ?? 0.5) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await self?.detectStacks()
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
    }

    func stack(containing windowId: WindowIdentifier) -> WindowStack? {
        detectedStacks.first { stack in
            stack.windows.contains { $0.id == windowId }
        }
    }

    // MARK: - Stack Grouping Algorithm

    private func groupWindowsIntoStacks(_ windows: [ManagedWindow], previousFocusedWindows: [String: WindowIdentifier]) -> [WindowStack] {
        let stackableWindows = windows.filter { window in
            window.isStackable && coordinateSystem.isWindowOnScreen(window)
        }

        let groupedBySpaceAndDisplay = Dictionary(grouping: stackableWindows) { window in
            SpaceDisplayKey(spaceIndex: window.spaceIndex, displayIndex: window.displayIndex)
        }

        var allStacks: [WindowStack] = []

        for (_, windowsInGroup) in groupedBySpaceAndDisplay {
            let stacks = groupByPosition(windowsInGroup, previousFocusedWindows: previousFocusedWindows)
            allStacks.append(contentsOf: stacks)
        }

        return allStacks.sorted(by: { (stack1: WindowStack, stack2: WindowStack) -> Bool in
            if stack1.spaceIndex != stack2.spaceIndex {
                return stack1.spaceIndex < stack2.spaceIndex
            }
            if stack1.displayIndex != stack2.displayIndex {
                return stack1.displayIndex < stack2.displayIndex
            }
            if stack1.frame.origin.y != stack2.frame.origin.y {
                return stack1.frame.origin.y < stack2.frame.origin.y
            }
            return stack1.frame.origin.x < stack2.frame.origin.x
        })
    }

    private func groupByPosition(_ windows: [ManagedWindow], previousFocusedWindows: [String: WindowIdentifier]) -> [WindowStack] {
        guard !windows.isEmpty else { return [] }

        var groups: [[ManagedWindow]] = []

        for window in windows {
            var foundGroup = false

            for i in groups.indices {
                if let firstWindow = groups[i].first,
                   isWithinTolerance(window.frame.origin, firstWindow.frame.origin) {
                    groups[i].append(window)
                    foundGroup = true
                    break
                }
            }

            if !foundGroup {
                groups.append([window])
            }
        }

        return groups.compactMap { (group: [ManagedWindow]) -> WindowStack? in
            guard !group.isEmpty else { return nil }
            guard let firstWindow = group.first else { return nil }

            let currentFocusedWindow = group.first { $0.isFocused }

            let stackId = WindowStack.generateId(
                displayIndex: firstWindow.displayIndex,
                spaceIndex: firstWindow.spaceIndex,
                frame: firstWindow.frame
            )

            let focusedWindowId: WindowIdentifier?
            if let currentFocused = currentFocusedWindow {
                focusedWindowId = currentFocused.id
            } else if let previousId = previousFocusedWindows[stackId],
                      group.contains(where: { $0.id == previousId }) {
                focusedWindowId = previousId
            } else {
                focusedWindowId = nil
            }

            return WindowStack(
                windows: group,
                displayIndex: firstWindow.displayIndex,
                focusedWindowId: focusedWindowId
            )
        }
    }

    private func isWithinTolerance(_ p1: CGPoint, _ p2: CGPoint) -> Bool {
        abs(p1.x - p2.x) <= Self.positionTolerance &&
        abs(p1.y - p2.y) <= Self.positionTolerance
    }
}

private struct SpaceDisplayKey: Hashable {
    let spaceIndex: Int
    let displayIndex: Int
}
