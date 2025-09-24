import SwiftUI
import AppKit

// MARK: - Static Menu Bar View
// This view NEVER updates after initial creation to prevent memory growth

struct StaticMenuBarView: View {
    // We don't observe the coordinator - just pass callbacks
    let onOpenConfig: () -> Void
    let onOpenMain: () -> Void
    let onToggleIndicators: () -> Void
    let onRefreshStacks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stackline")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            // No status display - completely static menu
            Button("Show Main Window") {
                onOpenMain()
            }

            Button("Toggle Indicators") {
                onToggleIndicators()
            }

            Button("Refresh Stacks") {
                onRefreshStacks()
            }

            Button("Configuration...") {
                onOpenConfig()
            }

            Divider()

            Button("Quit Stackline") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(minWidth: 180)
    }
}