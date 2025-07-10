import Foundation
import Combine
import os
import AppKit
import os.log

// MARK: - Core Graphics Functions (matching yabai's coordinate system)

private func CGGetActiveDisplayList(_ maxDisplays: UInt32, _ activeDisplays: UnsafeMutablePointer<CGDirectDisplayID>?, _ displayCount: UnsafeMutablePointer<UInt32>) -> CGError {
    return CoreGraphics.CGGetActiveDisplayList(maxDisplays, activeDisplays, displayCount)
}

// MARK: - Coordinate System Handler

/// Handles coordinate system conversions and validation using Core Graphics APIs (same as yabai)
class CoordinateSystemHandler {
    
    /// Gets all active display IDs using Core Graphics (same as yabai)
    static func getActiveDisplayList() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        guard result == .success, displayCount > 0 else {
            return []
        }
        
        var displays = Array<CGDirectDisplayID>(repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard result == .success else {
            return []
        }
        
        return Array(displays[0..<Int(displayCount)])
    }
    
    /// Gets display bounds using Core Graphics (same as yabai uses with CGDisplayBounds)
    static func getCoreGraphicsDisplayBounds() -> [CGRect] {
        let displays = getActiveDisplayList()
        return displays.map { CGDisplayBounds($0) }
    }
    
    /// Converts yabai window frame to NSRect - no validation, just conversion
    static func rectFromWindowFrame(_ frame: WindowFrame) -> NSRect {
        return NSRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }
    
    /// Checks if a window frame is positioned on any display using Core Graphics (matches yabai exactly)
    /// This uses the same coordinate system as yabai: CGDisplayBounds()
    static func isWindowOnAnyScreen(_ frame: WindowFrame) -> Bool {
        let rect = rectFromWindowFrame(frame)
        let displayBounds = getCoreGraphicsDisplayBounds()
        
        // Log the coordinate comparison for debugging
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stackline", category: "CoordinateSystemHandler")
        
        // First check: exact intersection
        for (index, bounds) in displayBounds.enumerated() {
            if rect.intersects(bounds) {
                logger.debug("Window (\(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height)) intersects display \(index): (\(bounds.origin.x), \(bounds.origin.y), \(bounds.width), \(bounds.height))")
                return true
            }
        }
        
        // Second check: tolerance for edge cases (matching our previous logic)
        let tolerance: CGFloat = 10.0
        for (index, bounds) in displayBounds.enumerated() {
            let expandedBounds = NSRect(
                x: bounds.origin.x - tolerance,
                y: bounds.origin.y - tolerance,
                width: bounds.width + (2 * tolerance),
                height: bounds.height + (2 * tolerance)
            )
            if rect.intersects(expandedBounds) {
                logger.debug("Window (\(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height)) intersects display \(index) with tolerance: (\(bounds.origin.x), \(bounds.origin.y), \(bounds.width), \(bounds.height))")
                return true
            }
        }
        
        // Log failure case for debugging
        logger.debug("Window (\(rect.origin.x), \(rect.origin.y), \(rect.width), \(rect.height)) does not intersect any display:")
        for (index, bounds) in displayBounds.enumerated() {
            logger.debug("  Display \(index): (\(bounds.origin.x), \(bounds.origin.y), \(bounds.width), \(bounds.height))")
        }
        
        return false
    }
    
    /// Gets the display that contains the majority of the given rect using Core Graphics
    static func primaryDisplay(for frame: WindowFrame) -> CGDirectDisplayID? {
        let rect = rectFromWindowFrame(frame)
        let displays = getActiveDisplayList()
        
        var bestDisplay: CGDirectDisplayID?
        var largestIntersection: CGFloat = 0
        
        for display in displays {
            let bounds = CGDisplayBounds(display)
            let intersection = rect.intersection(bounds)
            let intersectionArea = intersection.width * intersection.height
            
            if intersectionArea > largestIntersection {
                largestIntersection = intersectionArea
                bestDisplay = display
            }
        }
        
        return bestDisplay ?? CGMainDisplayID()
    }
    
