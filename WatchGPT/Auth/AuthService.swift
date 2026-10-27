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

    private static let claudeKeyAccount = "anthropic.apikey"

    private(set) var phase: Phase
    private(set) var tokens: AuthTokens?
    /// OpenAI API key for speech-to-text: obtained automatically from the ChatGPT login, or entered by hand.
    private(set) var apiKey: StoredAPIKey?
    private(set) var apiKeyError: String?
    private(set) var keyCheck: KeyCheck = .unknown
    private(set) var claudeKey: StoredAPIKey?
    private(set) var claudeKeyCheck: KeyCheck = .unknown

    var hasClaudeKey: Bool { claudeKey != nil }

    enum KeyCheck: Equatable {
        case unknown
        case checking
        case valid
        case invalid(String)
    }

    private var pairingTask: Task<Void, Never>?
    private var refreshTask: Task<AuthTokens, Error>?

    var isSignedIn: Bool { tokens != nil }

    init() {
        let stored = Keychain.load(AuthTokens.self, account: Self.keychainAccount)
        tokens = stored
        phase = stored == nil ? .signedOut : .signedIn
        apiKey = Keychain.load(StoredAPIKey.self, account: Self.apiKeyAccount)
        claudeKey = Keychain.load(StoredAPIKey.self, account: Self.claudeKeyAccount)
    }

    // MARK: Anthropic API key (Claude)

    func setManualClaudeKey(_ raw: String) {
        let key = raw.filter { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
        guard !key.isEmpty else { return }
        setClaudeKey(StoredAPIKey(key: key, isManual: true))
        Task { await verifyClaudeKey() }
    }

    func clearClaudeKey() {
        claudeKey = nil
        claudeKeyCheck = .unknown
        Keychain.delete(account: Self.claudeKeyAccount)
    }

    func verifyClaudeKey() async {
        guard let key = claudeKey?.key else {
            claudeKeyCheck = .unknown
            return
        }
        claudeKeyCheck = .checking
        do {
            _ = try await AnthropicClient(apiKey: key).fetchModels()
            guard claudeKey?.key == key else { return }
            claudeKeyCheck = .valid
        } catch {
            guard claudeKey?.key == key else { return }
            claudeKeyCheck = .invalid(error.localizedDescription)
            DiagnosticsLog.shared.record(.answer, message: "Ключ Anthropic не прошёл проверку", detail: error.localizedDescription)
        }
    }

    private func setClaudeKey(_ value: StoredAPIKey) {
        claudeKey = value
        claudeKeyCheck = .unknown
        Keychain.save(value, account: Self.claudeKeyAccount)
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
            Task { await verifyAPIKey() }
            return key
        } catch OAuth.Failure.noAPIOrganization {
            apiKeyError = OAuth.Failure.noAPIOrganization.errorDescription
            DiagnosticsLog.shared.record(.voice, message: "API-ключ не выдан: нет API-организации во входе ChatGPT", detail: "organization_id")
            throw OAuth.Failure.noAPIOrganization
        } catch {
            apiKeyError = "Не удалось получить API-ключ автоматически: \(error.localizedDescription)"
            DiagnosticsLog.shared.record(.voice, error)
            throw error
        }
    }

    func setManualAPIKey(_ raw: String) {
        let key = raw.filter { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
        guard !key.isEmpty else { return }
        setAPIKey(StoredAPIKey(key: key, isManual: true))
        apiKeyError = nil
        Task { await verifyAPIKey() }
    }

    func clearAPIKey() {
        apiKey = nil
        keyCheck = .unknown
        Keychain.delete(account: Self.apiKeyAccount)
    }

    func verifyAPIKey() async {
        guard let key = apiKey?.key else {
            keyCheck = .unknown
            return
        }
        keyCheck = .checking
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models/gpt-transcribe")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard apiKey?.key == key else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                keyCheck = .valid
                return
            }
            let message = OAuth.readableMessage(String(decoding: data, as: UTF8.self)).prefix(140)
            switch status {
            case 401: keyCheck = .invalid("Ключ не подходит. \(message)")
            case 403, 404: keyCheck = .invalid("Нет доступа к gpt-transcribe в этом проекте. \(message)")
            default: keyCheck = .invalid("Ошибка проверки (\(status)). \(message)")
            }
            DiagnosticsLog.shared.record(.voice, message: "API-ключ не прошёл проверку", detail: "HTTP \(status)")
        } catch {
            guard apiKey?.key == key else { return }
            keyCheck = .invalid("Не удалось проверить: \(error.localizedDescription)")
        }
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
