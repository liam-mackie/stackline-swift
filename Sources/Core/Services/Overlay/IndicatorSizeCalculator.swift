import Foundation
import AppKit

// MARK: - Indicator Size Calculator

struct IndicatorSizeCalculator {
    
    static func calculateSize(for stacks: [WindowStack], config: StacklineConfiguration) -> NSSize {
        let appearance = config.appearance
        let maxWindowsInStack = stacks.map(\.windows.count).max() ?? 1
        
        var indicatorWidth: CGFloat = 0
        var indicatorHeight: CGFloat = 0
        
        switch appearance.indicatorStyle {
        case .pill:
            if appearance.iconDirection == .vertical {
                indicatorWidth = appearance.pillWidth
                indicatorHeight = CGFloat(maxWindowsInStack) * appearance.pillHeight + 
                                 CGFloat(maxWindowsInStack - 1) * appearance.spacing
            } else {
                indicatorWidth = CGFloat(maxWindowsInStack) * appearance.pillWidth + 
                                CGFloat(maxWindowsInStack - 1) * appearance.spacing
                indicatorHeight = appearance.pillHeight
            }
            
        case .icons:
            if appearance.iconDirection == .vertical {
                indicatorWidth = appearance.iconSize
                indicatorHeight = CGFloat(maxWindowsInStack) * appearance.iconSize + 
                                 CGFloat(maxWindowsInStack - 1) * appearance.spacing
            } else {
                indicatorWidth = CGFloat(maxWindowsInStack) * appearance.iconSize + 
                                CGFloat(maxWindowsInStack - 1) * appearance.spacing
                indicatorHeight = appearance.iconSize
            }
            
        case .minimal:
            let circleSize: CGFloat = appearance.minimalSize
            let textHeight: CGFloat = 12
            
            if appearance.iconDirection == .vertical {
                indicatorWidth = circleSize
                indicatorHeight = CGFloat(maxWindowsInStack) * circleSize + 
                                 CGFloat(maxWindowsInStack - 1) * appearance.spacing + 
                                 4 + textHeight
            } else {
                indicatorWidth = CGFloat(maxWindowsInStack) * circleSize + 
                                CGFloat(maxWindowsInStack - 1) * appearance.spacing + 
                                4 + 20
                indicatorHeight = max(circleSize, textHeight)
            }
        }
        
        if appearance.showContainer {
            indicatorWidth += 16
            indicatorHeight += 16
        } else {
            indicatorWidth += 8
            indicatorHeight += 8
        }
        
        if stacks.count > 1 {
            indicatorHeight += CGFloat(stacks.count - 1) * 8
        }
        
        indicatorWidth = max(indicatorWidth, 20)
        indicatorHeight = max(indicatorHeight, 20)
        
        return NSSize(width: indicatorWidth, height: indicatorHeight)
    }
}