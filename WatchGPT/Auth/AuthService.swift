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
    private static let apiKeyAccount = "openai.apikey"

    struct StoredAPIKey: Codable, Equatable {
        var key: String
        var isManual: Bool
    }

    private(set) var phase: Phase
    private(set) var tokens: AuthTokens?
    /// OpenAI API key for speech-to-text: obtained automatically from the ChatGPT login, or entered by hand.
    private(set) var apiKey: StoredAPIKey?
    private(set) var apiKeyError: String?

    private var pairingTask: Task<Void, Never>?
    private var refreshTask: Task<AuthTokens, Error>?

    var isSignedIn: Bool { tokens != nil }

    init() {
        let stored = Keychain.load(AuthTokens.self, account: Self.keychainAccount)
        tokens = stored
        phase = stored == nil ? .signedOut : .signedIn
        apiKey = Keychain.load(StoredAPIKey.self, account: Self.apiKeyAccount)
    }

    // MARK: OpenAI API key (speech-to-text)

    /// Returns the stored key, or tries to obtain one from the ChatGPT login.
    func ensureAPIKey() async throws -> String {
        if let apiKey { return apiKey.key }
        return try await obtainAPIKey()
    }

    @discardableResult
    func obtainAPIKey() async throws -> String {
        let current = try await validTokens()
        do {
            let key = try await OAuth.obtainAPIKey(idToken: current.idToken)
            setAPIKey(StoredAPIKey(key: key, isManual: false))
            apiKeyError = nil
            return key
        } catch {
            apiKeyError = "Не удалось получить API-ключ автоматически. Можно ввести свой ключ вручную."
            throw error
        }
    }

    func setManualAPIKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        setAPIKey(StoredAPIKey(key: key, isManual: true))
        apiKeyError = nil
    }

    func clearAPIKey() {
        apiKey = nil
        Keychain.delete(account: Self.apiKeyAccount)
    }

    private func setAPIKey(_ value: StoredAPIKey) {
        apiKey = value
        Keychain.save(value, account: Self.apiKeyAccount)
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
        if apiKey?.isManual == false { clearAPIKey() }
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
