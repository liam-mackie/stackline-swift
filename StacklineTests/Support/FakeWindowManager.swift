import Foundation
import Synchronization
@testable import Stackline

/// A scriptable window manager for exercising the store.
final class FakeWindowManager: WindowManager {
    let events: AsyncStream<WindowManagerEvent>
    private let continuation: AsyncStream<WindowManagerEvent>.Continuation

    private struct State {
        var windows: [ManagedWindow] = []
        var failure: WindowManagerError?
        var queryCount = 0
        var focused: [WindowIdentifier] = []
        var isHoldingQueries = false
        var heldQueries: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func send(_ event: WindowManagerEvent) {
        continuation.yield(event)
    }

    func setWindows(_ windows: [ManagedWindow]) {
        state.withLock { $0.windows = windows }
    }

    /// Makes window queries fail with `failure`, or succeed again when nil.
    func setFailure(_ failure: WindowManagerError?) {
        state.withLock { $0.failure = failure }
    }

    /// The number of window queries started so far.
    var queryCount: Int {
        state.withLock { $0.queryCount }
    }

    var focusRequests: [WindowIdentifier] {
        state.withLock { $0.focused }
    }

    /// Makes window queries block until `releaseQueries()`.
    func holdQueries() {
        state.withLock { $0.isHoldingQueries = true }
    }

    func releaseQueries() {
        let held = state.withLock { state in
            state.isHoldingQueries = false
            defer { state.heldQueries = [] }
            return state.heldQueries
        }
        held.forEach { $0.resume() }
    }

    // MARK: - WindowManager

    func windows(on displays: DisplayGeometry) async throws -> [ManagedWindow] {
        await withCheckedContinuation { continuation in
            let proceed = state.withLock { state in
                state.queryCount += 1
                guard state.isHoldingQueries else { return true }
                state.heldQueries.append(continuation)
                return false
            }
            if proceed { continuation.resume() }
        }

        return try state.withLock { state in
            if let failure = state.failure { throw failure }
            return state.windows
        }
    }

    func focus(_ window: WindowIdentifier) async throws {
        state.withLock { $0.focused.append(window) }
    }
}
