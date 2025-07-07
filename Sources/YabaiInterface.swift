import Foundation
import Combine
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "yabai")

class YabaiInterface: ObservableObject {
    private let jsonDecoder = JSONDecoder()
    private let defaultYabaiPath = "/opt/homebrew/bin/yabai"
    private var yabaiPath: String
    @Published var isConnected: Bool = false
    @Published var lastError: String?
    
    init() {
        // Attempt to find the yabai executable
        self.yabaiPath = ""
        self.yabaiPath = self.findYabaiExecutable() ?? defaultYabaiPath
        logger.debug("Yabai path set to: \(self.yabaiPath)")
        checkYabaiConnection()
    }
    
    // MARK: - Connection Management
    
    private func checkYabaiConnection() {
        Task {
            do {
                _ = try await queryWindows()
                await MainActor.run {
                    self.isConnected = true
                    self.lastError = nil
                    logger.info("Successfully connected to Yabai")
                }
            } catch {
                await MainActor.run {
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    logger.error("Failed to connect to Yabai: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Query Operations
    
    func queryWindows() async throws -> [YabaiWindow] {
        let result = try await executeYabaiCommand(["query", "--windows"])
        return try jsonDecoder.decode([YabaiWindow].self, from: result)
    }
    
    func querySpaces() async throws -> [YabaiSpace] {
        let result = try await executeYabaiCommand(["query", "--spaces"])
        return try jsonDecoder.decode([YabaiSpace].self, from: result)
    }
    
    func queryDisplays() async throws -> [YabaiDisplay] {
        let result = try await executeYabaiCommand(["query", "--displays"])
        return try jsonDecoder.decode([YabaiDisplay].self, from: result)
    }
    
    func queryCurrentSpace() async throws -> YabaiSpace {
        let result = try await executeYabaiCommand(["query", "--spaces", "--space"])
        return try jsonDecoder.decode(YabaiSpace.self, from: result)
    }
    
    func queryCurrentDisplay() async throws -> YabaiDisplay {
        let result = try await executeYabaiCommand(["query", "--displays", "--display"])
        return try jsonDecoder.decode(YabaiDisplay.self, from: result)
    }
    
    func queryWindowsOnSpace(_ spaceIndex: Int) async throws -> [YabaiWindow] {
        let result = try await executeYabaiCommand(["query", "--windows", "--space", "\(spaceIndex)"])
        return try jsonDecoder.decode([YabaiWindow].self, from: result)
    }
    
    func queryWindowsOnDisplay(_ displayIndex: Int) async throws -> [YabaiWindow] {
        let result = try await executeYabaiCommand(["query", "--windows", "--display", "\(displayIndex)"])
        return try jsonDecoder.decode([YabaiWindow].self, from: result)
    }
    
    // MARK: - Window Control Operations
    
    func focusWindow(_ windowId: Int) async throws {
        _ = try await executeYabaiCommand(["window", "\(windowId)", "--focus"])
    }
    
    func moveWindowToSpace(_ windowId: Int, space: Int) async throws {
        _ = try await executeYabaiCommand(["window", "\(windowId)", "--space", "\(space)"])
    }
    
    func moveWindowToDisplay(_ windowId: Int, display: Int) async throws {
        _ = try await executeYabaiCommand(["window", "\(windowId)", "--display", "\(display)"])
    }
    
    func swapWindows(_ windowId1: Int, _ windowId2: Int) async throws {
        _ = try await executeYabaiCommand(["window", "\(windowId1)", "--swap", "\(windowId2)"])
    }
    
    func warpWindow(_ windowId: Int, direction: String) async throws {
        _ = try await executeYabaiCommand(["window", "\(windowId)", "--warp", direction])
    }
    
    func toggleWindowFloat(_ windowId: Int) async throws {
        _ = try await executeYabaiCommand(["window", "\(windowId)", "--toggle", "float"])
    }
    
    // MARK: - Stack Operations
    
    func cycleStackFocus(_ windowIds: [Int]) async throws {
        guard windowIds.count > 1 else { return }
        
        // Find the currently focused window in the stack
        let windows = try await queryWindows()
        let stackWindows = windows.filter { windowIds.contains($0.id) }
        
        if let focusedWindow = stackWindows.first(where: { $0.isFocused }) {
            // Find the next window in the stack
            if let focusedIndex = windowIds.firstIndex(of: focusedWindow.id) {
                let nextIndex = (focusedIndex + 1) % windowIds.count
                let nextWindowId = windowIds[nextIndex]
                try await focusWindow(nextWindowId)
            }
        } else if let firstWindowId = windowIds.first {
            // No focused window in stack, focus the first one
            try await focusWindow(firstWindowId)
        }
    }
    
    func bringStackWindowToFront(_ windowId: Int) async throws {
        try await focusWindow(windowId)
    }
    
    // MARK: - Signal Management
    
    func addSignal(event: String, action: String) async throws {
        _ = try await executeYabaiCommand(["signal", "--add", "event=\(event)", "action=\(action)"])
    }
    
    func removeSignal(event: String) async throws {
        _ = try await executeYabaiCommand(["signal", "--remove", "event=\(event)"])
    }
    
    func querySignals() async throws -> [YabaiSignal] {
        let result = try await executeYabaiCommand(["signal", "--list"])
        return try jsonDecoder.decode([YabaiSignal].self, from: result)
    }
    
    func removeSignalByAction(action: String) async throws {
        _ = try await executeYabaiCommand(["signal", "--remove", "action=\(action)"])
    }
    
    func removeSignalByIndex(_ index: Int) async throws {
        _ = try await executeYabaiCommand(["signal", "--remove", "\(index)"])
    }
    
    // MARK: - Signal Cleanup Utility
    
    func performSignalCleanup(timeout: TimeInterval) {
        let semaphore = DispatchSemaphore(value: 0)
        var cleanupCompleted = false
        
        let cleanupTask = Task {
            do {
                let signals = try await self.querySignals()
                
                // Find signals that contain our identifier
                let ourSignals = signals.filter { signal in
                    signal.action.contains("mackie-sh-stackline")
                }
                
                if ourSignals.isEmpty {
                    logger.info("No Stackline signals found to remove")
                } else {
                    logger.info("Found \(ourSignals.count) Stackline signals to remove")
                    
                    // Remove signals from highest index to lowest to avoid index shifting
                    let sortedSignals = ourSignals.sorted { $0.index > $1.index }
                    for signal in sortedSignals {
                        do {
                            try await self.removeSignalByIndex(signal.index)
                            logger.debug("✓ Removed signal: \(signal.event) (index \(signal.index))")
                        } catch {
                            logger.error("✗ Failed to remove signal \(signal.event) at index \(signal.index): \(error.localizedDescription)")
                        }
                    }
                }
                
                logger.info("Signal cleanup completed")
            } catch {
                logger.error("✗ Error during signal cleanup: \(error.localizedDescription)")
            }
            
            cleanupCompleted = true
            semaphore.signal()
        }
        
        // Wait for completion or timeout
        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        
        if timeoutResult == .timedOut {
            logger.warning("⚠️ Signal cleanup timed out after \(timeout) seconds")
            cleanupTask.cancel()
        } else if cleanupCompleted {
            logger.info("✓ Signal cleanup completed successfully")
        }
    }
    
    // MARK: - Command Execution
    
    private func executeYabaiCommand(_ arguments: [String]) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: yabaiPath)
            process.arguments = ["-m"] + arguments
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: YabaiError.commandFailed(errorMessage))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: YabaiError.processError(error))
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func isYabaiRunning() async -> Bool {
        do {
            _ = try await executeYabaiCommand(["query", "--spaces"])
            return true
        } catch {
            return false
        }
    }
    
    func getYabaiVersion() async throws -> String {
        let result = try await executeYabaiCommand(["--version"])
        return String(data: result, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
    }
}

// MARK: - Error Types

enum YabaiError: Error, LocalizedError {
    case commandFailed(String)
    case processError(Error)
    case notConnected
    case jsonParsingError
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Yabai command failed: \(message)"
        case .processError(let error):
            return "Process error: \(error.localizedDescription)"
        case .notConnected:
            return "Not connected to Yabai"
        case .jsonParsingError:
            return "Failed to parse JSON response from Yabai"
        }
    }
}

// MARK: - Extensions

extension YabaiInterface {
    func findYabaiExecutable() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai",
            "/usr/bin/yabai",
            "/bin/yabai"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                logger.debug("Found yabai executable at: \(path)")
                return path
            }
        }
        
        // Try to find yabai in PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yabai"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path {
                    logger.debug("Found yabai executable via PATH: \(path)")
                    return path
                }
            }
        } catch {
            logger.error("Error finding yabai executable: \(error.localizedDescription)")
        }
        
        logger.warning("Could not find yabai executable in standard locations")
        return nil
    }
} 
