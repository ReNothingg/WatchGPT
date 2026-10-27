import CryptoKit
import Foundation

struct RemoteChat: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var updatedAt: Date
}

struct RemoteConversation: Equatable, Sendable {
    var id: String
    var title: String
    var updatedAt: Date
    var messages: [ChatMessage]
    var images: [UUID: [RemoteImage]] = [:]
    var reasoning: [UUID: Reasoning] = [:]
    var live: LiveTurn?
}

struct RemoteImage: Equatable, Hashable, Identifiable, Sendable {
    var pointer: String
    var width: Int?
    var height: Int?

    var id: String { pointer }

    var aspect: Double {
        guard let width, let height, width > 0, height > 0 else { return 1 }
        return min(2, max(0.5, Double(width) / Double(height)))
    }
}

struct ReasoningStep: Equatable, Identifiable, Sendable {
    var id: Int
    var title: String
    var detail: String
    var icon: String?
}

struct Reasoning: Equatable, Sendable {
    var steps: [ReasoningStep] = []
    var seconds: Int?

    var isEmpty: Bool { steps.isEmpty && seconds == nil }

    static let maxSteps = 40

    mutating func add(title: String, detail: String, icon: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !detail.isEmpty else { return }
        if let last = steps.last, last.title == title, last.icon == icon, last.detail.isEmpty || detail.isEmpty || last.detail == detail {
            if last.detail.isEmpty { steps[steps.count - 1].detail = detail }
            return
        }
        steps.append(ReasoningStep(id: (steps.last?.id ?? -1) + 1, title: title, detail: detail, icon: icon))
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
    }

    mutating func absorb(_ other: Reasoning) {
        for step in other.steps { add(title: step.title, detail: step.detail, icon: step.icon) }
        if let seconds = other.seconds { self.seconds = (self.seconds ?? 0) + seconds }
    }
}

struct LiveTurn: Equatable, Sendable {
    var startedAt: Date
    var stage: String
    var icon: String
    var reasoning: Reasoning
}

extension ChatGPTClient {
    enum HistoryError: LocalizedError {
        case notAllowed(Int)
        case notFound
        case unreadable

        var errorDescription: String? {
            switch self {
            case let .notAllowed(code):
                return "ChatGPT не открыл историю для этого входа (\(code)). Возможно, OpenAI закрыл к ней доступ для Codex."
            case .notFound:
                return "Чат не найден: возможно, его удалили или перенесли в архив."
            case .unreadable:
                return "Не удалось прочитать историю ChatGPT."
            }
        }
    }

    struct ChatPage: Sendable {
        var items: [RemoteChat]
        var nextOffset: Int?
        var nextCursor: String?

        var hasMore: Bool { nextOffset != nil || nextCursor != nil }
    }

