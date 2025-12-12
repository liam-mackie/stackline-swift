import Foundation
import Logging
import os

public enum LogCategory: String, CaseIterable {
    case app = "app"
    case windowManager = "window-manager"
    case stackDetection = "stack-detection"
    case indicators = "indicators"
    case preferences = "preferences"
    case ui = "ui"
}

public final class LoggingService: @unchecked Sendable {
    public static let shared = LoggingService()

    nonisolated(unsafe) private static var isBootstrapped = false
    private static let bootstrapLock = NSLock()

    private let subsystem = "sh.mackie.stackline"
    private var loggers: [LogCategory: Logging.Logger] = [:]
    private let lock = NSLock()

    public var logLevel: Logging.Logger.Level = .info {
        didSet {
            lock.lock()
            defer { lock.unlock() }
            for category in LogCategory.allCases {
                loggers[category]?.logLevel = logLevel
            }
        }
    }

    public init() {
        Self.bootstrapLock.lock()
        if !Self.isBootstrapped {
            LoggingSystem.bootstrap { [subsystem] label in
                OSLogHandler(subsystem: subsystem, category: label)
            }
            Self.isBootstrapped = true
        }
        Self.bootstrapLock.unlock()

        for category in LogCategory.allCases {
            var logger = Logging.Logger(label: category.rawValue)
            logger.logLevel = logLevel
            loggers[category] = logger
        }
    }

    private func logger(for category: LogCategory) -> Logging.Logger {
        lock.lock()
        defer { lock.unlock() }
        return loggers[category] ?? Logging.Logger(label: category.rawValue)
    }

    public func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger(for: category).debug(
            Logging.Logger.Message(stringLiteral: message()),
            file: file,
            function: function,
            line: line
        )
    }

    public func info(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger(for: category).info(
            Logging.Logger.Message(stringLiteral: message()),
            file: file,
            function: function,
            line: line
        )
    }

    public func notice(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger(for: category).notice(
            Logging.Logger.Message(stringLiteral: message()),
            file: file,
            function: function,
            line: line
        )
    }

    public func warning(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger(for: category).warning(
            Logging.Logger.Message(stringLiteral: message()),
            file: file,
            function: function,
            line: line
        )
    }

    public func error(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger(for: category).error(
            Logging.Logger.Message(stringLiteral: message()),
            file: file,
            function: function,
            line: line
        )
    }

    public func critical(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger(for: category).critical(
            Logging.Logger.Message(stringLiteral: message()),
            file: file,
            function: function,
            line: line
        )
    }
}

public extension LoggingService {
    static func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        shared.debug(message(), category: category, file: file, function: function, line: line)
    }

    static func info(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        shared.info(message(), category: category, file: file, function: function, line: line)
    }

    static func notice(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        shared.notice(message(), category: category, file: file, function: function, line: line)
    }

    static func warning(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        shared.warning(message(), category: category, file: file, function: function, line: line)
    }

    static func error(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        shared.error(message(), category: category, file: file, function: function, line: line)
    }

    static func critical(
        _ message: @autoclosure () -> String,
        category: LogCategory = .app,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        shared.critical(message(), category: category, file: file, function: function, line: line)
    }
}
