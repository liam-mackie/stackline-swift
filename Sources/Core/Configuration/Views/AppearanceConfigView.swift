import SwiftUI

struct AppearanceConfigView: View {
    @ObservedObject var configManager: ConfigurationManager
    
    // Local state to prevent rapid updates
    @State private var localIconSize: Double = 24
    @State private var localPillWidth: Double = 40
    @State private var localPillHeight: Double = 6
    @State private var localSpacing: Double = 2
    @State private var localMinimalSize: Double = 8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConfigSection("Indicator Style") {
                VStack(spacing: 12) {
                    Picker("Style", selection: Binding(
                        get: { configManager.config.appearance.indicatorStyle },
                        set: { configManager.updateAppearance(\.indicatorStyle, value: $0) }
                    )) {
                        ForEach(IndicatorStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Icon Direction", selection: Binding(
                        get: { configManager.config.appearance.iconDirection },
                        set: { configManager.updateAppearance(\.iconDirection, value: $0) }
                    )) {
                        ForEach(IconDirection.allCases, id: \.self) { direction in
                            Text(direction.displayName).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            
            ConfigSection("Size") {
                VStack(spacing: 8) {
                    // Show relevant size options based on selected style
                    switch configManager.config.appearance.indicatorStyle {
                    case .icons:
                        ConfigSlider(
                            title: "Icon Size",
                            value: $localIconSize,
                            range: 16...48,
                            step: 2,
                            unit: "px"
                        ) { value in
                            configManager.updateAppearance(\.iconSize, value: CGFloat(value))
                        }
                        
                    case .pill:
                        ConfigSlider(
                            title: "Pill Width",
                            value: $localPillWidth,
                            range: 20...80,
                            step: 2,
                            unit: "px"
                        ) { value in
                            configManager.updateAppearance(\.pillWidth, value: CGFloat(value))
                        }
                        
                        ConfigSlider(
                            title: "Pill Height",
                            value: $localPillHeight,
                            range: 4...16,
                            step: 1,
                            unit: "px"
                        ) { value in
                            configManager.updateAppearance(\.pillHeight, value: CGFloat(value))
                        }
                        
                    case .minimal:
                        ConfigSlider(
                            title: "Minimal Size",
                            value: $localMinimalSize,
                            range: 4...16,
                            step: 1,
                            unit: "px"
                        ) { value in
                            configManager.updateAppearance(\.minimalSize, value: CGFloat(value))
                        }
                    }
                    
                    // Spacing is always shown
                    ConfigSlider(
                        title: "Spacing",
                        value: $localSpacing,
                        range: 0...8,
                        step: 1,
                        unit: "px"
                    ) { value in
                        configManager.updateAppearance(\.spacing, value: CGFloat(value))
                    }
                }
            }
            
            ConfigSection("Container") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show Container Background", isOn: Binding(
                        get: { configManager.config.appearance.showContainer },
                        set: { configManager.updateAppearance(\.showContainer, value: $0) }
                    ))
                    
                    Text("Shows a background container around the stack indicators")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Only show Colors section when relevant
            if configManager.config.appearance.indicatorStyle == .minimal || 
               configManager.config.appearance.indicatorStyle == .pill ||
               (configManager.config.appearance.indicatorStyle == .icons && configManager.config.appearance.showContainer) {
                
                ConfigSection("Colors") {
                    VStack(spacing: 8) {
                        ConfigColorPicker(
                            title: "Background",
                            color: Binding(
                                get: { configManager.config.appearance.backgroundColor.color },
                                set: { configManager.updateAppearance(\.backgroundColor, value: CodableColor($0)) }
                            )
                        )
                        
                        // Only show focused/unfocused colors for minimal and pill styles
                        if configManager.config.appearance.indicatorStyle == .minimal || configManager.config.appearance.indicatorStyle == .pill {
                            ConfigColorPicker(
                                title: "Focused Color",
                                color: Binding(
                                    get: { configManager.config.appearance.focusedColor.color },
                                    set: { configManager.updateAppearance(\.focusedColor, value: CodableColor($0)) }
                                )
                            )
                            
                            ConfigColorPicker(
                                title: "Unfocused Color",
                                color: Binding(
                                    get: { configManager.config.appearance.unfocusedColor.color },
                                    set: { configManager.updateAppearance(\.unfocusedColor, value: CodableColor($0)) }
                                )
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            // Initialize local state from config
            localIconSize = Double(configManager.config.appearance.iconSize)
            localPillWidth = Double(configManager.config.appearance.pillWidth)
            localPillHeight = Double(configManager.config.appearance.pillHeight)
            localSpacing = Double(configManager.config.appearance.spacing)
            localMinimalSize = Double(configManager.config.appearance.minimalSize)
        }
    }
}