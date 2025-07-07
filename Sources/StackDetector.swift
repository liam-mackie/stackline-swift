import Foundation
import Combine
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "stack-detector")

class StackDetector: ObservableObject {
    private let yabaiInterface: YabaiInterface
    
    @Published var detectedStacks: [WindowStack] = []
    @Published var lastUpdateTime: Date = Date()
    
    private var updateTimer: Timer?
    private var updateInterval: TimeInterval = 1.0 // Update every 1 second for reduced polling frequency
    
    // State tracking for stack visibility
    private var stackVisibilityState: [String: Int] = [:] // stackId -> lastFocusedWindowId
    private var lastWindowFocusState: [Int: Bool] = [:] // windowId -> wasFocused
    
    init(yabaiInterface: YabaiInterface) {
        self.yabaiInterface = yabaiInterface
        logger.debug("StackDetector initialized with \(self.updateInterval)s update interval")
        startPeriodicUpdates()
    }
    
    deinit {
        stopPeriodicUpdates()
        logger.debug("StackDetector deinitialized")
    }
    
    // MARK: - Periodic Updates
    
    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            Task {
                await self.updateStacks()
            }
        }
        
        // Initial update
        Task {
            await updateStacks()
        }
    }
    
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Stack Detection
    
    @MainActor
    func updateStacks() async {
        do {
            let windows = try await yabaiInterface.queryWindows()
            let stacks = await detectStacks(in: windows)
            
            // Clean up old stack visibility state
            await cleanupStackVisibilityState(for: stacks)
            
            self.detectedStacks = stacks
            self.lastUpdateTime = Date()
            
            if !stacks.isEmpty {
                logger.debug("Updated stacks: found \(stacks.count) stacks with \(stacks.reduce(0) { $0 + $1.windows.count }) total windows")
            }
        } catch {
            logger.error("Error updating stacks: \(error.localizedDescription)")
        }
    }
    
    func detectStacks(in windows: [YabaiWindow]) async -> [WindowStack] {
        // Track focus changes before processing stacks
        await trackFocusChanges(in: windows)
        
        // Filter to only visible, non-floating windows that are actually stacked
        // stackIndex of 0 means not stacked, 1+ means stacked
        let stackedWindows = windows.filter { window in
            window.isVisible && !window.isFloating && window.stackIndex > 0
        }
        
        // Group windows by space, display, and their stack position (same x,y coordinates)
        let windowsByStackGroup = Dictionary(grouping: stackedWindows) { window in
            StackGroupKey(
                space: window.space, 
                display: window.display, 
                x: Int(window.frame.x), 
                y: Int(window.frame.y)
            )
        }
        
        var allStacks: [WindowStack] = []
        
        // Process each stack group
        for (_, stackWindows) in windowsByStackGroup {
            // Only create a stack if there are multiple windows
            if stackWindows.count > 1 {
                // Sort by stack index (1 is frontmost, higher numbers are further back)
                let sortedWindows = stackWindows.sorted { $0.stackIndex < $1.stackIndex }
                
                // Create a temporary stack to get its ID
                let tempStack = WindowStack(windows: sortedWindows)
                let stackId = tempStack.id
                
                // Get the last focused window ID for this stack position
                let lastFocusedWindowId = stackVisibilityState[stackId]
                
                // Create the final stack with the tracked state
                let stack = WindowStack(windows: sortedWindows, lastFocusedWindowId: lastFocusedWindowId)
                allStacks.append(stack)
            }
        }
        
        // Sort stacks consistently by position for stable ordering
        // Sort by y-coordinate first (top to bottom), then by x-coordinate (left to right)
        allStacks.sort { left, right in
            if abs(left.frame.y - right.frame.y) < 50 { // Same row
                return left.frame.x < right.frame.x
            }
            return left.frame.y > right.frame.y // macOS coordinates: higher y = higher on screen
        }
        
        return allStacks
    }
    
    // MARK: - Focus Tracking
    
    private func trackFocusChanges(in windows: [YabaiWindow]) async {
        // Get current focus state
        let currentFocusState = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.hasFocus) })
        
        // Find windows that gained focus
        for (windowId, isFocused) in currentFocusState {
            let wasPreviouslyFocused = lastWindowFocusState[windowId] ?? false
            
            // If this window gained focus (wasn't focused before, now is)
            if isFocused && !wasPreviouslyFocused {
                await updateStackVisibilityForFocusedWindow(windowId, in: windows)
            }
        }
        
        // Update our tracking state
        lastWindowFocusState = currentFocusState
    }
    
    private func updateStackVisibilityForFocusedWindow(_ windowId: Int, in windows: [YabaiWindow]) async {
        // Find the window that gained focus
        guard let focusedWindow = windows.first(where: { $0.id == windowId }) else { return }
        
        // Check if this window is part of a stack
        guard focusedWindow.stackIndex > 0 else { return }
        
        // Find all windows in the same stack (same position and space)
        let stackWindows = windows.filter { window in
            window.space == focusedWindow.space &&
            window.display == focusedWindow.display &&
            window.stackIndex > 0 &&
            abs(window.frame.x - focusedWindow.frame.x) < 5 &&
            abs(window.frame.y - focusedWindow.frame.y) < 5
        }
        
        // Only update if there are multiple windows (i.e., it's actually a stack)
        if stackWindows.count > 1 {
            // Create the stack ID using the same logic as WindowStack
            let x = Int(focusedWindow.frame.x)
            let y = Int(focusedWindow.frame.y)
            let stackId = "stack_\(focusedWindow.space)_\(focusedWindow.display)_\(x)_\(y)"
            
            // Update the visibility state for this stack
            stackVisibilityState[stackId] = windowId
            
            logger.debug("Updated stack \(stackId) visibility: window \(windowId) (\(focusedWindow.app)) is now visible")
        }
    }
    
    private func cleanupStackVisibilityState(for currentStacks: [WindowStack]) async {
        let currentStackIds = Set(currentStacks.map(\.id))
        let trackedStackIds = Set(stackVisibilityState.keys)
        
        // Remove visibility state for stacks that no longer exist
        let stalStackIds = trackedStackIds.subtracting(currentStackIds)
        for staleId in stalStackIds {
            stackVisibilityState.removeValue(forKey: staleId)
        }
        
        if !stalStackIds.isEmpty {
            logger.debug("Cleaned up visibility state for \(stalStackIds.count) removed stacks")
        }
    }
    
    // MARK: - Stack Analysis
    
    func getStacksForCurrentSpace() async -> [WindowStack] {
        do {
            let currentSpace = try await yabaiInterface.queryCurrentSpace()
            return detectedStacks.filter { stack in
                stack.space == currentSpace.index
            }
        } catch {
            logger.error("Error getting current space: \(error.localizedDescription)")
            return []
        }
    }
    
    func getStacksForSpace(_ spaceIndex: Int) -> [WindowStack] {
        return detectedStacks.filter { stack in
            stack.space == spaceIndex
        }
    }
    
    func getStacksForDisplay(_ displayIndex: Int) -> [WindowStack] {
        return detectedStacks.filter { stack in
            stack.display == displayIndex
        }
    }
    
    func getStackContaining(windowId: Int) -> WindowStack? {
        return detectedStacks.first { stack in
            stack.windows.contains { $0.id == windowId }
        }
    }
    
    func isWindowInStack(windowId: Int) -> Bool {
        return getStackContaining(windowId: windowId) != nil
    }
    
    // MARK: - Stack Statistics
    
    func getStackCount() -> Int {
        return detectedStacks.count
    }
    
    func getTotalStackedWindows() -> Int {
        return detectedStacks.reduce(0) { total, stack in
            total + stack.windows.count
        }
    }
    
    func getStackSummary() -> StackSummary {
        let totalStacks = detectedStacks.count
        let totalWindows = getTotalStackedWindows()
        let stacksBySpace = Dictionary(grouping: detectedStacks) { $0.space }
        
        return StackSummary(
            totalStacks: totalStacks,
            totalStackedWindows: totalWindows,
            stacksBySpace: stacksBySpace.mapValues { $0.count },
            lastUpdateTime: lastUpdateTime
        )
    }
    
    // MARK: - Manual Detection
    
    func forceStackDetection() {
        Task {
            await updateStacks()
        }
    }
    
    func detectStacksForWindows(_ windows: [YabaiWindow]) async -> [WindowStack] {
        return await detectStacks(in: windows)
    }
    
    // MARK: - Manual Visibility Control
    
    func setVisibleWindow(_ windowId: Int, in stackId: String) {
        stackVisibilityState[stackId] = windowId
        logger.debug("Manually set window \(windowId) as visible in stack \(stackId)")
    }
    
    func getVisibilityState() -> [String: Int] {
        return stackVisibilityState
    }
}

