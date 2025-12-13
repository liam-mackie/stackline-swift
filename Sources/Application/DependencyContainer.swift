import Foundation

/// Central dependency injection container for the application
@MainActor
final class DependencyContainer {
    static let shared = DependencyContainer()

    // MARK: - Infrastructure

    lazy var preferences: UserDefaultsPreferences = {
        UserDefaultsPreferences()
    }()

    lazy var loggingService: LoggingService = {
        LoggingService.shared
    }()

    // MARK: - Window Manager

    lazy var windowManager: YabaiWindowManager = {
        YabaiWindowManager()
    }()

    // MARK: - Coordinate System

    lazy var coordinateSystem: CoordinateSystemProtocol = {
        CoreGraphicsCoordinateSystem()
    }()

    // MARK: - Stack Detection

    lazy var stackDetector: StackDetector = {
        StackDetector(
            windowManager: windowManager,
            coordinateSystem: coordinateSystem
        )
    }()

    // MARK: - UI

    lazy var indicatorCoordinator: IndicatorCoordinator = {
        IndicatorCoordinator(
            stackDetector: stackDetector,
            windowManager: windowManager,
            preferences: preferences,
            coordinateSystem: coordinateSystem
        )
    }()

    private init() {}

    // MARK: - Lifecycle

    func initialize() async throws {
        loggingService.info("Initializing Stackline...", category: .app)

        do {
            try await windowManager.connect()
            loggingService.info("Connected to Yabai", category: .windowManager)
        } catch {
            loggingService.error("Failed to connect to Yabai: \(error)", category: .windowManager)
            throw error
        }

        await stackDetector.startMonitoring()
        loggingService.info("Stack detection started", category: .stackDetection)

        indicatorCoordinator.start()
        loggingService.info("Indicator coordinator started", category: .indicators)

        loggingService.info("Stackline initialized successfully", category: .app)
    }

    func shutdown() async {
        loggingService.info("Shutting down Stackline...", category: .app)

        indicatorCoordinator.stop()
        stackDetector.stopMonitoring()
        await windowManager.disconnect()

        loggingService.info("Stackline shutdown complete", category: .app)
    }
}