    /// Logs screen configuration for debugging using Core Graphics (matches yabai exactly)
    static func logScreenConfiguration() {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stackline", category: "CoordinateSystemHandler")
        let displays = getActiveDisplayList()
        logger.debug("Available displays (using Core Graphics - same as yabai):")
        for (index, display) in displays.enumerated() {
            let bounds = CGDisplayBounds(display)
            logger.debug("  Display \(index) (ID: \(display)): origin=(\(bounds.origin.x), \(bounds.origin.y)), size=(\(bounds.width), \(bounds.height))")
        }
        
        // Also log NSScreen for comparison
        logger.debug("NSScreen displays (for comparison):")
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            logger.debug("  NSScreen \(index): origin=(\(frame.origin.x), \(frame.origin.y)), size=(\(frame.width), \(frame.height))")
        }
    }
    
    /// Converts absolute coordinates to display-relative coordinates using Core Graphics
    static func convertToDisplayRelative(_ frame: WindowFrame) -> (displayBounds: CGRect, relativeFrame: WindowFrame, displayIndex: Int) {
        let rect = rectFromWindowFrame(frame)
        let displays = getActiveDisplayList()
        
        // Find the display containing this window
        for (index, display) in displays.enumerated() {
            let displayBounds = CGDisplayBounds(display)
            if rect.intersects(displayBounds) {
                // Convert to display-relative coordinates
                let relativeX = frame.x - displayBounds.origin.x
                let relativeY = frame.y - displayBounds.origin.y
                let relativeFrame = WindowFrame(x: relativeX, y: relativeY, w: frame.w, h: frame.h)
                return (displayBounds, relativeFrame, index)
            }
        }
        
        // Fallback to main display if no intersection found
        let mainDisplay = CGMainDisplayID()
        let mainDisplayBounds = CGDisplayBounds(mainDisplay)
        let relativeX = frame.x - mainDisplayBounds.origin.x
        let relativeY = frame.y - mainDisplayBounds.origin.y
        let relativeFrame = WindowFrame(x: relativeX, y: relativeY, w: frame.w, h: frame.h)
        return (mainDisplayBounds, relativeFrame, 0)
    }
    
    /// Creates a position key for grouping windows by position within a display
    /// This ensures proper grouping even across multiple displays with different origins
    static func createPositionKey(for frame: WindowFrame, tolerance: Double, display: Int) -> String {
        let (_, relativeFrame, displayIndex) = convertToDisplayRelative(frame)
        
        // Use display-relative coordinates for position grouping
        let x = Int(relativeFrame.x / tolerance) * Int(tolerance)
        let y = Int(relativeFrame.y / tolerance) * Int(tolerance)
        
        return "display_\(displayIndex)_yabai_display_\(display)_pos_\(x)_\(y)"
    }
    
    // MARK: - Legacy methods for compatibility (now using Core Graphics)
    
    /// Validates screen rect using Core Graphics bounds
    static func validateScreenRect(from frame: WindowFrame) -> NSRect {
        let rect = rectFromWindowFrame(frame)
        let displayBounds = getCoreGraphicsDisplayBounds()
        
        // Check if the rect intersects with any display bounds
        for bounds in displayBounds {
            if rect.intersects(bounds) {
                return rect
            }
        }
        
        // If not intersecting any display, clamp to main display
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let clampedRect = rect.intersection(mainDisplayBounds)
        return clampedRect.isEmpty ? rect : clampedRect
    }
    
    /// Checks if a rect is valid and visible on any display using Core Graphics
    static func isRectVisible(_ rect: NSRect) -> Bool {
        let displayBounds = getCoreGraphicsDisplayBounds()
        return displayBounds.contains { bounds in
            rect.intersects(bounds)
        }
    }
    
    /// Normalizes window frame coordinates to ensure they're in valid display space
    static func normalizeWindowFrame(_ frame: WindowFrame) -> WindowFrame {
        let rect = validateScreenRect(from: frame)
        return WindowFrame(x: rect.origin.x, y: rect.origin.y, w: rect.size.width, h: rect.size.height)
    }
    
    /// Converts a point from window coordinates to screen coordinates
    static func convertToScreen(point: NSPoint, from window: NSWindow?) -> NSPoint {
        guard let window = window else { return point }
        return window.convertToScreen(NSRect(origin: point, size: .zero)).origin
    }
    
    /// Converts a point from screen coordinates to window coordinates
    static func convertFromScreen(point: NSPoint, to window: NSWindow?) -> NSPoint {
        guard let window = window else { return point }
        return window.convertFromScreen(NSRect(origin: point, size: .zero)).origin
    }
    
    /// Gets all display frames using Core Graphics (replaces NSScreen.screens.map { $0.frame })
    static func getAllDisplayFrames() -> [NSRect] {
        return getCoreGraphicsDisplayBounds()
    }
}

