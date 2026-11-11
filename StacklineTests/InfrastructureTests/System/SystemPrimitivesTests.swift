import XCTest
@testable import Stackline

final class InstanceLockTests: XCTestCase {
    func testOnlyOneHolderAtATime() throws {
        let directory = try TemporaryDirectory()
        let path = directory.file("stackline.lock")

        var first: InstanceLock? = try InstanceLock(path: path)
        XCTAssertThrowsError(try InstanceLock(path: path)) { error in
            guard case InstanceLock.Failure.alreadyHeld = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        // Releasing — which the kernel also does when the holder dies — frees it for the next.
        XCTAssertNotNil(first)
        first = nil
        XCTAssertNoThrow(try InstanceLock(path: path))
    }
}

final class ProcessExitTests: XCTestCase {
    private func spawnSleep(_ seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    func testReturnsWhenTheProcessExits() async throws {
        let process = try spawnSleep("0.3")
        let clock = ContinuousClock()
        let start = clock.now

        await ProcessExit.wait(for: process.processIdentifier)

        let elapsed = clock.now - start
        XCTAssertGreaterThan(elapsed, .milliseconds(150))
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    func testReturnsImmediatelyForAProcessThatIsAlreadyGone() async throws {
        let process = try spawnSleep("0")
        process.waitUntilExit()

        let elapsed = await ContinuousClock().measure {
            await ProcessExit.wait(for: process.processIdentifier)
        }

        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testCancellationEndsTheWait() async throws {
        let process = try spawnSleep("30")
        defer { process.terminate() }

        let waiting = Task { await ProcessExit.wait(for: process.processIdentifier) }
        try await Task.sleep(for: .milliseconds(50))

        let elapsed = await ContinuousClock().measure {
            waiting.cancel()
            await waiting.value
        }
        XCTAssertLessThan(elapsed, .seconds(1))
        XCTAssertTrue(process.isRunning)
    }

    func testAlreadyCancelledTaskDoesNotWait() async throws {
        let process = try spawnSleep("30")
        defer { process.terminate() }

        let waiting = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await ProcessExit.wait(for: process.processIdentifier)
        }

        let elapsed = await ContinuousClock().measure { await waiting.value }
        XCTAssertLessThan(elapsed, .seconds(1))
    }
}
