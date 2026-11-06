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
        var s = replace(citations, in: replace(entities, in: text, with: ""), with: "")
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
            if matches(rule, trimmed) || matches(tableSeparator, trimmed) { continue }
            if let match = heading.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range, in: trimmed) {
                let title = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
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
            lines.append(String(line[..<(line.lastIndex { !$0.isWhitespace }.map(line.index(after:)) ?? line.startIndex)]))
        }

        let joined = replace(blankRuns, in: lines.joined(separator: "\n"), with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clip(joined)
    }

    private static let entities = regex("\u{E200}[^\u{E201}]*\u{E201}")
    private static let citations = regex("【[^】]*】")
    private static let rule = regex(#"^([-*_]\s*){3,}$"#)
    private static let tableSeparator = regex(#"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#)
    private static let heading = regex(#"^#{1,6}\s+"#)
    private static let blankRuns = regex(#"\n{3,}"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func clip(_ text: String) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: "\n").map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n…"
    }
}
