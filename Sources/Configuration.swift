import SwiftUI
import Foundation
import Combine
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "configuration")

// MARK: - Configuration Models

struct StacklineConfiguration: Codable, Equatable {
    var appearance: AppearanceConfig = AppearanceConfig()
    var positioning: PositioningConfig = PositioningConfig()
    var behavior: BehaviorConfig = BehaviorConfig()
    
    static let `default` = StacklineConfiguration()
}

struct AppearanceConfig: Codable, Equatable {
    var indicatorStyle: IndicatorStyle = .pill
    var iconDirection: IconDirection = .vertical
    var iconSize: CGFloat = 24
    var pillHeight: CGFloat = 6
    var pillWidth: CGFloat = 40
    var minimalSize: CGFloat = 8
    var cornerRadius: CGFloat = 3
    var backgroundColor: CodableColor = CodableColor(.black.opacity(0.7))
    var borderColor: CodableColor = CodableColor(.white.opacity(0.3))
    var focusedColor: CodableColor = CodableColor(.white)
    var unfocusedColor: CodableColor = CodableColor(.gray.opacity(0.7))
    var borderWidth: CGFloat = 1
    var spacing: CGFloat = 2
    var showContainer: Bool = true
}

struct PositioningConfig: Codable, Equatable {
    var stackCorner: StackCornerPosition = .auto
    var edgeOffset: CGFloat = 0
    var cornerOffset: CGFloat = 0
    var stickToScreenEdge: Bool = true
}

struct BehaviorConfig: Codable, Equatable {
    var showByDefault: Bool = true
    var hideWhenNoStacks: Bool = false
    var clickToFocus: Bool = true
    var showOnAllSpaces: Bool = true
    var launchAtStartup: Bool = false
    var showMainWindowAtLaunch: Bool = true
}

enum IndicatorStyle: String, Codable, CaseIterable {
    case pill = "pill"
    case icons = "icons"
    case minimal = "minimal"
    
    var displayName: String {
        switch self {
        case .pill: return "Pill"
        case .icons: return "App Icons"
        case .minimal: return "Minimal"
        }
    }
}

enum IconDirection: String, Codable, CaseIterable {
    case horizontal = "horizontal"
    case vertical = "vertical"
    
    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

enum StackCornerPosition: String, Codable, CaseIterable {
    case auto = "auto"
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto (Smart)"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

// MARK: - Codable Color Support

struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    init(_ color: Color) {
        // Convert SwiftUI Color to RGBA components
        let nsColor = NSColor(color)
        
        // For dynamic colors, try to get the appropriate resolved color
        let resolvedColor: NSColor
        if #available(macOS 10.15, *) {
            // Try to resolve the color for the current appearance
            resolvedColor = nsColor.usingColorSpace(.sRGB) ?? NSColor.black
        } else {
            resolvedColor = nsColor
        }
        
        // Use a more robust method to get color components
        if let ciColor = CIColor(color: resolvedColor) {
            self.red = Double(ciColor.red)
            self.green = Double(ciColor.green)
            self.blue = Double(ciColor.blue)
            self.alpha = Double(ciColor.alpha)
        } else {
            // Fallback to default black color if CIColor conversion fails
            logger.warning("Could not convert color to CIColor, using default black")
            self.red = 0.0
            self.green = 0.0
            self.blue = 0.0
            self.alpha = 1.0
        }
    }
    