// MARK: - Stack Detector

@MainActor
class StackDetector: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Stackline", category: "StackDetector")
    private let yabaiInterface = YabaiInterface()
    
    @Published private(set) var detectedStacks: [WindowStack] = []
    @Published private(set) var lastUpdateTime = Date()
    
    // Track the last focused window for each stack to maintain visibility state
    private var stackVisibilityState: [String: Int] = [:]
    
    // Track window focus changes to update stack visibility
    private var lastWindowFocusState: [Int: Bool] = [:]
    
    // Detection parameters
    private let positionTolerance: Double = 5.0  // Pixels tolerance for considering windows at same position
    private let sameRowTolerance: Double = 50.0  // Pixels tolerance for considering windows in same row
    
    init() {
        // Log screen configuration for debugging multi-screen setups
        CoordinateSystemHandler.logScreenConfiguration()
        setupPeriodicUpdates()
    }
    
    // MARK: - Public Interface
    
    func startDetection() {
        Task {
            await updateStacks()
        }
    }
    
    func stopDetection() {
        // Implementation for stopping periodic updates if needed
    }
    
    // MARK: - Stack Detection Logic
    
    private func setupPeriodicUpdates() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                await self.updateStacks()
            }
        }
    }
    
    func updateStacks() async {
        do {
            let windows = try await yabaiInterface.queryWindows()
            
            // Log window distribution for debugging
            let windowsByDisplay = Dictionary(grouping: windows) { $0.display }
            for (display, displayWindows) in windowsByDisplay {
                logger.debug("Display \(display): \(displayWindows.count) windows")
            }
            
            // Filter out invalid or non-standard windows
            let validWindows = windows.filter { window in
                let isOnScreen = CoordinateSystemHandler.isWindowOnAnyScreen(window.frame)
                
                // Log filtered windows for debugging multi-screen issues
                if !isOnScreen {
                    logger.debug("Filtering out window '\(window.app)' (\(window.id)) at (\(window.frame.x), \(window.frame.y)) - not on any screen")
                }
                
                return isOnScreen &&
                       window.isVisible &&
                       !window.isMinimized &&
                       !window.isHidden &&
                       window.rootWindow
            }
            
            // Log filtering results
            let filteredCount = windows.count - validWindows.count
            if filteredCount > 0 {
                logger.debug("Filtered out \(filteredCount) windows (total: \(windows.count) -> valid: \(validWindows.count))")
            }
            
            // Track focus changes before detecting stacks
            await trackFocusChanges(in: validWindows)
            
            // Detect stacks using normalized coordinates
            let newStacks = await detectStacks(in: validWindows)
            
            // Clean up stale visibility state
            await cleanupStackVisibilityState(for: newStacks)
            
            // Update published state
            detectedStacks = newStacks
            lastUpdateTime = Date()
            
            logger.debug("Detected \(newStacks.count) stacks with \(newStacks.reduce(0) { $0 + $1.windows.count }) total stacked windows")
            
        } catch {
            logger.error("Error updating stacks: \(error.localizedDescription)")
        }
    }
    
    func detectStacks(in windows: [YabaiWindow]) async -> [WindowStack] {
        // Filter to only stacked windows (stackIndex > 0 means the window is part of a stack)
        let stackedWindows = windows.filter { $0.stackIndex > 0 }
        
        // Group windows by space and display first for efficiency
        let groupedWindows = Dictionary(grouping: stackedWindows) { window in
            StackGroupKey(space: window.space, display: window.display, x: 0, y: 0)
        }
        
        var allStacks: [WindowStack] = []
        
        for (_, spaceWindows) in groupedWindows {
            // Group windows by position within each space using screen-relative coordinates
            let positionGroups = Dictionary(grouping: spaceWindows) { window in
                // Use screen-relative positioning for proper multi-screen support
                let positionKey = CoordinateSystemHandler.createPositionKey(
                    for: window.frame, 
                    tolerance: positionTolerance, 
                    display: window.display
                )
                return positionKey
            }
            
            // Convert position groups to stacks
            for (_, stackWindows) in positionGroups {
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
        }
        
        // Sort stacks using proper multi-screen coordinate system
        // Group by screen first, then sort within each screen
        let stacksByScreen = Dictionary(grouping: allStacks) { stack in
            CoordinateSystemHandler.convertToDisplayRelative(stack.frame).displayIndex
        }
        
        var sortedStacks: [WindowStack] = []
        
        // Sort screens by their position (left to right, top to bottom)
        let sortedScreenIndices = stacksByScreen.keys.sorted { screenIndex1, screenIndex2 in
            let displays = CoordinateSystemHandler.getCoreGraphicsDisplayBounds()
            guard screenIndex1 < displays.count, screenIndex2 < displays.count else {
                return screenIndex1 < screenIndex2
            }
            
            let screen1 = displays[screenIndex1]
            let screen2 = displays[screenIndex2]
            
            // Sort by x-coordinate first (left to right), then by y-coordinate (top to bottom)
            if abs(screen1.origin.x - screen2.origin.x) < sameRowTolerance {
                return screen1.origin.y < screen2.origin.y
            }
            return screen1.origin.x < screen2.origin.x
        }
        
        // Within each screen, sort stacks by their screen-relative position
        for screenIndex in sortedScreenIndices {
            guard let screenStacks = stacksByScreen[screenIndex] else { continue }
            
            let sortedScreenStacks = screenStacks.sorted { left, right in
                let leftRelative = CoordinateSystemHandler.convertToDisplayRelative(left.frame).relativeFrame
                let rightRelative = CoordinateSystemHandler.convertToDisplayRelative(right.frame).relativeFrame
                
                // Check if they're in the same row (within tolerance)
                if abs(leftRelative.y - rightRelative.y) < sameRowTolerance {
                    // Same row: sort by x-coordinate (left to right)
                    return leftRelative.x < rightRelative.x
                }
                
                // Different rows: sort by y-coordinate (top to bottom)
                return leftRelative.y < rightRelative.y
            }
            
            sortedStacks.append(contentsOf: sortedScreenStacks)
        }
        
        return sortedStacks
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
        
        // Get screen-relative coordinates for the focused window
        let focusedRelativeData = CoordinateSystemHandler.convertToDisplayRelative(focusedWindow.frame)
        
        // Find all windows in the same stack (same position and space) using screen-relative coordinates
        let stackWindows = windows.filter { window in
            let windowRelativeData = CoordinateSystemHandler.convertToDisplayRelative(window.frame)
            return window.space == focusedWindow.space &&
                   window.display == focusedWindow.display &&
                   window.stackIndex > 0 &&
                   windowRelativeData.displayIndex == focusedRelativeData.displayIndex &&
                   abs(windowRelativeData.relativeFrame.x - focusedRelativeData.relativeFrame.x) < positionTolerance &&
                   abs(windowRelativeData.relativeFrame.y - focusedRelativeData.relativeFrame.y) < positionTolerance
        }
        
        // Only update if there are multiple windows (i.e., it's actually a stack)
        if stackWindows.count > 1 {
            // Create the stack ID using the same logic as WindowStack with screen-relative coordinates
            let stackId = CoordinateSystemHandler.createPositionKey(
                for: focusedWindow.frame, 
                tolerance: positionTolerance, 
                display: focusedWindow.display
            )
            
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
    /// Note: Update interval configuration removed in favor of simplified timer approach
    /// Use forceStackDetection() to trigger manual updates as needed
    
    /// Forces an immediate stack detection update
    /// This bypasses the normal timer-based updates
    func triggerImmediateUpdate() {
        Task {
            await updateStacks()
        }
    }
} 