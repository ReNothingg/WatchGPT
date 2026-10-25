import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    enum Source: String, Codable {
        case answer = "Ответ"
        case usage = "Лимиты"
        case models = "Модели"
        case voice = "Голос"
        case check = "Проверка"
    }

    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var date: Date
        var source: Source
        var message: String
        var detail: String?
    }

    private(set) var entries: [Entry] = []
    private(set) var lastSuccess: Date?

    private static let limit = 30
    private let defaults = UserDefaults.standard
    private let entriesKey = "diagnostics.entries"
    private let successKey = "diagnostics.lastSuccess"

    private init() {
        if let data = defaults.data(forKey: entriesKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
        lastSuccess = defaults.object(forKey: successKey) as? Date
    }

    func record(_ source: Source, _ error: Error) {
        record(source, message: ChatStore.describe(error), detail: Self.detail(for: error))
    }

    func record(_ source: Source, message: String, detail: String? = nil) {
        entries.insert(Entry(date: .now, source: source, message: message, detail: detail), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func markSuccess() {
        lastSuccess = .now
        defaults.set(lastSuccess, forKey: successKey)
    }

    func clear() {
        entries = []
        save()
    }

    static func detail(for error: Error) -> String? {
        switch error {
        case let api as ChatGPTClient.APIError:
            switch api {
            case .unauthorized: return "HTTP 401"
            case .usageLimit: return "usage_limit"
            case let .http(code, _): return "HTTP \(code)"
            case .stream: return "stream error"
            }
        case let url as URLError:
            return "URLError \(url.code.rawValue)"
        default:
            let ns = error as NSError
            return "\(ns.domain) \(ns.code)"
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: entriesKey)
        }
    }
}
