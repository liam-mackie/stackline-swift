import Foundation
import Combine

public typealias WindowIdentifier = Int

public enum WindowManagerError: Error, Equatable {
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)
    case commandFailed(String)
    case windowNotFound(WindowIdentifier)
    case invalidResponse
}

public enum WindowManagerEvent: Sendable, Equatable {
    case windowFocused(WindowIdentifier)
    case windowMoved(WindowIdentifier)
    case windowResized(WindowIdentifier)
    case windowCreated(WindowIdentifier)
    case windowDestroyed(WindowIdentifier)
    case spaceChanged(Int)
    case displayChanged(Int)
}

public protocol WindowManagerProtocol: Sendable {
    var isConnected: Bool { get async }

    func connect() async throws
    func disconnect() async

    func queryWindows() async throws -> [ManagedWindow]
    func querySpaces() async throws -> [ManagedSpace]
    func queryDisplays() async throws -> [ManagedDisplay]

    func focusWindow(_ windowId: WindowIdentifier) async throws

    func eventStream() -> AsyncStream<WindowManagerEvent>
}
