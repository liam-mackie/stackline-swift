import SwiftUI

struct StatusView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                StatusBadge(
                    title: "Yabai Status",
                    status: coordinator.yabaiInterface.isConnected ? "Connected" : "Disconnected",
                    color: coordinator.yabaiInterface.isConnected ? .green : .red
                )
                
                StatusBadge(
                    title: "Signal Manager",
                    status: coordinator.signalManager.isRunning ? "Running" : "Stopped",
                    color: coordinator.signalManager.isRunning ? .green : .red
                )
            }
            
            GridRow {
                StatusBadge(
                    title: "Signal Listener",
                    status: coordinator.signalListener.isListening ? "Listening" : "Inactive",
                    color: coordinator.signalListener.isListening ? .green : .gray
                )
                
                StatusBadge(
                    title: "Signal Count",
                    status: "\(coordinator.signalManager.signalCount)",
                    color: .blue
                )
            }
            
            GridRow {
                StatusBadge(
                    title: "Stacks",
                    status: "\(coordinator.stackDetector.detectedStacks.count)",
                    color: .blue
                )
                
                StatusBadge(
                    title: "Indicators",
                    status: coordinator.indicatorManager.isEnabled ? "Enabled" : "Disabled",
                    color: coordinator.indicatorManager.isEnabled ? .green : .gray
                )
            }
        }
        .padding()
    }
}