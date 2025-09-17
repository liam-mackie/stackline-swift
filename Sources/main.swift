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
    guard args.count >= 3 else {
        logger.error("Usage: stackline handle-signal <event>")
        print("Usage: stackline handle-signal <event>")
        exit(1)
    }

    let event = args[2]

    // Send signal via socket
    let message = "signal:\(event)"
    let success = SimpleSocketClient.sendMessage(message)

    if success {
        logger.info("Signal '\(event)' sent successfully")
        print("Signal '\(event)' sent successfully")
    } else {
        logger.error("Failed to send signal '\(event)' - is Stackline running?")
        print("Failed to send signal '\(event)' - is Stackline running?")
        exit(1)
    }
}

func runDaemon() {
    logger.info("Starting Stackline daemon...")
    print("Starting Stackline daemon...")
    
    // Run the SwiftUI app in daemon mode
    // This will start the signal manager automatically
    StacklineApp.main()
}

func testSignalClient() {
    logger.info("Testing socket system...")
    print("Testing socket system...")

    // Test socket connection
    logger.debug("Testing socket connection...")
    print("Testing socket connection...")

    if SimpleSocketClient.ping() {
        logger.info("✓ Socket connection successful")
        print("✓ Socket connection successful")

        // Test sending a signal
        if SimpleSocketClient.sendMessage("signal:test_signal") {
            logger.info("✓ Test signal sent successfully")
            print("✓ Test signal sent successfully")
        } else {
            logger.error("✗ Failed to send test signal")
            print("✗ Failed to send test signal")
        }
    } else {
        logger.error("✗ Socket connection failed - is Stackline running?")
        print("✗ Socket connection failed - is Stackline running?")
        exit(1)
    }

    logger.info("✓ Socket system test completed")
    print("✓ Socket system test completed")
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
