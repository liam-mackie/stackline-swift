import SwiftUI

struct ControlsView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {
                    coordinator.indicatorManager.toggle()
                }) {
                    HStack {
                        Image(systemName: coordinator.indicatorManager.isEnabled ? "eye.slash" : "eye")
                        Text(coordinator.indicatorManager.isEnabled ? "Hide Indicators" : "Show Indicators")
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Refresh Stacks") {
                    coordinator.stackDetector.forceStackDetection()
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                Button("Setup Yabai Signals") {
                    coordinator.signalListener.setupSignalsManually()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
    }
}