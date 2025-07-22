import SwiftUI

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Stackline")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Yabai Stack Indicator")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}