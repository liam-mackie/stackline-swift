import os

/// Unified-logging categories for Stackline.
///
/// Stream them with:
///
///     log stream --level debug --predicate 'subsystem == "sh.mackie.stackline"'
enum Log {
    private static let subsystem = "sh.mackie.stackline"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let windowManager = Logger(subsystem: subsystem, category: "window-manager")
    static let stacks = Logger(subsystem: subsystem, category: "stack-detection")
    static let indicators = Logger(subsystem: subsystem, category: "indicators")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")

    /// Intervals for the os_signpost instrument in Instruments
    /// (filter by subsystem `sh.mackie.stackline.performance`).
    static let signposter = OSSignposter(subsystem: "\(subsystem).performance", category: "Performance")
}
