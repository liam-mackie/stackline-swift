import SwiftUI
import AppKit

// MARK: - Stack Overlay Data

struct StackOverlayData: Equatable {
    let stack: WindowStack
    let position: CGRect
    let config: StacklineConfiguration

    static func == (lhs: StackOverlayData, rhs: StackOverlayData) -> Bool {
        return lhs.stack.id == rhs.stack.id &&
               lhs.position == rhs.position &&
               lhs.config == rhs.config
    }
}

// MARK: - Stack Overlay Window

struct StackOverlayWindow: View {
    let overlayData: StackOverlayData
    let onWindowClick: (Int) -> Void

    private var stack: WindowStack { overlayData.stack }
    private var config: StacklineConfiguration { overlayData.config }

    var body: some View {
        Group {
            switch config.appearance.indicatorStyle {
            case .pill:
                PillIndicatorView(
                    stack: stack,
                    config: config,
                    onWindowClick: onWindowClick
                )
            case .icons:
                IconIndicatorView(
                    stack: stack,
                    config: config,
                    onWindowClick: onWindowClick
                )
            case .minimal:
                MinimalIndicatorView(
                    stack: stack,
                    config: config,
                    onWindowClick: onWindowClick
                )
            }
        }
        .if(config.appearance.showContainer) { view in
            view
                .padding(8)
                .background(config.appearance.backgroundColor.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .if(!config.appearance.showContainer) { view in
            view.padding(4)
        }
    }
}

// MARK: - View Extension for Conditional Modifiers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}