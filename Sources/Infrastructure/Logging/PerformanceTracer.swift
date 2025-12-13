import Foundation
import os

/// Performance instrumentation using os_signpost for Instruments.app visualization.
///
/// Usage:
/// 1. Build and run the app
/// 2. Open Instruments.app → Blank template
/// 3. Add "os_signpost" instrument
/// 4. Filter by subsystem "sh.mackie.stackline.performance"
/// 5. Record and trigger window events to see timing data
public final class PerformanceTracer: @unchecked Sendable {
    public static let shared = PerformanceTracer()

    private let signposter: OSSignposter
    private let subsystem = "sh.mackie.stackline.performance"

    public enum Category: String {
        case signalHandling = "Signal Handling"
        case stackDetection = "Stack Detection"
        case yabaiQuery = "Yabai Query"
        case uiUpdate = "UI Update"
    }

    private init() {
        self.signposter = OSSignposter(subsystem: subsystem, category: "Performance")
    }

    /// Begin a traced interval. Call `end(_:)` with the returned state when done.
    public func begin(_ name: StaticString, category: Category) -> OSSignpostIntervalState {
        let id = signposter.makeSignpostID()
        return signposter.beginInterval(name, id: id, "\(category.rawValue)")
    }

    /// End a traced interval.
    public func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// End a traced interval with additional context.
    public func end(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: String) {
        signposter.endInterval(name, state, "\(message)")
    }

    /// Trace a synchronous operation.
    public func trace<T>(_ name: StaticString, category: Category, operation: () throws -> T) rethrows -> T {
        let state = begin(name, category: category)
        defer { end(name, state) }
        return try operation()
    }

    /// Trace an async operation.
    public func trace<T>(_ name: StaticString, category: Category, operation: () async throws -> T) async rethrows -> T {
        let state = begin(name, category: category)
        defer { end(name, state) }
        return try await operation()
    }

    /// Emit a single event point (not an interval).
    public func event(_ name: StaticString, _ message: String = "") {
        signposter.emitEvent(name, "\(message)")
    }
}
