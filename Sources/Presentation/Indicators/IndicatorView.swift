import SwiftUI

/// Root view for stack indicators - delegates to style-specific views
struct IndicatorView: View {
    let stack: WindowStack
    let style: IndicatorStyle
    let appearance: AppearancePreferences
    var onWindowClick: ((WindowIdentifier) -> Void)?

    var body: some View {
        switch style {
        case .pill:
            PillIndicatorView(stack: stack, appearance: appearance, onWindowClick: onWindowClick)
        case .icons:
            IconsIndicatorView(stack: stack, appearance: appearance, onWindowClick: onWindowClick)
        case .minimal:
            MinimalIndicatorView(stack: stack, appearance: appearance, onWindowClick: onWindowClick)
        }
    }
}

/// Pill-style indicator showing window count
struct PillIndicatorView: View {
    let stack: WindowStack
    let appearance: AppearancePreferences
    var onWindowClick: ((WindowIdentifier) -> Void)?

    private var pillSettings: PillStyleSettings { appearance.pillSettings }

    private var fontSize: CGFloat {
        max(8, pillSettings.pillHeight * 0.8)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let focusedIndex = focusedWindowIndex {
                Text("\(focusedIndex + 1)/\(stack.count)")
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
            } else {
                Text("\(stack.count)")
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
            }
        }
        .foregroundColor(pillSettings.textColor.color)
        .frame(minWidth: pillSettings.pillWidth, minHeight: pillSettings.pillHeight)
        .modifier(ContainerBackgroundModifier(
            color: appearance.backgroundColor.color,
            cornerRadius: appearance.cornerRadius,
            borderColor: appearance.borderColor.color,
            borderWidth: appearance.borderWidth,
            showContainer: appearance.showContainer,
            padding: appearance.containerPadding
        ))
        .contentShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .onTapGesture {
            guard let click = onWindowClick else { return }
            let nextWindow = nextWindowInStack()
            click(nextWindow.id)
        }
    }

    private var focusedWindowIndex: Int? {
        guard let focusedId = stack.focusedWindowId else { return nil }
        return stack.index(of: focusedId)
    }

    private func nextWindowInStack() -> ManagedWindow {
        guard let currentIndex = focusedWindowIndex, stack.count > 1 else {
            return stack.windows.first!
        }
        let nextIndex = (currentIndex + 1) % stack.count
        return stack.windows[nextIndex]
    }
}

/// Icons-style indicator showing app icons
struct IconsIndicatorView: View {
    let stack: WindowStack
    let appearance: AppearancePreferences
    var onWindowClick: ((WindowIdentifier) -> Void)?

    private var iconsSettings: IconsStyleSettings { appearance.iconsSettings }

    var body: some View {
        DirectionalStack(direction: iconsSettings.iconDirection, spacing: appearance.spacing) {
            ForEach(Array(stack.windows.enumerated()), id: \.element.id) { _, window in
                WindowIcon(
                    window: window,
                    isFocused: window.id == stack.focusedWindowId,
                    settings: iconsSettings,
                    onTap: { onWindowClick?(window.id) }
                )
            }
        }
        .modifier(ContainerBackgroundModifier(
            color: appearance.backgroundColor.color,
            cornerRadius: appearance.cornerRadius,
            borderColor: appearance.borderColor.color,
            borderWidth: appearance.borderWidth,
            showContainer: appearance.showContainer,
            padding: appearance.containerPadding
        ))
    }
}

/// Individual window icon in icons-style indicator
struct WindowIcon: View {
    let window: ManagedWindow
    let isFocused: Bool
    let settings: IconsStyleSettings
    var onTap: (() -> Void)?

    @State private var appIcon: NSImage?

    var body: some View {
        ZStack {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: settings.iconSize, height: settings.iconSize)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: settings.iconSize, height: settings.iconSize)
            }

            if isFocused {
                Circle()
                    .fill(settings.focusedColor.color)
                    .frame(width: 6, height: 6)
                    .offset(x: settings.iconSize / 2 - 3, y: settings.iconSize / 2 - 3)
            }
        }
        .opacity(isFocused ? 1.0 : settings.unfocusedOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .task(id: window.processId) {
            appIcon = await AppIconCache.shared.icon(for: window.processId)
        }
    }
}

/// Minimal-style indicator showing dots
struct MinimalIndicatorView: View {
    let stack: WindowStack
    let appearance: AppearancePreferences
    var onWindowClick: ((WindowIdentifier) -> Void)?

    private var minimalSettings: MinimalStyleSettings { appearance.minimalSettings }

    var body: some View {
        DirectionalStack(direction: minimalSettings.iconDirection, spacing: appearance.spacing) {
            ForEach(0..<stack.count, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: minimalSettings.minimalSize, height: minimalSettings.minimalSize)
                    .contentShape(Circle())
                    .onTapGesture {
                        onWindowClick?(stack.windows[index].id)
                    }
            }
        }
        .modifier(ContainerBackgroundModifier(
            color: appearance.backgroundColor.color,
            cornerRadius: appearance.cornerRadius,
            borderColor: appearance.borderColor.color,
            borderWidth: appearance.borderWidth,
            showContainer: appearance.showContainer,
            padding: appearance.containerPadding
        ))
    }

    private func dotColor(for index: Int) -> Color {
        let isFocused = stack.windows[index].id == stack.focusedWindowId
        return isFocused ? minimalSettings.focusedColor.color : minimalSettings.unfocusedColor.color
    }
}

// MARK: - Directional Stack Helper

struct DirectionalStack<Content: View>: View {
    let direction: IconDirection
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch direction {
        case .horizontal:
            HStack(spacing: spacing) { content() }
        case .vertical:
            VStack(spacing: spacing) { content() }
        }
    }
}

// MARK: - Container Background Modifier

struct ContainerBackgroundModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let borderColor: Color
    let borderWidth: CGFloat
    let showContainer: Bool
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if showContainer {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color)
                }
            }
            .overlay {
                if showContainer && borderWidth > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
            }
    }
}
