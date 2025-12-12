import Foundation
import CoreGraphics

/// Calculates indicator positions relative to window stacks
struct IndicatorPositioner {
    /// Default padding from screen edges
    static let defaultEdgePadding: CGFloat = 0

    /// Calculate the position for an indicator based on stack and corner preference
    static func position(
        for stack: WindowStack,
        corner: StackCorner,
        indicatorSize: CGSize,
        screenBounds: CGRect,
        horizontalOffset: CGFloat = 0,
        verticalOffset: CGFloat = 0,
        stickToScreenEdge: Bool = true
    ) -> CGPoint {
        let resolvedCorner = corner == .auto
            ? autoSelectCorner(for: stack, screenBounds: screenBounds)
            : corner

        return calculatePosition(
            stackFrame: stack.frame,
            corner: resolvedCorner,
            indicatorSize: indicatorSize,
            screenBounds: screenBounds,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            stickToScreenEdge: stickToScreenEdge
        )
    }

    /// Auto-select the best corner based on window position
    /// Places indicator in opposite corner to minimize overlap
    static func autoSelectCorner(for stack: WindowStack, screenBounds: CGRect) -> StackCorner {
        let frame = stack.frame
        let centerX = frame.midX
        let centerY = frame.midY
        let screenCenterX = screenBounds.midX
        let screenCenterY = screenBounds.midY

        let isLeft = centerX < screenCenterX
//      let isTop = centerY > screenCenterY
        let _ = centerY > screenCenterY
        
        // For now, just return top left or top right of the stack, but in future, may need to reconsider for horizontal stacks
        if isLeft {
            return .topLeft
        } else {
            return .topRight
        }
    }

    /// Detect the layout pattern from a set of stacks
    static func detectLayout(from stacks: [WindowStack], screenBounds: CGRect) -> LayoutPattern {
        guard !stacks.isEmpty else {
            return .empty
        }

        let signature = LayoutSignature.compute(from: stacks, screenBounds: screenBounds)
        return LayoutPattern(signature: signature)
    }

    /// Sort stacks in a consistent order based on their position (left-to-right, top-to-bottom)
    static func sortedStackIndices(for stacks: [WindowStack]) -> [Int] {
        let indexed = stacks.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { a, b in
            let aCenter = CGPoint(x: a.1.frame.midX, y: a.1.frame.midY)
            let bCenter = CGPoint(x: b.1.frame.midX, y: b.1.frame.midY)
            // Sort by Y first (top to bottom), then by X (left to right)
            // AppKit uses bottom-left origin: larger Y = top
            if abs(aCenter.y - bCenter.y) > 50 {
                return aCenter.y > bCenter.y
            }
            return aCenter.x < bCenter.x
        }
        return sorted.map { $0.0 }
    }

    /// Get the index of a stack within a sorted layout
    static func layoutIndex(for stack: WindowStack, in stacks: [WindowStack]) -> Int {
        let sortedIndices = sortedStackIndices(for: stacks)
        guard let originalIndex = stacks.firstIndex(where: { $0.id == stack.id }),
              let layoutIndex = sortedIndices.firstIndex(of: originalIndex) else {
            return 0
        }
        return layoutIndex
    }

    private static func calculatePosition(
        stackFrame: CGRect,
        corner: StackCorner,
        indicatorSize: CGSize,
        screenBounds: CGRect,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat,
        stickToScreenEdge: Bool
    ) -> CGPoint {
        var x: CGFloat
        var y: CGFloat

        // Offset semantics (relative to corner, positive moves away from corner edges):
        // - horizontalOffset: positive moves away from corner's horizontal edge
        // - verticalOffset: positive moves away from corner's vertical edge
        // AppKit uses bottom-left origin: minY is bottom, maxY is top
        switch corner {
        case .topLeft, .auto:
            // Top-left: horizontal positive = right, vertical positive = down
            x = stackFrame.minX + defaultEdgePadding + horizontalOffset
            y = stackFrame.maxY - indicatorSize.height - defaultEdgePadding - verticalOffset
        case .topRight:
            // Top-right: horizontal positive = left, vertical positive = down
            x = stackFrame.maxX - indicatorSize.width - defaultEdgePadding - horizontalOffset
            y = stackFrame.maxY - indicatorSize.height - defaultEdgePadding - verticalOffset
        case .bottomLeft:
            // Bottom-left: horizontal positive = right, vertical positive = up
            x = stackFrame.minX + defaultEdgePadding + horizontalOffset
            y = stackFrame.minY + defaultEdgePadding + verticalOffset
        case .bottomRight:
            // Bottom-right: horizontal positive = left, vertical positive = up
            x = stackFrame.maxX - indicatorSize.width - defaultEdgePadding - horizontalOffset
            y = stackFrame.minY + defaultEdgePadding + verticalOffset
        }

        if stickToScreenEdge {
            let screenPadding = defaultEdgePadding
            x = max(screenBounds.minX + screenPadding, min(x, screenBounds.maxX - indicatorSize.width - screenPadding))
            y = max(screenBounds.minY + screenPadding, min(y, screenBounds.maxY - indicatorSize.height - screenPadding))
        }

        return CGPoint(x: x, y: y)
    }
}

/// Calculates indicator sizes based on content, style, and appearance preferences
struct IndicatorSizeCalculator {
    static func size(for stack: WindowStack, appearance: AppearancePreferences) -> CGSize {
        switch appearance.indicatorStyle {
        case .pill:
            return pillSize(windowCount: stack.count, appearance: appearance)
        case .icons:
            return iconsSize(windowCount: stack.count, appearance: appearance)
        case .minimal:
            return minimalSize(windowCount: stack.count, appearance: appearance)
        }
    }

    static func pillSize(windowCount: Int, appearance: AppearancePreferences) -> CGSize {
        let padding = appearance.containerPadding
        let textWidth = CGFloat(windowCount) * 10.0 + padding * 2
        return CGSize(
            width: max(appearance.pillWidth, textWidth) + padding * 2,
            height: appearance.pillHeight + padding * 2
        )
    }

    static func iconsSize(windowCount: Int, appearance: AppearancePreferences) -> CGSize {
        let iconDimension = CGFloat(windowCount) * appearance.iconSize + CGFloat(max(0, windowCount - 1)) * appearance.spacing
        let padding = appearance.containerPadding * 2

        switch appearance.iconDirection {
        case .horizontal:
            return CGSize(width: iconDimension + padding, height: appearance.iconSize + padding)
        case .vertical:
            return CGSize(width: appearance.iconSize + padding, height: iconDimension + padding)
        }
    }

    static func minimalSize(windowCount: Int, appearance: AppearancePreferences) -> CGSize {
        let dotDimension = CGFloat(windowCount) * appearance.minimalSize + CGFloat(max(0, windowCount - 1)) * appearance.spacing
        let padding = appearance.containerPadding * 2

        switch appearance.iconDirection {
        case .horizontal:
            return CGSize(width: dotDimension + padding, height: appearance.minimalSize + padding)
        case .vertical:
            return CGSize(width: appearance.minimalSize + padding, height: dotDimension + padding)
        }
    }
}
