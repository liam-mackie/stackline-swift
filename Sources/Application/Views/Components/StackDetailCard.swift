import SwiftUI

struct StackDetailCard: View {
    let stack: WindowStack
    @ObservedObject var yabaiInterface: YabaiInterface
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stack \(stack.id)")
                        .font(.headline)
                    
                    HStack {
                        Text("Space \(stack.space)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        
                        Text("Display \(stack.display)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        
                        Text("\(stack.windows.count) windows")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                Button("Focus Stack") {
                    if let firstWindow = stack.windows.first {
                        Task {
                            try? await yabaiInterface.focusWindow(firstWindow.id)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            VStack(spacing: 8) {
                ForEach(Array(stack.windows.enumerated()), id: \.element.id) { index, window in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stack Index \(window.stackIndex)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(window.app)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(stack.visibleWindow?.id == window.id ? .blue : .primary)
                                
                                if stack.visibleWindow?.id == window.id {
                                    Image(systemName: "eye.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                }
                            }
                            
                            Text(window.title)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button("Focus") {
                            Task {
                                try? await yabaiInterface.focusWindow(window.id)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(stack.visibleWindow?.id == window.id ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}