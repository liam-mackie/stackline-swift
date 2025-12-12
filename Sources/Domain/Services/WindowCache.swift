import Foundation

/// Thread-safe cache for window state that supports optimistic updates
actor WindowCache {
    private var windows: [WindowIdentifier: ManagedWindow] = [:]
    private var lastFullRefresh: Date = .distantPast
    private var isDirty: Bool = false

    func populate(with windowList: [ManagedWindow]) {
        windows = Dictionary(uniqueKeysWithValues: windowList.map { ($0.id, $0) })
        lastFullRefresh = Date()
        isDirty = false
    }

    func allWindows() -> [ManagedWindow] {
        Array(windows.values)
    }

    func window(for id: WindowIdentifier) -> ManagedWindow? {
        windows[id]
    }

    func updateFocused(windowId: WindowIdentifier) {
        for (id, window) in windows where window.isFocused && id != windowId {
            windows[id] = window.with(isFocused: false)
        }

        if let window = windows[windowId] {
            windows[windowId] = window.with(isFocused: true)
        }
    }

    func remove(windowId: WindowIdentifier) {
        windows.removeValue(forKey: windowId)
    }

    func markDirty() {
        isDirty = true
    }

    func needsRefresh(maxAge: TimeInterval = 30) -> Bool {
        isDirty || Date().timeIntervalSince(lastFullRefresh) > maxAge
    }

    var isEmpty: Bool {
        windows.isEmpty
    }

    var count: Int {
        windows.count
    }
}
