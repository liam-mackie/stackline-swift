import AppKit

/// The menu bar status item and its menu.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let preferences: Preferences
    private let store: StackStore
    private let showPreferences: () -> Void

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let connectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let indicatorsItem = NSMenuItem(title: "Show Indicators", action: #selector(toggleIndicators), keyEquivalent: "")
    private var observation: ObservationLoop?

    init(preferences: Preferences, store: StackStore, showPreferences: @escaping () -> Void) {
        self.preferences = preferences
        self.store = store
        self.showPreferences = showPreferences
        super.init()

        let image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Stackline")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.menu = makeMenu()

        // The icon is dimmed while there is no window manager to show stacks for.
        observation = ObservationLoop { [weak self] in
            guard let self else { return }
            statusItem.button?.appearsDisabled = store.connection != .connected
        }
    }

    func remove() {
        observation?.cancel()
        observation = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        connectionItem.title = switch store.connection {
        case .connected: "Connected to yabai"
        case .waiting: "Waiting for yabai…"
        }
        indicatorsItem.state = preferences.behavior.showByDefault ? .on : .off
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        connectionItem.isEnabled = false
        menu.addItem(connectionItem)
        menu.addItem(.separator())

        indicatorsItem.target = self
        menu.addItem(indicatorsItem)
        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Stackline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func toggleIndicators() {
        preferences.behavior.showByDefault.toggle()
    }

    @objc private func openPreferences() {
        showPreferences()
    }
}
