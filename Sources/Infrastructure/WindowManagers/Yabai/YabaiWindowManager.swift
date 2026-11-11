import Darwin
import Foundation

/// Keeps Stackline attached to yabai for as long as the app runs.
///
/// yabai only remembers signals in memory, and it may start after Stackline, restart behind it,
/// or never run at all. `run()` therefore treats the connection as something to maintain rather
/// than establish once:
///
///     waiting ──(yabai reachable, signals registered)──▶ connected
///        ▲                                                   │
///        └────────(yabai exits or stops answering)───────────┘
///
/// While waiting it retries with back-off; while connected it watches the yabai process for exit
/// and periodically verifies its signals are still registered. Both transitions are announced on
/// `events`.
actor YabaiWindowManager: WindowManager {
    struct Configuration: Sendable {
        /// Delay before the first reconnection attempt; doubles after every failure.
        var initialRetryDelay: Duration = .milliseconds(100)
        var maximumRetryDelay: Duration = .seconds(2)
        /// How often to check that yabai still has Stackline's signals.
        var verificationInterval: Duration = .seconds(30)
        /// Suspends until the process exits.
        var processExit: @Sendable (pid_t) async -> Void = { await ProcessExit.wait(for: $0) }
    }

    nonisolated let events: AsyncStream<WindowManagerEvent>

    private let continuation: AsyncStream<WindowManagerEvent>.Continuation
    private let client: YabaiClient
    private let eventSocket: EventSocket
    private let subscription: YabaiSubscription
    private let configuration: Configuration

    /// Whether yabai may hold signals registered by this instance.
    private var mayHaveSignals = false

    init(
        client: YabaiClient = YabaiClient(),
        eventSocket: EventSocket,
        configuration: Configuration = Configuration()
    ) {
        let (events, continuation) = AsyncStream.makeStream(of: WindowManagerEvent.self)
        self.events = events
        self.continuation = continuation
        self.client = client
        self.eventSocket = eventSocket
        self.subscription = YabaiSubscription(eventSocketPath: eventSocket.path)
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    /// Maintains the connection until the calling task is cancelled. Call once.
    func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.forwardEvents() }
            group.addTask { await self.maintainConnection() }
        }
    }

    /// Removes this instance's signals from yabai and stops listening for events.
    ///
    /// Call after the task running `run()` has finished. Never takes longer than `timeout`: if
    /// yabai is gone there is nothing to remove, and if it is unresponsive the signals remove
    /// themselves the next time they fire.
    func shutdown(timeout: Duration = .seconds(1)) async {
        if mayHaveSignals {
            let deadline = ContinuousClock.now + timeout
            for label in subscription.labels {
                do {
                    _ = try await client.send(["signal", "--remove", label], deadline: deadline)
                } catch YabaiError.rejected {
                    continue // Not registered (any more).
                } catch {
                    Log.windowManager.notice("Could not remove yabai signals: \(String(describing: error), privacy: .public)")
                    break
                }
            }
            mayHaveSignals = false
        }

        eventSocket.close()
        continuation.finish()
    }

    // MARK: - WindowManager

    nonisolated func windows(on displays: DisplayGeometry) async throws -> [ManagedWindow] {
        let interval = Log.signposter.beginInterval("QueryWindows")
        defer { Log.signposter.endInterval("QueryWindows", interval) }

        let reply = try await request(["query", "--windows"])
        do {
            return try JSONDecoder().decode([YabaiWindow].self, from: reply).map { $0.managedWindow(on: displays) }
        } catch {
            throw WindowManagerError.failed("unreadable window list: \(error)")
        }
    }

    nonisolated func focus(_ window: WindowIdentifier) async throws {
        _ = try await request(["window", "--focus", String(window)])
    }

    private nonisolated func request(_ arguments: [String]) async throws -> Data {
        do {
            return try await client.send(arguments).body
        } catch let error as YabaiError {
            throw switch error {
            case .unavailable: WindowManagerError.unavailable
            case .timedOut: WindowManagerError.timedOut
            case .rejected(let message): WindowManagerError.rejected(message)
            case .transport(let message): WindowManagerError.failed(message)
            }
        }
    }

    // MARK: - Events

    private nonisolated func forwardEvents() async {
        for await line in eventSocket.lines {
            if let event = YabaiSubscription.event(from: line) {
                continuation.yield(event)
            } else {
                Log.windowManager.debug("Ignoring unknown event: \(line, privacy: .public)")
            }
        }
    }

    // MARK: - Connection

    private func maintainConnection() async {
        var retryDelay = configuration.initialRetryDelay
        var isWaiting = false

        while !Task.isCancelled {
            do {
                let pid = try await connect()
                retryDelay = configuration.initialRetryDelay
                isWaiting = false

                Log.windowManager.info("Connected to yabai (pid \(pid))")
                continuation.yield(.connected)
                await watch(pid)
                guard !Task.isCancelled else { return }

                Log.windowManager.info("Lost yabai (pid \(pid)); reconnecting")
                continuation.yield(.disconnected)
            } catch {
                guard !Task.isCancelled else { return }
                if !isWaiting {
                    isWaiting = true
                    Log.windowManager.info("Waiting for yabai: \(String(describing: error), privacy: .public)")
                }
            }

            try? await Task.sleep(for: retryDelay)
            retryDelay = min(retryDelay * 2, configuration.maximumRetryDelay)
        }
    }

    /// Registers Stackline's signals with yabai and returns the PID of the yabai process.
    private func connect() async throws -> pid_t {
        let listing = try await client.send(["signal", "--list"])
        let pid = listing.pid

        // Holding the instance lock means any Stackline signal already present was left behind
        // by an instance that had no chance to clean up.
        for label in Self.stacklineLabels(in: listing.body) ?? [] {
            do {
                _ = try await client.send(["signal", "--remove", label])
            } catch YabaiError.rejected {
                continue // Removed itself in the meantime.
            }
        }

        try await register(YabaiSignal.allCases, with: pid)
        return pid
    }

    private func register(_ signals: [YabaiSignal], with pid: pid_t) async throws {
        let executable = Self.executablePath(of: pid)
        mayHaveSignals = true

        for signal in signals {
            let response = try await client.send(subscription.registration(for: signal, yabaiExecutable: executable))
            // A different process answering means yabai restarted and forgot the earlier signals.
            guard response.pid == pid else { throw YabaiError.unavailable }
        }
    }

    /// Returns when the yabai process `pid` is gone or the task is cancelled.
    private func watch(_ pid: pid_t) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [configuration] in await configuration.processExit(pid) }
            group.addTask { await self.verifySignals(of: pid) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Periodically re-registers signals that went missing — removed by hand, or by their own
    /// self-removal after a failed delivery. Returns when yabai `pid` no longer answers.
    private func verifySignals(of pid: pid_t) async {
        while true {
            do {
                try await Task.sleep(for: configuration.verificationInterval)

                let listing = try await client.send(["signal", "--list"])
                guard listing.pid == pid else { return }
                guard let present = Self.stacklineLabels(in: listing.body) else { continue }

                let missing = YabaiSignal.allCases.filter { !present.contains(subscription.label(for: $0)) }
                guard !missing.isEmpty else { continue }

                Log.windowManager.notice("Re-registering \(missing.count) missing yabai signal(s)")
                try await register(missing, with: pid)
                continuation.yield(.windowsChanged) // Events may have been missed.
            } catch YabaiError.unavailable {
                return
            } catch is CancellationError {
                return
            } catch {
                // yabai is busy; the process-exit watcher covers the case where it is gone.
                Log.windowManager.debug("Could not verify yabai signals: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The Stackline-owned labels in a `signal --list` reply, or nil if the reply is unreadable.
    private static func stacklineLabels(in listing: Data) -> [String]? {
        do {
            return try JSONDecoder().decode([YabaiSignalEntry].self, from: listing)
                .map(\.label)
                .filter { $0.hasPrefix(YabaiSubscription.labelPrefix) }
        } catch {
            Log.windowManager.error("Unreadable signal list from yabai: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Path of the binary `pid` is running. Asking the kernel finds yabai wherever it is
    /// installed (Homebrew, Nix, a source build), which guessing well-known paths does not.
    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
