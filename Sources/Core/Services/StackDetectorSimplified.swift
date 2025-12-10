import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Simplified Stack Detector

@MainActor
final class StackDetectorSimplified: ObservableObject {
    private let logger = Logger(subsystem: "sh.mackie.stackline", category: "stack-detector")
    private let yabaiInterface = YabaiInterface()

    @Published private(set) var detectedStacks: [WindowStack] = []
    @Published private(set) var lastUpdateTime = Date()

    // Bounded state to prevent memory leaks
    private var stackFocusState: [String: Int] = [:]
    private let maxFocusStateEntries = 50

    // Event-driven updates instead of timer
    private var updateTask: Task<Void, Never>?

    // Detection parameters
    private let positionTolerance: Double = 5.0

    init() {
        logger.debug("StackDetectorSimplified initialized")
    }

    // MARK: - Public Interface

    func startDetection() {
        Task {
            await updateStacks()
        }
    }

    func stopDetection() {
        updateTask?.cancel()
        updateTask = nil
    }

    func forceStackDetection() {
        updateTask?.cancel()
        updateTask = Task {
            await updateStacks()
        }
    }

    // MARK: - Stack Detection Logic

    func updateStacks() async {
        do {
            let windows = try await yabaiInterface.queryWindows()

            // Filter valid windows using simplified coordinate check
            let validWindows = windows.filter { window in
                return CoordinateSystem.isWindowOnScreen(window.frame) &&
                       window.isVisible &&
                       !window.isMinimized &&
                       !window.isHidden &&
                       window.rootWindow
            }

            // Track focus changes
            trackFocusChanges(in: validWindows)

            // Detect stacks using simple position grouping
            let newStacks = detectStacks(in: validWindows)

            // Clean up stale focus state
            cleanupFocusState(for: newStacks)

            // Only update if stacks actually changed
            if detectedStacks != newStacks {
                detectedStacks = newStacks
                lastUpdateTime = Date()
                logger.debug("Detected \(newStacks.count) stacks")
            }
        } catch {
            logger.error("Failed to update stacks: \(error.localizedDescription)")
        }
    }

    private func detectStacks(in windows: [YabaiWindow]) -> [WindowStack] {
        // Group windows by position using simplified key
        let windowsByPosition = Dictionary(grouping: windows) { window in
            CoordinateSystem.createPositionKey(for: window.frame, tolerance: positionTolerance)
        }

        // Convert groups to stacks
        let stacks = windowsByPosition.compactMap { (position, windows) -> WindowStack? in
            guard windows.count > 1 else { return nil }

            // Sort by stack index or focus
            let sortedWindows = windows.sorted { left, right in
                if left.stackIndex != right.stackIndex {
                    return left.stackIndex < right.stackIndex
                }
                return left.isFocused && !right.isFocused
            }

            // Get last focused window ID for this stack position
            let lastFocusedId = stackFocusState[position]

            return WindowStack(windows: sortedWindows, lastFocusedWindowId: lastFocusedId)
        }

        return stacks.sorted { $0.id < $1.id }
    }

    private func trackFocusChanges(in windows: [YabaiWindow]) {
        for window in windows where window.isFocused {
            let positionKey = CoordinateSystem.createPositionKey(for: window.frame, tolerance: positionTolerance)
            stackFocusState[positionKey] = window.id
        }
    }

    private func cleanupFocusState(for stacks: [WindowStack]) {
        // Keep only relevant focus state and limit size
        let activePositions = Set(stacks.map { stack in
            CoordinateSystem.createPositionKey(for: stack.frame, tolerance: positionTolerance)
        })

        stackFocusState = stackFocusState.filter { key, _ in
            activePositions.contains(key)
        }

        // Ensure we don't exceed max entries
        if stackFocusState.count > maxFocusStateEntries {
            let excessCount = stackFocusState.count - maxFocusStateEntries
            let keysToRemove = Array(stackFocusState.keys.prefix(excessCount))
            for key in keysToRemove {
                stackFocusState.removeValue(forKey: key)
            }
        }
    }

    deinit {
        // Note: stopDetection() should be called explicitly before deinitialization
        // Cannot call @MainActor methods from deinit
        logger.debug("StackDetectorSimplified deinitialized")
    }
}