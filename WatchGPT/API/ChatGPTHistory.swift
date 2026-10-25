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

    static func conversation(from obj: [String: Any], id: String) throws -> RemoteConversation {
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
        for raw in chain.reversed() {
            guard let message = message(from: raw, fallbackDate: updatedAt) else { continue }
            if message.role == .assistant, let last = messages.last, last.role == .assistant {
                messages[messages.count - 1].text = HistoryText.clip(last.text + "\n\n" + message.text)
                messages[messages.count - 1].date = message.date
            } else {
                messages.append(message)
            }
        }

        let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return RemoteConversation(
            id: id,
            title: title.isEmpty ? "Без названия" : title,
            updatedAt: updatedAt,
            messages: messages
        )
    }

    private static func latestLeaf(_ mapping: [String: [String: Any]]) -> String? {
        func created(_ node: [String: Any]) -> Double {
            number((node["message"] as? [String: Any])?["create_time"]) ?? 0
        }
        let leaves = mapping.filter { ($0.value["children"] as? [Any])?.isEmpty ?? true }
        return leaves.max { created($0.value) < created($1.value) }?.key
    }

    private static func message(from raw: [String: Any], fallbackDate: Date) -> ChatMessage? {
        let roleName = (raw["author"] as? [String: Any])?["role"] as? String ?? ""
        let recipient = raw["recipient"] as? String ?? "all"
        let metadata = raw["metadata"] as? [String: Any]
        guard recipient == "all",
              metadata?["is_visually_hidden_from_conversation"] as? Bool != true,
              metadata?["is_user_system_message"] as? Bool != true,
              let content = raw["content"] as? [String: Any] else { return nil }

        let type = content["content_type"] as? String ?? ""
        guard type == "text" || type == "multimodal_text" else { return nil }
        let parts = content["parts"] as? [Any] ?? []

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
            guard imageCount(parts) > 0 else { return nil }
            role = .assistant
            text = imageLabel(imageCount(parts))
        default:
            return nil
        }
        guard !text.isEmpty else { return nil }

        let date = number(raw["create_time"]).map { Date(timeIntervalSince1970: $0) } ?? fallbackDate
        return ChatMessage(id: stableID(raw["id"] as? String), role: role, text: text, date: date, fromGPT: true)
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
        let images = imageCount(parts)
        guard images > 0 else { return text }
        return text.isEmpty ? imageLabel(images) : imageLabel(images) + "\n" + text
    }

    private static func imageCount(_ parts: [Any]) -> Int {
        parts.filter { ($0 as? [String: Any])?["content_type"] as? String == "image_asset_pointer" }.count
    }

    private static func imageLabel(_ count: Int) -> String {
        count == 1 ? "🖼 Изображение" : "🖼 Изображения: \(count)"
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
