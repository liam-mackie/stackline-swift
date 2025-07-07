# Stackline

A Swift application that interfaces with [Yabai](https://github.com/koekeishiya/yabai) to display interactive stack indicators for stacked windows on macOS.

## Installation

### Prerequisites

- macOS 13.0 or later
- [Yabai](https://github.com/koekeishiya/yabai) installed and running
- Swift 6+ (for building from source)

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/liam-mackie/stackline-swift.git
   cd stackline-swift
   ```

2. Build the application:
   ```bash
   swift build --configuration release
   ```

3. The built executable will be located at:
   ```bash
   .build/release/stackline
   ```

4. Copy it to your PATH:
   ```bash
   cp .build/release/stackline /usr/local/bin/
   ```

## Configuration

### Yabai Setup

Stackline automatically sets up Yabai signals for you! When you start Stackline, it will:

1. **Remove any old Stackline signals** (identified by `mackie-sh-stackline`)
2. **Add new signals** with the correct path to your current Stackline binary
3. **Periodically check** that signals are properly configured

**Manual Signal Setup**:
You can also manually trigger signal setup from the Stackline interface by clicking the "Setup Yabai Signals" button in the Status tab.

**Signal Cleanup**:
Stackline automatically removes its signals when terminating normally with a 20-second timeout. For manual cleanup (e.g., after an unclean shutdown), you can run:
```bash
stackline --cleanup
```

### Auto-start

To start Stackline automatically, ensure `stackline` is installed to your path, then run it. In the behaviour section of configuration, tick "Launch at startup"

## Usage

### Starting the Application

Run Stackline from the command line:
```bash
stackline
```

Or simply double-click the executable.

### Interacting with Stacks
You can click on a stacked application's icon, pill or dot to swap to the application.

## Command Line Interface

Stackline supports several command-line options:

```bash
# Start the application
stackline

# Handle a signal from Yabai (used internally by automatic signal setup)
stackline handle-signal window_created

# Show version information
stackline --version

# Show help
stackline --help

# Test signal system
stackline --test-client

# Clean up yabai signals
stackline --cleanup
```

## Development

### Building and Testing

```bash
# Build in debug mode
swift build

# Run tests
swift test

# Build for release
swift build --configuration release

# Run the application
swift run stackline
```

### Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable (I haven't)
5. Submit a pull request

## Requirements

- **macOS**: 13.0+ (Ventura or later) - tested on `15.5 (24F74)`.
- **Yabai**: Any recent version - tested with `yabai-v7.1.15`
- **Architecture**: Intel x86_64 or Apple Silicon (universal binary support)

## License

This project is licensed under the Apache 2 License. See the LICENSE file for details.

## Acknowledgments

- [Stackline](https://github.com/AdamWagner/stackline) by @AdamWagner - this was one of the main reasons I wanted to make this
- [Yabai](https://github.com/koekeishiya/yabai) by @koekeishiya - Yabai is essential to my workflow, as well as many others around the world
- Apple's SwiftUI framework for making this a relatively simple step into making a UI based app