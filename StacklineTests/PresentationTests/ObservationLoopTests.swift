import Observation
import XCTest
@testable import Stackline

@MainActor
final class ObservationLoopTests: XCTestCase {
    @Observable
    final class Model {
        var value = 0
        var unrelated = 0
    }

    func testRerunsOncePerBatchOfChangesToWhatItRead() async {
        let model = Model()
        var seen: [Int] = []
        let loop = ObservationLoop { seen.append(model.value) }
        defer { loop.cancel() }
        XCTAssertEqual(seen, [0])

        // Two changes within one main-actor turn are rendered once, with the final value.
        model.value = 1
        model.value = 2
        let updated = await waitUntil { seen.last == 2 }
        XCTAssertTrue(updated)
        XCTAssertEqual(seen, [0, 2])

        // It keeps following after the first change…
        model.value = 3
        let followed = await waitUntil { seen.last == 3 }
        XCTAssertTrue(followed)

        // …and ignores state it never read.
        model.unrelated = 1
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(seen, [0, 2, 3])
    }

    func testStopsAfterCancel() async {
        let model = Model()
        var runs = 0
        let loop = ObservationLoop {
            _ = model.value
            runs += 1
        }

        loop.cancel()
        model.value = 1
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(runs, 1)
    }
}
