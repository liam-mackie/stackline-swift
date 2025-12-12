import Foundation
import Combine

@MainActor
public protocol StackDetectorProtocol: AnyObject {
    var detectedStacks: [WindowStack] { get }
    var stacksPublisher: AnyPublisher<[WindowStack], Never> { get }

    func detectStacks() async throws -> [WindowStack]
    func startMonitoring() async
    func stopMonitoring()

    func stack(containing windowId: WindowIdentifier) -> WindowStack?
}
