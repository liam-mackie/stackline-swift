import XCTest
@testable import Stackline

final class YabaiSubscriptionTests: XCTestCase {
    private var directory: TemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
    }

    override func tearDown() {
        directory = nil
    }

    // MARK: - Labels

    func testLabelsAreUniquePerSignalAndCarryTheSweepablePrefix() {
        let subscription = YabaiSubscription(token: "4242", eventSocketPath: "/tmp/events.sock")

        XCTAssertEqual(Set(subscription.labels).count, YabaiSignal.allCases.count)
        XCTAssertTrue(subscription.labels.allSatisfy { $0.hasPrefix(YabaiSubscription.labelPrefix) })
        XCTAssertEqual(subscription.label(for: .windowFocused), "stackline-4242-window_focused")
    }

    func testInstancesNeverShareLabels() {
        let old = YabaiSubscription(token: "1", eventSocketPath: "/tmp/events.sock")
        let new = YabaiSubscription(token: "2", eventSocketPath: "/tmp/events.sock")

        XCTAssertTrue(Set(old.labels).isDisjoint(with: new.labels))
    }

    // MARK: - Parsing

    func testParsesEventLines() {
        XCTAssertEqual(YabaiSubscription.event(from: "window_focused 618"), .windowFocused(618))
        XCTAssertEqual(YabaiSubscription.event(from: "window_focused"), .windowsChanged)
        XCTAssertEqual(YabaiSubscription.event(from: "window_focused not-a-number"), .windowsChanged)
        XCTAssertEqual(YabaiSubscription.event(from: "window_resized"), .windowsChanged)
        XCTAssertEqual(YabaiSubscription.event(from: "application_hidden"), .windowsChanged)
        XCTAssertEqual(YabaiSubscription.event(from: "space_changed"), .windowsChanged)
        XCTAssertEqual(YabaiSubscription.event(from: "display_removed"), .displaysChanged)
        XCTAssertEqual(YabaiSubscription.event(from: "system_woke"), .displaysChanged)
        XCTAssertNil(YabaiSubscription.event(from: "something_else"))
        XCTAssertNil(YabaiSubscription.event(from: ""))
    }

    // MARK: - Actions, run for real through `sh` and `nc` exactly as yabai would

    func testActionDeliversTheEventWithItsPayload() async throws {
        // A directory name that needs quoting, to prove the action survives the shell.
        let nasty = directory.file("it's a dir")
        try FileManager.default.createDirectory(atPath: nasty, withIntermediateDirectories: false)
        let socket = try EventSocket(path: "\(nasty)/events.sock")
        defer { socket.close() }
        let recorder = Recorder<String>()
        let recording = recorder.record(socket.lines)
        defer { recording.cancel() }

        let subscription = YabaiSubscription(token: "7", eventSocketPath: socket.path)
        let focused = try runAsYabaiSignalAction(
            subscription.action(for: .windowFocused, yabaiExecutable: nil),
            environment: ["YABAI_WINDOW_ID": "618"]
        )
        let moved = try runAsYabaiSignalAction(subscription.action(for: .windowMoved, yabaiExecutable: nil))

        XCTAssertEqual(focused, 0)
        XCTAssertEqual(moved, 0)
        let received = await waitUntil { recorder.elements.count == 2 }
        XCTAssertTrue(received)
        XCTAssertEqual(recorder.elements.compactMap(YabaiSubscription.event), [.windowFocused(618), .windowsChanged])
    }

    func testActionRemovesItsOwnSignalOnceNobodyIsListening() throws {
        let log = directory.file("yabai-invocations")
        let fakeYabai = directory.file("fake yabai")
        try "#!/bin/sh\necho \"$@\" >> '\(log)'\n".write(toFile: fakeYabai, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeYabai)

        // What a killed Stackline leaves behind: a socket file with no listener.
        let socketPath = directory.file("events.sock")
        let abandoned = try UnixSocket.open()
        try UnixSocket.bind(abandoned, to: socketPath)
        close(abandoned)

        let subscription = YabaiSubscription(token: "7", eventSocketPath: socketPath)
        try runAsYabaiSignalAction(
            subscription.action(for: .windowFocused, yabaiExecutable: fakeYabai),
            environment: ["YABAI_WINDOW_ID": "618"]
        )

        let invocations = try String(contentsOfFile: log, encoding: .utf8)
        XCTAssertEqual(invocations, "-m signal --remove stackline-7-window_focused\n")
    }

    func testActionLeavesItsSignalAloneWhileStacklineIsListening() throws {
        let log = directory.file("yabai-invocations")
        let fakeYabai = directory.file("fake-yabai")
        try "#!/bin/sh\necho \"$@\" >> '\(log)'\n".write(toFile: fakeYabai, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeYabai)
        let socket = try EventSocket(path: directory.file("events.sock"))
        defer { socket.close() }

        let subscription = YabaiSubscription(token: "7", eventSocketPath: socket.path)
        try runAsYabaiSignalAction(subscription.action(for: .spaceChanged, yabaiExecutable: fakeYabai))

        XCTAssertFalse(FileManager.default.fileExists(atPath: log))
    }
}

final class EventSocketTests: XCTestCase {
    private var directory: TemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
    }

    override func tearDown() {
        directory = nil
    }

    private func send(_ text: String, to path: String) throws {
        let descriptor = try UnixSocket.open()
        defer { close(descriptor) }
        try UnixSocket.connect(descriptor, to: path)
        _ = text.withCString { write(descriptor, $0, strlen($0)) }
    }

    func testDeliversOneLinePerConnectionInOrder() async throws {
        let socket = try EventSocket(path: directory.file("events.sock"))
        defer { socket.close() }
        let recorder = Recorder<String>()
        let recording = recorder.record(socket.lines)
        defer { recording.cancel() }

        try send("first\n", to: socket.path)
        try send("second 2\nignored trailing data\n", to: socket.path)
        try send("\n", to: socket.path)
        try send("unterminated", to: socket.path)

        let received = await waitUntil { recorder.elements.count == 3 }
        XCTAssertTrue(received)
        XCTAssertEqual(recorder.elements, ["first", "second 2", "unterminated"])
    }

    func testTakesOverASocketFileLeftByACrashedInstance() async throws {
        let path = directory.file("events.sock")
        let crashed = try UnixSocket.open()
        try UnixSocket.bind(crashed, to: path)
        close(crashed)

        let socket = try EventSocket(path: path)
        defer { socket.close() }
        let recorder = Recorder<String>()
        let recording = recorder.record(socket.lines)
        defer { recording.cancel() }
        try send("hello\n", to: path)

        let received = await waitUntil { recorder.elements == ["hello"] }
        XCTAssertTrue(received)
    }

    func testClosingRemovesTheSocketFileAndEndsTheStream() async throws {
        let path = directory.file("events.sock")
        let socket = try EventSocket(path: path)
        let recorder = Recorder<String>()
        let recording = recorder.record(socket.lines)

        socket.close()
        await recording.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertThrowsError(try send("late\n", to: path))
    }

    func testRejectsAPathThatDoesNotFitASocketAddress() {
        let path = directory.file(String(repeating: "x", count: 120))

        XCTAssertThrowsError(try EventSocket(path: path)) { error in
            XCTAssertEqual(error as? SocketError, .pathTooLong(path))
        }
    }
}