    func fetchChats(offset: Int = 0, cursor: String? = nil, limit: Int = 28) async throws -> ChatPage {
        var components = URLComponents(url: Self.baseURL.appending(path: "conversations"), resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: "updated"),
            URLQueryItem(name: "is_archived", value: "false"),
        ]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        } else {
            query.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        components.queryItems = query

        let obj = try await getJSON(components.url!)
        let raw = obj["items"] as? [[String: Any]] ?? []
        let items = raw.compactMap { item -> RemoteChat? in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let updated = Self.date(item["update_time"]) ?? Self.date(item["create_time"]) ?? .distantPast
            return RemoteChat(id: id, title: title.isEmpty ? "Без названия" : title, updatedAt: updated)
        }

        let nextCursor = (obj["cursor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var nextOffset: Int?
        if nextCursor == nil, cursor == nil, raw.count >= limit {
            let next = offset + raw.count
            let total = Self.number(obj["total"]).map { Int($0) } ?? 0
            if total <= 0 || next < total { nextOffset = next }
        }
        return ChatPage(items: items, nextOffset: nextOffset, nextCursor: nextCursor)
    }

    func fetchConversation(id: String) async throws -> RemoteConversation {
        let obj = try await getJSON(Self.baseURL.appending(path: "conversation").appending(path: id))
        return try Self.conversation(from: obj, id: id)
    }

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        var request = makeRequest(url, method: "GET")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        switch status {
        case 200..<300:
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw HistoryError.unreadable
            }
            return obj
        case 401:
            throw APIError.unauthorized
        case 403:
            throw Self.networkBlock(body: data, response: http) ?? HistoryError.notAllowed(403)
        case 404:
            throw HistoryError.notFound
        default:
            throw Self.error(status: status, body: data, response: http)
        }
    }

    static func conversation(from obj: [String: Any], id: String, now: Date = .now) throws -> RemoteConversation {
        guard let mapping = obj["mapping"] as? [String: [String: Any]] else { throw HistoryError.unreadable }

        let updatedAt = date(obj["update_time"]) ?? date(obj["create_time"]) ?? .now
        var nodeID = (obj["current_node"] as? String).flatMap { mapping[$0] == nil ? nil : $0 } ?? latestLeaf(mapping)
        var chain: [[String: Any]] = []
        var seen = Set<String>()
        while let current = nodeID, let node = mapping[current], seen.insert(current).inserted {
            if let message = node["message"] as? [String: Any] { chain.append(message) }
            nodeID = node["parent"] as? String
        }

        var messages: [ChatMessage] = []
        var images: [UUID: [RemoteImage]] = [:]
        var reasoning: [UUID: Reasoning] = [:]
        var pending = Reasoning()
        var turnStart: Date?
        var turnAnswer: UUID?
        var lastRaw: [String: Any]?

        for raw in chain.reversed() {
            if role(raw) == "system" { continue }
            lastRaw = raw
            collectReasoning(raw, into: &pending)
            guard let parsed = message(from: raw, fallbackDate: updatedAt) else { continue }
            let (message, pictures) = parsed

            let target: UUID
            if message.role == .assistant, let last = messages.last, last.role == .assistant {
                let joined = [last.text, message.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
                messages[messages.count - 1].text = HistoryText.clip(joined)
                messages[messages.count - 1].date = message.date
                target = last.id
            } else {
                messages.append(message)
                target = message.id
            }
            if !pictures.isEmpty { images[target, default: []] += pictures }

            switch message.role {
            case .user:
                turnStart = message.date
                turnAnswer = nil
                pending = Reasoning()
            case .assistant:
                turnAnswer = target
                if !pending.isEmpty {
                    reasoning[target, default: Reasoning()].absorb(pending)
                    pending = Reasoning()
                }
            }
        }

        var live: LiveTurn?
        if let lastRaw, let turnStart, isUnfinished(lastRaw, now: now) {
            var current = Reasoning()
            if let turnAnswer, let attached = reasoning.removeValue(forKey: turnAnswer) { current = attached }
            current.absorb(pending)
            let phase = stage(of: lastRaw, reasoning: current)
            live = LiveTurn(startedAt: turnStart, stage: phase.0, icon: phase.1, reasoning: current)
        }

        let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return RemoteConversation(
            id: id,
            title: title.isEmpty ? "Без названия" : title,
            updatedAt: updatedAt,
            messages: messages,
            images: images,
            reasoning: reasoning,
            live: live
        )
    }

    private static func latestLeaf(_ mapping: [String: [String: Any]]) -> String? {
        func created(_ node: [String: Any]) -> Double {
            number((node["message"] as? [String: Any])?["create_time"]) ?? 0
        }
        let leaves = mapping.filter { ($0.value["children"] as? [Any])?.isEmpty ?? true }
        return leaves.max { created($0.value) < created($1.value) }?.key
    }

    private static func role(_ raw: [String: Any]) -> String {
        (raw["author"] as? [String: Any])?["role"] as? String ?? ""
    }

    private static func contentType(_ raw: [String: Any]) -> String {
        (raw["content"] as? [String: Any])?["content_type"] as? String ?? ""
    }

    private static func message(from raw: [String: Any], fallbackDate: Date) -> (ChatMessage, [RemoteImage])? {
        let roleName = role(raw)
        let recipient = raw["recipient"] as? String ?? "all"
        let metadata = raw["metadata"] as? [String: Any]
        guard recipient == "all",
              metadata?["is_visually_hidden_from_conversation"] as? Bool != true,
              metadata?["is_user_system_message"] as? Bool != true,
              let content = raw["content"] as? [String: Any] else { return nil }

        let type = content["content_type"] as? String ?? ""
        guard type == "text" || type == "multimodal_text" else { return nil }
        let parts = content["parts"] as? [Any] ?? []
        let pictures = imageParts(parts)

        let role: ChatMessage.Role
        let text: String
        switch roleName {
        case "user":
            role = .user
            text = HistoryText.clean(partsText(parts))
        case "assistant":
            role = .assistant
            text = HistoryText.clean(partsText(parts))
        case "tool":
            guard !pictures.isEmpty else { return nil }
            role = .assistant
            text = imageLabel(pictures.count)
        default:
            return nil
        }
        guard !text.isEmpty else { return nil }

        let date = number(raw["create_time"]).map { Date(timeIntervalSince1970: $0) } ?? fallbackDate
        let message = ChatMessage(id: stableID(raw["id"] as? String), role: role, text: text, date: date, fromGPT: true)
        return (message, pictures)
    }

    private static func collectReasoning(_ raw: [String: Any], into reasoning: inout Reasoning) {
        let metadata = raw["metadata"] as? [String: Any]
        let content = raw["content"] as? [String: Any] ?? [:]
        let recipient = raw["recipient"] as? String ?? "all"

        switch content["content_type"] as? String ?? "" {
        case "thoughts":
            for thought in content["thoughts"] as? [[String: Any]] ?? [] {
                let summary = thought["summary"] as? String ?? ""
                var body = thought["content"] as? String ?? ""
                if body.isEmpty, let chunks = thought["chunks"] as? [String] { body = chunks.joined(separator: " ") }
                reasoning.add(title: HistoryText.plain(summary, limit: 120), detail: HistoryText.plain(body, limit: 1200))
            }
        case "reasoning_recap":
            if reasoning.seconds == nil {
                reasoning.seconds = number(metadata?["finished_duration_sec"]).map { Int($0.rounded()) }
                    ?? (content["content"] as? String).flatMap(seconds(fromRecap:))
            }
        default:
            if role(raw) == "assistant", recipient != "all" {
                let (title, icon) = toolStage(recipient)
                reasoning.add(title: title, detail: toolDetail(content), icon: icon)
            }
        }

        if reasoning.seconds == nil, let seconds = number(metadata?["finished_duration_sec"]), seconds > 0 {
            reasoning.seconds = Int(seconds.rounded())
        }
    }

    private static func isUnfinished(_ raw: [String: Any], now: Date) -> Bool {
        let status = raw["status"] as? String ?? ""
        let recipient = raw["recipient"] as? String ?? "all"
        let type = contentType(raw)
        let parts = (raw["content"] as? [String: Any])?["parts"] as? [Any] ?? []

        let finished: Bool
        switch role(raw) {
        case "assistant":
            let isAnswer = recipient == "all" && (type == "text" || type == "multimodal_text")
            finished = isAnswer && (status == "finished_partial_completion"
                || (status != "in_progress" && raw["end_turn"] as? Bool != false))
        case "tool":
            finished = !imageParts(parts).isEmpty && status == "finished_successfully"
        default:
            finished = false
        }
        guard !finished else { return false }

        let activity = number(raw["update_time"]) ?? number(raw["create_time"])
        guard let activity else { return false }
        return now.timeIntervalSince1970 - activity < 15 * 60
    }

    private static func stage(of raw: [String: Any], reasoning: Reasoning) -> (String, String) {
        let recipient = raw["recipient"] as? String ?? "all"
        switch role(raw) {
        case "user":
            let parts = (raw["content"] as? [String: Any])?["parts"] as? [Any] ?? []
            return imageParts(parts).isEmpty ? ("Думает", "brain") : ("Смотрит на изображение", "eye")
        case "tool":
            let name = (raw["author"] as? [String: Any])?["name"] as? String ?? ""
            let (title, icon) = toolStage(name)
            return name.isEmpty ? ("Изучает результаты", "doc.text.magnifyingglass") : (title, icon)
        default:
            break
        }
        if recipient != "all" { return toolStage(recipient) }
        switch contentType(raw) {
        case "thoughts":
            let summary = reasoning.steps.last { $0.icon == nil }?.title ?? ""
            return (summary.isEmpty ? "Думает" : summary, "brain")
        case "text", "multimodal_text", "reasoning_recap":
            return ("Пишет ответ", "pencil")
        default:
            return ("Думает", "brain")
        }
    }

    static func toolStage(_ name: String) -> (String, String) {
        let n = name.lowercased()
        if n.hasPrefix("web") || n.contains("browser") || n.contains("search") {
            return ("Ищет в интернете", "globe")
        }
        if n.contains("dalle") || n.contains("image") || n.contains("t2uay3k") {
            return ("Рисует изображение", "paintbrush")
        }
        if n.contains("python") || n.contains("code") || n.contains("container") {
            return ("Запускает код", "terminal")
        }
        if n.contains("file") || n.contains("doc") {
            return ("Читает файлы", "doc.text")
        }
        if n.hasPrefix("bio") || n.contains("memory") {
            return ("Обновляет память", "brain.head.profile")
        }
        if n.contains("canmore") || n.contains("canvas") {
            return ("Пишет в холсте", "doc.richtext")
        }
        if n.contains("research") {
            return ("Исследует", "magnifyingglass")
        }
        return ("Использует инструменты", "wrench.and.screwdriver")
    }

    private static func toolDetail(_ content: [String: Any]) -> String {
        let text = (content["text"] as? String) ?? ((content["parts"] as? [Any])?.compactMap { $0 as? String }.joined(separator: "\n")) ?? ""
        guard !text.isEmpty else { return "" }
        if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
            var found: [String] = []
            collectQueries(json, into: &found)
            return found.prefix(3).map { "«\($0)»" }.joined(separator: "\n")
        }
        return ""
    }

    private static func collectQueries(_ any: Any, into found: inout [String]) {
        guard found.count < 3 else { return }
        if let dict = any as? [String: Any] {
            for key in ["q", "query", "prompt", "search_query", "queries"] {
                if let value = dict[key] as? String {
                    let flat = HistoryText.plain(value, limit: 120)
                    if !flat.isEmpty, !found.contains(flat) { found.append(flat) }
                }
            }
            for value in dict.values where !(value is String) { collectQueries(value, into: &found) }
        } else if let array = any as? [Any] {
            for value in array {
                if let string = value as? String {
                    let flat = HistoryText.plain(string, limit: 120)
                    if !flat.isEmpty, !found.contains(flat), found.count < 3 { found.append(flat) }
                } else {
                    collectQueries(value, into: &found)
                }
            }
        }
    }

    static func seconds(fromRecap text: String) -> Int? {
        let pattern = #"(\d+)\s*(h|ч|m|мин|s|с|сек)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var total = 0
        var matched = false
        for match in regex.matches(in: text, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: text), let value = Int(text[numberRange]) else { continue }
            let unit = Range(match.range(at: 2), in: text).map { text[$0].lowercased() } ?? "s"
            switch unit {
            case "h", "ч": total += value * 3600
            case "m", "мин": total += value * 60
            default: total += value
            }
            matched = true
        }
        return matched ? total : nil
    }

    private static func stableID(_ raw: String?) -> UUID {
        guard let raw, !raw.isEmpty else { return UUID() }
        if let uuid = UUID(uuidString: raw) { return uuid }
        var bytes = Array(SHA256.hash(data: Data(raw.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: bytes) as UUID
    }

    private static func partsText(_ parts: [Any]) -> String {
        var pieces: [String] = []
        for part in parts {
            if let string = part as? String {
                pieces.append(string)
            } else if let dict = part as? [String: Any],
                      dict["content_type"] as? String == "audio_transcription",
                      let transcript = dict["text"] as? String {
                pieces.append(transcript)
            }
        }
        let text = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let images = imageParts(parts).count
        guard images > 0 else { return text }
        return text.isEmpty ? imageLabel(images) : imageLabel(images) + "\n" + text
    }

    private static func imageParts(_ parts: [Any]) -> [RemoteImage] {
        parts.compactMap { part in
            guard let dict = part as? [String: Any],
                  dict["content_type"] as? String == "image_asset_pointer",
                  let pointer = dict["asset_pointer"] as? String, !pointer.isEmpty else { return nil }
            return RemoteImage(
                pointer: pointer,
                width: number(dict["width"]).map { Int($0) },
                height: number(dict["height"]).map { Int($0) }
            )
        }
    }

    private static func imageLabel(_ count: Int) -> String {
        count == 1 ? "\(HistoryText.imageMark) Изображение" : "\(HistoryText.imageMark) Изображения: \(count)"
    }

    func imageData(pointer: String, conversationID: String) async throws -> Data {
        guard let separator = pointer.range(of: "://") else { throw HistoryError.unreadable }
        let scheme = pointer[..<separator.lowerBound]
        let fileID = String(pointer[separator.upperBound...])
        guard !fileID.isEmpty else { throw HistoryError.unreadable }

        let infoURL: URL
        if scheme == "sediment" {
            var components = URLComponents(url: Self.baseURL.appending(path: "files/download").appending(path: fileID), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "conversation_id", value: conversationID),
                URLQueryItem(name: "inline", value: "false"),
            ]
            infoURL = components.url!
        } else {
            infoURL = Self.baseURL.appending(path: "files").appending(path: fileID).appending(path: "download")
        }

        let info = try await getJSON(infoURL)
        guard let link = info["download_url"] as? String,
              let url = URL(string: link, relativeTo: URL(string: "https://chatgpt.com")!)?.absoluteURL else {
            throw HistoryError.unreadable
        }

        var request = url.host?.hasSuffix("chatgpt.com") == true ? makeRequest(url, method: "GET") : URLRequest(url: url)
        request.timeoutInterval = 40
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), !data.isEmpty else {
            throw APIError.http(status, "Картинка не загрузилась (\(status)).")
        }
        return data
    }

    private static let preciseDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainDates = ISO8601DateFormatter()

    static func date(_ any: Any?) -> Date? {
        if let seconds = number(any), seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        guard let string = any as? String else { return nil }
        return preciseDates.date(from: string) ?? plainDates.date(from: string)
    }
}

