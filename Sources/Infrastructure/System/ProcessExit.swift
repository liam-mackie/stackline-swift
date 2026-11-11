import Darwin
import Dispatch

enum ProcessExit {
    private static let queue = DispatchQueue(label: "sh.mackie.stackline.process-exit")

    /// Suspends until the process identified by `pid` exits.
    ///
    /// Returns immediately if the process is already gone, and early if the calling task is cancelled.
    static func wait(for pid: pid_t) async {
        // The cancel handler is the single place the continuation is resumed: the exit event,
        // task cancellation, and the already-dead check below all funnel through `cancel()`,
        // and Dispatch invokes the cancel handler exactly once.
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                source.setEventHandler { source.cancel() }
                source.setCancelHandler { continuation.resume() }
                source.resume()

                // Registration cannot observe an exit that happened before it.
                if kill(pid, 0) != 0, errno == ESRCH {
                    source.cancel()
                }
            }
        } onCancel: {
            source.cancel()
        }
    }
}
