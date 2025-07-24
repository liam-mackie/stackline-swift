import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "launch-agent")

// MARK: - Launch Agent Management

extension ConfigurationManager {
    private var launchAgentURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let launchAgentsURL = libraryURL.appendingPathComponent("LaunchAgents")
        return launchAgentsURL.appendingPathComponent("sh.mackie.stackline.plist")
    }
    
    private var currentExecutablePath: String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return bundlePath
        } else if let executablePath = Bundle.main.executablePath {
            return executablePath
        } else {
            return CommandLine.arguments.first ?? "/usr/local/bin/stackline"
        }
    }
    
    func updateLaunchAtStartup(_ enabled: Bool) {
        config.behavior.launchAtStartup = enabled
        save()
        
        if enabled {
            createLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }
    
    private func createLaunchAgent() {
        do {
            let launchAgentsDir = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            
            let plistContent = createLaunchAgentPlist()
            
            try plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            logger.info("Created LaunchAgent at: \(self.launchAgentURL.path)")
            
            loadLaunchAgent()
            
        } catch {
            logger.error("Failed to create LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    private func removeLaunchAgent() {
        do {
            unloadLaunchAgent()
            
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
                logger.info("Removed LaunchAgent from: \(self.launchAgentURL.path)")
            }
        } catch {
            logger.error("Failed to remove LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    private func createLaunchAgentPlist() -> String {
        var executablePath = currentExecutablePath
        
        if executablePath .hasSuffix(".app") {
            executablePath = "\(executablePath)/Contents/MacOS/stackline"
        }
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>sh.mackie.stackline</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>LimitLoadToSessionType</key>
            <array>
                <string>Aqua</string>
            </array>
        </dict>
        </plist>
        """
    }
    
    private func loadLaunchAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", launchAgentURL.path]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logger.info("Successfully loaded LaunchAgent")
            } else {
                logger.warning("Failed to load LaunchAgent with launchctl")
            }
        } catch {
            logger.error("Error loading LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    private func unloadLaunchAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["unload", launchAgentURL.path]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logger.debug("Successfully unloaded LaunchAgent")
            } else {
                logger.debug("LaunchAgent was not loaded (this is normal)")
            }
        } catch {
            logger.error("Error unloading LaunchAgent: \(error.localizedDescription)")
        }
    }
    
    func checkLaunchAgentStatus() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }
    
    func syncLaunchAgentStatus() {
        let exists = checkLaunchAgentStatus()
        if config.behavior.launchAtStartup != exists {
            logger.info("Syncing launch agent status: config=\(self.config.behavior.launchAtStartup), exists=\(exists)")
            config.behavior.launchAtStartup = exists
            save()
        }
    }
}
