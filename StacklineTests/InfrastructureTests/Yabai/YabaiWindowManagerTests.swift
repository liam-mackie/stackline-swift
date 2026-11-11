import XCTest
@testable import Stackline

/// Lifecycle tests for the yabai connection, run against a fake yabai over real sockets.
final class YabaiWindowManagerTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var yabai: FakeYabai!
    private var yabaiExit: ProcessExitTrigger!
    private var eventSocketPath: String!
    private var manager: YabaiWindowManager!
    private var events: Recorder<WindowManagerEvent>!
    private var recording: Task<Void, Never>!
    private var running: Task<Void, Never>?

    private let signalCount = YabaiSignal.allCases.count

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        yabai = FakeYabai(socketPath: directory.file("yabai.socket"))
        eventSocketPath = directory.file("events.sock")

        let yabaiExit = ProcessExitTrigger()
        self.yabaiExit = yabaiExit

        var configuration = YabaiWindowManager.Configuration()
        configuration.initialRetryDelay = .milliseconds(5)
        configuration.maximumRetryDelay = .milliseconds(20)
        configuration.verificationInterval = .milliseconds(20)
        configuration.processExit = { _ in await yabaiExit.wait() }

        manager = YabaiWindowManager(
            client: YabaiClient(socketPath: yabai.socketPath),
            eventSocket: try EventSocket(path: eventSocketPath),
            configuration: configuration
        )
        events = Recorder()
        recording = events.record(manager.events)
    }

    override func tearDown() async throws {
        running?.cancel()
        await running?.value
        await manager.shutdown(timeout: .milliseconds(100))
        yabai.stop()
        recording.cancel()
        // XCTest keeps test case instances alive, so release what owns files explicitly.
        manager = nil
        directory = nil
    }

    private func start() {
        running = Task { [manager] in await manager!.run() }
    }

    private func stopRunning() async {
        running?.cancel()
        await running?.value
        running = nil
    }

    private func waitForEvents(_ expected: [WindowManagerEvent], file: StaticString = #filePath, line: UInt = #line) async {
        let arrived = await waitUntil { self.events.elements == expected }
        XCTAssertTrue(arrived, "Expected events \(expected), got \(events.elements)", file: file, line: line)
    }

    private var stacklineLabels: Set<String> {
        yabai.labels.filter { $0.hasPrefix("stackline-") }
    }

    // MARK: - Connecting

    func testRegistersItsSignalsWhenYabaiIsRunning() async throws {
        try yabai.start()

        start()

        await waitForEvents([.connected])
        XCTAssertEqual(stacklineLabels.count, signalCount)
        XCTAssertEqual(Set(yabai.signals.map(\.event)), Set(YabaiSignal.allCases.map(\.rawValue)))
    }

    func testWaitsForYabaiThatStartsLater() async throws {
        start()

        // Long enough for many failed attempts; none of them may surface as an event.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(events.elements, [])

        try yabai.start()

        await waitForEvents([.connected])
        XCTAssertEqual(stacklineLabels.count, signalCount)
    }

    func testSweepsSignalsLeftBehindByADeadInstance() async throws {
        try yabai.start()
        yabai.addSignal(.init(event: "window_focused", label: "stackline-99999-window_focused", action: "stale"))
        yabai.addSignal(.init(event: "window_focused", label: "stackline-window_focused", action: "stale, label of an older version"))
        yabai.addSignal(.init(event: "dock_did_restart", label: "", action: "sudo yabai --load-sa"))
        yabai.addSignal(.init(event: "window_created", label: "my-own-signal", action: "true"))

        start()

        await waitForEvents([.connected])
        XCTAssertFalse(yabai.signals.contains { $0.action.hasPrefix("stale") })
        XCTAssertEqual(stacklineLabels.count, signalCount)
        // Signals that are not Stackline's are none of its business.
        XCTAssertTrue(yabai.signals.contains { $0.action == "sudo yabai --load-sa" })
        XCTAssertTrue(yabai.labels.contains("my-own-signal"))
    }

    // MARK: - Staying connected

    func testReconnectsAndRegistersAgainAfterYabaiRestarts() async throws {
        try yabai.start()
        start()
        await waitForEvents([.connected])

        yabai.stop()
        yabaiExit.fire()
        await waitForEvents([.connected, .disconnected])

        try yabai.start()

        await waitForEvents([.connected, .disconnected, .connected])
        XCTAssertEqual(stacklineLabels.count, signalCount)
    }

    func testRestoresSignalsThatGoMissingWhileYabaiKeepsRunning() async throws {
        try yabai.start()
        start()
        await waitForEvents([.connected])
        let removed = stacklineLabels.first { $0.hasSuffix("window_focused") }!

        yabai.removeSignal(labelled: removed)

        let restored = await waitUntil { self.yabai.labels.contains(removed) }
        XCTAssertTrue(restored)
        // Events may have been lost meanwhile, so the model is told to re-read.
        await waitForEvents([.connected, .windowsChanged])
    }

    // MARK: - Events

    func testForwardsSignalsFiredByYabai() async throws {
        try yabai.start()
        start()
        await waitForEvents([.connected])

        // Fire the registered actions the way yabai does: through the shell.
        let focused = try XCTUnwrap(yabai.signals.first { $0.event == "window_focused" })
        let displayAdded = try XCTUnwrap(yabai.signals.first { $0.event == "display_added" })
        try runAsYabaiSignalAction(focused.action, environment: ["YABAI_WINDOW_ID": "42"])
        try runAsYabaiSignalAction(displayAdded.action)

        await waitForEvents([.connected, .windowFocused(42), .displaysChanged])
        // Delivery succeeded, so neither signal removed itself.
        XCTAssertEqual(stacklineLabels.count, signalCount)
    }

    // MARK: - Queries

    func testQueriesWindowsAndFocusesThem() async throws {
        try yabai.start()
        yabai.setWindows(#"""
        [{"id":7,"pid":70,"app":"Notes","frame":{"x":0,"y":40,"w":1280,"h":1400},"display":1,"space":1,
          "stack-index":1,"has-focus":true,"is-visible":true,"is-minimized":false,"is-hidden":false,
          "is-floating":false,"is-native-fullscreen":false}]
        """#)

        let windows = try await manager.windows(on: .single)
        try await manager.focus(7)

        XCTAssertEqual(windows.map(\.id), [7])
        XCTAssertEqual(windows.first?.frame, CGRect(x: 0, y: 0, width: 1280, height: 1400))
        XCTAssertEqual(yabai.requests.last, ["window", "--focus", "7"])
    }

    func testQueryFailuresAreReportedAsWindowManagerErrors() async throws {
        do {
            _ = try await manager.windows(on: .single)
            XCTFail("Expected yabai to be unavailable")
        } catch {
            XCTAssertEqual(error as? WindowManagerError, .unavailable)
        }

        try yabai.start()
        yabai.rejectFocus(with: "could not locate window with the specified id '7'.")
        do {
            try await manager.focus(7)
            XCTFail("Expected the focus request to be rejected")
        } catch {
            XCTAssertEqual(error as? WindowManagerError, .rejected("could not locate window with the specified id '7'."))
        }
    }

    // MARK: - Shutting down

    func testShutdownRemovesItsSignalsAndItsSocket() async throws {
        try yabai.start()
        yabai.addSignal(.init(event: "window_created", label: "my-own-signal", action: "true"))
        start()
        await waitForEvents([.connected])

        await stopRunning()
        await manager.shutdown()

        XCTAssertEqual(yabai.labels, ["my-own-signal"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventSocketPath))
    }

    func testShutdownIsImmediateWhileStillWaitingForYabai() async throws {
        start()
        try await Task.sleep(for: .milliseconds(30))

        let elapsed = await ContinuousClock().measure {
            await stopRunning()
            await manager.shutdown()
        }

        XCTAssertLessThan(elapsed, .milliseconds(500))
        XCTAssertEqual(events.elements, [])
    }

    func testShutdownIsImmediateAfterYabaiHasGone() async throws {
        try yabai.start()
        start()
        await waitForEvents([.connected])
        yabai.stop()

        let elapsed = await ContinuousClock().measure {
            await stopRunning()
            await manager.shutdown()
        }

        XCTAssertLessThan(elapsed, .milliseconds(500))
    }

    /// The old shutdown waited five seconds per signal for a yabai that would never answer.
    func testShutdownGivesUpOnAYabaiThatStoppedAnswering() async throws {
        try yabai.start()
        start()
        await waitForEvents([.connected])
        yabai.hang()

        let elapsed = await ContinuousClock().measure {
            await stopRunning()
            await manager.shutdown(timeout: .milliseconds(200))
        }

        XCTAssertGreaterThan(elapsed, .milliseconds(150))
        XCTAssertLessThan(elapsed, .seconds(1))
    }
}
