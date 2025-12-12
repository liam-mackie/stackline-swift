import Foundation
import Synchronization

/// Errors that can occur during Yabai command execution
enum YabaiExecutorError: Error, Sendable {
    case yabaiNotFound
    case executionFailed(String)
    case decodingFailed(String)
    case timeout
}

/// Protocol for executing Yabai commands (enables testing with mocks)
protocol YabaiCommandExecuting: Sendable {
    /// Execute a query command and decode the JSON response
    func query<T: Decodable & Sendable>(_ args: [String]) async throws -> T

    /// Execute a command that doesn't return data
    func execute(_ args: [String]) async throws

    /// Check if Yabai is available
    func isAvailable() async -> Bool
}

/// Production implementation that shells out to the Yabai binary
final class YabaiCommandExecutor: YabaiCommandExecuting, @unchecked Sendable {
    private let yabaiPath: String
    private let timeout: TimeInterval
    private let decoder: JSONDecoder

    /// Common paths where yabai might be installed
    private static let commonPaths = [
        "/opt/homebrew/bin/yabai",      // Apple Silicon Homebrew
        "/usr/local/bin/yabai",          // Intel Homebrew
        "/run/current-system/sw/bin/yabai", // NixOS
    ]

    init(yabaiPath: String? = nil, timeout: TimeInterval = 5.0) {
        self.yabaiPath = yabaiPath ?? Self.findYabai() ?? "/opt/homebrew/bin/yabai"
        self.timeout = timeout
        self.decoder = JSONDecoder()
    }

    private static func findYabai() -> String? {
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try using `which` as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yabai"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Ignore errors, will fall back to default
        }

        return nil
    }

    func query<T: Decodable & Sendable>(_ args: [String]) async throws -> T {
        let output = try await run(args)

        guard let data = output.data(using: .utf8) else {
            throw YabaiExecutorError.decodingFailed("Invalid UTF-8 output")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw YabaiExecutorError.decodingFailed("JSON decode failed: \(error.localizedDescription)")
        }
    }

    func execute(_ args: [String]) async throws {
        _ = try await run(args)
    }

    func isAvailable() async -> Bool {
        do {
            _ = try await run(["-m", "query", "--spaces"])
            return true
        } catch {
            return false
        }
    }

    private func run(_ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: yabaiPath)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            if (error as NSError).domain == NSCocoaErrorDomain &&
               (error as NSError).code == NSFileNoSuchFileError {
                throw YabaiExecutorError.yabaiNotFound
            }
            throw YabaiExecutorError.executionFailed("Failed to launch: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let hasResumed = Mutex(false)

            @Sendable func resumeOnce(with result: Result<String, Error>) {
                let shouldResume = hasResumed.withLock { resumed -> Bool in
                    if resumed { return false }
                    resumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(with: result)
                }
            }

            DispatchQueue.global().async {
                let timeoutWorkItem = DispatchWorkItem {
                    process.terminate()
                    resumeOnce(with: .failure(YabaiExecutorError.timeout))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + self.timeout, execute: timeoutWorkItem)

                process.waitUntilExit()
                timeoutWorkItem.cancel()

                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    resumeOnce(with: .failure(YabaiExecutorError.executionFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))))
                    return
                }

                let output = String(data: outputData, encoding: .utf8) ?? ""
                resumeOnce(with: .success(output))
            }
        }
    }
}
