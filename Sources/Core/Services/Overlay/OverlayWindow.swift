import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "overlay-window")

// MARK: - Overlay Window

final class OverlayWindow: NSWindow {
    private var hostingView: NSHostingView<IndicatorContentView>?
    private let configManager: ConfigurationManager
    private let onWindowClick: (Int) -> Void
    private var currentStacks: [WindowStack] = []
    private var lastStackPositions: [String: CGRect] = [:] {
        didSet {
            // Limit dictionary size to prevent unbounded growth
            if lastStackPositions.count > 50 {
                // Keep only the 25 most recent entries
                let sortedKeys = lastStackPositions.keys.sorted()
                let keysToRemove = sortedKeys.dropLast(25)
                for key in keysToRemove {
                    lastStackPositions.removeValue(forKey: key)
                }
            }
        }
    }
    private var viewModel: IndicatorViewModel?
    private var lastIndicatorSize: NSSize = .zero
    private var lastStacksHash: Int = 0
    
    init(configManager: ConfigurationManager, onWindowClick: @escaping (Int) -> Void) {
        self.configManager = configManager
        self.onWindowClick = onWindowClick
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
    }
    
    private func setupWindow() {
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = NSWindow.Level.floating
        self.ignoresMouseEvents = false
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.masksToBounds = true
        
        self.animationBehavior = .utilityWindow
        
        if configManager.config.behavior.showOnAllSpaces {
            self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else {
            self.collectionBehavior = [.stationary]
        }
    }
    
    private func createContentView() {
        // Create view model only once
        if viewModel == nil {
            viewModel = IndicatorViewModel(
                stacks: currentStacks,
                config: configManager.config,
                onWindowClick: onWindowClick
            )
        } else {
            // Update existing view model
            viewModel?.updateStacks(currentStacks)
            viewModel?.updateConfig(configManager.config)
        }

        // Only create hosting view if it doesn't exist
        if hostingView == nil {
            let contentView = IndicatorContentView(viewModel: viewModel!)
            let newHostingView = NSHostingView(rootView: contentView)
            newHostingView.wantsLayer = true
            newHostingView.layer?.masksToBounds = true

            hostingView = newHostingView
            self.contentView = newHostingView
        }
    }
    
    func positionRelativeToStack(_ stack: WindowStack) {
        guard let screen = CoordinateSystemHandler.findNSScreenForCoreGraphicsFrame(stack.frame) else { return }
        
        let screenFrame = screen.visibleFrame
        let convertedStackFrame = CoordinateSystemHandler.convertCoreGraphicsToNSScreen(stack.frame)
        
        logger.debug("Original stack frame (Core Graphics): (\(stack.frame.x), \(stack.frame.y), \(stack.frame.w), \(stack.frame.h))")
        logger.debug("Converted stack frame (NSScreen): \(NSStringFromRect(convertedStackFrame))")
        logger.debug("Screen frame: \(NSStringFromRect(screenFrame))")
        
        let indicatorSize = IndicatorSizeCalculator.calculateSize(for: [stack], config: configManager.config)
        
        var cornerPosition = configManager.config.positioning.stackCorner
        
        if cornerPosition == .auto {
            cornerPosition = OverlayPositioner.chooseBestCorner(for: convertedStackFrame, screenFrame: screenFrame)
        }
        
        let indicatorFrame = OverlayPositioner.calculateFrame(
            for: convertedStackFrame,
            cornerPosition: cornerPosition,
            indicatorSize: indicatorSize,
            config: configManager.config
        )
        
        let finalFrame = configManager.config.positioning.stickToScreenEdge ?
            OverlayPositioner.constrainToScreen(indicatorFrame, screenFrame: screenFrame) :
            indicatorFrame
        
        logger.debug("Final indicator frame: \(NSStringFromRect(finalFrame))")
        self.setFrame(finalFrame, display: true, animate: false)
    }
    
    func updateStacksEfficiently(_ stacks: [WindowStack]) {
        guard let stack = stacks.first else { return }

        // Check if stacks actually changed using hash
        let newHash = computeStacksHash(stacks)
        let stacksChanged = newHash != lastStacksHash

        // Check if position changed
        let convertedStackFrame = CoordinateSystemHandler.convertCoreGraphicsToNSScreen(stack.frame)
        let lastPosition = lastStackPositions[stack.id]
        let positionChanged = lastPosition == nil || !convertedStackFrame.equalTo(lastPosition!)

        // Only reposition if frame actually changed
        if positionChanged {
            // Cache the indicator size to avoid recalculation
            let newSize = IndicatorSizeCalculator.calculateSize(for: stacks, config: configManager.config)
            if !newSize.equalTo(lastIndicatorSize) || positionChanged {
                positionRelativeToStack(stack)
                lastStackPositions[stack.id] = convertedStackFrame
                lastIndicatorSize = newSize
            }
        }

        // Only update view model if stacks actually changed
        if stacksChanged {
            self.currentStacks = stacks
            self.lastStacksHash = newHash

            // Update the view model instead of creating new views
            if let viewModel = viewModel {
                viewModel.updateStacks(stacks)
            } else {
                createContentView()
            }
        }
    }
    
    func forceUpdateStacks(_ stacks: [WindowStack]) {
        guard let stack = stacks.first else { return }

        positionRelativeToStack(stack)

        let stackFrame = CGRect(x: stack.frame.x, y: stack.frame.y, width: stack.frame.w, height: stack.frame.h)
        lastStackPositions[stack.id] = stackFrame

        self.currentStacks = stacks

        // Update the view model instead of creating new views
        if let viewModel = viewModel {
            viewModel.updateStacks(stacks)
        } else {
            createContentView()
        }
    }
    
    func updateStacks(_ stacks: [WindowStack]) {
        updateStacksEfficiently(stacks)
    }
    
    private func stacksAreEqual(_ lhs: [WindowStack], _ rhs: [WindowStack]) -> Bool {
        return computeStacksHash(lhs) == computeStacksHash(rhs)
    }

    private func computeStacksHash(_ stacks: [WindowStack]) -> Int {
        var hasher = Hasher()
        for stack in stacks {
            hasher.combine(stack.id)
            hasher.combine(stack.windows.count)
            hasher.combine(stack.visibleWindow?.id ?? -1)
            for window in stack.windows {
                hasher.combine(window.id)
            }
        }
        return hasher.finalize()
    }
    
    func updateConfig() {
        if configManager.config.behavior.showOnAllSpaces {
            self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else {
            self.collectionBehavior = [.stationary]
        }

        // Update the view model config instead of recreating views
        viewModel?.updateConfig(configManager.config)
    }
    
    func show() {
        guard !self.isVisible else { return }
        
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 1.0
        })
    }
    
    func hide() {
        guard self.isVisible else { return }
        
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.15
            self?.animator().alphaValue = 0
        }) { [weak self] in
            self?.orderOut(nil)
        }
    }
    
    func cleanup() {
        // Clear view model
        viewModel = nil

        // Remove hosting view
        hostingView?.removeFromSuperview()
        hostingView = nil

        // Clear stacks and positions
        currentStacks.removeAll()
        lastStackPositions.removeAll()
        lastIndicatorSize = .zero
        lastStacksHash = 0

        // Hide and close window
        self.orderOut(nil)
        self.contentView = nil

        logger.debug("OverlayWindow cleanup completed")
    }

    deinit {
        // Note: cleanup() should be called explicitly before deallocation
        cleanup()
        logger.debug("OverlayWindow deinitialized")
    }
}