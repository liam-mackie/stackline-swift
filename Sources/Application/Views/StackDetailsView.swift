import SwiftUI

struct StackDetailsView: View {
    @ObservedObject var coordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section - fixed at top
            HStack {
                Text("Detected Stacks")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(coordinator.stackDetector.detectedStacks.count) stacks found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Refresh") {
                    coordinator.stackDetector.forceStackDetection()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.windowBackgroundColor))
            
            // Scrollable content area
            ScrollView {
                LazyVStack(spacing: 16) {
                    if coordinator.stackDetector.detectedStacks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No stacks detected")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Create stacks in Yabai to see them here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(coordinator.stackDetector.detectedStacks) { stack in
                            StackDetailCard(stack: stack, yabaiInterface: coordinator.yabaiInterface)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            coordinator.stackDetector.forceStackDetection()
        }
    }
}