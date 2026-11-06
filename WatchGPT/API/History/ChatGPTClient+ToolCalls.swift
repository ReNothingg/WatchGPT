import Foundation

extension ChatGPTClient {
    static func toolStage(_ name: String) -> (String, String) {
        let n = name.lowercased()
        if n.hasPrefix("web") || n.contains("browser") || n.contains("search") {
            return ("Ищу в интернете", "globe")
        }
        if n.contains("dalle") || n.contains("image") || n.contains("t2uay3k") {
            return ("Рисую изображение", "paintbrush")
        }
        if n.contains("python") || n.contains("code") || n.contains("container") {
            return ("Запускаю код", "terminal")
        }
        if n.contains("file") || n.contains("doc") {
            return ("Читаю файлы", "doc.text")
        }
        if n.hasPrefix("bio") || n.contains("memory") {
            return ("Обновляю память", "brain.head.profile")
        }
        if n.contains("canmore") || n.contains("canvas") {
            return ("Пишу в холсте", "doc.richtext")
        }
        if n.contains("research") {
            return ("Исследую", "magnifyingglass")
        }
        return ("Использую инструменты", "wrench.and.screwdriver")
    }

    static func toolCall(recipient: String, content: [String: Any]) -> (title: String, detail: String, icon: String) {
        let text = (content["text"] as? String) ?? ((content["parts"] as? [Any])?.compactMap { $0 as? String }.joined(separator: "\n")) ?? ""
        let json = text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }

        var server = ""
        var tool = ""
        var payload: Any? = json
        if recipient.hasPrefix("api_tool"), let dict = json as? [String: Any] {
            let path = (dict["path"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let pieces = path.split(separator: "/", maxSplits: 1).map(String.init)
            server = pieces.first ?? ""
            tool = pieces.count > 1 ? pieces[1] : ""
            payload = dict["args"] ?? dict
        } else if let dot = recipient.firstIndex(of: "."), !isBuiltIn(recipient) {
            server = String(recipient[..<dot])
            tool = String(recipient[recipient.index(after: dot)...])
        }

        var found: [String] = []
        if let payload { collectQueries(payload, into: &found) }
        let detail = found.prefix(2).joined(separator: "\n")

        guard !server.isEmpty else {
            let (title, icon) = toolStage(recipient)
            return (title, found.prefix(3).map { "«\($0)»" }.joined(separator: "\n"), icon)
        }
        let name = serviceName(server)
        let action = toolAction(tool)
        return (action.isEmpty ? name : "\(name): \(action)", detail, serviceIcon(name))
    }

    private static func isBuiltIn(_ recipient: String) -> Bool {
        let n = recipient.lowercased()
        return ["web", "browser", "python", "dalle", "bio", "canmore", "file_search", "myfiles_browser", "container", "image_gen", "research_kickoff_tool"]
            .contains { n.hasPrefix($0) }
    }

    private static func serviceName(_ raw: String) -> String {
        var key = raw.lowercased()
        for prefix in ["connector_openai_", "connector_", "mcp_", "openai_"] where key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
        }
        let known: [String: String] = [
            "github": "GitHub", "gmail": "Gmail", "google_drive": "Google Drive", "gdrive": "Google Drive",
            "google_calendar": "Google Calendar", "gcal": "Google Calendar", "notion": "Notion", "slack": "Slack",
            "linear": "Linear", "jira": "Jira", "confluence": "Confluence", "dropbox": "Dropbox", "box": "Box",
            "sharepoint": "SharePoint", "outlook": "Outlook", "teams": "Teams", "hubspot": "HubSpot",
            "figma": "Figma", "canva": "Canva", "asana": "Asana", "zapier": "Zapier", "stripe": "Stripe",
            "automations": "Задачи",
        ]
        if let name = known[key] { return name }
        if key.count > 20, key.allSatisfy({ $0.isHexDigit }) { return "Интеграция" }
        let words = key.split(whereSeparator: { $0 == "_" || $0 == "-" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? raw : words.joined(separator: " ")
    }

    private static func serviceIcon(_ name: String) -> String {
        switch name {
        case "GitHub": return "chevron.left.forwardslash.chevron.right"
        case "Gmail", "Outlook": return "envelope"
        case "Google Calendar": return "calendar"
        case "Google Drive", "Dropbox", "Box", "SharePoint": return "folder"
        case "Slack", "Teams": return "bubble.left.and.bubble.right"
        case "Задачи": return "clock"
        default: return "puzzlepiece.extension"
        }
    }

    private static func toolAction(_ tool: String) -> String {
        let t = tool.lowercased()
        guard !t.isEmpty else { return "" }
        if t.contains("search") || t.contains("find") || t.contains("query") { return "поиск" }
        if t.contains("fetch") || t.contains("get") || t.contains("read") || t.contains("open") || t.contains("download") { return "читаю" }
        if t.contains("list") { return "список" }
        if t.contains("create") || t.contains("add") || t.contains("write") || t.contains("send") || t.contains("post") { return "создаю" }
        if t.contains("update") || t.contains("edit") || t.contains("patch") { return "изменяю" }
        if t.contains("delete") || t.contains("remove") { return "удаляю" }
        if t.contains("run") || t.contains("exec") || t.contains("command") { return "выполняю команду" }
        return tool.replacingOccurrences(of: "_", with: " ")
    }

    private static func collectQueries(_ any: Any, into found: inout [String]) {
        guard found.count < 3 else { return }
        if let dict = any as? [String: Any] {
            for key in ["q", "query", "prompt", "search_query", "queries", "title", "repository_full_name", "repo", "file_path", "path", "url", "cmd", "command", "name"] {
                if let value = dict[key] as? String {
                    let flat = HistoryText.plain(value, limit: 120)
                    if !flat.isEmpty, !found.contains(flat) { found.append(flat) }
                }
            }
            for value in dict.values where !(value is String) { collectQueries(value, into: &found) }
        } else if let array = any as? [Any] {
            for value in array {
                if let string = value as? String {
                    let flat = HistoryText.plain(string, limit: 120)
                    if !flat.isEmpty, !found.contains(flat), found.count < 3 { found.append(flat) }
                } else {
                    collectQueries(value, into: &found)
                }
            }
        }
    }

    private static let recapRegex = try? NSRegularExpression(pattern: #"(\d+)\s*(h|ч|m|мин|s|с|сек)?"#, options: .caseInsensitive)

    static func seconds(fromRecap text: String) -> Int? {
        guard let regex = recapRegex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var total = 0
        var matched = false
        for match in regex.matches(in: text, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: text), let value = Int(text[numberRange]) else { continue }
            let unit = Range(match.range(at: 2), in: text).map { text[$0].lowercased() } ?? "s"
            switch unit {
            case "h", "ч": total += value * 3600
            case "m", "мин": total += value * 60
            default: total += value
            }
            matched = true
        }
        return matched ? total : nil
    }
}
