import Foundation
@testable import Stackline

/// Mock implementation of YabaiCommandExecuting for testing
final class MockYabaiCommandExecutor: YabaiCommandExecuting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "sh.mackie.stackline.mockexecutor")

    /// Predefined responses for query commands
    private var _queryResponses: [String: Any] = [:]

    /// Executed commands for verification
    private var _executedCommands: [[String]] = []
    var executedCommands: [[String]] {
        queue.sync { _executedCommands }
    }

    /// Control availability
    private var _available: Bool = true
    var available: Bool {
        get { queue.sync { _available } }
        set { queue.sync { _available = newValue } }
    }

    /// Optional error to throw
    private var _errorToThrow: YabaiExecutorError?
    var errorToThrow: YabaiExecutorError? {
        get { queue.sync { _errorToThrow } }
        set { queue.sync { _errorToThrow = newValue } }
    }

    func setQueryResponse<T: Encodable>(_ response: T, for args: [String]) {
        let key = args.joined(separator: " ")
        queue.sync {
            _queryResponses[key] = response
        }
    }

    func query<T: Decodable & Sendable>(_ args: [String]) async throws -> T {
        recordCommand(args)

        let error = queue.sync { _errorToThrow }
        if let error = error {
            throw error
        }

        let key = args.joined(separator: " ")
        let response = queue.sync { _queryResponses[key] }

        guard let response = response else {
            throw YabaiExecutorError.executionFailed("No mock response for: \(key)")
        }

        if let encodable = response as? Encodable {
            let data = try JSONEncoder().encode(AnyEncodable(encodable))
            return try JSONDecoder().decode(T.self, from: data)
        }

        throw YabaiExecutorError.decodingFailed("Invalid response type")
    }

    func execute(_ args: [String]) async throws {
        recordCommand(args)

        let error = queue.sync { _errorToThrow }
        if let error = error {
            throw error
        }
    }

    func isAvailable() async -> Bool {
        queue.sync { _available }
    }

    private func recordCommand(_ args: [String]) {
        queue.sync {
            _executedCommands.append(args)
        }
    }

    func reset() {
        queue.sync {
            _executedCommands.removeAll()
            _queryResponses.removeAll()
            _errorToThrow = nil
            _available = true
        }
    }
}

/// Type-erased Encodable wrapper
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}
