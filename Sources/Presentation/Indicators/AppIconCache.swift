import AppKit

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var cache: [Int: NSImage] = [:]

    private init() {}

    func icon(for processId: Int) async -> NSImage? {
        if let cached = cache[processId] {
            return cached
        }
        let icon = loadIcon(for: processId)
        if let icon = icon {
            cache[processId] = icon
        }
        return icon
    }

    private func loadIcon(for processId: Int) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: pid_t(processId)) else {
            return nil
        }
        return app.icon
    }

    func invalidate(processId: Int) {
        cache.removeValue(forKey: processId)
    }

    func invalidateAll() {
        cache.removeAll()
    }
}
