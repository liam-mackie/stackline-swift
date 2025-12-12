import Foundation
import CoreGraphics

/// Yabai implementation of WindowManagerProtocol
actor YabaiWindowManager: WindowManagerProtocol {
    private let executor: YabaiCommandExecuting
    private let signalManager: YabaiSignalManager
    private let eventListener: YabaiEventListener
    private let tracer = PerformanceTracer.shared
    private var _isConnected: Bool = false

    nonisolated var isConnected: Bool {
        get async {
            await _isConnected
        }
    }

    init(
        executor: YabaiCommandExecuting? = nil,
        signalManager: YabaiSignalManager? = nil,
        eventListener: YabaiEventListener? = nil
    ) {
        let exec = executor ?? YabaiCommandExecutor()
        self.executor = exec
        self.signalManager = signalManager ?? YabaiSignalManager(executor: exec)
        self.eventListener = eventListener ?? YabaiEventListener()
    }

    func connect() async throws {
        guard await executor.isAvailable() else {
            throw WindowManagerError.connectionFailed("Yabai is not running or not found")
        }

        do {
            try await signalManager.registerSignals()
        } catch {
            throw WindowManagerError.connectionFailed("Failed to register signals: \(error.localizedDescription)")
        }

        _isConnected = true
    }

    func disconnect() async {
        await signalManager.unregisterSignals()
        eventListener.stopListening()
        _isConnected = false
    }

    func queryWindows() async throws -> [ManagedWindow] {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }

        let state = tracer.begin("QueryWindows", category: .yabaiQuery)
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let yabaiWindows: [YabaiWindow] = try await executor.query(["-m", "query", "--windows"])
        let result = yabaiWindows.map { $0.toManagedWindow(screenHeight: screenHeight) }
        tracer.end("QueryWindows", state, "count=\(result.count)")
        return result
    }

    func querySpaces() async throws -> [ManagedSpace] {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }

        let state = tracer.begin("QuerySpaces", category: .yabaiQuery)
        let yabaiSpaces: [YabaiSpace] = try await executor.query(["-m", "query", "--spaces"])
        let result = yabaiSpaces.map { $0.toManagedSpace() }
        tracer.end("QuerySpaces", state, "count=\(result.count)")
        return result
    }

    func queryDisplays() async throws -> [ManagedDisplay] {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }

        let state = tracer.begin("QueryDisplays", category: .yabaiQuery)
        let screenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let yabaiDisplays: [YabaiDisplay] = try await executor.query(["-m", "query", "--displays"])
        let result = yabaiDisplays.map { $0.toManagedDisplay(screenHeight: screenHeight) }
        tracer.end("QueryDisplays", state, "count=\(result.count)")
        return result
    }

    func focusWindow(_ windowId: WindowIdentifier) async throws {
        guard _isConnected else {
            throw WindowManagerError.notConnected
        }

        do {
            try await executor.execute(["-m", "window", "--focus", "\(windowId)"])
        } catch let error as YabaiExecutorError {
            switch error {
            case .executionFailed(let message) where message.contains("could not locate"):
                throw WindowManagerError.windowNotFound(windowId)
            default:
                throw WindowManagerError.commandFailed("Focus failed: \(error)")
            }
        }
    }

    nonisolated func eventStream() -> AsyncStream<WindowManagerEvent> {
        eventListener.startListening()
    }
}
