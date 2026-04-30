import Foundation

actor RefreshScheduler {
    private var task: Task<Void, Never>?
    private var interval: TimeInterval
    private var isRunning: Bool = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func start(interval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        self.interval = interval
        self.isRunning = true

        task = Task {
            while !Task.isCancelled {
                guard !Task.isCancelled else { break }
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await action()
            }
            await self.markAsStopped()
        }

        AppLogger.debug("RefreshScheduler started with interval: \(interval)s")
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        AppLogger.debug("RefreshScheduler stopped")
    }

    func updateInterval(_ newInterval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        self.interval = newInterval
        if isRunning {
            start(interval: newInterval, action: action)
        }
    }

    func getIsRunning() -> Bool {
        isRunning
    }

    private func markAsStopped() {
        isRunning = false
    }
}