    var color: Color {
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Configuration Manager

@MainActor
class ConfigurationManager: ObservableObject {
    @Published var config: StacklineConfiguration
    
    private let configURL: URL
    
    init() {
        // Set up configuration file path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stacklineDir = appSupport.appendingPathComponent("Stackline")
        
        do {
            try FileManager.default.createDirectory(at: stacklineDir, withIntermediateDirectories: true)
            logger.debug("Configuration directory created/verified at: \(stacklineDir.path)")
        } catch {
            logger.error("Failed to create configuration directory: \(error.localizedDescription)")
        }
        
        configURL = stacklineDir.appendingPathComponent("config.json")
        
        // Load existing configuration or use default
        self.config = Self.loadConfiguration(from: configURL) ?? .default
        logger.info("Configuration manager initialized with config at: \(self.configURL.path)")
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            logger.debug("Configuration saved to \(self.configURL.path)")
        } catch {
            logger.error("Failed to save configuration: \(error.localizedDescription)")
        }
    }
    
    func reset() {
        config = .default
        save()
        logger.info("Configuration reset to defaults")
    }
    
    private static func loadConfiguration(from url: URL) -> StacklineConfiguration? {
        guard let data = try? Data(contentsOf: url) else { 
            logger.debug("No existing configuration file found")
            return nil 
        }
        
        do {
            let config = try JSONDecoder().decode(StacklineConfiguration.self, from: data)
            logger.info("Successfully loaded configuration from file")
            return config
        } catch {
            logger.error("Failed to load configuration: \(error.localizedDescription)")
            logger.info("Resetting configuration to defaults...")
            
            // Try to remove the corrupted configuration file
            do {
                try FileManager.default.removeItem(at: url)
                logger.debug("Removed corrupted configuration file")
            } catch {
                logger.warning("Could not remove corrupted configuration file: \(error.localizedDescription)")
            }
            
            return nil
        }
    }
    
    // MARK: - Convenience Methods
    
    func updateAppearance<T>(_ keyPath: WritableKeyPath<AppearanceConfig, T>, value: T) {
        config.appearance[keyPath: keyPath] = value
        save()
    }
    
    func updatePositioning<T>(_ keyPath: WritableKeyPath<PositioningConfig, T>, value: T) {
        config.positioning[keyPath: keyPath] = value
        save()
    }
    
    func updateBehavior<T>(_ keyPath: WritableKeyPath<BehaviorConfig, T>, value: T) {
        config.behavior[keyPath: keyPath] = value
        save()
    }
}

// MARK: - Configuration Views

struct ConfigurationView: View {
    @ObservedObject var configManager: ConfigurationManager
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Top tab bar
            HStack(spacing: 0) {
                TabButton(
                    title: "Appearance",
                    icon: "paintbrush",
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }
                
                TabButton(
                    title: "Positioning",
                    icon: "move.3d",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }
                
                TabButton(
                    title: "Behavior",
                    icon: "gear",
                    isSelected: selectedTab == 2
                ) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content area
            ScrollView {
                Group {
                    switch selectedTab {
                    case 0:
                        AppearanceConfigView(configManager: configManager)
                    case 1:
                        PositioningConfigView(configManager: configManager)
                    case 2:
                        BehaviorConfigView(configManager: configManager)
                    default:
                        AppearanceConfigView(configManager: configManager)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Bottom section with reset button
            Divider()
            
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    configManager.reset()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle()) // Make entire area clickable
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(NSColor.selectedControlColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

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

struct PositioningConfigView: View {
    @ObservedObject var configManager: ConfigurationManager
    
    // Local state to prevent rapid updates
    @State private var localEdgeOffset: Double = 0
    @State private var localCornerOffset: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConfigSection("Position") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Stack Corner", selection: Binding(
                        get: { configManager.config.positioning.stackCorner },
                        set: { configManager.updatePositioning(\.stackCorner, value: $0) }
                    )) {
                        ForEach(StackCornerPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    
                    if configManager.config.positioning.stackCorner == .auto {
                        Text("Auto chooses the corner closest to a screen edge and positions the stackline to extend towards that edge")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Stackline will overlap with the \(configManager.config.positioning.stackCorner.displayName.lowercased()) corner of each stack")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            ConfigSection("Offsets") {
                VStack(spacing: 8) {
                    ConfigSlider(
                        title: "Edge Offset",
                        value: $localEdgeOffset,
                        range: 0...100,
                        step: 5,
                        unit: "px"
                    ) { value in
                        configManager.updatePositioning(\.edgeOffset, value: CGFloat(value))
                    }
                    
                    Text("Distance the stackline extends away from the stack (0 = overlapping)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ConfigSlider(
                        title: "Corner Offset",
                        value: $localCornerOffset,
                        range: -50...50,
                        step: 5,
                        unit: "px"
                    ) { value in
                        configManager.updatePositioning(\.cornerOffset, value: CGFloat(value))
                    }
                    
                    Text("Vertical adjustment from the corner (positive = down, negative = up)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ConfigSection("Options") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Stick to Screen Edge", isOn: Binding(
                        get: { configManager.config.positioning.stickToScreenEdge },
                        set: { configManager.updatePositioning(\.stickToScreenEdge, value: $0) }
                    ))
                    
                    Text("Prevents indicators from extending beyond screen boundaries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            // Initialize local state from config
            localEdgeOffset = Double(configManager.config.positioning.edgeOffset)
            localCornerOffset = Double(configManager.config.positioning.cornerOffset)
        }
        .onReceive(configManager.$config) { newConfig in
            // Update local state when configuration changes
            localEdgeOffset = Double(newConfig.positioning.edgeOffset)
            localCornerOffset = Double(newConfig.positioning.cornerOffset)
        }
    }
}

struct BehaviorConfigView: View {
    @ObservedObject var configManager: ConfigurationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConfigSection("Interaction") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Click to Focus", isOn: Binding(
                        get: { configManager.config.behavior.clickToFocus },
                        set: { configManager.updateBehavior(\.clickToFocus, value: $0) }
                    ))
                }
            }
            
            ConfigSection("Startup") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at Startup", isOn: Binding(
                        get: { configManager.config.behavior.launchAtStartup },
                        set: { configManager.updateLaunchAtStartup($0) }
                    ))
                    
