import Foundation

struct QuickPrompt: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var asksVoice: Bool

    func message(with spoken: String) -> String {
        let tail = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard asksVoice, !tail.isEmpty else { return text }
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = head.hasSuffix(":") || head.hasSuffix("…") ? " " : ": "
        return head + separator + tail
    }

    static let defaults: [QuickPrompt] = [
        QuickPrompt(text: "Переведи на английский", asksVoice: true),
        QuickPrompt(text: "Объясни простыми словами", asksVoice: true),
        QuickPrompt(text: "Посчитай", asksVoice: true),
        QuickPrompt(text: "Главные новости сегодня", asksVoice: false),
    ]

    static let limit = 12
}
