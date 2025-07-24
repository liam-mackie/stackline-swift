import SwiftUI
import AppKit

struct SingletonErrorView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Stackline Already Running")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Another instance of Stackline is already running.")
                .font(.body)
                .multilineTextAlignment(.center)
            
            Text("This instance will close automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Close Now") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}