// MARK: - Helper Types

private struct StackGroupKey: Hashable {
    let space: Int
    let display: Int
    let x: Int
    let y: Int
}

struct StackSummary {
    let totalStacks: Int
    let totalStackedWindows: Int
    let stacksBySpace: [Int: Int]
    let lastUpdateTime: Date
}

// MARK: - Extensions

extension StackDetector {
    func getStacksGroupedBySpace() -> [Int: [WindowStack]] {
        return Dictionary(grouping: detectedStacks) { $0.space }
    }
    
    func getStacksGroupedByDisplay() -> [Int: [WindowStack]] {
        return Dictionary(grouping: detectedStacks) { $0.display }
    }
    
    func getStacksWithMultipleWindows() -> [WindowStack] {
        return detectedStacks.filter { $0.windows.count > 1 }
    }
    
    func getStacksWithFocusedWindow() -> [WindowStack] {
        return detectedStacks.filter { stack in
            stack.windows.contains { $0.isFocused }
        }
    }
}

// MARK: - Configuration

extension StackDetector {
    func setUpdateInterval(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        
        stopPeriodicUpdates()
        updateInterval = interval
        startPeriodicUpdates()
    }
    
    func pauseUpdates() {
        stopPeriodicUpdates()
    }
    
    func resumeUpdates() {
        startPeriodicUpdates()
    }
} 