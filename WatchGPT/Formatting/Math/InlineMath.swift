import SwiftUI

extension MathFormat {
    private final class InlineBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private static let inlineCache: NSCache<NSString, InlineBox> = {
        let cache = NSCache<NSString, InlineBox>()
        cache.countLimit = 300
        cache.totalCostLimit = 400_000
        return cache
    }()

    static func inline(_ text: String, size: CGFloat, cached: Bool = true) -> AttributedString {
        guard cached else { return renderInline(text, size: size) }
        let key = "\(size)|\(text)" as NSString
        if let hit = inlineCache.object(forKey: key) { return hit.value }
        let value = renderInline(text, size: size)
        inlineCache.setObject(InlineBox(value), forKey: key, cost: text.utf8.count)
        return value
    }

    private final class NodeBox {
        let value: MathNode
        init(_ value: MathNode) { self.value = value }
    }

    private static let nodeCache: NSCache<NSString, NodeBox> = {
        let cache = NSCache<NSString, NodeBox>()
        cache.countLimit = 200
        return cache
    }()

    static func parsed(_ latex: String) -> MathNode {
        let key = latex as NSString
        if let hit = nodeCache.object(forKey: key) { return hit.value }
        let node = MathParser.parse(latex)
        nodeCache.setObject(NodeBox(node), forKey: key)
        return node
    }

