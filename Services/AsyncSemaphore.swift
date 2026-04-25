import Foundation

/// Counting semaphore safe to use from async contexts.
///
/// Replaces `DispatchSemaphore` in async code where blocking the cooperative
/// thread pool is unacceptable. Waiters suspend on a `CheckedContinuation`
/// instead of blocking a physical thread.
actor AsyncSemaphore {
    private let limit: Int
    private var current = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0, "AsyncSemaphore limit must be positive")
        self.limit = limit
    }

    /// Acquires a permit, suspending until one is available.
    func acquire() async {
        if current < limit {
            current += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases one permit. If waiters are queued, the oldest is resumed.
    func release() {
        if waiters.isEmpty {
            current = max(0, current - 1)
        } else {
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
    }
}
