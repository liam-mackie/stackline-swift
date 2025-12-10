import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "indicator-manager")

// MARK: - SwiftUI Indicator Manager

@MainActor
final class SwiftUIIndicatorManager: ObservableObject {
    @Published var isEnabled: Bool = true
    @Published private(set) var activeOverlays: [StackOverlayData] = []

    private let configManager: ConfigurationManager
    private var currentStacks: [WindowStack] = []

    init(configManager: ConfigurationManager) {
        self.configManager = configManager
        logger.debug("SwiftUIIndicatorManager initialized")
    }

    func updateIndicators(for stacks: [WindowStack]) {
        self.currentStacks = stacks

        let shouldShow = configManager.config.behavior.showByDefault && isEnabled &&
                        (!configManager.config.behavior.hideWhenNoStacks || !stacks.isEmpty)

        if shouldShow && !stacks.isEmpty {
            updateOverlays(for: stacks)
        } else {
            hideAllOverlays()
        }
    }

    private func updateOverlays(for stacks: [WindowStack]) {
        let newOverlays: [StackOverlayData] = stacks.compactMap { stack in
            guard let position = calculateOverlayPosition(for: stack) else { return nil }

            return StackOverlayData(
                stack: stack,
                position: position,
                config: configManager.config
            )
        }

        // Only update if overlays actually changed
        if activeOverlays != newOverlays {
            activeOverlays = newOverlays
            logger.debug("Updated overlays: \(newOverlays.count) active")
        }
    }

    private func calculateOverlayPosition(for stack: WindowStack) -> CGRect? {
        guard let screen = stack.frame.containingScreen else {
            logger.warning("Could not find screen for stack \(stack.id)")
            return nil
        }

        let screenFrame = screen.visibleFrame
        let stackFrame = stack.frame.swiftUIRect

        // Calculate indicator size
        let indicatorSize = calculateIndicatorSize(for: stack)

        // Determine corner position
        var cornerPosition = configManager.config.positioning.stackCorner
        if cornerPosition == .auto {
            cornerPosition = chooseBestCorner(for: stackFrame, in: screenFrame)
        }

        // Calculate final position
        var position = calculatePosition(
            for: stackFrame,
            corner: cornerPosition,
            size: indicatorSize
        )

        // Constrain to screen if needed
        if configManager.config.positioning.stickToScreenEdge {
            position = constrainToScreen(position, screenFrame: screenFrame)
        }

        return position
    }

    private func calculateIndicatorSize(for stack: WindowStack) -> CGSize {
        // Simplified size calculation - can be enhanced based on config
        let baseHeight: CGFloat = 30
        let baseWidth: CGFloat = 150

        switch configManager.config.appearance.indicatorStyle {
        case .pill:
            return CGSize(width: baseWidth, height: baseHeight)
        case .icons:
            let iconCount = min(stack.count, 5)
            return CGSize(width: CGFloat(iconCount * 25 + 20), height: baseHeight)
        case .minimal:
            return CGSize(width: 60, height: 20)
        }
    }

    private func chooseBestCorner(for stackFrame: CGRect, in screenFrame: CGRect) -> StackCornerPosition {
        let centerX = stackFrame.midX
        let centerY = stackFrame.midY
        let screenCenterX = screenFrame.midX
        let screenCenterY = screenFrame.midY

        if centerX < screenCenterX && centerY < screenCenterY {
            return .bottomRight
        } else if centerX >= screenCenterX && centerY < screenCenterY {
            return .bottomLeft
        } else if centerX < screenCenterX && centerY >= screenCenterY {
            return .topRight
        } else {
            return .topLeft
        }
    }

    private func calculatePosition(
        for stackFrame: CGRect,
        corner: StackCornerPosition,
        size: CGSize
    ) -> CGRect {
        let offset: CGFloat = 5

        switch corner {
        case .topLeft:
            return CGRect(
                x: stackFrame.minX - size.width - offset,
                y: stackFrame.maxY + offset,
                width: size.width,
                height: size.height
            )
        case .topRight:
            return CGRect(
                x: stackFrame.maxX + offset,
                y: stackFrame.maxY + offset,
                width: size.width,
                height: size.height
            )
        case .bottomLeft:
            return CGRect(
                x: stackFrame.minX - size.width - offset,
                y: stackFrame.minY - size.height - offset,
                width: size.width,
                height: size.height
            )
        case .bottomRight:
            return CGRect(
                x: stackFrame.maxX + offset,
                y: stackFrame.minY - size.height - offset,
                width: size.width,
                height: size.height
            )
        case .auto:
            // This shouldn't happen as auto is resolved before calling this method
            return calculatePosition(for: stackFrame, corner: .bottomRight, size: size)
        }
    }

    private func constrainToScreen(_ frame: CGRect, screenFrame: CGRect) -> CGRect {
        var constrainedFrame = frame

        if constrainedFrame.minX < screenFrame.minX {
            constrainedFrame.origin.x = screenFrame.minX
        }
        if constrainedFrame.maxX > screenFrame.maxX {
            constrainedFrame.origin.x = screenFrame.maxX - constrainedFrame.width
        }
        if constrainedFrame.minY < screenFrame.minY {
            constrainedFrame.origin.y = screenFrame.minY
        }
        if constrainedFrame.maxY > screenFrame.maxY {
            constrainedFrame.origin.y = screenFrame.maxY - constrainedFrame.height
        }

        return constrainedFrame
    }

    private func hideAllOverlays() {
        if !activeOverlays.isEmpty {
            activeOverlays.removeAll()
            logger.debug("Hidden all overlays")
        }
    }

    func toggle() {
        isEnabled.toggle()

        if isEnabled {
            updateIndicators(for: currentStacks)
        } else {
            hideAllOverlays()
        }
    }

    func refreshAll() {
        updateIndicators(for: currentStacks)
    }

    func cleanup() {
        hideAllOverlays()
        currentStacks.removeAll()
        logger.debug("SwiftUIIndicatorManager cleanup completed")
    }

    deinit {
        logger.debug("SwiftUIIndicatorManager deinitialized")
    }
}