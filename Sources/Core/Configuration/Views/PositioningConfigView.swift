import SwiftUI
import Combine

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