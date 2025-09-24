import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "app")

// MARK: - Stackline App

struct StacklineApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        // Initialize coordinator immediately on app launch
        // This ensures services start right away without waiting for menu interaction
        logger.info("Stackline app initializing")
    }

    var body: some Scene {
        // Main window using Window scene to prevent NSHostingView recreation leaks
        Window("Stackline", id: "main") {
            ContentView(coordinator: coordinator)
                .onAppear {
                    if !coordinator.isAppInitialized {
                        coordinator.initializeApp()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 600)

        // Configuration window as separate WindowGroup
        WindowGroup("Configuration", id: "config") {
            ConfigurationView(configManager: coordinator.configManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 450, height: 400)

        // MenuBarExtra as primary interface
        MenuBarExtra("Stackline", systemImage: "rectangle.stack") {
            MenuView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}