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
    private var lastStackPositions: [String: CGRect] = [:]
    
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
        let contentView = IndicatorContentView(
            stacks: currentStacks,
            config: configManager.config,
            onWindowClick: onWindowClick
        )
        
        if let oldView = hostingView {
            oldView.removeFromSuperview()
        }
        
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.wantsLayer = true
        hostingView?.layer?.masksToBounds = true
        
        self.contentView = hostingView
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
        
        let convertedStackFrame = CoordinateSystemHandler.convertCoreGraphicsToNSScreen(stack.frame)
        let lastPosition = lastStackPositions[stack.id]
        
        if lastPosition == nil || !convertedStackFrame.equalTo(lastPosition!) {
            positionRelativeToStack(stack)
            lastStackPositions[stack.id] = convertedStackFrame
        }
        
        if !stacksAreEqual(currentStacks, stacks) {
            self.currentStacks = stacks
            
            if let hostingView = hostingView {
                hostingView.rootView = IndicatorContentView(
                    stacks: currentStacks,
                    config: configManager.config,
                    onWindowClick: onWindowClick
                )
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
        if let hostingView = hostingView {
            hostingView.rootView = IndicatorContentView(
                stacks: currentStacks,
                config: configManager.config,
                onWindowClick: onWindowClick
            )
        } else {
            createContentView()
        }
    }
    
    func updateStacks(_ stacks: [WindowStack]) {
        updateStacksEfficiently(stacks)
    }
    
    private func stacksAreEqual(_ lhs: [WindowStack], _ rhs: [WindowStack]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        for (left, right) in zip(lhs, rhs) {
            if left != right {
                return false
            }
        }
        
        return true
    }
    
    func updateConfig() {
        if configManager.config.behavior.showOnAllSpaces {
            self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else {
            self.collectionBehavior = [.stationary]
        }
        
        createContentView()
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
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }) {
            self.orderOut(nil)
        }
    }
    
    deinit {
        hostingView?.removeFromSuperview()
        hostingView = nil
    }
}