import XCTest
import Logging
@testable import Stackline

final class MockLogHandler: LogHandler {
    var metadata: Logging.Logger.Metadata = [:]
    var logLevel: Logging.Logger.Level = .trace

    struct LogEntry {
        let level: Logging.Logger.Level
        let message: String
        let metadata: Logging.Logger.Metadata?
        let source: String
        let file: String
        let function: String
        let line: UInt
    }

    private(set) var entries: [LogEntry] = []
    private let lock = NSLock()

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(LogEntry(
            level: level,
            message: message.description,
            metadata: metadata,
            source: source,
            file: file,
            function: function,
            line: line
        ))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

final class LoggingServiceTests: XCTestCase {
    func testLogCategoriesExist() {
        XCTAssertEqual(LogCategory.allCases.count, 6)
        XCTAssertTrue(LogCategory.allCases.contains(.app))
        XCTAssertTrue(LogCategory.allCases.contains(.windowManager))
        XCTAssertTrue(LogCategory.allCases.contains(.stackDetection))
        XCTAssertTrue(LogCategory.allCases.contains(.indicators))
        XCTAssertTrue(LogCategory.allCases.contains(.preferences))
        XCTAssertTrue(LogCategory.allCases.contains(.ui))
    }

    func testLogCategoryRawValues() {
        XCTAssertEqual(LogCategory.app.rawValue, "app")
        XCTAssertEqual(LogCategory.windowManager.rawValue, "window-manager")
        XCTAssertEqual(LogCategory.stackDetection.rawValue, "stack-detection")
        XCTAssertEqual(LogCategory.indicators.rawValue, "indicators")
        XCTAssertEqual(LogCategory.preferences.rawValue, "preferences")
        XCTAssertEqual(LogCategory.ui.rawValue, "ui")
    }

    func testOSLogHandlerMapsLogLevelsCorrectly() {
        let handler = OSLogHandler(subsystem: "test", category: "test")

        XCTAssertEqual(handler.logLevel, .info)
    }

    func testLoggingServiceSharedInstance() {
        let service1 = LoggingService.shared
        let service2 = LoggingService.shared

        XCTAssertTrue(service1 === service2)
    }

    func testLoggingServiceDefaultLogLevel() {
        let service = LoggingService()

        XCTAssertEqual(service.logLevel, .info)
    }

    func testLoggingServiceLogLevelChange() {
        let service = LoggingService()

        service.logLevel = .debug
        XCTAssertEqual(service.logLevel, .debug)

        service.logLevel = .error
        XCTAssertEqual(service.logLevel, .error)
    }

    func testMockLogHandlerCapturesEntries() {
        let handler = MockLogHandler()
        var logger = Logging.Logger(label: "test")
        logger.handler = handler
        logger.logLevel = .trace

        logger.debug("Test debug message")
        logger.info("Test info message")
        logger.error("Test error message")

        XCTAssertEqual(handler.entries.count, 3)
        XCTAssertEqual(handler.entries[0].level, .debug)
        XCTAssertEqual(handler.entries[0].message, "Test debug message")
        XCTAssertEqual(handler.entries[1].level, .info)
        XCTAssertEqual(handler.entries[1].message, "Test info message")
        XCTAssertEqual(handler.entries[2].level, .error)
        XCTAssertEqual(handler.entries[2].message, "Test error message")
    }

    func testMockLogHandlerRespectsLogLevel() {
        let handler = MockLogHandler()
        handler.logLevel = .warning

        var logger = Logging.Logger(label: "test")
        logger.handler = handler
        logger.logLevel = .warning

        logger.debug("Should not appear")
        logger.info("Should not appear")
        logger.warning("Should appear")
        logger.error("Should appear")

        XCTAssertEqual(handler.entries.count, 2)
        XCTAssertEqual(handler.entries[0].level, .warning)
        XCTAssertEqual(handler.entries[1].level, .error)
    }

    func testMockLogHandlerClear() {
        let handler = MockLogHandler()
        var logger = Logging.Logger(label: "test")
        logger.handler = handler
        logger.logLevel = .trace

        logger.info("Message 1")
        logger.info("Message 2")
        XCTAssertEqual(handler.entries.count, 2)

        handler.clear()
        XCTAssertEqual(handler.entries.count, 0)
    }

    func testMockLogHandlerMetadata() {
        let handler = MockLogHandler()
        var logger = Logging.Logger(label: "test")
        logger.handler = handler
        logger.logLevel = .trace

        logger[metadataKey: "request-id"] = "12345"
        logger.info("Request processed")

        XCTAssertEqual(handler.entries.count, 1)
    }
}
