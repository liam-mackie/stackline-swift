import AppKit

@main
enum StacklineApp {
    @MainActor
    static func main() {
        switch CommandLine.arguments.dropFirst().first {
        case "--version", "-v":
            print("Stackline \(version)")
        case "--help", "-h":
            print(usage)
        case let argument? where !argument.hasPrefix("-"):
            // Flags are left alone: the system and Xcode pass their own (-NS…, -Apple…, -psn…).
            FileHandle.standardError.write(Data("Unknown argument: \(argument)\n\n\(usage)\n".utf8))
            exit(EXIT_FAILURE)
        default:
            runApplication()
        }
    }

    @MainActor
    private static func runApplication() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // The bundled app is an agent via LSUIElement; this covers running the bare executable.
        application.setActivationPolicy(.accessory)
        application.run()
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "(development build)"
    }

    private static let usage = """
        Stackline - stack indicators for yabai

        Usage:
          stackline            Run as a menu bar application
          stackline --help     Show this help message
          stackline --version  Show the version
        """
}
