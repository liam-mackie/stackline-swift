import SwiftUI

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