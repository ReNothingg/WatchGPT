import Foundation

struct AnthropicClient: Sendable {
    static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let maxTokens = 32_000

    let apiKey: String

    enum APIError: LocalizedError {
        case noKey
        case unauthorized
        case forbidden(String)
        case modelNotFound
        case rateLimited
        case overloaded
        case lowBalance
        case refusal
        case http(Int, String)
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Добавьте API-ключ Anthropic: Настройки → Claude."
            case .unauthorized:
                return "API-ключ Anthropic не подходит. Проверьте его в настройках."
            case let .forbidden(message):
                return message.isEmpty ? "Anthropic: доступ запрещён (403)." : "Anthropic: доступ запрещён — \(message)"
            case .modelNotFound:
                return "Эта модель Claude недоступна для вашего ключа. Выберите другую."
            case .rateLimited:
                return "Слишком много запросов к Claude. Подождите немного."
            case .overloaded:
                return "Claude сейчас перегружен. Попробуйте чуть позже."
            case .lowBalance:
                return "На балансе Anthropic не хватает денег. Пополните его в console.anthropic.com."
            case .refusal:
                return "Claude отказался отвечать на этот вопрос."
            case let .http(code, message):
                return message.isEmpty ? "Ошибка Claude (\(code))." : message
            case let .stream(message):
                return message
            }
        }
    }

    struct Options: Sendable {
        var model: String
        var effort: String?
        var thinking: Bool
        var webSearch: Bool
        var instructions: String
        var context: String?
    }

    // MARK: Messages (streaming)

    func stream(messages: [ChatMessage], options: Options) -> AsyncThrowingStream<ChatGPTClient.StreamEvent, Error> {
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
        continuation: AsyncThrowingStream<ChatGPTClient.StreamEvent, Error>.Continuation
    ) async throws {
        var request = makeRequest(Self.baseURL.appending(path: "messages"), method: "POST")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if Self.supportsFallbacks(options.model) {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(messages: messages, options: options))
        request.timeoutInterval = 180

        let delegate = ConnectivityDelegate { continuation.yield(.waitingForNetwork) }
        let (bytes, response) = try await ChatGPTClient.streamSession.bytes(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw APIError.stream("Нет ответа от сервера Anthropic.") }
        continuation.yield(.responseStarted)

        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 16_384 { break }
            }
            throw Self.error(status: http.statusCode, body: data)
        }

        var sawText = false
        var needsBreak = false
        var stopReason: String?
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any]
                let blockType = block?["type"] as? String ?? ""
                if blockType == "server_tool_use" {
                    continuation.yield(.searching)
                }
                if blockType == "text" {
                    if let text = block?["text"] as? String, !text.isEmpty {
                        continuation.yield(.textDelta((needsBreak ? "\n\n" : "") + text))
                        needsBreak = false
                        sawText = true
                    }
                } else if sawText, blockType != "fallback" {
                    needsBreak = true
                }
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any]
                guard (delta?["type"] as? String) == "text_delta",
                      let text = delta?["text"] as? String, !text.isEmpty else { continue }
                continuation.yield(.textDelta((needsBreak ? "\n\n" : "") + text))
                needsBreak = false
                sawText = true
            case "message_delta":
                let delta = event["delta"] as? [String: Any]
                if let reason = delta?["stop_reason"] as? String { stopReason = reason }
            case "message_stop":
                if stopReason == "refusal", !sawText { throw APIError.refusal }
                continuation.yield(.completed)
                return
            case "error":
                let error = event["error"] as? [String: Any]
                throw Self.streamError(type: error?["type"] as? String ?? "", message: error?["message"] as? String ?? "")
            default:
                continue
            }
        }
        if stopReason == "refusal", !sawText { throw APIError.refusal }
        continuation.yield(.completed)
    }

    static func body(messages: [ChatMessage], options: Options) -> [String: Any] {
        var turns: [(role: String, texts: [String])] = []
        for message in messages where !message.isError && !message.text.isEmpty {
            let role = message.role == .user ? "user" : "assistant"
            if turns.isEmpty && role == "assistant" { continue }
            if let last = turns.indices.last, turns[last].role == role {
                turns[last].texts.append(message.modelText)
            } else {
                turns.append((role, [message.modelText]))
            }
        }

        var payload: [[String: Any]] = turns.map { turn in
            ["role": turn.role, "content": turn.texts.map { ["type": "text", "text": $0] }]
        }
        if let context = options.context, !context.isEmpty,
           let last = payload.indices.last, (payload[last]["role"] as? String) == "user",
           var content = payload[last]["content"] as? [[String: Any]] {
            content.insert(["type": "text", "text": "<context>\(context)</context>"], at: 0)
            payload[last]["content"] = content
        }

        var body: [String: Any] = [
            "model": options.model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": options.instructions,
            "messages": payload,
            "cache_control": ["type": "ephemeral"],
        ]
        if options.thinking {
            body["thinking"] = ["type": "adaptive"]
        }
        if let effort = options.effort {
            body["output_config"] = ["effort": effort]
        }
        if options.webSearch {
            body["tools"] = [["type": webSearchTool(options.model), "name": "web_search", "max_uses": 3]]
        }
        if supportsFallbacks(options.model) {
            body["fallbacks"] = "default"
        }
        return body
    }

    static func supportsFallbacks(_ model: String) -> Bool {
        ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
    }

    static func webSearchTool(_ model: String) -> String {
        let dynamic = [
            "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
            "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6",
        ]
        return dynamic.contains(model) ? "web_search_20260209" : "web_search_20250305"
    }

    // MARK: Models

    func fetchModels() async throws -> [ModelOption] {
        var components = URLComponents(url: Self.baseURL.appending(path: "models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        var request = makeRequest(components.url!, method: "GET")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.error(status: status, body: data) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return [] }

        let levels = ["low", "medium", "high", "xhigh", "max"]
        return list.enumerated().compactMap { index, m -> ModelOption? in
            guard let id = m["id"] as? String else { return nil }
            let caps = m["capabilities"] as? [String: Any]
            let effortCaps = caps?["effort"] as? [String: Any]
            let efforts = (effortCaps?["supported"] as? Bool) == true
                ? levels.filter { ((effortCaps?[$0] as? [String: Any])?["supported"] as? Bool) == true }
                : []
            let thinkingTypes = (caps?["thinking"] as? [String: Any])?["types"] as? [String: Any]
            let adaptive = ((thinkingTypes?["adaptive"] as? [String: Any])?["supported"] as? Bool) == true
            return ModelOption(
                slug: id,
                displayName: (m["display_name"] as? String) ?? id,
                summary: Self.summary(id),
                efforts: efforts,
                defaultEffort: efforts.contains("low") ? "low" : efforts.first,
                supportsVerbosity: false,
                priority: index,
                supportsFast: false,
                thinking: adaptive
            )
        }
    }

    static func summary(_ id: String) -> String? {
        if id.contains("fable") || id.contains("mythos") { return "Самая мощная и самая дорогая" }
        if id.contains("opus") { return "Умная, для сложных задач" }
        if id.contains("sonnet") { return "Быстрая и умная, дешевле Opus" }
        if id.contains("haiku") { return "Самая быстрая и дешёвая" }
        return nil
    }

    // MARK: Helpers

    func makeRequest(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
    }

    private final class ConnectivityDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let onWaiting: @Sendable () -> Void

        init(onWaiting: @escaping @Sendable () -> Void) {
            self.onWaiting = onWaiting
        }

        func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
            onWaiting()
        }
    }

    static func error(status: Int, body: Data) -> APIError {
        let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let error = obj?["error"] as? [String: Any]
        let type = error?["type"] as? String ?? ""
        let message = error?["message"] as? String ?? ""
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return type == "not_found_error" && message.lowercased().contains("model") ? .modelNotFound : .http(404, message)
        case 429: return .rateLimited
        case 529: return .overloaded
        default: return streamError(type: type, message: message, status: status)
        }
    }

    static func streamError(type: String, message: String, status: Int = 0) -> APIError {
        let lower = message.lowercased()
        if lower.contains("credit balance") || lower.contains("billing") { return .lowBalance }
        switch type {
        case "authentication_error": return .unauthorized
        case "permission_error": return .forbidden(message)
        case "rate_limit_error": return .rateLimited
        case "overloaded_error": return .overloaded
        default:
            if status == 0 { return .stream(message.isEmpty ? "Claude прервал ответ." : message) }
            return .http(status, message)
        }
    }
}
