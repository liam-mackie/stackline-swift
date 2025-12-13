import AppKit
import SwiftUI

/// Manages the menu bar status item and dropdown menu
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let container: DependencyContainer

    init(container: DependencyContainer) {
        self.container = container
        super.init()
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Stackline")
            button.image?.isTemplate = true
        }

        statusItem?.menu = createMenu()
    }

    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: "Stackline", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(
            title: "Show Indicators",
            action: #selector(toggleIndicators),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = container.preferences.behavior.showByDefault ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Stackline",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleIndicators(_ sender: NSMenuItem) {
        var behavior = container.preferences.behavior
        behavior.showByDefault.toggle()
        container.preferences.behavior = behavior

        sender.state = behavior.showByDefault ? .on : .off
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openPreferences, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let openPreferences = Notification.Name("sh.mackie.stackline.openPreferences")
}
