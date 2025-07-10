import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "indicator-manager")

// MARK: - Simple Indicator Manager

@MainActor
class SimpleIndicatorManager: ObservableObject {
    @Published var isEnabled: Bool = true
    
    private var overlayWindows: [String: SimpleOverlayWindow] = [:]
    private let configManager: ConfigurationManager
    private var currentStacks: [WindowStack] = []
    private var isWindowVisible: Bool = false
    
    init(configManager: ConfigurationManager) {
        self.configManager = configManager
        logger.debug("SimpleIndicatorManager initialized")
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
        // Relative position is the only supported mode for now
        showRelativeOverlays(for: stacks)
    }
    
    private func showRelativeOverlays(for stacks: [WindowStack]) {
        // Remove old windows for stacks that no longer exist
        let currentStackIds = Set(stacks.map(\.id))
        let existingStackIds = Set(overlayWindows.keys)
        
        for oldStackId in existingStackIds.subtracting(currentStackIds) {
            overlayWindows[oldStackId]?.hide()
            overlayWindows[oldStackId]?.close()
            overlayWindows.removeValue(forKey: oldStackId)
        }
        
        // Create or update windows for each stack
        for stack in stacks {
            if overlayWindows[stack.id] == nil {
                let window = SimpleOverlayWindow(
                    configManager: configManager,
                    onWindowClick: { [weak self] windowId in
                        self?.handleWindowClick(windowId)
                    }
                )
                overlayWindows[stack.id] = window
                // Only position on initial creation
                overlayWindows[stack.id]?.positionRelativeToStack(stack)
            }
            
            // Update content and position only if needed
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
        // Force a complete refresh of all overlay windows
        for (stackId, window) in overlayWindows {
            window.updateConfig()
            
            // Find the corresponding stack and force reposition
            if let stack = currentStacks.first(where: { $0.id == stackId }) {
                window.forceUpdateStacks([stack])
            }
        }
        
        // Also update indicators to handle any new stacks or changes
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

// MARK: - Simple Overlay Window

class SimpleOverlayWindow: NSWindow {
    private var hostingView: NSHostingView<SimpleIndicatorContentView>?
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
        
        // Enable layer-backed views to reduce tearing
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.masksToBounds = true
        
        // Optimize for smooth animations
        self.animationBehavior = .utilityWindow
        
        if configManager.config.behavior.showOnAllSpaces {
            self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else {
            self.collectionBehavior = [.stationary]
        }
    }
    
    private func createContentView() {
        let contentView = SimpleIndicatorContentView(
            stacks: currentStacks,
            config: configManager.config,
            onWindowClick: onWindowClick
        )
        
        // Clean up old hosting view
        if let oldView = hostingView {
            oldView.removeFromSuperview()
        }
        
        hostingView = NSHostingView(rootView: contentView)
        
        // Enable layer-backed views for smoother rendering
        hostingView?.wantsLayer = true
        hostingView?.layer?.masksToBounds = true
        
        self.contentView = hostingView
    }
    
    func positionRelativeToStack(_ stack: WindowStack) {
        // Use the coordinate conversion helper to find the correct screen
        guard let screen = CoordinateSystemHandler.findNSScreenForCoreGraphicsFrame(stack.frame) else { return }
        
        let screenFrame = screen.visibleFrame
        
        // Convert the stack frame from Core Graphics coordinates to NSScreen coordinates
        let convertedStackFrame = CoordinateSystemHandler.convertCoreGraphicsToNSScreen(stack.frame)
        
        logger.debug("Original stack frame (Core Graphics): (\(stack.frame.x), \(stack.frame.y), \(stack.frame.w), \(stack.frame.h))")
        logger.debug("Converted stack frame (NSScreen): \(NSStringFromRect(convertedStackFrame))")
        logger.debug("Screen frame: \(NSStringFromRect(screenFrame))")
        
        // Calculate indicator size based on content
        let indicatorSize = calculateIndicatorSize(for: [stack])
        
        var cornerPosition = configManager.config.positioning.stackCorner
        
        // Auto positioning: choose the best corner based on available space and screen edges
        if cornerPosition == .auto {
            cornerPosition = chooseBestCorner(for: convertedStackFrame, screenFrame: screenFrame)
        }
        
        let edgeOffset = configManager.config.positioning.edgeOffset
        let cornerOffset = configManager.config.positioning.cornerOffset
        var indicatorFrame: NSRect
        
        switch cornerPosition {
        case .topLeft:
            // Default: stackline overlaps with stack, left edges aligned
            // With offset: move indicator further left (away from stack)
            indicatorFrame = NSRect(
                x: convertedStackFrame.origin.x - edgeOffset,
                y: convertedStackFrame.origin.y + convertedStackFrame.height - indicatorSize.height - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .topRight:
            // Default: stackline overlaps with stack, right edges aligned
            // With offset: move indicator further right (away from stack)
            indicatorFrame = NSRect(
                x: convertedStackFrame.origin.x + convertedStackFrame.width - indicatorSize.width + edgeOffset,
                y: convertedStackFrame.origin.y + convertedStackFrame.height - indicatorSize.height - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .bottomLeft:
            // Default: stackline overlaps with stack, left edges aligned
            // With offset: move indicator further left (away from stack)
            indicatorFrame = NSRect(
                x: convertedStackFrame.origin.x - edgeOffset,
                y: convertedStackFrame.origin.y - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .bottomRight:
            // Default: stackline overlaps with stack, right edges aligned
            // With offset: move indicator further right (away from stack)
            indicatorFrame = NSRect(
                x: convertedStackFrame.origin.x + convertedStackFrame.width - indicatorSize.width + edgeOffset,
                y: convertedStackFrame.origin.y - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .auto:
            // This should not happen as we handle auto above
            indicatorFrame = NSRect(x: convertedStackFrame.origin.x, y: convertedStackFrame.origin.y, width: indicatorSize.width, height: indicatorSize.height)
        }
        
        // Apply screen edge constraints if enabled
        if configManager.config.positioning.stickToScreenEdge {
            indicatorFrame = constrainToScreen(indicatorFrame, screenFrame: screenFrame)
        }
        
        logger.debug("Final indicator frame: \(NSStringFromRect(indicatorFrame))")
        self.setFrame(indicatorFrame, display: true, animate: false)
    }
    
    private func calculateIndicatorSize(for stacks: [WindowStack]) -> NSSize {
        let config = configManager.config.appearance
        let maxWindowsInStack = stacks.map(\.windows.count).max() ?? 1
        
        var indicatorWidth: CGFloat = 0
        var indicatorHeight: CGFloat = 0
        
        // Calculate size based on indicator style
        switch config.indicatorStyle {
        case .pill:
            if config.iconDirection == .vertical {
                // Vertical layout: stack pills vertically
                indicatorWidth = config.pillWidth
                indicatorHeight = CGFloat(maxWindowsInStack) * config.pillHeight + 
                                 CGFloat(maxWindowsInStack - 1) * config.spacing
            } else {
                // Horizontal layout: stack pills horizontally
                indicatorWidth = CGFloat(maxWindowsInStack) * config.pillWidth + 
                                CGFloat(maxWindowsInStack - 1) * config.spacing
                indicatorHeight = config.pillHeight
            }
            
        case .icons:
            if config.iconDirection == .vertical {
                // Vertical layout: stack icons vertically
                indicatorWidth = config.iconSize
                indicatorHeight = CGFloat(maxWindowsInStack) * config.iconSize + 
                                 CGFloat(maxWindowsInStack - 1) * config.spacing
            } else {
                // Horizontal layout: stack icons horizontally
                indicatorWidth = CGFloat(maxWindowsInStack) * config.iconSize + 
                                CGFloat(maxWindowsInStack - 1) * config.spacing
                indicatorHeight = config.iconSize
            }
            
        case .minimal:
            let circleSize: CGFloat = config.minimalSize
            let textHeight: CGFloat = 12 // Approximate height for caption2 text
            
            if config.iconDirection == .vertical {
                // Vertical layout: circles + text below
                indicatorWidth = circleSize
                indicatorHeight = CGFloat(maxWindowsInStack) * circleSize + 
                                 CGFloat(maxWindowsInStack - 1) * config.spacing + 
                                 4 + textHeight // 4px spacing between circles and text
            } else {
                // Horizontal layout: circles + text to the right
                indicatorWidth = CGFloat(maxWindowsInStack) * circleSize + 
                                CGFloat(maxWindowsInStack - 1) * config.spacing + 
                                4 + 20 // 4px spacing + ~20px for text width
                indicatorHeight = max(circleSize, textHeight)
            }
        }
        
        // Add container padding if enabled
        if config.showContainer {
            indicatorWidth += 16  // 8px padding on each side
            indicatorHeight += 16 // 8px padding on top and bottom
        } else {
            indicatorWidth += 8   // 4px padding on each side (minimal padding)
            indicatorHeight += 8  // 4px padding on top and bottom
        }
        
        // Add spacing between multiple stacks (if more than one)
        if stacks.count > 1 {
            indicatorHeight += CGFloat(stacks.count - 1) * 8 // 8px spacing between stacks
        }
        
        // Ensure minimum size for clickability
        indicatorWidth = max(indicatorWidth, 20)
        indicatorHeight = max(indicatorHeight, 20)
        
        return NSSize(width: indicatorWidth, height: indicatorHeight)
    }
    
    private func chooseBestCorner(for stackFrame: NSRect, screenFrame: NSRect) -> StackCornerPosition {
        // Calculate distances to screen edges
        let distanceToLeft = stackFrame.minX - screenFrame.minX
        let distanceToRight = screenFrame.maxX - stackFrame.maxX
        let distanceToTop = screenFrame.maxY - stackFrame.maxY
        let distanceToBottom = stackFrame.minY - screenFrame.minY
        
        // Find the closest edge
        let minDistance = min(distanceToLeft, distanceToRight, distanceToTop, distanceToBottom)
        
        // Choose corner based on which edge is closest, allowing stackline to extend towards that edge
        if minDistance == distanceToLeft {
            // Stack is closest to left edge, use left-side positioning
            return distanceToTop < distanceToBottom ? .topLeft : .bottomLeft
        } else if minDistance == distanceToRight {
            // Stack is closest to right edge, use right-side positioning  
            return distanceToTop < distanceToBottom ? .topRight : .bottomRight
        } else if minDistance == distanceToTop {
            // Stack is closest to top edge, use top positioning
            return distanceToLeft < distanceToRight ? .topLeft : .topRight
        } else {
            // Stack is closest to bottom edge, use bottom positioning
            return distanceToLeft < distanceToRight ? .bottomLeft : .bottomRight
        }
    }
    
    private func chooseBestPlacement(for stackFrame: WindowFrame, screenFrame: NSRect, indicatorSize: NSSize) -> String {
        // This method is no longer used since we use corner-based positioning
        // Keep for compatibility but return a default value
        return "left"
    }
    
    private func constrainToScreen(_ frame: NSRect, screenFrame: NSRect) -> NSRect {
        var constrainedFrame = frame
        
        // Log the screen bounds being used for debugging
        logger.debug("Constraining overlay to screen bounds: \(NSStringFromRect(screenFrame))")
        logger.debug("Original overlay frame: \(NSStringFromRect(frame))")
        
        // Ensure it doesn't go off the left edge
        if constrainedFrame.minX < screenFrame.minX {
            constrainedFrame.origin.x = screenFrame.minX
        }
        
        // Ensure it doesn't go off the right edge
        if constrainedFrame.maxX > screenFrame.maxX {
            constrainedFrame.origin.x = screenFrame.maxX - constrainedFrame.width
        }
        
        // Ensure it doesn't go off the top edge
        if constrainedFrame.maxY > screenFrame.maxY {
            constrainedFrame.origin.y = screenFrame.maxY - constrainedFrame.height
        }
        
        // Ensure it doesn't go off the bottom edge
        if constrainedFrame.minY < screenFrame.minY {
            constrainedFrame.origin.y = screenFrame.minY
        }
        
        // Additional validation: if the overlay is still not fully on screen, 
        // force it to the center of the screen as a fallback
        if constrainedFrame.maxX > screenFrame.maxX || constrainedFrame.minX < screenFrame.minX ||
           constrainedFrame.maxY > screenFrame.maxY || constrainedFrame.minY < screenFrame.minY {
            logger.warning("Overlay still not fully on screen after constraint, centering it")
            constrainedFrame.origin.x = screenFrame.minX + (screenFrame.width - constrainedFrame.width) / 2
            constrainedFrame.origin.y = screenFrame.minY + (screenFrame.height - constrainedFrame.height) / 2
        }
        
        logger.debug("Final constrained overlay frame: \(NSStringFromRect(constrainedFrame))")
        return constrainedFrame
    }
    
    func updateStacksEfficiently(_ stacks: [WindowStack]) {
        guard let stack = stacks.first else { return }
        
        // Check if we need to reposition the window using converted coordinates
        let convertedStackFrame = CoordinateSystemHandler.convertCoreGraphicsToNSScreen(stack.frame)
        let lastPosition = lastStackPositions[stack.id]
        
        // Only reposition if the stack has actually moved
        if lastPosition == nil || !convertedStackFrame.equalTo(lastPosition!) {
            positionRelativeToStack(stack)
            lastStackPositions[stack.id] = convertedStackFrame
        }
        
        // Only update content if stacks actually changed
        if !stacksAreEqual(currentStacks, stacks) {
            self.currentStacks = stacks
            
            // Update content without animation to prevent jumping
            if let hostingView = hostingView {
                hostingView.rootView = SimpleIndicatorContentView(
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
        
        // Force repositioning regardless of whether stack has moved (for config changes)
        positionRelativeToStack(stack)
        
        // Update position tracking
        let stackFrame = CGRect(x: stack.frame.x, y: stack.frame.y, width: stack.frame.w, height: stack.frame.h)
        lastStackPositions[stack.id] = stackFrame
        
        // Update content
        self.currentStacks = stacks
        if let hostingView = hostingView {
            hostingView.rootView = SimpleIndicatorContentView(
                stacks: currentStacks,
                config: configManager.config,
                onWindowClick: onWindowClick
            )
        } else {
            createContentView()
        }
    }
    
    func updateStacks(_ stacks: [WindowStack]) {
        // Delegate to the more efficient update method
        updateStacksEfficiently(stacks)
    }
    
    // Helper to compare stack arrays
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
        // Update collection behavior if needed
        if configManager.config.behavior.showOnAllSpaces {
            self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        } else {
            self.collectionBehavior = [.stationary]
        }
        
        // Content and positioning will be updated by the calling method
        createContentView()
    }
    
    func show() {
        guard !self.isVisible else { return }
        
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)
        
        // Simple fade in animation
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

// MARK: - Simple Indicator Content View

struct SimpleIndicatorContentView: View {
    let stacks: [WindowStack]
    let config: StacklineConfiguration
    let onWindowClick: (Int) -> Void
    
    private func isVisibleWindow(_ window: YabaiWindow, in stack: WindowStack) -> Bool {
        return stack.visibleWindow?.id == window.id
    }
    
    var body: some View {
        let content = VStack(spacing: 8) {
            ForEach(stacks, id: \.id) { stack in
                stackIndicatorView(for: stack)
            }
        }
        
        if config.appearance.showContainer {
            content
                .padding(8)
                .background(config.appearance.backgroundColor.color)
                .cornerRadius(8)
        } else {
            content
                .padding(4) // Minimal padding to prevent clipping
        }
    }
    
    @ViewBuilder
    private func stackIndicatorView(for stack: WindowStack) -> some View {
        VStack(spacing: 4) {
            switch config.appearance.indicatorStyle {
            case .pill:
                pillIndicator(for: stack)
            case .icons:
                iconIndicator(for: stack)
            case .minimal:
                minimalIndicator(for: stack)
            }
        }
    }
    
    private func pillIndicator(for stack: WindowStack) -> some View {
        Group {
            if config.appearance.iconDirection == .vertical {
                VStack(spacing: CGFloat(config.appearance.spacing)) {
                    pillButtons(for: stack)
                }
            } else {
                HStack(spacing: CGFloat(config.appearance.spacing)) {
                    pillButtons(for: stack)
                }
            }
        }
    }
    
    @ViewBuilder
    private func pillButtons(for stack: WindowStack) -> some View {
        ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
            Button(action: {
                onWindowClick(window.id)
            }) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isVisibleWindow(window, in: stack) ? config.appearance.focusedColor.color : config.appearance.unfocusedColor.color)
                    .frame(
                        width: config.appearance.pillWidth,
                        height: config.appearance.pillHeight
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func iconIndicator(for stack: WindowStack) -> some View {
        Group {
            if config.appearance.iconDirection == .vertical {
                VStack(spacing: CGFloat(config.appearance.spacing)) {
                    iconButtons(for: stack)
                }
            } else {
                HStack(spacing: CGFloat(config.appearance.spacing)) {
                    iconButtons(for: stack)
                }
            }
        }
    }
    
    @ViewBuilder
    private func iconButtons(for stack: WindowStack) -> some View {
        ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
            Button(action: {
                onWindowClick(window.id)
            }) {
                AppIconView(appName: window.app, size: config.appearance.iconSize)
                    .opacity(isVisibleWindow(window, in: stack) ? 1.0 : 0.4)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func minimalIndicator(for stack: WindowStack) -> some View {
        Group {
            if config.appearance.iconDirection == .vertical {
                VStack(spacing: CGFloat(config.appearance.spacing)) {
                    minimalButtons(for: stack)
                    minimalText(for: stack)
                }
            } else {
                HStack(spacing: CGFloat(config.appearance.spacing)) {
                    minimalButtons(for: stack)
                    minimalText(for: stack)
                }
            }
        }
    }
    
    @ViewBuilder
    private func minimalButtons(for stack: WindowStack) -> some View {
        Group {
            if config.appearance.iconDirection == .vertical {
                VStack(spacing: CGFloat(config.appearance.spacing)) {
                    ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
                        minimalButton(for: window, isFocused: isVisibleWindow(window, in: stack))
                    }
                }
            } else {
                HStack(spacing: CGFloat(config.appearance.spacing)) {
                    ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
                        minimalButton(for: window, isFocused: isVisibleWindow(window, in: stack))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func minimalButton(for window: YabaiWindow, isFocused: Bool) -> some View {
        Button(action: {
            onWindowClick(window.id)
        }) {
            Circle()
                .fill(isFocused ? config.appearance.focusedColor.color : config.appearance.unfocusedColor.color)
                .frame(width: config.appearance.minimalSize, height: config.appearance.minimalSize)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func minimalText(for stack: WindowStack) -> some View {
        Text("\(stack.windows.count)")
            .font(.caption2)
            .foregroundColor(.white)
            .opacity(0.8)
    }
}

// MARK: - App Icon View

struct AppIconView: View {
    let appName: String
    let size: CGFloat
    
    @State private var appIcon: NSImage?
    
    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(appName.prefix(1)))
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            loadAppIcon()
        }
    }
    
    private func loadAppIcon() {
        Task {
            if let icon = await fetchAppIcon(for: appName) {
                await MainActor.run {
                    self.appIcon = icon
                }
            }
        }
    }
    
    private func fetchAppIcon(for appName: String) async -> NSImage? {
        // First try to find the app by display name
        let workspace = NSWorkspace.shared
        
        // Try to find the running application first
        let runningApps = workspace.runningApplications
        if let runningApp = runningApps.first(where: { $0.localizedName == appName }) {
            if let bundleURL = runningApp.bundleURL {
                return workspace.icon(forFile: bundleURL.path)
            }
        }
        
        // Try to find app by bundle identifier (in case appName is actually a bundle ID)
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appName) {
            return workspace.icon(forFile: appURL.path)
        }
        
        // Try to find app by searching for the app name in Applications folder
        let applicationFolders = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            "/System/Applications/Utilities"
        ]
        
        for folder in applicationFolders {
            let folderURL = URL(fileURLWithPath: folder)
            if let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                for appURL in contents {
                    if appURL.pathExtension == "app" {
                        let appDisplayName = appURL.deletingPathExtension().lastPathComponent
                        if appDisplayName == appName {
                            return workspace.icon(forFile: appURL.path)
                        }
                    }
                }
            }
        }
        
        // Try using the app name as a potential bundle identifier pattern
        let possibleBundleIDs = [
            "com.apple.\(appName.lowercased())",
            "com.\(appName.lowercased()).\(appName.lowercased())",
            "org.\(appName.lowercased()).\(appName.lowercased())"
        ]
        
        for bundleID in possibleBundleIDs {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return workspace.icon(forFile: appURL.path)
            }
        }
        
        // Last resort: try to get a generic app icon
        if let genericAppURL = workspace.urlForApplication(toOpen: URL(fileURLWithPath: "/")) {
            return workspace.icon(forFile: genericAppURL.path)
        }
        
        return nil
    }
} 
