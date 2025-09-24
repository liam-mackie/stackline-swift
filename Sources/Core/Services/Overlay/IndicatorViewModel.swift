import SwiftUI
import Foundation

// MARK: - Indicator View Model

@MainActor
final class IndicatorViewModel: ObservableObject {
    @Published var stacks: [WindowStack] = []
    @Published var config: StacklineConfiguration
    let onWindowClick: (Int) -> Void

    // Cache for deep equality check
    private var previousStacksHash: Int = 0

    init(
        stacks: [WindowStack] = [],
        config: StacklineConfiguration,
        onWindowClick: @escaping (Int) -> Void
    ) {
        self.stacks = stacks
        self.config = config
        self.onWindowClick = onWindowClick
        self.previousStacksHash = computeStacksHash(stacks)
    }

    func updateStacks(_ newStacks: [WindowStack]) {
        // Deep equality check using hash to prevent unnecessary updates
        let newHash = computeStacksHash(newStacks)
        if newHash != previousStacksHash {
            // Only update if the actual content has changed
            self.stacks = newStacks
            self.previousStacksHash = newHash
        }
    }

    func updateConfig(_ newConfig: StacklineConfiguration) {
        // Only update if config actually changed
        if newConfig != self.config {
            self.config = newConfig
        }
    }

    private func computeStacksHash(_ stacks: [WindowStack]) -> Int {
        var hasher = Hasher()
        for stack in stacks {
            hasher.combine(stack.id)
            hasher.combine(stack.windows.count)
            // Include visible window to detect focus changes
            hasher.combine(stack.visibleWindow?.id ?? -1)
            // Include window IDs to detect order changes
            for window in stack.windows {
                hasher.combine(window.id)
            }
        }
        return hasher.finalize()
    }
}