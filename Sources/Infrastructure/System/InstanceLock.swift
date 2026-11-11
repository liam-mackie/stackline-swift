import Darwin

/// An advisory lock that guarantees a single running Stackline per user.
///
/// The kernel releases the lock when the process exits for any reason — including `SIGKILL` —
/// so a crash can never leave a stale lock behind.
final class InstanceLock {
    enum Failure: Error {
        /// Another process holds the lock.
        case alreadyHeld
        case posix(operation: String, code: Int32)
    }

    private let descriptor: Int32

    init(path: String) throws(Failure) {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .posix(operation: "open", code: errno) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            throw code == EWOULDBLOCK ? .alreadyHeld : .posix(operation: "flock", code: code)
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}
