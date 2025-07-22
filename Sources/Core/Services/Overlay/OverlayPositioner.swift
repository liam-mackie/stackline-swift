import Foundation
import AppKit
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "overlay-positioner")

// MARK: - Overlay Positioner

struct OverlayPositioner {
    
    static func chooseBestCorner(for stackFrame: NSRect, screenFrame: NSRect) -> StackCornerPosition {
        let distanceToLeft = stackFrame.minX - screenFrame.minX
        let distanceToRight = screenFrame.maxX - stackFrame.maxX
        let distanceToTop = screenFrame.maxY - stackFrame.maxY
        let distanceToBottom = stackFrame.minY - screenFrame.minY
        
        let minDistance = min(distanceToLeft, distanceToRight, distanceToTop, distanceToBottom)
        
        if minDistance == distanceToLeft {
            return distanceToTop < distanceToBottom ? .topLeft : .bottomLeft
        } else if minDistance == distanceToRight {
            return distanceToTop < distanceToBottom ? .topRight : .bottomRight
        } else if minDistance == distanceToTop {
            return distanceToLeft < distanceToRight ? .topLeft : .topRight
        } else {
            return distanceToLeft < distanceToRight ? .bottomLeft : .bottomRight
        }
    }
    
    static func calculateFrame(
        for stackFrame: NSRect,
        cornerPosition: StackCornerPosition,
        indicatorSize: NSSize,
        config: StacklineConfiguration
    ) -> NSRect {
        let edgeOffset = config.positioning.edgeOffset
        let cornerOffset = config.positioning.cornerOffset
        
        switch cornerPosition {
        case .topLeft:
            return NSRect(
                x: stackFrame.origin.x - edgeOffset,
                y: stackFrame.origin.y + stackFrame.height - indicatorSize.height - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .topRight:
            return NSRect(
                x: stackFrame.origin.x + stackFrame.width - indicatorSize.width + edgeOffset,
                y: stackFrame.origin.y + stackFrame.height - indicatorSize.height - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .bottomLeft:
            return NSRect(
                x: stackFrame.origin.x - edgeOffset,
                y: stackFrame.origin.y - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .bottomRight:
            return NSRect(
                x: stackFrame.origin.x + stackFrame.width - indicatorSize.width + edgeOffset,
                y: stackFrame.origin.y - cornerOffset,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        case .auto:
            return NSRect(
                x: stackFrame.origin.x,
                y: stackFrame.origin.y,
                width: indicatorSize.width,
                height: indicatorSize.height
            )
        }
    }
    
    static func constrainToScreen(_ frame: NSRect, screenFrame: NSRect) -> NSRect {
        var constrainedFrame = frame
        
        logger.debug("Constraining overlay to screen bounds: \(NSStringFromRect(screenFrame))")
        logger.debug("Original overlay frame: \(NSStringFromRect(frame))")
        
        if constrainedFrame.minX < screenFrame.minX {
            constrainedFrame.origin.x = screenFrame.minX
        }
        
        if constrainedFrame.maxX > screenFrame.maxX {
            constrainedFrame.origin.x = screenFrame.maxX - constrainedFrame.width
        }
        
        if constrainedFrame.maxY > screenFrame.maxY {
            constrainedFrame.origin.y = screenFrame.maxY - constrainedFrame.height
        }
        
        if constrainedFrame.minY < screenFrame.minY {
            constrainedFrame.origin.y = screenFrame.minY
        }
        
        if constrainedFrame.maxX > screenFrame.maxX || constrainedFrame.minX < screenFrame.minX ||
           constrainedFrame.maxY > screenFrame.maxY || constrainedFrame.minY < screenFrame.minY {
            logger.warning("Overlay still not fully on screen after constraint, centering it")
            constrainedFrame.origin.x = screenFrame.minX + (screenFrame.width - constrainedFrame.width) / 2
            constrainedFrame.origin.y = screenFrame.minY + (screenFrame.height - constrainedFrame.height) / 2
        }
        
        logger.debug("Final constrained overlay frame: \(NSStringFromRect(constrainedFrame))")
        return constrainedFrame
    }
}