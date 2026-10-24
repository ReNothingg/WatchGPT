import Foundation

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    var isError = false
    var date = Date.now
}

struct ModelOption: Codable, Identifiable, Hashable, Sendable {
    var slug: String
    var displayName: String
    var summary: String?
    var efforts: [String]
    var defaultEffort: String?
    var supportsVerbosity: Bool
    var priority: Int
    var supportsFast: Bool?

    var id: String { slug }

    /// Used until the live list arrives from ChatGPT (and when offline).
    static let fallback: [ModelOption] = [
        .init(slug: "gpt-6.1-sol", displayName: "GPT-6.1-Sol", summary: "Основная модель на каждый день", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: true, priority: 1),
        .init(slug: "gpt-6-astra", displayName: "GPT-6-Astra", summary: "Самая умная, для сложных задач", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: true, priority: 2),
        .init(slug: "gpt-6-sol", displayName: "GPT-6-Sol", summary: "Прошлое поколение", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium", supportsVerbosity: true, priority: 3),
        .init(slug: "gpt-6-luna", displayName: "GPT-6-Luna", summary: "Быстрая и лёгкая", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium", supportsVerbosity: true, priority: 4),
        .init(slug: "gpt-5.6-sol", displayName: "GPT-5.6-Sol", summary: "Старое поколение", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: true, priority: 5),
        .init(slug: "gpt-5.5", displayName: "GPT-5.5", summary: "Устаревшая", efforts: ["low", "medium", "high", "xhigh"], defaultEffort: "medium", supportsVerbosity: true, priority: 13),
    ]

    static func effortRank(_ effort: String) -> Int {
        ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].firstIndex(of: effort) ?? 3
    }

    static func effortLabel(_ effort: String) -> String {
        switch effort {
        case "none": return "Без рассуждений"
        case "minimal": return "Минимальное"
        case "low": return "Низкое"
        case "medium": return "Среднее"
        case "high": return "Высокое"
        case "xhigh": return "Очень высокое"
        case "max": return "Максимальное"
        case "ultra": return "Ультра"
        default: return effort.capitalized
        }
    }
}

struct ChatThread: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var preview: String
    var updatedAt: Date
    var messages: [ChatMessage]

    init?(id: String, messages: [ChatMessage]) {
        let kept = messages.filter { !$0.text.isEmpty }
        guard let question = kept.first(where: { $0.role == .user }) else { return nil }
        self.id = id
        self.messages = kept
        self.title = Self.clip(question.text, 80)
        let answer = kept.last { $0.role == .assistant && !$0.isError }
        self.preview = answer.map { Self.clip(MathFormat.plain($0.text), 140) } ?? ""
        self.updatedAt = kept.last?.date ?? question.date
    }

    var messageCount: Int { messages.count }

    private static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
