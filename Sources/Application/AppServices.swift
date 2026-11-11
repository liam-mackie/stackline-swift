import Foundation

/// The composition root: builds the object graph and owns its lifetime.
@MainActor
final class AppServices {
    let preferences: Preferences
    let store: StackStore

    private let instanceLock: InstanceLock
    private let windowManager: YabaiWindowManager
    private let indicators: IndicatorController
    private var connection: Task<Void, Never>?
    private var modelUpdates: Task<Void, Never>?

    /// - Throws: `InstanceLock.Failure.alreadyHeld` if Stackline is already running for this
    ///   user; any other error means the app cannot work at all.
    init() throws {
        let directory = try Self.stateDirectory()
        // The lock comes first: holding it is what makes it safe to replace the event socket
        // and to treat any Stackline signal found in yabai as stale.
        instanceLock = try InstanceLock(path: directory.appending(path: "stackline.lock").path(percentEncoded: false))
        let eventSocket = try EventSocket(path: directory.appending(path: "events.sock").path(percentEncoded: false))

        windowManager = YabaiWindowManager(eventSocket: eventSocket)
        preferences = Preferences(loginItem: MainAppLoginItem())
        store = StackStore(windowManager: windowManager, systemEvents: SystemEvents.stream())
        indicators = IndicatorController(store: store, preferences: preferences)
    }

    func start() {
        guard connection == nil else { return }

        indicators.start()
        // Detached, so that the connection can be wound down without the main actor (see `stop`).
        connection = Task.detached { [windowManager] in await windowManager.run() }
        modelUpdates = Task { [store] in await store.run() }
    }

    /// Takes the indicators down at once, and returns a task that finishes when Stackline has
    /// unregistered from yabai: within about a second even if yabai is hung, and immediately if
    /// it is not running.
    ///
    /// The returned task never needs the main actor. That matters because the main thread is
    /// not free while the app quits: AppKit sits in a nested run loop waiting for the reply.
    func stop() -> Task<Void, Never> {
        indicators.stop()
        modelUpdates?.cancel()
        connection?.cancel()

        return Task.detached { [connection, windowManager] in
            await connection?.value
            await windowManager.shutdown()
        }
    }

    /// `~/Library/Application Support/Stackline`, private to the user.
    private static func stateDirectory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Stackline", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }
}
