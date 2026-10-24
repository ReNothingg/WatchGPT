import Foundation

/// Tokens from "Sign in with ChatGPT" (the same OAuth flow Codex uses).
struct AuthTokens: Codable, Equatable, Sendable {
    var idToken: String
    var accessToken: String
    var refreshToken: String
    var lastRefresh: Date

    var accountID: String? { JWT.authClaim(idToken, "chatgpt_account_id") ?? JWT.authClaim(accessToken, "chatgpt_account_id") }
    var planType: String? { JWT.authClaim(idToken, "chatgpt_plan_type") ?? JWT.authClaim(accessToken, "chatgpt_plan_type") }
    var email: String? {
        let claims = JWT.claims(idToken)
        if let email = claims?["email"] as? String { return email }
        let profile = JWT.claims(accessToken)?["https://api.openai.com/profile"] as? [String: Any]
        return profile?["email"] as? String
    }

    var accessTokenExpiry: Date? {
        guard let exp = JWT.claims(accessToken)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Refresh 5 minutes before expiry, or after 8 days if expiry is unknown.
    var needsRefresh: Bool {
        if let exp = accessTokenExpiry { return exp.timeIntervalSinceNow < 5 * 60 }
        return Date.now.timeIntervalSince(lastRefresh) > 8 * 24 * 3600
    }
}

enum JWT {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static func authClaim(_ token: String, _ key: String) -> String? {
        let auth = claims(token)?["https://api.openai.com/auth"] as? [String: Any]
        return auth?[key] as? String
    }
}