                    Text("Automatically start Stackline when you log in")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Show Main Window at Launch", isOn: Binding(
                        get: { configManager.config.behavior.showMainWindowAtLaunch },
                        set: { configManager.updateBehavior(\.showMainWindowAtLaunch, value: $0) }
                    ))
                    
                    Text("When disabled, Stackline will start as a menu bar-only app")
                        .font(.caption)
                        .foregroundColor(.secondary)

                }
            }
        }
    }
}

// MARK: - Helper Components

struct ConfigSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
        }
    }
}

struct ConfigSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let formatter: ((Double) -> Int)?
    let onEditingChanged: (Double) -> Void
    
    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        formatter: ((Double) -> Int)? = nil,
        onEditingChanged: @escaping (Double) -> Void
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.formatter = formatter
        self.onEditingChanged = onEditingChanged
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            
            Spacer()
            
            Slider(value: $value, in: range, step: step) { editing in
                if !editing {
                    onEditingChanged(value)
                }
            }
            
            Text(formattedValue)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
    
    private var formattedValue: String {
        if let formatter = formatter {
            return "\(formatter(value))\(unit)"
        } else {
            // Check if the value is effectively a whole number
            if abs(value - value.rounded()) < 0.01 {
                return "\(Int(value.rounded()))\(unit)"
            } else {
                return String(format: "%.1f\(unit)", value)
            }
        }
    }
}

struct ConfigColorPicker: View {
    let title: String
    @Binding var color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            
            Spacer()
            
            ColorPicker("", selection: $color)
                .labelsHidden()
                .frame(width: 40, height: 30)
        }
    }
}

// MARK: - Launch Agent Management

extension ConfigurationManager {
    private var launchAgentURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let launchAgentsURL = libraryURL.appendingPathComponent("LaunchAgents")
        return launchAgentsURL.appendingPathComponent("sh.mackie.stackline.plist")
    }
    
    private var currentExecutablePath: String {
        // Check if we're in an app bundle
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            // If we're in an app bundle, use the app bundle path
            return bundlePath
        } else if let executablePath = Bundle.main.executablePath {
            // If we're a standalone executable, use that path
            return executablePath
        } else {
            // Fallback to command line argument
            return CommandLine.arguments.first ?? "/usr/local/bin/stackline"
        }
    }
    
    func updateLaunchAtStartup(_ enabled: Bool) {
        config.behavior.launchAtStartup = enabled
        save()
        
        if enabled {
            createLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }
    
    private func createLaunchAgent() {
        do {
            // Ensure LaunchAgents directory exists
            let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            
            // Create the plist content
            let plistContent = createLaunchAgentPlist()
            
            // Write the plist file
            try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            logger.info("Created LaunchAgent at: \(self.launchAgentURL.path)")
            
            // Load the launch agent
            loadLaunchAgent()
            
        } catch {
            logger.error("Failed to create LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    private func removeLaunchAgent() {
        do {
            // Unload the launch agent first
            unloadLaunchAgent()
            
            // Remove the plist file
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
                logger.info("Removed LaunchAgent from: \(self.launchAgentURL.path)")
            }
        } catch {
            logger.error("Failed to remove LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    private func createLaunchAgentPlist() -> String {
        let executablePath = currentExecutablePath
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>sh.mackie.stackline</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>LimitLoadToSessionType</key>
            <array>
                <string>Aqua</string>
            </array>
        </dict>
        </plist>
        """
    }
    
    private func loadLaunchAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", launchAgentURL.path]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logger.info("Successfully loaded LaunchAgent")
            } else {
                logger.warning("Failed to load LaunchAgent with launchctl")
            }
        } catch {
            logger.error("Error loading LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    private func unloadLaunchAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", launchAgentURL.path]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logger.debug("Successfully unloaded LaunchAgent")
            } else {
                logger.debug("LaunchAgent was not loaded (this is normal)")
            }
        } catch {
            logger.error("Error unloading LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    func checkLaunchAgentStatus() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    func syncLaunchAgentStatus() {
        let exists = checkLaunchAgentStatus()
        if config.behavior.launchAtStartup != exists {
            logger.info("Syncing launch agent status: config=\(self.config.behavior.launchAtStartup), exists=\(exists)")
            config.behavior.launchAtStartup = exists
            save()
        }
    }
} 
