import Foundation

/// "Sign in with ChatGPT" via the device-code flow used by `codex login --device-auth`.
/// The watch shows a QR + one-time code, you confirm on the iPhone, the watch receives tokens.
enum OAuth {
    static let issuer = URL(string: "https://auth.openai.com")!
    /// Public OAuth client id of the Codex CLI.
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    struct DeviceCode: Equatable, Sendable {
        let verificationURL: URL
        let userCode: String
        let deviceAuthID: String
        let interval: TimeInterval
        let expiresAt: Date
    }

    enum Failure: LocalizedError {
        case deviceCodeDisabled
        case expired
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .deviceCodeDisabled:
                return "Вход по коду недоступен. Включите «Device code» для Codex в настройках безопасности ChatGPT."
            case .expired: return "Код истёк. Попробуйте снова."
            case let .http(code, body): return "Ошибка входа (\(code)). \(body.prefix(120))"
            case .badResponse: return "Неожиданный ответ сервера."
            }
        }
    }

    // MARK: Device code

    static func requestDeviceCode() async throws -> DeviceCode {
        let url = issuer.appending(path: "api/accounts/deviceauth/usercode")
        let (data, response) = try await postJSON(url, ["client_id": clientID])
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw Failure.deviceCodeDisabled }
        guard (200..<300).contains(status) else { throw Failure.http(status, String(decoding: data, as: UTF8.self)) }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authID = obj["device_auth_id"] as? String,
              let code = (obj["user_code"] ?? obj["usercode"]) as? String else { throw Failure.badResponse }
        let interval: TimeInterval
        if let s = obj["interval"] as? String, let v = Double(s.trimmingCharacters(in: .whitespaces)) {
            interval = v
        } else if let v = obj["interval"] as? Double {
            interval = v
        } else {
            interval = 5
        }
        return DeviceCode(
            verificationURL: issuer.appending(path: "codex/device"),
            userCode: code,
            deviceAuthID: authID,
            interval: max(2, interval),
            expiresAt: parseDate(obj["expires_at"] as? String) ?? .now.addingTimeInterval(15 * 60)
        )
    }

    /// Parses "2026-10-24T09:05:23.013148+00:00" (microseconds are trimmed for ISO8601DateFormatter).
    private static func parseDate(_ string: String?) -> Date? {
        guard var s = string else { return nil }
        if let dot = s.firstIndex(of: "."),
           let zone = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            s.removeSubrange(dot..<zone)
        }
        let date = ISO8601DateFormatter().date(from: s)
        // Ignore obviously wrong values (clock skew etc.).
        guard let date, date > .now, date < .now.addingTimeInterval(3600) else { return nil }
        return date
    }

    /// Polls until the user approves on the phone, then exchanges the code for tokens.
    static func waitForApproval(_ code: DeviceCode) async throws -> AuthTokens {
        let url = issuer.appending(path: "api/accounts/deviceauth/token")
        while true {
            try Task.checkCancellation()
            if Date.now >= code.expiresAt { throw Failure.expired }

            let (data, response) = try await postJSON(url, [
                "device_auth_id": code.deviceAuthID,
                "user_code": code.userCode,
            ])
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let authCode = obj["authorization_code"] as? String,
                      let verifier = obj["code_verifier"] as? String else { throw Failure.badResponse }
                return try await exchange(authorizationCode: authCode, codeVerifier: verifier)
            }
            if status == 403 || status == 404 {
                try await Task.sleep(nanoseconds: UInt64(code.interval * 1_000_000_000))
                continue
            }
            throw Failure.http(status, String(decoding: data, as: UTF8.self))
        }
    }

    private static func exchange(authorizationCode: String, codeVerifier: String) async throws -> AuthTokens {
        var request = URLRequest(url: issuer.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", authorizationCode),
            ("redirect_uri", issuer.appending(path: "deviceauth/callback").absoluteString),
            ("code_verifier", codeVerifier),
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status, String(decoding: data, as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id_token"] as? String,
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else { throw Failure.badResponse }
        return AuthTokens(idToken: id, accessToken: access, refreshToken: refresh, lastRefresh: .now)
    }

    // MARK: Refresh

    enum RefreshFailure: Error { case permanent, transient(Error) }

    static func refresh(_ tokens: AuthTokens) async throws -> AuthTokens {
        let url = issuer.appending(path: "oauth/token")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await postJSON(url, [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": tokens.refreshToken,
            ])
        } catch {
            throw RefreshFailure.transient(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 { throw RefreshFailure.permanent }
        guard (200..<300).contains(status),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RefreshFailure.transient(Failure.http(status, ""))
        }
        var updated = tokens
        if let id = obj["id_token"] as? String { updated.idToken = id }
        if let access = obj["access_token"] as? String { updated.accessToken = access }
        if let refresh = obj["refresh_token"] as? String { updated.refreshToken = refresh }
        updated.lastRefresh = .now
        return updated
    }

    // MARK: OpenAI API key

    /// Exchanges the ChatGPT id_token for an OpenAI API key (same as `codex login` does).
    /// Used for OpenAI speech-to-text (gpt-4o-transcribe). Fails if the account has no API organization.
    static func obtainAPIKey(idToken: String) async throws -> String {
        var request = URLRequest(url: issuer.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            ("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange"),
            ("client_id", clientID),
            ("requested_token", "openai-api-key"),
            ("subject_token", idToken),
            ("subject_token_type", "urn:ietf:params:oauth:token-type:id_token"),
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status, String(decoding: data, as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = obj["access_token"] as? String, !key.isEmpty else { throw Failure.badResponse }
        return key
    }

    // MARK: Helpers

    private static func postJSON(_ url: URL, _ body: [String: String]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private static func formEncode(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = pairs.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
