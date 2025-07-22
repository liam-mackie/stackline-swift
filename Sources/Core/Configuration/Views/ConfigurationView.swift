import SwiftUI

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
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color(NSColor.selectedControlColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}