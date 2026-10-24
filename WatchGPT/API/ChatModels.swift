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

    var id: String { slug }

    /// Used until the live list arrives from ChatGPT (and when offline).
    static let fallback: [ModelOption] = [
        .init(slug: "gpt-6.1-sol", displayName: "GPT-6.1-Sol", summary: "Основная модель на каждый день", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "low", supportsVerbosity: true, priority: 1),
        .init(slug: "gpt-6-astra", displayName: "GPT-6-Astra", summary: "Самая умная, для сложных задач", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "low", supportsVerbosity: true, priority: 2),
        .init(slug: "gpt-6-sol", displayName: "GPT-6-Sol", summary: "Прошлое поколение", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "medium", supportsVerbosity: true, priority: 3),
        .init(slug: "gpt-6-luna", displayName: "GPT-6-Luna", summary: "Быстрая и лёгкая", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium", supportsVerbosity: true, priority: 4),
        .init(slug: "gpt-5.6-sol", displayName: "GPT-5.6-Sol", summary: "Старое поколение", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "low", supportsVerbosity: true, priority: 5),
        .init(slug: "gpt-5.5", displayName: "GPT-5.5", summary: "Устаревшая", efforts: ["low", "medium", "high", "xhigh"], defaultEffort: "medium", supportsVerbosity: true, priority: 13),
    ]

    static func effortLabel(_ effort: String) -> String {
        switch effort {
        case "none": return "Без размышлений"
        case "minimal": return "Минимум"
        case "low": return "Быстро"
        case "medium": return "Средне"
        case "high": return "Глубоко"
        case "xhigh": return "Очень глубоко"
        case "max": return "Максимум"
        case "ultra": return "Ультра"
        default: return effort.capitalized
        }
    }
}
