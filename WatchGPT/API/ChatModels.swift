import Foundation

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    enum Refinement: String, Codable, Sendable {
        case shorter, longer

        var label: String {
            switch self {
            case .shorter: return "Короче"
            case .longer: return "Подробнее"
            }
        }

        var icon: String {
            switch self {
            case .shorter: return "arrow.down.right.and.arrow.up.left"
            case .longer: return "arrow.up.left.and.arrow.down.right"
            }
        }

        var prompt: String {
            switch self {
            case .shorter:
                return "Rewrite your previous answer much shorter: one or two sentences with only the key point. Reply in the same language as your previous answer."
            case .longer:
                return "Expand your previous answer: add more detail, explanation and an example, but keep it easy to read on a small watch screen. Reply in the same language as your previous answer."
            }
        }

        var verbosity: String {
            switch self {
            case .shorter: return "low"
            case .longer: return "high"
            }
        }
    }

    var id = UUID()
    var role: Role
    var text: String
    var isError = false
    var date = Date.now
    var fromGPT: Bool?
    var refine: Refinement?
    var claude: Bool?

    var modelText: String { refine?.prompt ?? text }
}

enum Provider: String, Codable, CaseIterable, Sendable {
    case chatgpt, claude

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        }
    }
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
    var thinking: Bool?

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

    static let claudeFallback: [ModelOption] = [
        .init(slug: "claude-opus-5-5", displayName: "Claude Opus 5.5", summary: AnthropicClient.summary("claude-opus-5-5"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 1, supportsFast: false, thinking: true),
        .init(slug: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5", summary: AnthropicClient.summary("claude-sonnet-5-5"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 2, supportsFast: false, thinking: true),
        .init(slug: "claude-haiku-5-5", displayName: "Claude Haiku 5.5", summary: AnthropicClient.summary("claude-haiku-5-5"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 3, supportsFast: false, thinking: true),
        .init(slug: "claude-fable-5-1", displayName: "Claude Fable 5.1", summary: AnthropicClient.summary("claude-fable-5-1"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 4, supportsFast: false, thinking: true),
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

    static let gptPrefix = "gpt-"

    static func gptID(_ remoteID: String) -> String { gptPrefix + remoteID }

    init?(id: String, messages: [ChatMessage], title: String? = nil) {
        let kept = messages.filter { !$0.text.isEmpty }
        guard let question = kept.first(where: { $0.role == .user }) else { return nil }
        self.id = id
        self.messages = kept
        let custom = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = Self.clip(custom.isEmpty ? question.text : custom, 80)
        let answer = kept.last { $0.role == .assistant && !$0.isError }
        self.preview = answer.map { Self.clip(MathFormat.plain($0.text), 140) } ?? ""
        self.updatedAt = kept.last?.date ?? question.date
    }

    var messageCount: Int { messages.count П}

    var isFromGPT: Bool { id.hasPrefix(Self.gptPrefix) }

    var isClaude: Bool { messages.last { $0.role == .assistant && !$0.isError }?.claude == true }

    private static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
