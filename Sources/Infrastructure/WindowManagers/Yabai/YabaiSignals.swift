import Foundation

/// The yabai events Stackline subscribes to: everything that can change which windows are
/// stacked, where the stacks are, or which window is on top.
enum YabaiSignal: String, CaseIterable, Sendable {
    case windowCreated = "window_created"
    case windowDestroyed = "window_destroyed"
    case windowFocused = "window_focused"
    case windowMoved = "window_moved"
    case windowResized = "window_resized"
    case windowMinimized = "window_minimized"
    case windowDeminimized = "window_deminimized"
    case applicationVisible = "application_visible"
    case applicationHidden = "application_hidden"
    case spaceChanged = "space_changed"
    case displayAdded = "display_added"
    case displayRemoved = "display_removed"
    case displayMoved = "display_moved"
    case displayResized = "display_resized"
    case missionControlExit = "mission_control_exit"
    case systemWoke = "system_woke"

    /// The environment variable yabai sets for this event whose value is forwarded with it.
    var payloadVariable: String? {
        self == .windowFocused ? "YABAI_WINDOW_ID" : nil
    }

    func event(payload: Int?) -> WindowManagerEvent {
        switch self {
        case .windowFocused:
            payload.map(WindowManagerEvent.windowFocused) ?? .windowsChanged
        case .displayAdded, .displayRemoved, .displayMoved, .displayResized, .systemWoke:
            .displaysChanged
        case .windowCreated, .windowDestroyed, .windowMoved, .windowResized, .windowMinimized,
             .windowDeminimized, .applicationVisible, .applicationHidden, .spaceChanged, .missionControlExit:
            .windowsChanged
        }
    }
}

/// How one Stackline instance registers itself with yabai.
///
/// Each signal's action pipes one line — `<event> [payload]` — into Stackline's event socket using
/// stock `nc`, so yabai never launches the Stackline binary. If nobody is listening (Stackline
/// crashed or was killed) the action removes its own signal, so yabai converges to a clean state
/// even when Stackline had no chance to clean up.
struct YabaiSubscription: Sendable {
    /// Every label Stackline has ever registered starts with this, which is what allows a fresh
    /// instance to sweep signals left behind by a dead one.
    static let labelPrefix = "stackline-"

    /// Distinguishes this instance's labels from a previous instance's, so a dying action of the
    /// old instance can never remove a signal the new one just registered.
    let token: String
    let eventSocketPath: String

    init(token: String = String(ProcessInfo.processInfo.processIdentifier), eventSocketPath: String) {
        self.token = token
        self.eventSocketPath = eventSocketPath
    }

    var labels: [String] {
        YabaiSignal.allCases.map(label)
    }

    func label(for signal: YabaiSignal) -> String {
        "\(Self.labelPrefix)\(token)-\(signal.rawValue)"
    }

    /// The shell command yabai runs for `signal`.
    ///
    /// - Parameter yabaiExecutable: Path of the running yabai binary, used for self-removal.
    func action(for signal: YabaiSignal, yabaiExecutable: String?) -> String {
        var message = signal.rawValue
        if let variable = signal.payloadVariable {
            message += " \"$\(variable)\""
        }

        var action = "echo \(message) | /usr/bin/nc -w 5 -U \(eventSocketPath.shellQuoted) 2>/dev/null"
        if let yabaiExecutable {
            action += " || \(yabaiExecutable.shellQuoted) -m signal --remove \(label(for: signal).shellQuoted) >/dev/null 2>&1"
        }
        return action
    }

    /// The arguments for `yabai -m` that register `signal`. Re-adding an existing label replaces it.
    func registration(for signal: YabaiSignal, yabaiExecutable: String?) -> [String] {
        [
            "signal", "--add",
            "event=\(signal.rawValue)",
            "label=\(label(for: signal))",
            "action=\(action(for: signal, yabaiExecutable: yabaiExecutable))",
        ]
    }

    /// Parses a line received on the event socket.
    static func event(from line: String) -> WindowManagerEvent? {
        let fields = line.split(separator: " ", maxSplits: 1)
        guard let name = fields.first, let signal = YabaiSignal(rawValue: String(name)) else { return nil }
        return signal.event(payload: fields.dropFirst().first.flatMap { Int($0) })
    }
}

extension String {
    /// The string as a single POSIX-shell word.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
