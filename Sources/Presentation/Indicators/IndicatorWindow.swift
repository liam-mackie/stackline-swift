import AppKit
import SwiftUI

/// NSWindow wrapper for displaying stack indicators
final class IndicatorWindow: NSWindow {
    private let stackId: String

    init(stackId: String, contentRect: NSRect, clickable: Bool = false) {
        self.stackId = stackId

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configureWindow(clickable: clickable)
    }

    private func configureWindow(clickable: Bool) {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = !clickable
        isReleasedWhenClosed = false
    }

    func setClickable(_ clickable: Bool) {
        ignoresMouseEvents = !clickable
    }

    func updatePosition(_ point: CGPoint) {
        setFrameOrigin(point)
    }

    func updateSize(_ size: CGSize) {
        setContentSize(size)
    }

    func setIndicatorView<Content: View>(_ view: Content) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }
}
