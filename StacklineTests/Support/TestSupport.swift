import Foundation
import Synchronization
import XCTest
@testable import Stackline

/// A scratch directory whose path is short enough to hold Unix socket addresses.
final class TemporaryDirectory {
    let path: String

    init() throws {
        var template = Array("/tmp/stackline-tests-XXXXXX".utf8CString)
        guard mkdtemp(&template) != nil else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        path = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    func file(_ name: String) -> String {
        "\(path)/\(name)"
    }
}

/// Polls `condition` until it holds. Returns false if it still does not after `timeout`.
func waitUntil(
    timeout: Duration = .seconds(5),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

/// Collects the elements of a stream as they arrive.
final class Recorder<Element: Sendable>: Sendable {
    private let storage = Mutex<[Element]>([])

    var elements: [Element] {
        storage.withLock { $0 }
    }

    func record(_ stream: AsyncStream<Element>) -> Task<Void, Never> {
        Task {
            for await element in stream {
                storage.withLock { $0.append(element) }
            }
        }
    }
}

/// Runs `command` the way yabai runs a signal action and returns its exit status.
@discardableResult
func runAsYabaiSignalAction(_ command: String, environment: [String: String] = [:]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["sh", "-c", command]
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

extension ManagedWindow {
    static func make(
        id: WindowIdentifier,
        frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
        space: Int = 1,
        display: Int = 1,
        stackIndex: Int = 0,
        processId: Int = 100,
        isVisible: Bool = true,
        isFocused: Bool = false,
        isFloating: Bool = false,
        isMinimized: Bool = false,
        isFullscreen: Bool = false
    ) -> ManagedWindow {
        ManagedWindow(
            id: id,
            processId: processId,
            applicationName: "App",
            frame: frame,
            spaceIndex: space,
            displayIndex: display,
            stackIndex: stackIndex,
            isVisible: isVisible,
            isFocused: isFocused,
            isFloating: isFloating,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen
        )
    }
}

extension DisplayGeometry {
    /// One 2560x1440 display.
    static let single = DisplayGeometry(
        screens: [CGRect(x: 0, y: 0, width: 2560, height: 1440)],
        primaryHeight: 1440
    )
}

extension WindowStack {
    static func make(
        _ windows: [ManagedWindow],
        screenFrame: CGRect = DisplayGeometry.single.screens[0]
    ) -> WindowStack {
        WindowStack(windows: windows, screenFrame: screenFrame)
    }
}
