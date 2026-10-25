import Foundation

/// One rate-limit window of the ChatGPT plan (e.g. the 5-hour or the weekly window).
struct UsageWindow: Codable, Equatable, Sendable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetAt: Date?

    /// Percent left right now (resets to 100 once the window has rolled over).
    func remainingPercent(at date: Date = .now) -> Double {
        if let resetAt, date >= resetAt { return 100 }
        return min(100, max(0, 100 - usedPercent))
    }

    /// "5ч", "нед", "24ч"…
    var shortLabel: String {
        guard let m = windowMinutes, m > 0 else { return "лимит" }
        if m >= 7 * 24 * 60 - 60 { return "нед" }
        if m >= 24 * 60 { return "\(Int((Double(m) / 1440).rounded()))д" }
        if m >= 60 { return "\(Int((Double(m) / 60).rounded()))ч" }
        return "\(m)м"
    }

    var longLabel: String {
        guard let m = windowMinutes, m > 0 else { return "Лимит" }
        if m >= 7 * 24 * 60 - 60 { return "Неделя" }
        if m >= 60 { return "\(Int((Double(m) / 60).rounded())) часов" }
        return "\(m) минут"
    }
}

struct UsageSnapshot: Codable, Equatable, Sendable {
    var primary: UsageWindow?
    var secondary: UsageWindow?
    var planType: String?
    var limitReached: Bool = false
    var updatedAt: Date = .now

    /// The window that is closest to running out — what the user cares about.
    func tightest(at date: Date = .now) -> UsageWindow? {
        [primary, secondary].compactMap { $0 }.min { $0.remainingPercent(at: date) < $1.remainingPercent(at: date) }
    }

    var ignoringTimestamp: UsageSnapshot {
        var copy = self
        copy.updatedAt = .distantPast
        return copy
    }

    var forWidget: UsageSnapshot {
        func normalized(_ window: UsageWindow?) -> UsageWindow? {
            guard let window else { return nil }
            return UsageWindow(
                usedPercent: window.usedPercent.rounded(),
                windowMinutes: window.windowMinutes,
                resetAt: window.resetAt.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 60).rounded(.up) * 60) }
            )
        }
        return UsageSnapshot(primary: normalized(primary), secondary: normalized(secondary), updatedAt: .distantPast)
    }

    /// Merges a partial update (e.g. from response headers) over the previous value.
    func merged(with newer: UsageSnapshot) -> UsageSnapshot {
        UsageSnapshot(
            primary: newer.primary ?? primary,
            secondary: newer.secondary ?? secondary,
            planType: newer.planType ?? planType,
            limitReached: newer.limitReached,
            updatedAt: newer.updatedAt
        )
    }

    var planLabel: String? {
        guard let p = planType?.lowercased(), !p.isEmpty else { return nil }
        switch p {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite", "pro_lite": return "Pro Lite"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        case "go": return "Go"
        case "free": return "Free"
        default: return p.capitalized
        }
    }
}

/// What the app shares with the widget through the App Group.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var signedIn: Bool = false
    var usage: UsageSnapshot?
    var lastAnswer: WidgetAnswer?
}

struct WidgetAnswer: Codable, Equatable, Sendable {
    var question: String
    var answer: String
    var date: Date
    var chatID: String
}

enum SharedStore {
    static let snapshotKey = "widget.snapshot.v1"
    static let askWidgetKind = "WatchGPTAsk"
    static let answerWidgetKind = "WatchGPTAnswer"
    static let limitsWidgetKind = "WatchGPTLimits"
    static let deepLinkAsk = URL(string: "watchgpt://ask")!
    static let deepLinkOpen = URL(string: "watchgpt://open")!
    static let deepLinkUsage = URL(string: "watchgpt://usage")!

    static func deepLink(chatID: String) -> URL {
        var components = URLComponents(url: deepLinkOpen, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chat", value: chatID)]
        return components.url ?? deepLinkOpen
    }

    /// App Group id comes from Info.plist (`AppGroupID`, set from the APP_GROUP build setting).
    static let groupID: String? = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String

    static let defaults: UserDefaults = {
        if let id = groupID, let d = UserDefaults(suiteName: id) { return d }
        return .standard
    }()

    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snap
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}
