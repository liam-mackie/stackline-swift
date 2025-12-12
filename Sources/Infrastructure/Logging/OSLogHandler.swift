import Foundation
import Logging
import os

public struct OSLogHandler: LogHandler {
    private let osLogger: os.Logger
    public var metadata: Logging.Logger.Metadata = [:]
    public var logLevel: Logging.Logger.Level = .info

    public init(subsystem: String, category: String) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let osLogType = mapLogLevel(level)
        let formattedMessage = formatMessage(message, metadata: metadata, file: file, line: line)
        osLogger.log(level: osLogType, "\(formattedMessage)")
    }

    private func mapLogLevel(_ level: Logging.Logger.Level) -> OSLogType {
        switch level {
        case .trace, .debug:
            return .debug
        case .info, .notice:
            return .info
        case .warning:
            return .default
        case .error, .critical:
            return .error
        }
    }

    private func formatMessage(
        _ message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        file: String,
        line: UInt
    ) -> String {
        var output = "\(message)"

        let mergedMetadata = self.metadata.merging(metadata ?? [:]) { _, new in new }
        if !mergedMetadata.isEmpty {
            let metadataString = mergedMetadata
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            output += " [\(metadataString)]"
        }

        return output
    }
}
