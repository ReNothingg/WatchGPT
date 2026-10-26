import Foundation

enum ClientVersion {
    static let bundled = "0.164.0"

    enum Source {
        case bundled, github, manual

        var label: String {
            switch self {
            case .bundled: return "из сборки"
            case .github: return "с GitHub"
            case .manual: return "вручную"
            }
        }
    }

    enum CheckResult: Equatable {
        case updated(String)
        case upToDate
        case skipped
        case failed
    }

    private static let fetchedKey = "codex.clientVersion.fetched"
    private static let manualKey = "codex.clientVersion.manual"
    private static let checkedKey = "codex.clientVersion.checkedAt"
    private static let latestURL = URL(string: "https://api.github.com/repos/openai/codex/releases/latest")!

    static let dailyInterval: TimeInterval = 24 * 3600
    static let errorInterval: TimeInterval = 10 * 60

    private static var defaults: UserDefaults { .standard }

    static var manual: String? { defaults.string(forKey: manualKey).flatMap(normalize) }

    static var fetched: String? {
        defaults.string(forKey: fetchedKey).flatMap(normalize).flatMap { isNewer($0, than: bundled) ? $0 : nil }
    }

    static var lastCheck: Date? { defaults.object(forKey: checkedKey) as? Date }

    static var current: String { manual ?? fetched ?? bundled }

    static var source: Source {
        if manual != nil { return .manual }
        if fetched != nil { return .github }
        return .bundled
    }

    @discardableResult
    static func setManual(_ raw: String?) -> Bool {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            defaults.removeObject(forKey: manualKey)
            return true
        }
        guard let version = normalize(raw) else { return false }
        defaults.set(version, forKey: manualKey)
        return true
    }

    static func refresh(minInterval: TimeInterval = dailyInterval) async -> CheckResult {
        if minInterval > 0, let last = lastCheck, Date.now.timeIntervalSince(last) < minInterval { return .skipped }
        defaults.set(Date.now, forKey: checkedKey)
        let before = current
        guard let latest = await fetchLatest() else { return .failed }
        if isNewer(latest, than: fetched ?? bundled) {
            defaults.set(latest, forKey: fetchedKey)
        }
        return current != before ? .updated(current) : .upToDate
    }

    static func refreshAfterError(_ error: Error) async -> Bool {
        guard looksOutdated(error) else { return false }
        if case .updated = await refresh(minInterval: errorInterval) { return true }
        return false
    }

    static func reset() {
        defaults.removeObject(forKey: fetchedKey)
        defaults.removeObject(forKey: checkedKey)
    }

    static func looksOutdated(_ error: Error) -> Bool {
        let message: String
        switch error {
        case let ChatGPTClient.APIError.http(code, text):
            if [400, 404, 410, 412, 426].contains(code) { return true }
            message = text
        case let ChatGPTClient.APIError.stream(text):
            message = text
        default:
            return false
        }
        let lowered = message.lowercased()
        return ["version", "upgrade", "outdated", "update codex", "client_version"].contains(where: lowered.contains)
    }

    static func normalize(_ raw: String) -> String? {
        guard let range = raw.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else { return nil }
        return String(raw[range])
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func fetchLatest() async -> String? {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WatchGPT", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["prerelease"] as? Bool != true,
              let tag = obj["tag_name"] as? String else { return nil }
        return normalize(tag)
    }
}
