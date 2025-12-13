import Foundation
import CoreGraphics
@testable import Stackline

/// Mock implementation of CoordinateSystemProtocol for testing
final class MockCoordinateSystem: CoordinateSystemProtocol, @unchecked Sendable {
    private var displayFrames: [CGRect] = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440)
    ]

    func setDisplayFrames(_ frames: [CGRect]) {
        displayFrames = frames
    }

    func getAllDisplayFrames() -> [CGRect] {
        displayFrames
    }

    func isWindowOnScreen(_ window: ManagedWindow) -> Bool {
        let windowCenter = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )

        return displayFrames.contains { display in
            display.contains(windowCenter)
        }
    }

    func displayContaining(point: CGPoint) -> CGRect? {
        displayFrames.first { $0.contains(point) }
    }

    func displayContaining(rect: CGRect) -> CGRect? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displayContaining(point: center)
    }
}
