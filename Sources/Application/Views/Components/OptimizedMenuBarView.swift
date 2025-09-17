import SwiftUI
import AppKit

// MARK: - Optimized Menu Bar View
// This view minimizes updates to prevent memory growth from menu tracking sessions

struct OptimizedMenuBarView: View {
    // Use unowned to avoid retain cycles
    @ObservedObject var coordinator: AppCoordinator

    let onOpenConfig: () -> Void
    let onOpenMain: () -> Void

    // Cache computed values to reduce recalculations
    @State private var cachedStackCount: Int = 0
    @State private var cachedSignalCount: Int = 0
    @State private var cachedIndicatorState: Bool = false
    @State private var cachedSignalState: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stackline")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            // Static status display that updates less frequently
            statusSection

            Divider()

            // Action buttons that don't observe state
            actionButtons

            Divider()

            Button("Quit Stackline") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(minWidth: 200)
        .onAppear {
            updateCachedValues()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            updateCachedValues()
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            MenuBarStatusRow(
                title: "Stacks:",
                value: "\(cachedStackCount)",
                color: .secondary
            )
            MenuBarStatusRow(
                title: "Indicators:",
                value: cachedIndicatorState ? "Enabled" : "Disabled",
                color: cachedIndicatorState ? .green : .red
            )
            MenuBarStatusRow(
                title: "Signal Manager:",
                value: cachedSignalState ? "Running" : "Stopped",
                color: cachedSignalState ? .green : .red
            )
            MenuBarStatusRow(
                title: "Signal Count:",
                value: "\(cachedSignalCount)",
                color: .secondary
            )
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Group {
            Button("Show Main Window") {
                onOpenMain()
            }

            Button(action: {
                coordinator.indicatorManager.toggle()
                updateCachedValues()
            }) {
                HStack {
                    Image(systemName: cachedIndicatorState ? "eye.slash" : "eye")
                    Text(cachedIndicatorState ? "Hide Indicators" : "Show Indicators")
                }
            }

            Button("Refresh Stacks") {
                coordinator.stackDetector.forceStackDetection()
                updateCachedValues()
            }

            Button("Configuration...") {
                onOpenConfig()
            }
        }
    }

    private func updateCachedValues() {
        // Update cached values to reduce property access
        cachedStackCount = coordinator.stackDetector.detectedStacks.count
        cachedSignalCount = coordinator.signalManager.signalCount
        cachedIndicatorState = coordinator.indicatorManager.isEnabled
        cachedSignalState = coordinator.signalManager.isRunning
    }
}

// Reuse the existing status row view
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