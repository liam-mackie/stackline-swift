import XCTest
@testable import Stackline

final class YabaiCommandExecutorTests: XCTestCase {

    // MARK: - Error Types Tests

    func testYabaiExecutorErrorEquality() {
        XCTAssertEqual(
            YabaiExecutorError.yabaiNotFound.localizedDescription,
            YabaiExecutorError.yabaiNotFound.localizedDescription
        )
    }

    func testYabaiExecutorErrorCases() {
        let notFound = YabaiExecutorError.yabaiNotFound
        let execFailed = YabaiExecutorError.executionFailed("test error")
        let decodeFailed = YabaiExecutorError.decodingFailed("decode error")
        let timeout = YabaiExecutorError.timeout

        switch notFound {
        case .yabaiNotFound:
            break
        default:
            XCTFail("Expected yabaiNotFound")
        }

        switch execFailed {
        case .executionFailed(let msg):
            XCTAssertEqual(msg, "test error")
        default:
            XCTFail("Expected executionFailed")
        }

        switch decodeFailed {
        case .decodingFailed(let msg):
            XCTAssertEqual(msg, "decode error")
        default:
            XCTFail("Expected decodingFailed")
        }

        switch timeout {
        case .timeout:
            break
        default:
            XCTFail("Expected timeout")
        }
    }

    // MARK: - Mock Executor Tests

    func testMockExecutorRecordsCommands() async throws {
        let mock = MockYabaiCommandExecutor()

        try await mock.execute(["-m", "window", "--focus", "123"])

        XCTAssertEqual(mock.executedCommands.count, 1)
        XCTAssertEqual(mock.executedCommands[0], ["-m", "window", "--focus", "123"])
    }

    func testMockExecutorReturnsAvailability() async {
        let mock = MockYabaiCommandExecutor()

        mock.available = true
        let available = await mock.isAvailable()
        XCTAssertTrue(available)

        mock.available = false
        let notAvailable = await mock.isAvailable()
        XCTAssertFalse(notAvailable)
    }

    func testMockExecutorThrowsConfiguredError() async {
        let mock = MockYabaiCommandExecutor()
        mock.errorToThrow = .timeout

        do {
            try await mock.execute(["-m", "query", "--windows"])
            XCTFail("Expected error to be thrown")
        } catch let error as YabaiExecutorError {
            if case .timeout = error {
                // Expected
            } else {
                XCTFail("Expected timeout error")
            }
        } catch {
            XCTFail("Unexpected error type")
        }
    }

    func testMockExecutorReset() async throws {
        let mock = MockYabaiCommandExecutor()

        mock.available = false
        mock.errorToThrow = .timeout
        try? await mock.execute(["test"])

        mock.reset()

        XCTAssertTrue(mock.available)
        XCTAssertNil(mock.errorToThrow)
        XCTAssertTrue(mock.executedCommands.isEmpty)
    }

    func testMockExecutorQueryWithResponse() async throws {
        let mock = MockYabaiCommandExecutor()

        struct TestResponse: Codable, Equatable {
            let value: String
        }

        mock.setQueryResponse(TestResponse(value: "test"), for: ["-m", "test"])

        let result: TestResponse = try await mock.query(["-m", "test"])

        XCTAssertEqual(result.value, "test")
    }
}
