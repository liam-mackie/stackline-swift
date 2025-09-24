import SwiftUI
import AppKit

// MARK: - Indicator Content View

struct IndicatorContentView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private func isVisibleWindow(_ window: YabaiWindow, in stack: WindowStack) -> Bool {
        return stack.visibleWindow?.id == window.id
    }

    var body: some View {
        let content = VStack(spacing: 8) {
            // Use indices to prevent ForEach state accumulation
            ForEach(0..<viewModel.stacks.count, id: \.self) { index in
                stackIndicatorView(for: viewModel.stacks[index])
                    .id(viewModel.stacks[index].id) // Stable ID for view recycling
            }
        }

        if viewModel.config.appearance.showContainer {
            content
                .padding(8)
                .background(viewModel.config.appearance.backgroundColor.color)
                .cornerRadius(8)
        } else {
            content
                .padding(4)
        }
    }

    @ViewBuilder
    private func stackIndicatorView(for stack: WindowStack) -> some View {
        VStack(spacing: 4) {
            switch viewModel.config.appearance.indicatorStyle {
            case .pill:
                PillIndicatorView(stack: stack, config: viewModel.config, onWindowClick: viewModel.onWindowClick)
                    .id("\(stack.id)-pill") // Stable ID for each style
            case .icons:
                IconIndicatorView(stack: stack, config: viewModel.config, onWindowClick: viewModel.onWindowClick)
                    .id("\(stack.id)-icon")
            case .minimal:
                MinimalIndicatorView(stack: stack, config: viewModel.config, onWindowClick: viewModel.onWindowClick)
                    .id("\(stack.id)-minimal")
            }
        }
    }
}