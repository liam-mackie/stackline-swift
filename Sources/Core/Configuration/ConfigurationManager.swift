import SwiftUI
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "configuration-manager")

// MARK: - Configuration Manager

@MainActor
final class ConfigurationManager: ObservableObject {
    @Published var config: StacklineConfiguration
    
    private let configURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let stacklineDir = appSupport.appendingPathComponent("Stackline")
        
        do {
            try FileManager.default.createDirectory(at: stacklineDir, withIntermediateDirectories: true)
            logger.debug("Configuration directory created/verified at: \(stacklineDir.path)")
        } catch {
            logger.error("Failed to create configuration directory: \(error.localizedDescription)")
        }
        
        configURL = stacklineDir.appendingPathComponent("config.json")
        
        self.config = Self.loadConfiguration(from: configURL) ?? .default
        logger.info("Configuration manager initialized with config at: \(self.configURL.path)")
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            logger.debug("Configuration saved to \(self.configURL.path)")
        } catch {
            logger.error("Failed to save configuration: \(error.localizedDescription)")
        }
    }
    
    func reset() {
        config = .default
        save()
        logger.info("Configuration reset to defaults")
    }
    
    private static func loadConfiguration(from url: URL) -> StacklineConfiguration? {
        guard let data = try? Data(contentsOf: url) else { 
            logger.debug("No existing configuration file found")
            return nil 
        }
        
        do {
            let config = try JSONDecoder().decode(StacklineConfiguration.self, from: data)
            logger.info("Successfully loaded configuration from file")
            return config
        } catch {
            logger.error("Failed to load configuration: \(error.localizedDescription)")
            logger.info("Resetting configuration to defaults...")
            
            do {
                try FileManager.default.removeItem(at: url)
                logger.debug("Removed corrupted configuration file")
            } catch {
                logger.warning("Could not remove corrupted configuration file: \(error.localizedDescription)")
            }
            
            return nil
        }
    }
    
    // MARK: - Convenience Methods
    
    func updateAppearance<T>(_ keyPath: WritableKeyPath<AppearanceConfig, T>, value: T) {
        config.appearance[keyPath: keyPath] = value
        save()
    }
    
    func updatePositioning<T>(_ keyPath: WritableKeyPath<PositioningConfig, T>, value: T) {
        config.positioning[keyPath: keyPath] = value
        save()
    }
    
    func updateBehavior<T>(_ keyPath: WritableKeyPath<BehaviorConfig, T>, value: T) {
        config.behavior[keyPath: keyPath] = value
        save()
    }
    
}