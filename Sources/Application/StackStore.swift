import Foundation
import Observation

/// The app's model: which stacks exist right now, and whether the window manager is reachable.
///
/// Everything that can change the answer — window manager events, connection changes, display
/// reconfiguration, wake from sleep — funnels into one coalescing refresh that re-reads the
/// window list. Events are treated as hints that something changed, never as the change itself,
/// so a lost or duplicated event cannot leave the model wrong for longer than the next refresh.
@MainActor
@Observable
final class StackStore {
    enum Connection: Equatable {
        case waiting
        case connected
    }

    private(set) var stacks: [WindowStack] = []
    private(set) var connection: Connection = .waiting

    @ObservationIgnored private let windowManager: any WindowManager
    @ObservationIgnored private let systemEvents: AsyncStream<SystemEvent>
    @ObservationIgnored private let displays: @Sendable () -> DisplayGeometry
    @ObservationIgnored private let settleDelays: [Duration]

    /// Recently focused windows, most recent first.
    @ObservationIgnored private var focusHistory: [WindowIdentifier] = []
    @ObservationIgnored private var settling: Task<Void, Never>?

    /// A one-element buffer makes this a dirty flag: any number of requests made while a refresh
    /// is in flight result in exactly one more refresh.
    @ObservationIgnored private let refreshRequests: AsyncStream<Void>
    @ObservationIgnored private let refreshRequested: AsyncStream<Void>.Continuation

    /// - Parameters:
    ///   - displays: Captures the current display arrangement.
    ///   - settleDelays: Pauses between the extra refreshes that follow a display change, while
    ///     the system and the window manager are still moving windows around.
    init(
        windowManager: any WindowManager,
        systemEvents: AsyncStream<SystemEvent>,
        displays: @escaping @Sendable () -> DisplayGeometry = { .current() },
        settleDelays: [Duration] = [.milliseconds(250), .seconds(1), .seconds(3)]
    ) {
        self.windowManager = windowManager
        self.systemEvents = systemEvents
        self.displays = displays
        self.settleDelays = settleDelays
        (refreshRequests, refreshRequested) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Keeps the model up to date until the calling task is cancelled. Call once.
    func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in self.windowManager.events {
                    await self.handle(event)
                }
            }
            group.addTask {
                for await event in self.systemEvents {
                    await self.handle(event)
                }
            }
            group.addTask {
                for await _ in self.refreshRequests {
                    await self.refresh()
                }
            }
        }
        settling?.cancel()
    }

    /// Asks the window manager to focus `window`.
    func focus(_ window: WindowIdentifier) {
        Task { [windowManager] in
            do {
                try await windowManager.focus(window)
            } catch {
                Log.stacks.notice("Could not focus window \(window): \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Events

    private func handle(_ event: WindowManagerEvent) {
        switch event {
        case .connected:
            connection = .connected
            requestRefresh()
        case .disconnected:
            connection = .waiting
            settling?.cancel()
            focusHistory.removeAll()
            publish([])
        case .windowFocused(let window):
            noteFocus(of: window)
            requestRefresh()
        case .windowsChanged:
            requestRefresh()
        case .displaysChanged:
            refreshUntilSettled()
        }
    }

    private func handle(_ event: SystemEvent) {
        switch event {
        case .displaysChanged:
            refreshUntilSettled()
        case .spaceChanged:
            requestRefresh()
        }
    }

    // MARK: - Refreshing

    private func requestRefresh() {
        refreshRequested.yield()
    }

    /// Refreshes now and again after each settle delay. A display change is followed by a period
    /// in which frames keep changing without any further notification.
    private func refreshUntilSettled() {
        requestRefresh()

        settling?.cancel()
        settling = Task { [settleDelays] in
            for delay in settleDelays {
                guard (try? await Task.sleep(for: delay)) != nil else { return }
                requestRefresh()
            }
        }
    }

    private func refresh() async {
        guard connection == .connected else { return }

        let interval = Log.signposter.beginInterval("Refresh")
        defer { Log.signposter.endInterval("Refresh", interval) }

        do {
            let geometry = displays()
            let windows = try await windowManager.windows(on: geometry)
            // The connection may have dropped while the query was in flight.
            guard connection == .connected else { return }

            if let focused = windows.first(where: \.isFocused) {
                noteFocus(of: focused.id)
            }
            let existing = Set(windows.map(\.id))
            focusHistory.removeAll { !existing.contains($0) }

            publish(StackBuilder.stacks(from: windows, on: geometry, focusHistory: focusHistory))
        } catch is CancellationError {
            return
        } catch {
            Log.stacks.notice("Could not query windows: \(String(describing: error), privacy: .public)")
        }
    }

    private func noteFocus(of window: WindowIdentifier) {
        guard focusHistory.first != window else { return }
        focusHistory.removeAll { $0 == window }
        focusHistory.insert(window, at: 0)
    }

    private func publish(_ stacks: [WindowStack]) {
        guard stacks != self.stacks else { return }
        self.stacks = stacks
    }
}
