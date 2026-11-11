import AppKit

/// Application icons by process ID.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var icons: [Int: NSImage] = [:]

    private init() {}

    func icon(for processId: Int) -> NSImage? {
        if let icon = icons[processId] {
            return icon
        }
        guard let icon = NSRunningApplication(processIdentifier: pid_t(processId))?.icon else {
            return nil
        }
        icons[processId] = icon
        return icon
    }

    /// Forgets every icon except those of `processIds`. Process IDs are reused, so an icon must
    /// not outlive the process it was loaded for.
    func prune(keeping processIds: Set<Int>) {
        icons = icons.filter { processIds.contains($0.key) }
    }
}
