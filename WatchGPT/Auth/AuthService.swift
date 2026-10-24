import Foundation
import Observation

@MainActor
@Observable
final class AuthService {
    enum Phase: Equatable {
        case signedOut
        case requestingCode
        case waiting(OAuth.DeviceCode)
        case failed(String)
        case signedIn
    }

    enum AuthError: LocalizedError {
        case signedOut
        var errorDescription: String? { "Сессия ChatGPT истекла. Подключите аккаунт заново." }
    }

    private static let keychainAccount = "chatgpt.tokens"

    private(set) var phase: Phase
    private(set) var tokens: AuthTokens?

    private var pairingTask: Task<Void, Never>?
    private var refreshTask: Task<AuthTokens, Error>?

    var isSignedIn: Bool { tokens != nil }

    init() {
        let stored = Keychain.load(AuthTokens.self, account: Self.keychainAccount)
        tokens = stored
        phase = stored == nil ? .signedOut : .signedIn
    }

    // MARK: Pairing

    func startPairing() {
        pairingTask?.cancel()
        phase = .requestingCode
        pairingTask = Task { [weak self] in
            do {
                let code = try await OAuth.requestDeviceCode()
                self?.phase = .waiting(code)
                let tokens = try await OAuth.waitForApproval(code)
                self?.store(tokens)
                self?.phase = .signedIn
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        if tokens == nil { phase = .signedOut }
    }

    func signOut() {
        pairingTask?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        tokens = nil
        Keychain.delete(account: Self.keychainAccount)
        phase = .signedOut
    }

    // MARK: Tokens

    /// Returns tokens that are valid for at least a few minutes.
    func validTokens() async throws -> AuthTokens {
        guard let current = tokens else { throw AuthError.signedOut }
        if current.needsRefresh { return try await refresh() }
        return current
    }

    /// Forces a refresh (e.g. after a 401). Concurrent callers share one request.
    @discardableResult
    func refresh() async throws -> AuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokens else { throw AuthError.signedOut }

        let task = Task<AuthTokens, Error> {
            try await OAuth.refresh(current)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let updated = try await task.value
            store(updated)
            return updated
        } catch OAuth.RefreshFailure.permanent {
            signOut()
            throw AuthError.signedOut
        } catch OAuth.RefreshFailure.transient(let error) {
            throw error
        }
    }

    private func store(_ tokens: AuthTokens) {
        self.tokens = tokens
        Keychain.save(tokens, account: Self.keychainAccount)
    }
}
