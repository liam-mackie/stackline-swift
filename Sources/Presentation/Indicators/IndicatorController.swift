import AppKit

/// Renders the stacks in the store as indicator windows, one per stack.
///
/// Rendering is a pure function of the store and the preferences: whenever either changes, the
/// windows are diffed against the desired set. Nothing else creates, moves or closes them.
@MainActor
final class IndicatorController {
    private let store: StackStore
    private let preferences: Preferences

    private var windows: [WindowStack.ID: IndicatorWindow] = [:]
    private var observation: ObservationLoop?
    private var screenObserver: (any NSObjectProtocol)?

    init(store: StackStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
    }

    func start() {
        guard observation == nil else { return }

        observation = ObservationLoop { [weak self] in self?.render() }

        // AppKit relocates windows by itself when displays change, which the model knows nothing
        // about, so put them back where they belong.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// Closes every indicator and stops reacting to changes.
    func stop() {
        observation?.cancel()
        observation = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil

        for window in windows.values {
            window.close()
        }
        windows.removeAll()
    }

    private func render() {
        let interval = Log.signposter.beginInterval("Render")
        defer { Log.signposter.endInterval("Render", interval) }

        let appearance = preferences.appearance
        let positioning = preferences.positioning
        let behavior = preferences.behavior
        let stacks = store.stacks

        AppIconCache.shared.prune(keeping: Set(stacks.lazy.flatMap(\.windows).map(\.processId)))

        let indicated = behavior.showByDefault
            ? stacks.filter { $0.count > 1 || positioning.showSingleWindowIndicators }
            : []
        let onWindowClick: ((WindowIdentifier) -> Void)? = behavior.clickToFocus
            ? { [store] in store.focus($0) }
            : nil

        var unclaimed = windows
        windows.removeAll(keepingCapacity: true)

        for stack in indicated where windows[stack.id] == nil {
            let frame = IndicatorPositioner.frame(for: stack, among: stacks, appearance: appearance, positioning: positioning)
            let view = IndicatorView(
                stack: stack,
                style: appearance.indicatorStyle,
                appearance: appearance,
                onWindowClick: onWindowClick
            )

            if let window = unclaimed.removeValue(forKey: stack.id) {
                window.update(view: view, frame: frame, clickable: behavior.clickToFocus)
                windows[stack.id] = window
            } else {
                let window = IndicatorWindow(view: view, frame: frame, clickable: behavior.clickToFocus)
                window.orderFront(nil)
                windows[stack.id] = window
            }
        }

        for window in unclaimed.values {
            window.close()
        }
    }
}
