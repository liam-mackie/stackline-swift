import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject {
    private var window: NSWindow?
    private var hostingController: NSHostingController<PreferencesView>?
    private let preferences: UserDefaultsPreferences
    private let stackDetector: StackDetector

    init(preferences: UserDefaultsPreferences, stackDetector: StackDetector) {
        self.preferences = preferences
        self.stackDetector = stackDetector
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showPreferences),
            name: .openPreferences,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func showPreferences() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let preferencesView = PreferencesView(preferences: preferences, stackDetector: stackDetector)
        let controller = NSHostingController(rootView: preferencesView)
        hostingController = controller

        let newWindow = NSWindow(contentViewController: controller)
        newWindow.title = "Stackline Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 650, height: 520))
        newWindow.center()
        newWindow.delegate = self

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cleanupWindow() {
        hostingController = nil
        window = nil
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            cleanupWindow()
        }
    }
}

// MARK: - Preferences Section

enum PreferencesSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case positioning = "Positioning"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .positioning: return "square.on.square"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

// MARK: - Main Preferences View

struct PreferencesView: View {
    @ObservedObject var preferences: UserDefaultsPreferences
    @ObservedObject var stackDetector: StackDetector
    @State private var selectedSection: PreferencesSection = .general

    var body: some View {
        NavigationSplitView {
            List(PreferencesSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 650, minHeight: 520)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .general:
            GeneralPreferencesView(behavior: $preferences.behavior)
        case .appearance:
            AppearancePreferencesView(appearance: $preferences.appearance)
        case .positioning:
            PositioningPreferencesView(
                positioning: $preferences.positioning,
                appearance: preferences.appearance,
                stacks: stackDetector.detectedStacks
            )
        case .advanced:
            AdvancedPreferencesView(preferences: preferences)
        }
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @Binding var behavior: BehaviorPreferences

    var body: some View {
        Form {
            Section("Indicators") {
                Toggle("Show Indicators", isOn: $behavior.showByDefault)
                Toggle("Click to Focus Window", isOn: $behavior.clickToFocus)
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $behavior.launchAtStartup)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("General")
    }
}

// MARK: - Appearance Preferences

struct AppearancePreferencesView: View {
    @Binding var appearance: AppearancePreferences

    var body: some View {
        Form {
            Section("Style") {
                Picker("Indicator Style", selection: $appearance.indicatorStyle) {
                    Text("Pill").tag(IndicatorStyle.pill)
                    Text("Icons").tag(IndicatorStyle.icons)
                    Text("Minimal").tag(IndicatorStyle.minimal)
                }
                .pickerStyle(.segmented)
            }

            Section("Dimensions") {
                switch appearance.indicatorStyle {
                case .pill:
                    DimensionControl(label: "Pill Height", value: $appearance.pillSettings.pillHeight, range: 4...24, step: 1)
                    DimensionControl(label: "Pill Width", value: $appearance.pillSettings.pillWidth, range: 20...120, step: 5)

                case .icons:
                    Picker("Layout Direction", selection: $appearance.iconsSettings.iconDirection) {
                        Text("Horizontal").tag(IconDirection.horizontal)
                        Text("Vertical").tag(IconDirection.vertical)
                    }
                    DimensionControl(label: "Icon Size", value: $appearance.iconsSettings.iconSize, range: 12...48, step: 2)

                case .minimal:
                    Picker("Layout Direction", selection: $appearance.minimalSettings.iconDirection) {
                        Text("Horizontal").tag(IconDirection.horizontal)
                        Text("Vertical").tag(IconDirection.vertical)
                    }
                    DimensionControl(label: "Dot Size", value: $appearance.minimalSettings.minimalSize, range: 4...20, step: 2)
                }

                DimensionControl(label: "Spacing", value: $appearance.spacing, range: 0...16, step: 1)
            }

            Section("Container") {
                Toggle("Show Background", isOn: $appearance.showContainer)
                DimensionControl(label: "Padding", value: $appearance.containerPadding, range: 0...20, step: 1)
                DimensionControl(label: "Corner Radius", value: $appearance.cornerRadius, range: 0...20, step: 1)
                DimensionControl(label: "Border Width", value: $appearance.borderWidth, range: 0...4, step: 0.5)

                ColorPicker("Background Color", selection: backgroundColorBinding)
                ColorPicker("Border Color", selection: borderColorBinding)
            }

            Section("Indicator") {
                switch appearance.indicatorStyle {
                case .pill:
                    ColorPicker("Text Color", selection: pillTextColorBinding)

                case .icons:
                    ColorPicker("Focused Dot Color", selection: iconsFocusedColorBinding)
                    OpacityControl(label: "Unfocused Opacity", value: $appearance.iconsSettings.unfocusedOpacity)

                case .minimal:
                    ColorPicker("Focused Color", selection: minimalFocusedColorBinding)
                    ColorPicker("Unfocused Color", selection: minimalUnfocusedColorBinding)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Appearance")
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { appearance.backgroundColor.color },
            set: { newValue in
                DispatchQueue.main.async { appearance.backgroundColor = CodableColor(newValue) }
            }
        )
    }

    private var borderColorBinding: Binding<Color> {
        Binding(
            get: { appearance.borderColor.color },
            set: { newValue in
                DispatchQueue.main.async { appearance.borderColor = CodableColor(newValue) }
            }
        )
    }

    private var pillTextColorBinding: Binding<Color> {
        Binding(
            get: { appearance.pillSettings.textColor.color },
            set: { newValue in
                DispatchQueue.main.async { appearance.pillSettings.textColor = CodableColor(newValue) }
            }
        )
    }

    private var iconsFocusedColorBinding: Binding<Color> {
        Binding(
            get: { appearance.iconsSettings.focusedColor.color },
            set: { newValue in
                DispatchQueue.main.async { appearance.iconsSettings.focusedColor = CodableColor(newValue) }
            }
        )
    }

    private var minimalFocusedColorBinding: Binding<Color> {
        Binding(
            get: { appearance.minimalSettings.focusedColor.color },
            set: { newValue in
                DispatchQueue.main.async { appearance.minimalSettings.focusedColor = CodableColor(newValue) }
            }
        )
    }

    private var minimalUnfocusedColorBinding: Binding<Color> {
        Binding(
            get: { appearance.minimalSettings.unfocusedColor.color },
            set: { newValue in
                DispatchQueue.main.async { appearance.minimalSettings.unfocusedColor = CodableColor(newValue) }
            }
        )
    }
}

// MARK: - Opacity Control

struct OpacityControl: View {
    let label: String
    @Binding var value: CGFloat

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: $value, in: 0...1, step: 0.05)
                    .frame(minWidth: 120)

                Text("\(Int(value * 100))%")
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Positioning Preferences

struct PositioningPreferencesView: View {
    @Binding var positioning: PositioningPreferences
    let appearance: AppearancePreferences
    let stacks: [WindowStack]
    @State private var selectedDisplayIndex: Int = 1
    @State private var selectedStackIndex: Int = 0

    private var displayIndices: [Int] {
        Array(Set(stacks.map(\.displayIndex))).sorted()
    }

    private var stacksForSelectedDisplay: [WindowStack] {
        stacks.filter { $0.displayIndex == selectedDisplayIndex }
    }

    private var screenBoundsForDisplay: CGRect {
        if let stack = stacksForSelectedDisplay.first {
            return CoreGraphicsCoordinateSystem().displayContaining(rect: stack.frame)
                ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        return NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private var currentLayout: LayoutPattern {
        IndicatorPositioner.detectLayout(from: stacksForSelectedDisplay, screenBounds: screenBoundsForDisplay)
    }

    var body: some View {
        Form {
            if displayIndices.count > 1 {
                Section("Display") {
                    Picker("Display", selection: $selectedDisplayIndex) {
                        ForEach(displayIndices, id: \.self) { index in
                            Text("Display \(index)")
                                .tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Layout") {
                CurrentLayoutPreview(
                    stacks: stacksForSelectedDisplay,
                    layout: currentLayout,
                    selectedIndex: $selectedStackIndex,
                    positioning: positioning,
                    screenBounds: screenBoundsForDisplay
                )
                .frame(height: 180)

                if stacksForSelectedDisplay.isEmpty {
                    Text("No stacks on this display")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            if !stacksForSelectedDisplay.isEmpty {
                Section("Stack \(selectedStackIndex + 1) Settings") {
                    StackSettingsEditor(
                        positioning: $positioning,
                        layout: currentLayout,
                        stackIndex: selectedStackIndex
                    )
                }
            }

            Section("Global Offset") {
                OffsetControl(label: "Horizontal", value: $positioning.globalHorizontalOffset)
                OffsetControl(label: "Vertical", value: $positioning.globalVerticalOffset)
                Text("Applies to all indicators. Per-stack adjustments are added to this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global Settings") {
                Toggle("Stick to Screen Edge", isOn: $positioning.stickToScreenEdge)
                Text("Keep indicators within screen bounds")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Indicator for Single Windows", isOn: $positioning.showSingleWindowIndicators)
                Text("When disabled, indicators only appear for stacks with 2+ windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Positioning")
        .onChange(of: displayIndices) { _, newIndices in
            Task { @MainActor in
                if !newIndices.contains(selectedDisplayIndex), let first = newIndices.first {
                    selectedDisplayIndex = first
                }
            }
        }
        .onChange(of: stacksForSelectedDisplay.count) { _, newCount in
            Task { @MainActor in
                if selectedStackIndex >= newCount {
                    selectedStackIndex = max(0, newCount - 1)
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                if let first = displayIndices.first {
                    selectedDisplayIndex = first
                }
            }
        }
    }
}

// MARK: - Current Layout Preview

struct CurrentLayoutPreview: View {
    let stacks: [WindowStack]
    let layout: LayoutPattern
    @Binding var selectedIndex: Int
    let positioning: PositioningPreferences
    let screenBounds: CGRect

    var body: some View {
        GeometryReader { geometry in
            let previewSize = CGSize(
                width: min(geometry.size.width - 20, (geometry.size.height - 20) * 1.6),
                height: min(geometry.size.height - 20, (geometry.size.width - 20) / 1.6)
            )
            let scale = previewSize.width / screenBounds.width

            ZStack {
                // Screen background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .frame(width: previewSize.width, height: previewSize.height)

                // Stack representations
                ForEach(Array(sortedStacks.enumerated()), id: \.element.id) { index, stack in
                    StackPreviewButton(
                        stack: stack,
                        index: index,
                        isSelected: index == selectedIndex,
                        scale: scale,
                        screenBounds: screenBounds
                    ) {
                        withAnimation(.spring(duration: 0.2)) {
                            selectedIndex = index
                        }
                    }
                }

                if stacks.isEmpty {
                    Text("No stacks")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sortedStacks: [WindowStack] {
        let indices = IndicatorPositioner.sortedStackIndices(for: stacks)
        return indices.map { stacks[$0] }
    }
}

struct StackPreviewButton: View {
    let stack: WindowStack
    let index: Int
    let isSelected: Bool
    let scale: CGFloat
    let screenBounds: CGRect
    let action: () -> Void

    private var scaledFrame: CGRect {
        let frame = stack.frame
        // Convert from AppKit (bottom-left origin) to SwiftUI (top-left origin)
        let swiftUIY = screenBounds.height - (frame.minY - screenBounds.minY) - frame.height
        return CGRect(
            x: (frame.minX - screenBounds.minX) * scale,
            y: swiftUIY * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.accentColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? Color.accentColor : Color.accentColor.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )

                Text("\(index + 1)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(width: max(40, scaledFrame.width), height: max(30, scaledFrame.height))
        }
        .buttonStyle(.plain)
        .offset(
            x: scaledFrame.midX - screenBounds.width * scale / 2,
            y: scaledFrame.midY - screenBounds.height * scale / 2
        )
    }
}

// MARK: - Stack Settings Editor

struct StackSettingsEditor: View {
    @Binding var positioning: PositioningPreferences
    let layout: LayoutPattern
    let stackIndex: Int

    private var settings: StackPositionSettings {
        positioning.settings(for: stackIndex, in: layout)
    }

    var body: some View {
        Group {
            Picker("Indicator Corner", selection: cornerBinding) {
                Text("Auto").tag(StackCorner.auto)
                Text("Top Left").tag(StackCorner.topLeft)
                Text("Top Right").tag(StackCorner.topRight)
                Text("Bottom Left").tag(StackCorner.bottomLeft)
                Text("Bottom Right").tag(StackCorner.bottomRight)
            }

            OffsetControl(label: "Horizontal Adjustment", value: horizontalOffsetBinding)
            OffsetControl(label: "Vertical Adjustment", value: verticalOffsetBinding)
        }
    }

    private var cornerBinding: Binding<StackCorner> {
        Binding(
            get: { settings.stackCorner },
            set: { newValue in
                var newSettings = settings
                newSettings.stackCorner = newValue
                positioning.setSettings(newSettings, for: stackIndex, in: layout)
            }
        )
    }

    private var horizontalOffsetBinding: Binding<CGFloat> {
        Binding(
            get: { settings.horizontalOffset },
            set: { newValue in
                var newSettings = settings
                newSettings.horizontalOffset = newValue
                positioning.setSettings(newSettings, for: stackIndex, in: layout)
            }
        )
    }

    private var verticalOffsetBinding: Binding<CGFloat> {
        Binding(
            get: { settings.verticalOffset },
            set: { newValue in
                var newSettings = settings
                newSettings.verticalOffset = newValue
                positioning.setSettings(newSettings, for: stackIndex, in: layout)
            }
        )
    }
}

// MARK: - Advanced Preferences

struct AdvancedPreferencesView: View {
    @ObservedObject var preferences: UserDefaultsPreferences
    @State private var showingResetAlert = false

    var body: some View {
        Form {
            Section("Reset") {
                Button("Reset All Preferences to Defaults") {
                    showingResetAlert = true
                }
                .alert("Reset Preferences", isPresented: $showingResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        preferences.resetToDefaults()
                    }
                } message: {
                    Text("This will reset all preferences to their default values. This action cannot be undone.")
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                }
            }

            Section("Debug") {
                LabeledContent("Config Location") {
                    Text("~/Library/Preferences")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Advanced")
    }
}

// MARK: - Offset Control (Slider + Text Field)

struct OffsetControl: View {
    let label: String
    @Binding var value: CGFloat

    @State private var textValue: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: $value, in: -100...100, step: 1)
                    .frame(minWidth: 120)

                TextField("", text: $textValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .focused($isTextFieldFocused)
                    .onAppear {
                        Task { @MainActor in
                            textValue = formatValue(value)
                        }
                    }
                    .onChange(of: value) { _, newValue in
                        Task { @MainActor in
                            if !isTextFieldFocused {
                                textValue = formatValue(newValue)
                            }
                        }
                    }
                    .onChange(of: isTextFieldFocused) { _, focused in
                        if !focused {
                            applyTextValue()
                        }
                    }
                    .onSubmit {
                        applyTextValue()
                    }

                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatValue(_ val: CGFloat) -> String {
        String(format: "%.0f", val)
    }

    private func applyTextValue() {
        if let parsed = Double(textValue) {
            value = CGFloat(parsed)
        }
        textValue = formatValue(value)
    }
}

// MARK: - Dimension Control (Slider + Text Field for positive values)

struct DimensionControl: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat

    @State private var textValue: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 120)

                TextField("", text: $textValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .focused($isTextFieldFocused)
                    .onAppear {
                        Task { @MainActor in
                            textValue = formatValue(value)
                        }
                    }
                    .onChange(of: value) { _, newValue in
                        Task { @MainActor in
                            if !isTextFieldFocused {
                                textValue = formatValue(newValue)
                            }
                        }
                    }
                    .onChange(of: isTextFieldFocused) { _, focused in
                        if !focused {
                            applyTextValue()
                        }
                    }
                    .onSubmit {
                        applyTextValue()
                    }

                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatValue(_ val: CGFloat) -> String {
        String(format: "%.0f", val)
    }

    private func applyTextValue() {
        if let parsed = Double(textValue) {
            let clamped = min(max(CGFloat(parsed), range.lowerBound), range.upperBound)
            value = clamped
        }
        textValue = formatValue(value)
    }
}
