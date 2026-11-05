import CryptoKit
import Foundation

extension ChatGPTClient {
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
        var lastRaw: [String: Any]?

        for raw in chain.reversed() {
            if role(raw) == "system" { continue }
            lastRaw = raw
            collectReasoning(raw, into: &pending)
            guard let parsed = message(from: raw, fallbackDate: updatedAt) else { continue }
            let (message, pictures) = parsed

            let target: UUID
            if message.role == .assistant, pending.isEmpty, let last = messages.last, last.role == .assistant {
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
                pending = Reasoning()
            case .assistant:
                if !pending.isEmpty {
                    reasoning[target, default: Reasoning()].absorb(pending)
                    pending = Reasoning()
                }
            }
        }

        var live: LiveTurn?
        if let lastRaw, let turnStart, isUnfinished(lastRaw, now: now) {
            let current = pending
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
                let call = toolCall(recipient: recipient, content: content)
                reasoning.add(title: call.title, detail: call.detail, icon: call.icon)
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
            return imageParts(parts).isEmpty ? ("Думаю", "brain") : ("Смотрю на изображение", "eye")
        case "tool":
            let name = (raw["author"] as? [String: Any])?["name"] as? String ?? ""
            let (title, icon) = toolStage(name)
            return name.isEmpty ? ("Изучаю результаты", "doc.text.magnifyingglass") : (title, icon)
        default:
            break
        }
        if recipient != "all" {
            let call = toolCall(recipient: recipient, content: raw["content"] as? [String: Any] ?? [:])
            return (call.title, call.icon)
        }
        switch contentType(raw) {
        case "thoughts":
            return ("Думаю", "brain")
        case "text", "multimodal_text", "reasoning_recap":
            return ("Пишу ответ", "pencil")
        default:
            return ("Думаю", "brain")
        }
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
