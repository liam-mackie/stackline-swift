import SwiftUI
import Combine

struct StacklineOverlay: View {
    @ObservedObject var stackDetector: StackDetector
    @ObservedObject var yabaiInterface: YabaiInterface
    
    @State private var currentSpace: Int = 1
    @State private var currentDisplay: Int = 1
    @State private var hoveredStack: String?
    @State private var isDragging: Bool = false
    @State private var overlayPosition: CGPoint = CGPoint(x: 20, y: 100)
    
    private let stackButtonSize: CGFloat = 50
    private let stackButtonSpacing: CGFloat = 8
    private let overlayBackgroundColor = Color.black.opacity(0.8)
    private let overlayCornerRadius: CGFloat = 12
    
    var body: some View {
        VStack(spacing: 0) {
            if !stackDetector.detectedStacks.isEmpty {
                StackIndicatorView(
                    stacks: stacksForCurrentSpace,
                    yabaiInterface: yabaiInterface,
                    hoveredStack: $hoveredStack,
                    stackButtonSize: stackButtonSize,
                    stackButtonSpacing: stackButtonSpacing
                )
                .background(overlayBackgroundColor)
                .cornerRadius(overlayCornerRadius)
                .shadow(radius: 8)
            }
        }
        .position(overlayPosition)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    overlayPosition = value.location
                }
                .onEnded { _ in
                    isDragging = false
                    // Snap to screen edges
                    snapToEdge()
                }
        )
        .onAppear {
            updateCurrentSpaceAndDisplay()
        }
        .onReceive(stackDetector.$detectedStacks) { _ in
            updateCurrentSpaceAndDisplay()
        }
    }
    
    private var stacksForCurrentSpace: [WindowStack] {
        return stackDetector.detectedStacks.filter { stack in
            stack.space == currentSpace && stack.display == currentDisplay
        }
    }
    
    private func updateCurrentSpaceAndDisplay() {
        Task {
            do {
                let space = try await yabaiInterface.queryCurrentSpace()
                let display = try await yabaiInterface.queryCurrentDisplay()
                
                await MainActor.run {
                    currentSpace = space.index
                    currentDisplay = display.index
                }
            } catch {
                print("Error getting current space/display: \(error)")
            }
        }
    }
    
    private func snapToEdge() {
        let screenBounds = NSScreen.main?.frame ?? CGRect.zero
        let margin: CGFloat = 20
        
        // Determine which edge to snap to
        let distanceToLeft = overlayPosition.x
        let distanceToRight = screenBounds.width - overlayPosition.x
        let distanceToTop = overlayPosition.y
        let distanceToBottom = screenBounds.height - overlayPosition.y
        
        let minDistance = min(distanceToLeft, distanceToRight, distanceToTop, distanceToBottom)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if minDistance == distanceToLeft {
                // Snap to left edge
                overlayPosition.x = margin
            } else if minDistance == distanceToRight {
                // Snap to right edge
                overlayPosition.x = screenBounds.width - margin
            } else if minDistance == distanceToTop {
                // Snap to top edge
                overlayPosition.y = margin
            } else {
                // Snap to bottom edge
                overlayPosition.y = screenBounds.height - margin
            }
        }
    }
}

struct StackIndicatorView: View {
    let stacks: [WindowStack]
    let yabaiInterface: YabaiInterface
    @Binding var hoveredStack: String?
    let stackButtonSize: CGFloat
    let stackButtonSpacing: CGFloat
    
    var body: some View {
        VStack(spacing: stackButtonSpacing) {
            if stacks.isEmpty {
                Text("No stacks detected")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(stacks) { stack in
                    StackButton(
                        stack: stack,
                        yabaiInterface: yabaiInterface,
                        size: stackButtonSize,
                        isHovered: hoveredStack == stack.id
                    )
                    .onHover { hovering in
                        hoveredStack = hovering ? stack.id : nil
                    }
                }
            }
        }
        .padding(8)
    }
}

struct StackButton: View {
    let stack: WindowStack
    let yabaiInterface: YabaiInterface
    let size: CGFloat
    let isHovered: Bool
    
    @State private var isPressed: Bool = false
    @State private var showingDetail: Bool = false
    
    var body: some View {
        Button(action: {
            cycleStackFocus()
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundGradient)
                    .frame(width: size, height: size)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
                
                // Stack count indicator
                VStack(spacing: 2) {
                    Text("\(stack.count)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("windows")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Focus indicator
                if stack.focusedWindow != nil {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: size/2 - 8, y: -size/2 + 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.5) {
            showingDetail = true
        }
        .pressEvents(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
        .contextMenu {
            stackContextMenu
        }
        .popover(isPresented: $showingDetail) {
            StackDetailView(stack: stack, yabaiInterface: yabaiInterface)
        }
    }
    
    private var backgroundGradient: LinearGradient {
        if isHovered {
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.8), Color.gray.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var stackContextMenu: some View {
        VStack {
            ForEach(stack.windows, id: \.id) { window in
                Button(action: {
                    focusWindow(window)
                }) {
                    HStack {
                        Image(systemName: window.isFocused ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(window.isFocused ? .green : .gray)
                        
                        Text(window.app)
                            .font(.system(size: 12))
                        
                        Spacer()
                        
                        Text(window.title.prefix(20))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            Button("Show Details") {
                showingDetail = true
            }
        }
    }
    
    private func cycleStackFocus() {
        let windowIds = stack.windows.map { $0.id }
        Task {
            do {
                try await yabaiInterface.cycleStackFocus(windowIds)
            } catch {
                print("Error cycling stack focus: \(error)")
            }
        }
    }
    
    private func focusWindow(_ window: YabaiWindow) {
        Task {
            do {
                try await yabaiInterface.focusWindow(window.id)
            } catch {
                print("Error focusing window: \(error)")
            }
        }
    }
}

struct StackDetailView: View {
    let stack: WindowStack
    let yabaiInterface: YabaiInterface
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stack Details")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Text("Windows:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(stack.count)")
                    .font(.subheadline)
            }
            
            HStack {
                Text("Space:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(stack.space)")
                    .font(.subheadline)
            }
            
            HStack {
                Text("Display:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(stack.display)")
                    .font(.subheadline)
            }
            
            Divider()
            
            Text("Windows in Stack:")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ForEach(stack.windows, id: \.id) { window in
                HStack {
                    Image(systemName: window.isFocused ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(window.isFocused ? .green : .gray)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.app)
                            .font(.system(size: 12, weight: .medium))
                        
                        Text(window.title)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button("Focus") {
                        focusWindow(window)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: 400)
    }
    
    private func focusWindow(_ window: YabaiWindow) {
        Task {
            do {
                try await yabaiInterface.focusWindow(window.id)
            } catch {
                print("Error focusing window: \(error)")
            }
        }
    }
}

// MARK: - Custom Button Style for Press Events

struct PressEventModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                if pressing {
                    onPress()
                } else {
                    onRelease()
                }
            }, perform: {})
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventModifier(onPress: onPress, onRelease: onRelease))
    }
} 