import SwiftUI

// MARK: - Menu View (Idiomatic SwiftUI Pattern)

struct MenuView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.isCheckingSingleton {
                Text("Checking for other instances...")
                    .foregroundColor(.secondary)
                    .onAppear {
                        coordinator.checkSingletonStatus()
                    }
            } else if coordinator.isSingletonValid {
                // Main menu content
                Group {
                    Text("Stackline")
                        .font(.headline)
                        .padding(.bottom, 4)

                    Divider()

                    Button("Show Main Window") {
                        openWindow(id: "main")
                        // Show dock icon when opening window
                        NSApplication.shared.setActivationPolicy(.regular)
                    }

                    Button("Toggle Indicators") {
                        coordinator.indicatorManager.toggle()
                    }

                    Button("Refresh Stacks") {
                        coordinator.stackDetector.forceStackDetection()
                    }

                    Button("Configuration...") {
                        openWindow(id: "config")
                    }

                    Divider()

                    Button("Quit Stackline") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } else {
                VStack {
                    Text("Another instance is running")
                        .foregroundColor(.secondary)

                    Button("Close This Instance") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 180)
    }
}