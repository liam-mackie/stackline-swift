import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "app")

// MARK: - Stackline App

struct StacklineApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        // Main window using Window scene for better control
        Window("Stackline", id: coordinator.mainWindowId) {
            if coordinator.isCheckingSingleton {
                LoadingView()
                    .onAppear {
                        coordinator.checkSingletonStatus()
                    }
            } else if coordinator.isSingletonValid {
                ContentView(coordinator: coordinator)
                    .onAppear {
                        handleMainWindowAppearance()
                        
                        if !coordinator.isAppInitialized {
                            coordinator.initializeApp()
                            // Set up close handler for the initial window if it's shown at launch
                            coordinator.setupInitialWindowIfNeeded()
                        }
                    }
            } else {
                SingletonErrorView()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Show Main Window") {
                    coordinator.openMainWindow()
                }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Stackline") {
                    coordinator.showAboutPanel()
                }
            }
        }
        
        // Menu bar
        MenuBarExtra("Stackline", systemImage: "rectangle.stack") {
            if coordinator.isCheckingSingleton {
                Text("Checking for other instances...")
                    .foregroundColor(.secondary)
            } else if coordinator.isSingletonValid {
                MenuBarView(
                    coordinator: coordinator,
                    onOpenConfig: {
                        coordinator.openConfigurationWindow()
                    },
                    onOpenMain: {
                        coordinator.openMainWindow()
                    }
                )
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
        .menuBarExtraStyle(.menu)
    }
    
    private func handleMainWindowAppearance() {
        if !coordinator.configManager.config.behavior.showMainWindowAtLaunch {
            let windows = NSApplication.shared.windows
            for window in windows {
                if window.styleMask.contains(.titled) && window.contentView != nil {
                    window.alphaValue = 0.0
                    window.orderOut(nil)
                    logger.debug("Hidden main window at launch")
                }
            }
        }
    }
}