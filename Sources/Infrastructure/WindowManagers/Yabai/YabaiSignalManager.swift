import Foundation

/// Manages Yabai signal registration and cleanup
actor YabaiSignalManager {
    private let executor: YabaiCommandExecuting
    private let signalIdentifier: String
    private let executablePath: String
    private var registeredSignals: Set<YabaiSignal> = []

    /// Yabai signals that Stackline listens to
    enum YabaiSignal: String, CaseIterable, Sendable {
        case windowFocused = "window_focused"
        case windowMoved = "window_moved"
        case windowResized = "window_resized"
        case windowCreated = "window_created"
        case windowDestroyed = "window_destroyed"
        case spaceChanged = "space_changed"

        var environmentVariables: [String] {
            switch self {
            case .windowFocused, .windowMoved, .windowResized,
                 .windowCreated, .windowDestroyed:
                return ["YABAI_WINDOW_ID"]
            case .spaceChanged:
                return ["YABAI_SPACE_ID"]
            }
        }
    }

    init(
        executor: YabaiCommandExecuting,
        signalIdentifier: String = "stackline",
        executablePath: String? = nil
    ) {
        self.executor = executor
        self.signalIdentifier = signalIdentifier
        self.executablePath = executablePath ?? ProcessInfo.processInfo.arguments.first ?? "/usr/local/bin/stackline"
    }

    /// Register all signals with Yabai
    func registerSignals() async throws {
        for signal in YabaiSignal.allCases {
            try await registerSignal(signal)
        }
    }

    /// Unregister all signals from Yabai
    func unregisterSignals() async {
        let signals = registeredSignals

        for signal in signals {
            try? await unregisterSignal(signal)
        }
    }

    private func registerSignal(_ signal: YabaiSignal) async throws {
        let label = "\(signalIdentifier)-\(signal.rawValue)"
        // Note: Do NOT escape the $ - yabai needs to expand $YABAI_WINDOW_ID at runtime
        let envVars = signal.environmentVariables.map { "$\($0)" }.joined(separator: " ")
        let action = envVars.isEmpty
            ? "\(executablePath) handle-signal \(signal.rawValue)"
            : "\(executablePath) handle-signal \(signal.rawValue) \(envVars)"

        try await executor.execute([
            "-m", "signal", "--add",
            "event=\(signal.rawValue)",
            "label=\(label)",
            "action=\(action)"
        ])

        registeredSignals.insert(signal)
    }

    private func unregisterSignal(_ signal: YabaiSignal) async throws {
        let label = "\(signalIdentifier)-\(signal.rawValue)"

        try await executor.execute([
            "-m", "signal", "--remove",
            label
        ])

        registeredSignals.remove(signal)
    }
}
