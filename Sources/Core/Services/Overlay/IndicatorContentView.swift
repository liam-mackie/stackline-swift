import SwiftUI
import AppKit

// MARK: - Indicator Content View

struct IndicatorContentView: View {
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
                .padding(4)
        }
    }
    
    @ViewBuilder
    private func stackIndicatorView(for stack: WindowStack) -> some View {
        VStack(spacing: 4) {
            switch config.appearance.indicatorStyle {
            case .pill:
                PillIndicatorView(stack: stack, config: config, onWindowClick: onWindowClick)
            case .icons:
                IconIndicatorView(stack: stack, config: config, onWindowClick: onWindowClick)
            case .minimal:
                MinimalIndicatorView(stack: stack, config: config, onWindowClick: onWindowClick)
            }
        }
    }
}