# Stackline

A Swift application that interfaces with [Yabai](https://github.com/koekeishiya/yabai) to display interactive stack indicators for stacked windows on macOS.

## Installation

### Prerequisites

- macOS 13.0 or later
- [Yabai](https://github.com/koekeishiya/yabai) installed and running

### Installing the pre-built binary

1. Download the DMG from [the releases](https://github.com/liam-mackie/stackline-swift/releases/latest)
2. Mount the DMG by double clicking
3. Drag the app from the DMG to the Applications folder
4. Run the application

The application is signed, notarized and stapled, so you should be able to just run from there!

### Building from Source

*Note: I recently swapped from using plain old swift to xcode to build a signed app bundle*

#### Prerequisites
* XCode 26+ (for the app icon)
  * It will compile with a lower version, but your mileage may vary

#### Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/liam-mackie/stackline-swift.git
   cd stackline-swift
   ```

2. Build the application:
   ```bash
   xcodebuild -scheme Stackline -configuration Release -derivedDataPath build
   ```

3. The built app will be located at:
   ```bash
   build/Build/Products/Release/Stackline.app
   ```

4. Copy it to your applications folder:
   ```bash
   cp -r build/Build/Products/Release/Stackline.app /Applications
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
/Applications/Stackline.app/Contents/MacOS/Stackline --cleanup
```

### Auto-start

To start Stackline automatically, ensure `stackline` is installed to your applications folder, then run it. In the behaviour section of configuration, tick "Launch at startup"

## Usage

### Interacting with Stacks
You can click on a stacked application's icon, pill or dot to swap to the application.

## Command Line Interface

Stackline supports several command-line options:

```bash
# Start the application
/Applications/Stackline.app/Contents/MacOS/Stackline

# Handle a signal from Yabai (used internally by automatic signal setup)
/Applications/Stackline.app/Contents/MacOS/Stackline handle-signal window_created

# Show version information
/Applications/Stackline.app/Contents/MacOS/Stackline --version

# Show help
/Applications/Stackline.app/Contents/MacOS/Stackline --help

# Test signal system
/Applications/Stackline.app/Contents/MacOS/Stackline --test-client

# Clean up yabai signals
/Applications/Stackline.app/Contents/MacOS/Stackline --cleanup
```

## Development

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

## Acknowledgments

- [Stackline](https://github.com/AdamWagner/stackline) by @AdamWagner - this was one of the main reasons I wanted to make this
- [Yabai](https://github.com/koekeishiya/yabai) by @koekeishiya - Yabai is essential to my workflow, as well as many others around the world
- Apple's SwiftUI framework for making this a relatively simple step into making a UI based app