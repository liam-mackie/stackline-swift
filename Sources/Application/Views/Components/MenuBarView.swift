import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    let onOpenConfig: () -> Void
    let onOpenMain: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stackline")
                .font(.headline)
                .padding(.bottom, 4)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 3) {
                MenuBarStatusRow(title: "Stacks:", value: "\(coordinator.stackDetector.detectedStacks.count)", color: .secondary)
                MenuBarStatusRow(title: "Indicators:", value: coordinator.indicatorManager.isEnabled ? "Enabled" : "Disabled", color: coordinator.indicatorManager.isEnabled ? .green : .red)
                MenuBarStatusRow(title: "Signal Manager:", value: coordinator.signalManager.isRunning ? "Running" : "Stopped", color: coordinator.signalManager.isRunning ? .green : .red)
                MenuBarStatusRow(title: "Signal Count:", value: "\(coordinator.signalManager.signalCount)", color: .secondary)
            }
            
            Divider()
            
            Button("Show Main Window") {
                onOpenMain()
            }
            
            Button(action: {
                coordinator.indicatorManager.toggle()
            }) {
                HStack {
                    Image(systemName: coordinator.indicatorManager.isEnabled ? "eye.slash" : "eye")
                    Text(coordinator.indicatorManager.isEnabled ? "Hide Indicators" : "Show Indicators")
                }
            }
            
            Button("Refresh Stacks") {
                coordinator.stackDetector.forceStackDetection()
            }
            
            Button("Configuration...") {
                onOpenConfig()
            }
            
            Divider()
            
            Button("Quit Stackline") {
                NSApplication.shared.terminate(NSApp)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

private struct MenuBarStatusRow: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(color)
        }
    }
}