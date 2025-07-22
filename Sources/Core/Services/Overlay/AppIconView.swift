import SwiftUI
import AppKit

// MARK: - App Icon View

struct AppIconView: View {
    let appName: String
    let size: CGFloat
    
    @State private var appIcon: NSImage?
    
    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(appName.prefix(1)))
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            loadAppIcon()
        }
    }
    
    private func loadAppIcon() {
        Task {
            if let icon = await AppIconLoader.fetchAppIcon(for: appName) {
                await MainActor.run {
                    self.appIcon = icon
                }
            }
        }
    }
}

// MARK: - App Icon Loader

struct AppIconLoader {
    static func fetchAppIcon(for appName: String) async -> NSImage? {
        let workspace = NSWorkspace.shared
        
        // Try to find the running application first
        let runningApps = workspace.runningApplications
        if let runningApp = runningApps.first(where: { $0.localizedName == appName }) {
            if let bundleURL = runningApp.bundleURL {
                return workspace.icon(forFile: bundleURL.path)
            }
        }
        
        // Try to find app by bundle identifier
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appName) {
            return workspace.icon(forFile: appURL.path)
        }
        
        // Try to find app by searching in Applications folder
        let applicationFolders = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            "/System/Applications/Utilities"
        ]
        
        for folder in applicationFolders {
            let folderURL = URL(fileURLWithPath: folder)
            if let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                for appURL in contents {
                    if appURL.pathExtension == "app" {
                        let appDisplayName = appURL.deletingPathExtension().lastPathComponent
                        if appDisplayName == appName {
                            return workspace.icon(forFile: appURL.path)
                        }
                    }
                }
            }
        }
        
        // Try common bundle identifier patterns
        let possibleBundleIDs = [
            "com.apple.\(appName.lowercased())",
            "com.\(appName.lowercased()).\(appName.lowercased())",
            "org.\(appName.lowercased()).\(appName.lowercased())"
        ]
        
        for bundleID in possibleBundleIDs {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return workspace.icon(forFile: appURL.path)
            }
        }
        
        // Last resort: generic app icon
        if let genericAppURL = workspace.urlForApplication(toOpen: URL(fileURLWithPath: "/")) {
            return workspace.icon(forFile: genericAppURL.path)
        }
        
        return nil
    }
}