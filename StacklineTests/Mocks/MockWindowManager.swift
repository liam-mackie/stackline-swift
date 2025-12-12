import Foundation
@testable import Stackline

/// Mock implementation of WindowManagerProtocol for testing
actor MockWindowManager: WindowManagerProtocol {
    private var _isConnected: Bool = false
    private var _windows: [ManagedWindow] = []
    private var _spaces: [ManagedSpace] = []
    private var _displays: [ManagedDisplay] = []
    private var _eventContinuation: AsyncStream<WindowManagerEvent>.Continuation?

    nonisolated var isConnected: Bool {
        get async {
            await _isConnected
        }
    }

    func setWindows(_ windows: [ManagedWindow]) {
        _windows = windows
    }

    func setSpaces(_ spaces: [ManagedSpace]) {
        _spaces = spaces
    }

    func setDisplays(_ displays: [ManagedDisplay]) {
        _displays = displays
    }

    func connect() async throws {
        _isConnected = true
    }

    func disconnect() async {
        _isConnected = false
        _eventContinuation?.finish()
    }

    func queryWindows() async throws -> [ManagedWindow] {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }
        return _windows
    }

    func querySpaces() async throws -> [ManagedSpace] {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }
        return _spaces
    }

    func queryDisplays() async throws -> [ManagedDisplay] {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }
        return _displays
    }

    func focusWindow(_ windowId: WindowIdentifier) async throws {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }

        guard _windows.contains(where: { $0.id == windowId }) else {
            throw WindowManagerError.windowNotFound(windowId)
        }
    }

    nonisolated func eventStream() -> AsyncStream<WindowManagerEvent> {
        AsyncStream { continuation in
            Task {
                await self.setEventContinuation(continuation)
            }
        }
    }

    private func setEventContinuation(_ continuation: AsyncStream<WindowManagerEvent>.Continuation) {
        _eventContinuation = continuation
    }

    func emitEvent(_ event: WindowManagerEvent) {
        _eventContinuation?.yield(event)
    }
}
