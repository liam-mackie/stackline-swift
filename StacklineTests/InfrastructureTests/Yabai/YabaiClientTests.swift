import XCTest
@testable import Stackline

final class YabaiClientTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var yabai: FakeYabai!
    private var client: YabaiClient!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        yabai = FakeYabai(socketPath: directory.file("yabai.socket"))
        client = YabaiClient(socketPath: yabai.socketPath)
    }

    override func tearDown() {
        yabai.stop()
        directory = nil
    }

    // MARK: - Wire format

    func testRequestIsLengthPrefixedNulSeparatedArguments() {
        let message = YabaiClient.encode(["query", "--windows"])

        // int32 length 17, then "query\0--windows\0\0".
        XCTAssertEqual(Array(message.prefix(4)), [17, 0, 0, 0])
        XCTAssertEqual(Array(message.dropFirst(4)), Array("query\0--windows\0\0".utf8))
    }

    func testReplyStartingWithBellIsAFailure() {
        XCTAssertThrowsError(try YabaiClient.decode(Data([0x07]) + Data("no such window\n".utf8))) { error in
            XCTAssertEqual(error as? YabaiError, .rejected("no such window"))
        }
        XCTAssertEqual(try YabaiClient.decode(Data("[]".utf8)), Data("[]".utf8))
    }

    // MARK: - Round trips

    func testDeliversArgumentsAndReturnsReply() async throws {
        try yabai.start()
        yabai.setWindows(#"[{"id":1}]"#)

        let response = try await client.send(["query", "--windows"])

        XCTAssertEqual(yabai.requests, [["query", "--windows"]])
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), #"[{"id":1}]"#)
    }

    func testReportsWhichProcessAnswered() async throws {
        try yabai.start()

        let response = try await client.send(["signal", "--list"])

        XCTAssertEqual(response.pid, getpid())
    }

    /// Replies larger than a socket buffer (the old implementation stalled at the 64 KiB pipe limit).
    func testReadsRepliesLargerThanTheSocketBuffer() async throws {
        try yabai.start()
        let large = "[" + String(repeating: #"{"title":"0123456789abcdef"},"#, count: 20_000) + "{}]"
        yabai.setWindows(large)

        let response = try await client.send(["query", "--windows"])

        XCTAssertEqual(response.body.count, large.utf8.count)
    }

    func testArgumentsWithShellSyntaxArriveVerbatim() async throws {
        try yabai.start()
        let action = #"echo window_focused "$YABAI_WINDOW_ID" | nc -U '/tmp/it'\''s here' || true"#

        _ = try await client.send(["signal", "--add", "event=window_focused", "label=x", "action=\(action)"])

        XCTAssertEqual(yabai.signals, [.init(event: "window_focused", label: "x", action: action)])
    }

    // MARK: - Failures

    func testYabaiFailureMessageIsReported() async throws {
        try yabai.start()

        do {
            _ = try await client.send(["signal", "--remove", "missing"])
            XCTFail("Expected the request to be rejected")
        } catch {
            XCTAssertEqual(error as? YabaiError, .rejected("signal with label 'missing' not found."))
        }
    }

    func testUnavailableWhenYabaiIsNotRunning() async {
        do {
            _ = try await client.send(["signal", "--list"])
            XCTFail("Expected yabai to be unavailable")
        } catch {
            XCTAssertEqual(error as? YabaiError, .unavailable)
        }
    }

    func testUnavailableAfterYabaiExitsLeavingItsSocketFileBehind() async throws {
        // A crashed yabai leaves the socket file; nobody is listening on it any more.
        let stale = try UnixSocket.open()
        defer { close(stale) }
        try UnixSocket.bind(stale, to: directory.file("stale.socket"))

        do {
            _ = try await YabaiClient(socketPath: directory.file("stale.socket")).send(["signal", "--list"])
            XCTFail("Expected yabai to be unavailable")
        } catch {
            XCTAssertEqual(error as? YabaiError, .unavailable)
        }
    }

    func testTimesOutWhenYabaiDoesNotAnswer() async throws {
        try yabai.start()
        yabai.hang()

        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await client.send(["query", "--windows"], timeout: .milliseconds(100))
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? YabaiError, .timedOut)
        }
        XCTAssertLessThan(clock.now - start, .seconds(2))
    }

    func testCancellationAbortsARequestInFlight() async throws {
        try yabai.start()
        yabai.hang()

        let request = Task { [client] in
            try await client!.send(["query", "--windows"], timeout: .seconds(30))
        }
        let delivered = await waitUntil { self.yabai.requests.count == 1 }
        XCTAssertTrue(delivered)

        let clock = ContinuousClock()
        let start = clock.now
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
        XCTAssertLessThan(clock.now - start, .seconds(2))
    }
}
