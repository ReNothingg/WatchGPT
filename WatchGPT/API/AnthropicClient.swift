import Foundation

struct AnthropicClient: Sendable {
    static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let fastBeta = "fast-mode-2026-02-01"
    static let maxTokens = 32_000
    static let maxRounds = 4

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
                return String(localized: "Добавьте API-ключ Anthropic: Настройки → Claude.")
            case .unauthorized:
                return String(localized: "API-ключ Anthropic не подходит. Проверьте его в настройках.")
            case let .forbidden(message):
                return message.isEmpty ? String(localized: "Anthropic: доступ запрещён (403).") : String(localized: "Anthropic: доступ запрещён — \(message)")
            case .modelNotFound:
                return String(localized: "Эта модель Claude недоступна для вашего ключа. Выберите другую.")
            case .rateLimited:
                return String(localized: "Слишком много запросов к Claude. Подождите немного.")
            case .overloaded:
                return String(localized: "Claude сейчас перегружен. Попробуйте чуть позже.")
            case .lowBalance:
                return String(localized: "На балансе Anthropic не хватает денег. Пополните его в console.anthropic.com.")
            case .refusal:
                return String(localized: "Claude отказался отвечать на этот вопрос.")
            case let .http(code, message):
                return message.isEmpty ? String(localized: "Ошибка Claude (\(code)).") : message
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
        var fast: Bool = false
        var summarizeThinking = true
        var instructions: String
        var context: String?
    }

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

    private struct RoundState {
        var sawText = false
        var needsBreak = false
        var sawThinking = false
        var cited = false
        var results: [ChatMessage.Source] = []
    }

    private func runStream(
        messages: [ChatMessage],
        options: Options,
        continuation: AsyncThrowingStream<ChatGPTClient.StreamEvent, Error>.Continuation
    ) async throws {
        var options = options
        var state = RoundState()
        var carried: [[String: Any]] = []
        var stopReason: String?
        for round in 0..<Self.maxRounds {
            let (reason, blocks) = try await runRound(
                messages: messages, options: &options, carried: carried, state: &state, continuation: continuation
            )
            stopReason = reason
            carried += blocks
            if reason != "pause_turn" || carried.isEmpty || round == Self.maxRounds - 1 { break }
        }

        if !state.cited {
            for source in state.results.prefix(3) { continuation.yield(.source(source)) }
        }
        switch stopReason {
        case "refusal":
            if !state.sawText { throw APIError.refusal }
            continuation.yield(.stopped(.refusal))
        case "max_tokens":
            continuation.yield(.stopped(.maxTokens))
        case "model_context_window_exceeded":
            continuation.yield(.stopped(.contextWindow))
        case "pause_turn":
            continuation.yield(.stopped(.paused))
        default:
            break
        }
        continuation.yield(.completed)
    }

    private func runRound(
        messages: [ChatMessage],
        options: inout Options,
        carried: [[String: Any]],
        state: inout RoundState,
        continuation: AsyncThrowingStream<ChatGPTClient.StreamEvent, Error>.Continuation
    ) async throws -> (stopReason: String?, blocks: [[String: Any]]) {
        while true {
            var request = makeRequest(Self.baseURL.appending(path: "messages"), method: "POST")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var betas: [String] = []
            if Self.supportsFallbacks(options.model) { betas.append(Self.fallbackBeta) }
            if options.fast { betas.append(Self.fastBeta) }
            if !betas.isEmpty {
                request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
            }
            request.httpBody = try JSONSerialization.data(
                withJSONObject: Self.body(messages: messages, options: options, carried: carried)
            )
            request.timeoutInterval = 180

            let delegate = ConnectivityDelegate { continuation.yield(.waitingForNetwork) }
            let (bytes, response) = try await ChatGPTClient.streamSession.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.stream(String(localized: "Нет ответа от сервера Anthropic."))
            }
            continuation.yield(.responseStarted)

            guard (200..<300).contains(http.statusCode) else {
                var data = Data()
                for try await byte in bytes {
                    data.append(byte)
                    if data.count > 16_384 { break }
                }
                let error = Self.error(status: http.statusCode, body: data)
                if options.fast, Self.fastUnavailable(error) {
                    options.fast = false
                    continue
                }
                if options.summarizeThinking, Self.displayUnsupported(error) {
                    options.summarizeThinking = false
                    continue
                }
                throw error
            }

            var blocks: [Int: [String: Any]] = [:]
            var partials: [Int: String] = [:]
            var stopReason: String?

            func finished() -> [[String: Any]] {
                blocks.keys.sorted().compactMap { index -> [String: Any]? in
                    guard var block = blocks[index] else { return nil }
                    if let partial = partials[index], !partial.isEmpty,
                       let data = partial.data(using: .utf8),
                       let input = try? JSONSerialization.jsonObject(with: data) {
                        block["input"] = input
                    }
                    if (block["type"] as? String) == "text", (block["text"] as? String ?? "").isEmpty { return nil }
                    return block
                }
            }

            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                guard let data = payload.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = event["type"] as? String else { continue }

                switch type {
                case "content_block_start":
                    guard let block = event["content_block"] as? [String: Any] else { continue }
                    if let index = event["index"] as? Int { blocks[index] = block }
                    let blockType = block["type"] as? String ?? ""
                    switch blockType {
                    case "server_tool_use":
                        continuation.yield(.searching)
                    case "web_search_tool_result":
                        for result in block["content"] as? [[String: Any]] ?? [] {
                            guard let source = ChatMessage.Source(url: result["url"] as? String, title: result["title"] as? String),
                                  !state.results.contains(source) else { continue }
                            state.results.append(source)
                        }
                    case "thinking":
                        if let text = block["thinking"] as? String, !text.isEmpty {
                            continuation.yield(.thinkingDelta((state.sawThinking ? "\n\n" : "") + text))
                            state.sawThinking = true
                        } else if state.sawThinking {
                            continuation.yield(.thinkingDelta("\n\n"))
                        }
                    default:
                        break
                    }
                    if blockType == "text" {
                        if let text = block["text"] as? String, !text.isEmpty {
                            continuation.yield(.textDelta((state.needsBreak ? "\n\n" : "") + text))
                            state.needsBreak = false
                            state.sawText = true
                        }
                    } else if state.sawText, blockType != "fallback" {
                        state.needsBreak = true
                    }
                case "content_block_delta":
                    guard let delta = event["delta"] as? [String: Any] else { continue }
                    let index = event["index"] as? Int ?? -1
                    switch delta["type"] as? String {
                    case "text_delta":
                        guard let text = delta["text"] as? String, !text.isEmpty else { continue }
                        let previous = blocks[index]?["text"] as? String ?? ""
                        blocks[index]?["text"] = previous + text
                        continuation.yield(.textDelta((state.needsBreak ? "\n\n" : "") + text))
                        state.needsBreak = false
                        state.sawText = true
                    case "thinking_delta":
                        guard let text = delta["thinking"] as? String, !text.isEmpty else { continue }
                        let previous = blocks[index]?["thinking"] as? String ?? ""
                        blocks[index]?["thinking"] = previous + text
                        continuation.yield(.thinkingDelta(text))
                        state.sawThinking = true
                    case "signature_delta":
                        if let signature = delta["signature"] as? String { blocks[index]?["signature"] = signature }
                    case "citations_delta":
                        guard let citation = delta["citation"] as? [String: Any] else { continue }
                        let previous = blocks[index]?["citations"] as? [[String: Any]] ?? []
                        blocks[index]?["citations"] = previous + [citation]
                        if let source = ChatMessage.Source(url: citation["url"] as? String, title: citation["title"] as? String) {
                            state.cited = true
                            continuation.yield(.source(source))
                        }
                    case "input_json_delta":
                        if let partial = delta["partial_json"] as? String { partials[index, default: ""] += partial }
                    default:
                        continue
                    }
                case "message_delta":
                    let delta = event["delta"] as? [String: Any]
                    if let reason = delta?["stop_reason"] as? String { stopReason = reason }
                case "message_stop":
                    return (stopReason, finished())
                case "error":
                    let error = event["error"] as? [String: Any]
                    throw Self.streamError(type: error?["type"] as? String ?? "", message: error?["message"] as? String ?? "")
                default:
                    continue
                }
            }
            return (stopReason, finished())
        }
    }

    static func body(messages: [ChatMessage], options: Options, carried: [[String: Any]] = []) -> [String: Any] {
        var turns: [(role: String, blocks: [[String: Any]])] = []
        for message in messages where !message.isError && !message.text.isEmpty {
            let role = message.role == .user ? "user" : "assistant"
            if turns.isEmpty && role == "assistant" { continue }
            var blocks: [[String: Any]] = []
            if role == "user" {
                for name in message.images ?? [] {
                    guard let data = Attachments.base64(name) else { continue }
                    blocks.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data]])
                }
            }
            blocks.append(["type": "text", "text": message.modelText])
            if let last = turns.indices.last, turns[last].role == role {
                turns[last].blocks.append(contentsOf: blocks)
            } else {
                turns.append((role, blocks))
            }
        }

        var payload: [[String: Any]] = turns.map { turn in
            ["role": turn.role, "content": turn.blocks]
        }
        if let context = options.context, !context.isEmpty,
           let last = payload.indices.last, (payload[last]["role"] as? String) == "user",
           var content = payload[last]["content"] as? [[String: Any]] {
            content.insert(["type": "text", "text": "<context>\(context)</context>"], at: 0)
            payload[last]["content"] = content
        }
        if !carried.isEmpty {
            payload.append(["role": "assistant", "content": carried])
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
            body["thinking"] = options.summarizeThinking
                ? ["type": "adaptive", "display": "summarized"]
                : ["type": "adaptive"]
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
        if options.fast {
            body["speed"] = "fast"
        }
        return body
    }

    static func supportsFallbacks(_ model: String) -> Bool {
        ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"].contains(model)
    }

    static func supportsFast(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"].contains(model)
    }

    static func fastUnavailable(_ error: APIError) -> Bool {
        switch error {
        case .rateLimited, .overloaded:
            return true
        case let .http(400, message), let .forbidden(message):
            let lower = message.lowercased()
            return lower.contains("speed") || lower.contains("fast")
        default:
            return false
        }
    }

    static func displayUnsupported(_ error: APIError) -> Bool {
        if case let .http(400, message) = error { return message.lowercased().contains("display") }
        return false
    }

    static func webSearchTool(_ model: String) -> String {
        let dynamic = [
            "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
            "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6",
        ]
        return dynamic.contains(model) ? "web_search_20260209" : "web_search_20250305"
    }

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
                supportsFast: Self.supportsFast(id),
                thinking: adaptive
            )
        }
    }

    static func summary(_ id: String) -> String? {
        if id.contains("fable") || id.contains("mythos") { return String(localized: "Самая мощная и самая дорогая") }
        if id.contains("opus") { return String(localized: "Умная, для сложных задач") }
        if id.contains("sonnet") { return String(localized: "Быстрая и умная, дешевле Opus") }
        if id.contains("haiku") { return String(localized: "Самая быстрая и дешёвая") }
        return nil
    }

    func makeRequest(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
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
            if status == 0 { return .stream(message.isEmpty ? String(localized: "Claude прервал ответ.") : message) }
            return .http(status, message)
        }
    }
}
