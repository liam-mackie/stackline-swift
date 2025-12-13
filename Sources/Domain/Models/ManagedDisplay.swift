import Foundation
import CoreGraphics

public struct ManagedDisplay: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public let index: Int
    public let frame: CGRect
    public let spaceIds: [Int]

    public init(
        id: Int,
        index: Int,
        frame: CGRect,
        spaceIds: [Int]
    ) {
        self.id = id
        self.index = index
        self.frame = frame
        self.spaceIds = spaceIds
    }

    public func contains(point: CGPoint) -> Bool {
        frame.contains(point)
    }

    public func contains(rect: CGRect) -> Bool {
        frame.intersects(rect)
    }

    public func relativeFrame(for windowFrame: CGRect) -> CGRect {
        CGRect(
            x: windowFrame.origin.x - frame.origin.x,
            y: windowFrame.origin.y - frame.origin.y,
            width: windowFrame.width,
            height: windowFrame.height
        )
    }
}
