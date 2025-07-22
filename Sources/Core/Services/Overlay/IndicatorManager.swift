import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "indicator-manager")

// MARK: - Indicator Manager

@MainActor
final class IndicatorManager: ObservableObject {
    @Published var isEnabled: Bool = true
    
    private var overlayWindows: [String: OverlayWindow] = [:]
    private let configManager: ConfigurationManager
    private var currentStacks: [WindowStack] = []
    private var isWindowVisible: Bool = false
    
    init(configManager: ConfigurationManager) {
        self.configManager = configManager
        logger.debug("IndicatorManager initialized")
    }
    
    func updateIndicators(for stacks: [WindowStack]) {
        self.currentStacks = stacks
        
        let shouldShow = configManager.config.behavior.showByDefault && isEnabled && 
                        (!configManager.config.behavior.hideWhenNoStacks || !stacks.isEmpty)
        
        if shouldShow && !stacks.isEmpty {
            showOverlay(for: stacks)
        } else {
            hideOverlay()
        }
    }
    
    private func showOverlay(for stacks: [WindowStack]) {
        showRelativeOverlays(for: stacks)
    }
    
    private func showRelativeOverlays(for stacks: [WindowStack]) {
        let currentStackIds = Set(stacks.map(\.id))
        let existingStackIds = Set(overlayWindows.keys)
        
        // Remove old windows for stacks that no longer exist
        for oldStackId in existingStackIds.subtracting(currentStackIds) {
            overlayWindows[oldStackId]?.hide()
            overlayWindows[oldStackId]?.close()
            overlayWindows.removeValue(forKey: oldStackId)
        }
        
        // Create or update windows for each stack
        for stack in stacks {
            if overlayWindows[stack.id] == nil {
                let window = OverlayWindow(
                    configManager: configManager,
                    onWindowClick: { [weak self] windowId in
                        self?.handleWindowClick(windowId)
                    }
                )
                overlayWindows[stack.id] = window
                overlayWindows[stack.id]?.positionRelativeToStack(stack)
            }
            
            overlayWindows[stack.id]?.updateStacksEfficiently([stack])
            
            if !(overlayWindows[stack.id]?.isVisible ?? false) {
                overlayWindows[stack.id]?.show()
            }
        }
        
        isWindowVisible = !stacks.isEmpty
    }
    
    private func hideOverlay() {
        if isWindowVisible {
            for window in overlayWindows.values {
                window.hide()
            }
            isWindowVisible = false
        }
    }
    
    private func handleWindowClick(_ windowId: Int) {
        guard configManager.config.behavior.clickToFocus else { return }
        
        Task {
            do {
                let yabaiInterface = YabaiInterface()
                try await yabaiInterface.focusWindow(windowId)
                logger.debug("Successfully focused window \(windowId)")
            } catch {
                logger.error("Failed to focus window \(windowId): \(error.localizedDescription)")
            }
        }
    }
    
    func toggle() {
        isEnabled.toggle()
        
        if isEnabled {
            updateIndicators(for: currentStacks)
        } else {
            hideOverlay()
        }
    }
    
    func refreshAll() {
        for (stackId, window) in overlayWindows {
            window.updateConfig()
            
            if let stack = currentStacks.first(where: { $0.id == stackId }) {
                window.forceUpdateStacks([stack])
            }
        }
        
        updateIndicators(for: currentStacks)
    }
    
    deinit {
        for window in overlayWindows.values {
            Task { @MainActor in
                window.close()
            }
        }
        overlayWindows.removeAll()
        isWindowVisible = false
    }
}