import SwiftUI

// MARK: - Layout Helper

@ViewBuilder
private func DirectionalStack<Content: View>(
    direction: IconDirection,
    spacing: CGFloat,
    @ViewBuilder content: () -> Content
) -> some View {
    if direction == .vertical {
        VStack(spacing: spacing) {
            content()
        }
    } else {
        HStack(spacing: spacing) {
            content()
        }
    }
}

// MARK: - Pill Indicator View

struct PillIndicatorView: View {
    let stack: WindowStack
    let config: StacklineConfiguration
    let onWindowClick: (Int) -> Void
    
    private func isVisibleWindow(_ window: YabaiWindow) -> Bool {
        return stack.visibleWindow?.id == window.id
    }
    
    var body: some View {
        DirectionalStack(direction: config.appearance.iconDirection, spacing: CGFloat(config.appearance.spacing)) {
            pillButtons
        }
    }
    
    @ViewBuilder
    private var pillButtons: some View {
        ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
            Button(action: {
                onWindowClick(window.id)
            }) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isVisibleWindow(window) ? config.appearance.focusedColor.color : config.appearance.unfocusedColor.color)
                    .frame(
                        width: config.appearance.pillWidth,
                        height: config.appearance.pillHeight
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Icon Indicator View

struct IconIndicatorView: View {
    let stack: WindowStack
    let config: StacklineConfiguration
    let onWindowClick: (Int) -> Void
    
    private func isVisibleWindow(_ window: YabaiWindow) -> Bool {
        return stack.visibleWindow?.id == window.id
    }
    
    var body: some View {
        DirectionalStack(direction: config.appearance.iconDirection, spacing: CGFloat(config.appearance.spacing)) {
            iconButtons
        }
    }
    
    @ViewBuilder
    private var iconButtons: some View {
        ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
            Button(action: {
                onWindowClick(window.id)
            }) {
                AppIconView(appName: window.app, size: config.appearance.iconSize)
                    .opacity(isVisibleWindow(window) ? 1.0 : 0.4)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Minimal Indicator View

struct MinimalIndicatorView: View {
    let stack: WindowStack
    let config: StacklineConfiguration
    let onWindowClick: (Int) -> Void
    
    private func isVisibleWindow(_ window: YabaiWindow) -> Bool {
        return stack.visibleWindow?.id == window.id
    }
    
    var body: some View {
        DirectionalStack(direction: config.appearance.iconDirection, spacing: CGFloat(config.appearance.spacing)) {
            minimalButtons
            minimalText
        }
    }
    
    @ViewBuilder
    private var minimalButtons: some View {
        DirectionalStack(direction: config.appearance.iconDirection, spacing: CGFloat(config.appearance.spacing)) {
            ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
                minimalButton(for: window, isFocused: isVisibleWindow(window))
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
    private var minimalText: some View {
        Text("\(stack.windows.count)")
            .font(.caption2)
            .foregroundColor(.white)
            .opacity(0.8)
    }
}