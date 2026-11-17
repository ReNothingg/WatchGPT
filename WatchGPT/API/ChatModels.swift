import Foundation

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    enum Refinement: String, Codable, Sendable {
        case shorter, longer

        var label: String {
            switch self {
            case .shorter: return String(localized: "Короче")
            case .longer: return String(localized: "Подробнее")
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

    enum StopNote: String, Codable, Sendable {
        case maxTokens, contextWindow, refusal, filtered, paused

        var canContinue: Bool { self == .maxTokens || self == .paused }

        var label: String {
            switch self {
            case .maxTokens: return String(localized: "Ответ обрезан: достигнут предел длины.")
            case .contextWindow: return String(localized: "Чат стал слишком длинным, ответ обрезан. Начните новый чат.")
            case .refusal: return String(localized: "Модель прервала ответ и отказалась продолжать.")
            case .filtered: return String(localized: "Ответ остановлен фильтром содержимого.")
            case .paused: return String(localized: "Поиск занял слишком много шагов, ответ может быть неполным.")
            }
        }
    }

    struct Source: Codable, Equatable, Hashable, Identifiable, Sendable {
        var url: String
        var title: String

        var id: String { url }

        var host: String {
            let host = URL(string: url)?.host() ?? url
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }

        init?(url: String?, title: String?) {
            guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  var components = URLComponents(string: raw), components.scheme?.hasPrefix("http") == true else { return nil }
            let kept = components.queryItems?.filter { !$0.name.hasPrefix("utm_") }
            components.queryItems = kept?.isEmpty == false ? kept : nil
            self.url = components.string ?? raw
            let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.title = name.isEmpty ? (components.host ?? raw) : name
        }
    }

    static let maxSources = 12
    static let maxReasoning = 12_000

    var id = UUID()
    var role: Role
    var text: String
    var isError = false
    var date = Date.now
    var fromGPT: Bool?
    var refine: Refinement?
    var claude: Bool?
    var versions: [[ChatMessage]]?
    var versionIndex: Int?
    var images: [String]?
    var stop: StopNote?
    var sources: [Source]?
    var reasoning: String?
    var thinkingSeconds: Int?

    var modelText: String { refine?.prompt ?? text }

    var allImages: [String] {
        (images ?? []) + (versions ?? []).flatMap { $0.flatMap(\.allImages) }
    }
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

    static let fallback: [ModelOption] = [
        .init(slug: "gpt-6.1-sol", displayName: "GPT-6.1-Sol", summary: String(localized: "Основная модель на каждый день"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: true, priority: 1),
        .init(slug: "gpt-6-astra", displayName: "GPT-6-Astra", summary: String(localized: "Самая умная, для сложных задач"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: true, priority: 2),
        .init(slug: "gpt-6-sol", displayName: "GPT-6-Sol", summary: String(localized: "Прошлое поколение"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium", supportsVerbosity: true, priority: 3),
        .init(slug: "gpt-6-luna", displayName: "GPT-6-Luna", summary: String(localized: "Быстрая и лёгкая"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium", supportsVerbosity: true, priority: 4),
        .init(slug: "gpt-5.6-sol", displayName: "GPT-5.6-Sol", summary: String(localized: "Старое поколение"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: true, priority: 5),
        .init(slug: "gpt-5.5", displayName: "GPT-5.5", summary: String(localized: "Устаревшая"), efforts: ["low", "medium", "high", "xhigh"], defaultEffort: "medium", supportsVerbosity: true, priority: 13),
    ]

    static let claudeFallback: [ModelOption] = [
        .init(slug: "claude-opus-5-5", displayName: "Claude Opus 5.5", summary: AnthropicClient.summary("claude-opus-5-5"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 1, supportsFast: true, thinking: true),
        .init(slug: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5", summary: AnthropicClient.summary("claude-sonnet-5-5"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 2, supportsFast: false, thinking: true),
        .init(slug: "claude-haiku-5-5", displayName: "Claude Haiku 5.5", summary: AnthropicClient.summary("claude-haiku-5-5"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 3, supportsFast: false, thinking: true),
        .init(slug: "claude-fable-5-1", displayName: "Claude Fable 5.1", summary: AnthropicClient.summary("claude-fable-5-1"), efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "low", supportsVerbosity: false, priority: 4, supportsFast: false, thinking: true),
    ]

    static func effortRank(_ effort: String) -> Int {
        ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].firstIndex(of: effort) ?? 3
    }

    static func effortLabel(_ effort: String) -> String {
        switch effort {
        case "none": return String(localized: "Без рассуждений")
        case "minimal": return String(localized: "Минимальное")
        case "low": return String(localized: "Низкое")
        case "medium": return String(localized: "Среднее")
        case "high": return String(localized: "Высокое")
        case "xhigh": return String(localized: "Очень высокое")
        case "max": return String(localized: "Максимальное")
        case "ultra": return String(localized: "Ультра")
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

    var messageCount: Int { messages.count }

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
