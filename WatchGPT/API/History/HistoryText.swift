import Foundation

enum HistoryText {
    static let limit = 6000
    static let imageMark = "🖼"

    static func withoutImageLabel(_ text: String) -> String {
        guard text.hasPrefix(imageMark) else { return text }
        let rest = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first ?? ""
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plain(_ text: String, limit: Int) -> String {
        let cleaned = clean(text)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func clean(_ text: String) -> String {
        var s = text
            .replacingOccurrences(of: "\u{E200}[^\u{E201}]*\u{E201}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "【[^】]*】", with: "", options: .regularExpression)
        s.unicodeScalars.removeAll { (0xE000...0xF8FF).contains($0.value) }

        var lines: [String] = []
        var inCode = false
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode {
                lines.append(trimmed.isEmpty || line.contains("`") ? line : "`\(line)`")
                continue
            }
            if trimmed.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil { continue }
            if trimmed.range(of: #"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, options: .regularExpression) != nil { continue }
            if let heading = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let title = trimmed[heading.upperBound...].trimmingCharacters(in: .whitespaces)
                lines.append(title.isEmpty ? "" : "**\(title.replacingOccurrences(of: "**", with: ""))**")
                continue
            }
            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|"), trimmed.count > 1 {
                let cells = trimmed.dropFirst().dropLast()
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                lines.append(cells.joined(separator: " · "))
                continue
            }
            lines.append(line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression))
        }

        let joined = lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clip(joined)
    }

    static func clip(_ text: String) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: "\n").map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n…"
    }
}
