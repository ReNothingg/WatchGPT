import WatchKit

/// Keeps the app frontmost and running while the wrist is down (recording, waiting for an answer).
@MainActor
final class KeepAlive: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    private var wanted = false
    private var releaseTask: Task<Void, Never>?

    func hold() {
        releaseTask?.cancel()
        releaseTask = nil
        wanted = true
        if let session, session.state != .invalid { return }
        guard WKApplication.shared().applicationState == .active else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        session.start()
    }

    func release(after delay: Duration) {
        guard wanted else { return }
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func stop() {
        releaseTask = nil
        wanted = false
        if session?.state == .running { session?.invalidate() }
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard self.session === extendedRuntimeSession, !self.wanted else { return }
            extendedRuntimeSession.invalidate()
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            guard self.session === extendedRuntimeSession else { return }
            self.session = nil
        }
    }
}
