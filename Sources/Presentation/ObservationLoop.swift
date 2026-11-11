import Observation

/// Runs a closure, and runs it again after any change to the `@Observable` state it read.
///
/// This is how AppKit code follows observable models. Changes made within one main-actor turn
/// are coalesced into a single re-run.
@MainActor
final class ObservationLoop {
    private var body: (@MainActor () -> Void)?

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
        run()
    }

    func cancel() {
        body = nil
    }

    private func run() {
        guard let body else { return }

        withObservationTracking {
            body()
        } onChange: { [weak self] in
            Task { @MainActor in self?.run() }
        }
    }
}
