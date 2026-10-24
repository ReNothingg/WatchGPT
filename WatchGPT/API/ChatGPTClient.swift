import Foundation

/// Talks to the ChatGPT backend with your subscription (the endpoints Codex uses).
struct ChatGPTClient: Sendable {
    static let baseURL = URL(string: "https://chatgpt.com/backend-api")!
    /// Codex client version reported to the backend (used to pick which models are offered).
    static let clientVersion = "0.164.0"

    let tokens: AuthTokens

    enum APIError: LocalizedError {
        case unauthorized
        case usageLimit(resetAt: Date?)
        case http(Int, String)
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Нужно заново войти в ChatGPT."
            case let .usageLimit(resetAt):
                if let resetAt {
                    return "Лимит исчерпан. Сброс \(resetAt.formatted(.relative(presentation: .named)))."
                }
                return "Лимит подписки исчерпан."
            case let .http(code, message):
                return message.isEmpty ? "Ошибка сервера (\(code))." : message
            case let .stream(message):
                return message
            }
        }
    }

    enum StreamEvent: Sendable {
        case textDelta(String)
        case searching
        case usage(UsageSnapshot)
        case completed
    }

    struct Options: Sendable {
        var model: String
        var effort: String?
        var webSearch: Bool
        var verbosity: String?
        var instructions: String
        var conversationID: String
    }

    // MARK: Responses (streaming)

    func stream(messages: [ChatMessage], options: Options) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await runStream(messages: messages, options: options, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runStream(
        messages: [ChatMessage],
        options: Options,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var request = makeRequest(Self.baseURL.appending(path: "codex/responses"), method: "POST")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(options.conversationID, forHTTPHeaderField: "session_id")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(messages: messages, options: options))
        request.timeoutInterval = 180

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.stream("Нет ответа от сервера.") }

        if let usage = Self.usage(fromHeaders: http) {
            continuation.yield(.usage(usage))
        }

        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 16_384 { break }
            }
            throw Self.error(status: http.statusCode, body: data)
        }

        var sawText = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "response.output_text.delta":
                if let delta = event["delta"] as? String, !delta.isEmpty {
                    sawText = true
                    continuation.yield(.textDelta(delta))
                }
            case "response.output_text.done":
                if !sawText, let text = event["text"] as? String, !text.isEmpty {
                    sawText = true
                    continuation.yield(.textDelta(text))
                }
            case "response.output_item.added":
                if let item = event["item"] as? [String: Any], (item["type"] as? String) == "web_search_call" {
                    continuation.yield(.searching)
                }
            case "codex.rate_limits":
                if let usage = Self.usage(fromEvent: event) { continuation.yield(.usage(usage)) }
            case "response.completed", "response.incomplete":
                continuation.yield(.completed)
                return
            case "response.failed":
                let response = event["response"] as? [String: Any]
                let error = response?["error"] as? [String: Any]
                throw APIError.stream((error?["message"] as? String) ?? "Не удалось получить ответ.")
            case "error":
                let error = event["error"] as? [String: Any]
                let message = (event["message"] as? String) ?? (error?["message"] as? String) ?? "Ошибка генерации."
                throw APIError.stream(message)
            default:
                continue
            }
        }
        continuation.yield(.completed)
    }

    static func body(messages: [ChatMessage], options: Options) -> [String: Any] {
        var input: [[String: Any]] = [[
            "type": "message",
            "role": "developer",
            "content": [["type": "input_text", "text": options.instructions]],
        ]]
        for message in messages where !message.isError && !message.text.isEmpty {
            let isUser = message.role == .user
            input.append([
                "type": "message",
                "role": isUser ? "user" : "assistant",
                "content": [["type": isUser ? "input_text" : "output_text", "text": message.text]],
            ])
        }

        var body: [String: Any] = [
            "model": options.model,
            "stream": true,
            "store": false,
            "input": input,
            "tool_choice": "auto",
            "parallel_tool_calls": false,
            "include": [String](),
            "prompt_cache_key": options.conversationID,
        ]
        if options.webSearch {
            body["tools"] = [["type": "web_search", "external_web_access": true]]
        }
        if let effort = options.effort {
            body["reasoning"] = ["effort": effort]
        }
        if let verbosity = options.verbosity {
            body["text"] = ["verbosity": verbosity]
        }
        return body
    }

    // MARK: Usage

    func fetchUsage() async throws -> UsageSnapshot {
        let request = makeRequest(Self.baseURL.appending(path: "wham/usage"), method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.error(status: status, body: data) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.stream("Не удалось прочитать лимиты.")
        }

        func window(_ any: Any?) -> UsageWindow? {
            guard let w = any as? [String: Any], let used = Self.number(w["used_percent"]) else { return nil }
            let seconds = Self.number(w["limit_window_seconds"])
            var resetAt = Self.number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            if resetAt == nil, let after = Self.number(w["reset_after_seconds"]) {
                resetAt = Date.now.addingTimeInterval(after)
            }
            return UsageWindow(usedPercent: used, windowMinutes: seconds.map { Int($0 / 60) }, resetAt: resetAt)
        }

        let limit = obj["rate_limit"] as? [String: Any]
        return UsageSnapshot(
            primary: window(limit?["primary_window"]),
            secondary: window(limit?["secondary_window"]),
            planType: obj["plan_type"] as? String,
            limitReached: (limit?["limit_reached"] as? Bool) ?? false,
            updatedAt: .now
        )
    }

    static func usage(fromHeaders http: HTTPURLResponse) -> UsageSnapshot? {
        func window(_ prefix: String) -> UsageWindow? {
            guard let used = http.value(forHTTPHeaderField: "x-codex-\(prefix)-used-percent").flatMap(Double.init) else { return nil }
            let minutes = http.value(forHTTPHeaderField: "x-codex-\(prefix)-window-minutes").flatMap(Int.init)
            let reset = http.value(forHTTPHeaderField: "x-codex-\(prefix)-reset-at").flatMap(Double.init)
            return UsageWindow(usedPercent: used, windowMinutes: minutes, resetAt: reset.map { Date(timeIntervalSince1970: $0) })
        }
        let primary = window("primary")
        let secondary = window("secondary")
        guard primary != nil || secondary != nil else { return nil }
        return UsageSnapshot(primary: primary, secondary: secondary, planType: nil, updatedAt: .now)
    }

    static func usage(fromEvent event: [String: Any]) -> UsageSnapshot? {
        let limits = event["rate_limits"] as? [String: Any]
        func window(_ any: Any?) -> UsageWindow? {
            guard let w = any as? [String: Any], let used = number(w["used_percent"]) else { return nil }
            return UsageWindow(
                usedPercent: used,
                windowMinutes: number(w["window_minutes"]).map { Int($0) },
                resetAt: number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
            )
        }
        let primary = window(limits?["primary"])
        let secondary = window(limits?["secondary"])
        guard primary != nil || secondary != nil else { return nil }
        return UsageSnapshot(primary: primary, secondary: secondary, planType: event["plan_type"] as? String, updatedAt: .now)
    }

    // MARK: Models

    func fetchModels() async throws -> [ModelOption] {
        var components = URLComponents(url: Self.baseURL.appending(path: "codex/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "client_version", value: Self.clientVersion)]
        let request = makeRequest(components.url!, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.error(status: status, body: data) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }

        return models.compactMap { m -> ModelOption? in
            guard let slug = m["slug"] as? String else { return nil }
            if let visibility = m["visibility"] as? String, visibility != "list" { return nil }
            let levels = (m["supported_reasoning_levels"] as? [[String: Any]])?.compactMap { $0["effort"] as? String } ?? []
            return ModelOption(
                slug: slug,
                displayName: (m["display_name"] as? String) ?? slug,
                summary: m["description"] as? String,
                efforts: levels,
                defaultEffort: m["default_reasoning_level"] as? String,
                supportsVerbosity: (m["support_verbosity"] as? Bool) ?? false,
                priority: (m["priority"] as? Int) ?? 100
            )
        }
        .sorted { $0.priority < $1.priority }
    }

    // MARK: Helpers

    private func makeRequest(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        if let account = tokens.accountID {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("codex_cli_rs/\(Self.clientVersion) (watchOS; WatchGPT)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func number(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func error(status: Int, body: Data) -> APIError {
        if status == 401 { return .unauthorized }

        let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let error = obj?["error"] as? [String: Any]
        let type = (error?["type"] as? String) ?? (error?["code"] as? String) ?? ""
        let message = (error?["message"] as? String) ?? (obj?["detail"] as? String) ?? ""

        if status == 429 || type.contains("usage_limit") {
            var resetAt = number(error?["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            if resetAt == nil, let seconds = number(error?["resets_in_seconds"]) {
                resetAt = Date.now.addingTimeInterval(seconds)
            }
            if type.contains("usage_limit") || resetAt != nil { return .usageLimit(resetAt: resetAt) }
            return .http(status, message.isEmpty ? "Слишком много запросов. Подождите немного." : message)
        }
        return .http(status, message)
    }
}
