import Foundation

@MainActor
final class KeepAlive {
    private var activity: DispatchSemaphore?
    private var releaseTask: Task<Void, Never>?

    func hold() {
        releaseTask?.cancel()
        releaseTask = nil
        guard activity == nil else { return }
        let semaphore = DispatchSemaphore(value: 0)
        activity = semaphore
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Finishing WatchGPT answer") { [weak self] expired in
            if expired {
                semaphore.signal()
                Task { @MainActor [weak self] in
                    guard let self, self.activity === semaphore else { return }
                    self.activity = nil
                }
            } else {
                semaphore.wait()
            }
        }
    }

    func release(after delay: Duration) {
        guard activity != nil else { return }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func stop() {
        releaseTask = nil
        activity?.signal()
        activity = nil
    }
}
