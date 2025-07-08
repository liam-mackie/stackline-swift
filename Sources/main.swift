import SwiftUI
import AppKit
import Foundation
import os

// MARK: - Logging

private let logger = Logger(subsystem: "sh.mackie.stackline", category: "main")

// MARK: - Command Line Interface

func handleCommandLineArgs() {
    let args = CommandLine.arguments
    
    // Handle version flag
    if args.contains("--version") || args.contains("-v") {
        print("Stackline v1.0.0")
        exit(0)
    }
    
    // Handle help flag
    if args.contains("--help") || args.contains("-h") {
        showHelp()
        exit(0)
    }
    
    // Handle signal processing (called by Yabai)
    if args.contains("handle-signal") {
        handleSignalCommand(args)
        exit(0)
    }
    
    // Handle daemon mode
    if args.contains("--daemon") || args.contains("-d") {
        runDaemon()
        exit(0)
    }
    
    // Handle test client mode
    if args.contains("--test-client") {
        testSignalClient()
        exit(0)
    }
    
    // Handle cleanup mode
    if args.contains("--cleanup") {
        cleanupStacklineSignals()
        exit(0)
    }
}

func showHelp() {
    print("""
    Stackline - Yabai Stack Indicator v1.0.0
    
    USAGE:
        stackline [OPTIONS]
    
    OPTIONS:
        --daemon, -d             Run in daemon mode (background process)
        handle-signal <event>    Send signal to running stackline instance
        --test-client           Test signal client connection
        --cleanup               Remove all stackline signals from yabai
        --version, -v           Show version information
        --help, -h              Show this help message
    
    EXAMPLES:
        stackline                           # Run with GUI
        stackline --daemon                  # Run in background
        stackline handle-signal window_focused    # Send signal to running instance
        stackline --test-client             # Test signal client connection
        stackline --cleanup                 # Remove all stackline signals from yabai
    
    YABAI INTEGRATION:
        Stackline automatically sets up Yabai signals! No manual configuration needed.
        
    """)
}

func handleSignalCommand(_ args: [String]) {
    guard args.count >= 2 else {
        logger.error("Usage: stackline handle-signal <event>")
        print("Usage: stackline handle-signal <event>")
        exit(1)
    }
    
    let event = args[1]
    
    // Send signal directly via distributed notification
    DistributedNotificationCenter.default().post(
        name: Notification.Name("StacklineExternalSignal"),
        object: event
    )
    
    logger.info("Signal '\(event)' sent successfully")
    print("Signal '\(event)' sent successfully")
}

func runDaemon() {
    logger.info("Starting Stackline daemon...")
    print("Starting Stackline daemon...")
    
    // Run the SwiftUI app in daemon mode
    // This will start the signal manager automatically
    StacklineApp.main()
}

func testSignalClient() {
    logger.info("Testing signal system...")
    print("Testing signal system...")
    
    // Test direct signal posting
    logger.debug("Testing direct signal posting...")
    print("Testing direct signal posting...")
    DistributedNotificationCenter.default().post(
        name: Notification.Name("StacklineExternalSignal"),
        object: "test_signal"
    )
    logger.info("✓ Direct signal posting works")
    print("✓ Direct signal posting works")
    
    logger.info("✓ Signal system test completed")
    print("✓ Signal system test completed")
}

// MARK: - Signal Management Helper

func addYabaiSignals() {
    logger.info("Adding Yabai signals...")
    print("Adding Yabai signals...")
    
    let signals = [
        "window_focused",
        "window_moved",
        "window_resized",
        "window_destroyed",
        "window_created",
        "space_changed"
    ]
    
    for signal in signals {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["-m", "signal", "--add", "event=\(signal)", "action=stackline handle-signal \(signal)"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logger.info("✓ Added signal: \(signal)")
                print("✓ Added signal: \(signal)")
            } else {
                logger.error("✗ Failed to add signal: \(signal)")
                print("✗ Failed to add signal: \(signal)")
            }
        } catch {
            logger.error("✗ Error adding signal \(signal): \(error.localizedDescription)")
            print("✗ Error adding signal \(signal): \(error)")
        }
    }
}

func removeYabaiSignals() {
    logger.info("Removing Yabai signals...")
    print("Removing Yabai signals...")
    
    let signals = [
        "window_focused",
        "window_moved",
        "window_resized",
        "window_destroyed",
        "window_created",
        "space_changed"
    ]
    
    for signal in signals {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yabai")
        task.arguments = ["-m", "signal", "--remove", "event=\(signal)"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                logger.info("✓ Removed signal: \(signal)")
                print("✓ Removed signal: \(signal)")
            } else {
                logger.warning("✗ Failed to remove signal: \(signal)")
                print("✗ Failed to remove signal: \(signal)")
            }
        } catch {
            logger.error("✗ Error removing signal \(signal): \(error.localizedDescription)")
            print("✗ Error removing signal \(signal): \(error)")
        }
    }
}

func cleanupStacklineSignals() {
    logger.info("Cleaning up Stackline signals...")
    print("Cleaning up Stackline signals...")
    let yabaiInterface = YabaiInterface()
    yabaiInterface.performSignalCleanup(timeout: 20.0)
}

// MARK: - Main Entry Point

// Handle command line arguments first
handleCommandLineArgs()

// If no special flags, run the SwiftUI app
StacklineApp.main() 
