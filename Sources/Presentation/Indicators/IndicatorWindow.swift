import AppKit
import SwiftUI

/// A borderless, transparent window showing the indicator for one stack on every space.
final class IndicatorWindow: NSWindow {
    private let hostingView: NSHostingView<IndicatorView>

    init(view: IndicatorView, frame: NSRect, clickable: Bool) {
        hostingView = NSHostingView(rootView: view)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = !clickable
        isReleasedWhenClosed = false
        contentView = hostingView
    }

    /// Updates the indicator in place, so SwiftUI diffs the content instead of rebuilding it.
    func update(view: IndicatorView, frame: NSRect, clickable: Bool) {
        hostingView.rootView = view
        ignoresMouseEvents = !clickable

        // Compared against the actual frame rather than the last one requested: AppKit moves
        // windows on its own when displays are reconfigured.
        if self.frame != frame {
            setFrame(frame, display: true)
        }
    }
}