enum HistoryText {
    static let limit = 6000
    static let imageMark = "🖼"

    static func withoutImageLabel(_ text: String) -> String {
        guard text.hasPrefix(imageMark) else { return text }
        let rest = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first ?? ""
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plain(_ text: String, limit: Int) -> String {
        let cleaned = clean(text)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func clean(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "\u{E200}[^\u{E201}]*\u{E201}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "【[^】]*】", with: "", options: .regularExpression)
        s.unicodeScalars.removeAll { (0xE000...0xF8FF).contains($0.value) }

        var lines: [String] = []
        var inCode = false
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode {
                lines.append(trimmed.isEmpty || line.contains("`") ? line : "`\(line)`")
                continue
            }
            if trimmed.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { continue }
            if trimmed.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil { continue }
            if let heading = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let title = trimmed[heading.upperBound...].trimmingCharacters(in: .whitespaces)
                lines.append(title.isEmpty ? "" : "**\(title.replacingOccurrences(of: "**", with: ""))**")
                continue
            }
            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|"), trimmed.count > 1 {
                let cells = trimmed.dropFirst().dropLast()
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                lines.append(cells.joined(separator: " · "))
                continue
            }
            lines.append(line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression))
        }

        let joined = lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clip(joined)
    }

    static func clip(_ text: String) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: "\n").map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n…"
    }
}