    private static func renderInline(_ text: String, size: CGFloat) -> AttributedString {
        let (masked, maths) = mask(text)
        let attributed = (try? AttributedString(
            markdown: masked,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(masked)
        guard !maths.isEmpty else { return attributed }

        let renderer = InlineMathRenderer()
        var result = AttributedString()
        for run in attributed.runs {
            var buffer = ""
            func flush() {
                guard !buffer.isEmpty else { return }
                var piece = AttributedString(buffer)
                piece.setAttributes(run.attributes)
                result += piece
                buffer = ""
            }
            for ch in String(attributed[run.range].characters) {
                if let k = placeholderIndex(ch), k < maths.count {
                    flush()
                    result += renderer.render(parsed(maths[k]), fs: size)
                } else {
                    buffer.append(ch)
                }
            }
            flush()
        }
        return result
    }

    static func plain(_ text: String) -> String {
        blocks(text).map { block -> String in
            switch block {
            case let .math(latex):
                return PlainMath.render(MathParser.parse(latex))
            case let .text(t):
                return plainText(t)
            case let .code(_, code):
                return code
            case let .table(rows, _):
                return rows.map { $0.map(plainText).joined(separator: ", ") }.joined(separator: "\n")
            case let .list(items):
                return items.map { item -> String in
                    let prefix: String
                    switch item.marker {
                    case .bullet: prefix = "• "
                    case let .number(n): prefix = n + " "
                    case let .task(done): prefix = done ? "☑ " : "☐ "
                    }
                    return String(repeating: "  ", count: item.level) + prefix + plainText(item.text)
                }.joined(separator: "\n")
            case let .quote(inner):
                return plain(inner)
            }
        }
        .joined(separator: "\n")
    }

    private static func plainText(_ t: String) -> String {
        let (masked, maths) = mask(t)
        guard !maths.isEmpty else { return t }
        var out = ""
        for ch in masked {
            if let k = placeholderIndex(ch), k < maths.count {
                out += PlainMath.render(MathParser.parse(maths[k]))
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static let placeholderBase: UInt32 = 0xE000

    private static func placeholder(_ k: Int) -> Character {
        Character(Unicode.Scalar(placeholderBase + UInt32(k))!)
    }

    private static func placeholderIndex(_ ch: Character) -> Int? {
        guard ch.unicodeScalars.count == 1, let v = ch.unicodeScalars.first?.value,
              v >= placeholderBase, v < placeholderBase + 0x1000 else { return nil }
        return Int(v - placeholderBase)
    }

    private static func mask(_ text: String) -> (String, [String]) {
        guard text.containsAnyByte("\\$^_") else { return (text, []) }
        let c = Array(text)
        var out: [Character] = []
        var maths: [String] = []
        var i = 0

        func add(_ latex: String) {
            out.append(placeholder(maths.count))
            maths.append(latex)
        }

        while i < c.count {
            if c[i] == "`" {
                let end = c.find("`", from: i + 1).map { $0 + 1 } ?? c.count
                out.append(contentsOf: c[i..<end])
                i = end
            } else if c.has("\\(", at: i) {
                let close = c.find("\\)", from: i + 2)
                add(String(c[(i + 2)..<(close ?? c.count)]))
                i = close.map { $0 + 2 } ?? c.count
            } else if c.has("\\$", at: i) {
                out.append(contentsOf: c[i...(i + 1)])
                i += 2
            } else if c[i] == "$", let close = dollarClose(c, open: i) {
                add(String(c[(i + 1)..<close]))
                i = close + 1
            } else {
                out.append(c[i])
                i += 1
            }
        }
        return nakedMath(out, maths: maths)
    }

    private static func dollarClose(_ c: [Character], open: Int) -> Int? {
        let start = open + 1
        guard start < c.count, !c[start].isWhitespace, c[start] != "$" else { return nil }
        if c[start].isNumber {
            var k = start
            while k < c.count, c[k].isNumber || c[k] == "." || c[k] == "," { k += 1 }
            if k >= c.count || c[k].isWhitespace || c[k].isPunctuation { return nil }
        }
        var j = start
        while j < c.count {
            if c[j] == "\n" || c[j] == "`" { return nil }
            if c[j] == "$", c[j - 1].isWhitespace { return nil }
            if c[j] == "$", c[j - 1] != "\\" {
                if j + 1 < c.count, c[j + 1].isNumber { return nil }
                return j
            }
            j += 1
        }
        return nil
    }

    private static let strongPattern = #"\\[A-Za-z]+|[\^_]\{|[A-Za-z0-9)\]]\^[A-Za-z0-9(+\-−]|(^|[^A-Za-z])[A-Za-z]_[0-9A-Za-z]($|[^A-Za-z0-9])"#
    private static let weakPattern = #"^[0-9=+\-−*/^_().,<>|!\[\]{}'·×÷±≤≥≠≈∞→]*([A-Za-z]|sin|cos|tan|ln|log|lim|exp|max|min|dx|dy|dt)?[0-9=+\-−*/^_().,<>|!\[\]{}'·×÷±≤≥≠≈∞→]*$"#
    private static let strongRegex = try? NSRegularExpression(pattern: strongPattern)
    private static let weakRegex = try? NSRegularExpression(pattern: weakPattern)

    private static func matches(_ regex: NSRegularExpression?, _ word: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) != nil
    }

    private static func mayBeStrong(_ word: String) -> Bool {
        word.contains { $0 == "\\" || $0 == "^" || $0 == "_" }
    }

    private static func nakedMath(_ c: [Character], maths: [String]) -> (String, [String]) {
        var maths = maths
        var tokens: [(start: Int, end: Int, strong: Bool, weak: Bool)] = []
        var i = 0
        while i < c.count {
            if c[i].isWhitespace { i += 1; continue }
            let start = i
            while i < c.count, !c[i].isWhitespace { i += 1 }
            let word = String(c[start..<i])
            let usable = !word.containsBytes("://") && !word.containsAnyByte("@`")
                && !word.unicodeScalars.contains { $0.value >= placeholderBase && $0.value < placeholderBase + 0x1000 }
            let strong = usable && mayBeStrong(word) && matches(strongRegex, word)
            tokens.append((start, i, strong, usable))
        }
        guard tokens.contains(where: { $0.strong }) else { return (String(c), maths) }
        for index in tokens.indices where !tokens[index].strong && tokens[index].weak {
            let word = String(c[tokens[index].start..<tokens[index].end])
            tokens[index].weak = matches(weakRegex, word)
        }

        var spans: [(Int, Int)] = []
        var k = 0
        while k < tokens.count {
            guard tokens[k].strong || tokens[k].weak else { k += 1; continue }
            var e = k
            var hasStrong = tokens[k].strong
            while e + 1 < tokens.count, tokens[e + 1].strong || tokens[e + 1].weak,
                  !c[tokens[e].end..<tokens[e + 1].start].contains("\n") {
                e += 1
                hasStrong = hasStrong || tokens[e].strong
            }
            if hasStrong {
                var s = tokens[k].start
                var t = tokens[e].end
                while s < t, "*_".contains(c[s]) { s += 1 }
                while t > s, "*_.,;:!?".contains(c[t - 1]) { t -= 1 }
                if s < t { spans.append((s, t)) }
            }
            k = e + 1
        }

        var out: [Character] = []
        var last = 0
        for (s, t) in spans {
            out.append(contentsOf: c[last..<s])
            out.append(placeholder(maths.count))
            maths.append(String(c[s..<t]))
            last = t
        }
        out.append(contentsOf: c[last...])
        return (String(out), maths)
    }
}
