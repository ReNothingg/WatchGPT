import SwiftUI

indirect enum MathNode {
    case row([MathNode])
    case atom(String, MathAtom)
    case text(String, bold: Bool)
    case frac(MathNode, MathNode, bar: Bool)
    case sqrt(MathNode, index: MathNode?)
    case scripts(MathNode, sup: MathNode?, sub: MathNode?)
    case limits(MathNode, over: MathNode?, under: MathNode?)
    case fenced(String, MathNode, String)
    case accent(MathNode, MathAccent)
    case table([[MathNode]], MathTable)
    case space(CGFloat)

    static let empty = MathNode.row([])
}

enum MathAtom {
    case ident, number, symbol, bin, rel, open, close, punct, fn, largeOp
}

enum MathAccent {
    case vec, hat, bar, dot, ddot, tilde, overline, underline
}

enum MathTable: Equatable {
    case matrix(String, String)
    case cases
    case aligned
}

enum MathClass {
    case ord, op, bin, rel, open, close, punct
}

enum MathFormat {
    enum Block {
        case text(String)
        case math(String)
    }

    static func blocks(_ text: String) -> [Block] {
        guard text.contains("$$") || text.contains("\\[") || text.contains("\\begin{") else { return [.text(text)] }
        let c = Array(text)
        var blocks: [Block] = []
        var buffer: [Character] = []
        var i = 0

        func flush() {
            let s = String(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { blocks.append(.text(s)) }
            buffer.removeAll()
        }

        while i < c.count {
            if c.has("```", at: i) {
                let end = c.find("```", from: i + 3).map { $0 + 3 } ?? c.count
                buffer.append(contentsOf: c[i..<end])
                i = end
            } else if c[i] == "`" {
                let end = c.find("`", from: i + 1).map { $0 + 1 } ?? c.count
                buffer.append(contentsOf: c[i..<end])
                i = end
            } else if c.has("\\(", at: i) {
                let end = c.find("\\)", from: i + 2).map { $0 + 2 } ?? c.count
                buffer.append(contentsOf: c[i..<end])
                i = end
            } else if c.has("$$", at: i) {
                let close = c.find("$$", from: i + 2)
                flush()
                blocks.append(.math(String(c[(i + 2)..<(close ?? c.count)])))
                i = close.map { $0 + 2 } ?? c.count
            } else if c.has("\\[", at: i) {
                let close = c.find("\\]", from: i + 2)
                flush()
                blocks.append(.math(String(c[(i + 2)..<(close ?? c.count)])))
                i = close.map { $0 + 2 } ?? c.count
            } else if c.has("\\begin{", at: i), let nameEnd = c.find("}", from: i + 7) {
                let name = String(c[(i + 7)..<nameEnd])
                let endTag = Array("\\end{\(name)}")
                let close = c.find(String(endTag), from: nameEnd)
                flush()
                blocks.append(.math(String(c[i..<(close.map { $0 + endTag.count } ?? c.count)])))
                i = close.map { $0 + endTag.count } ?? c.count
            } else {
                buffer.append(c[i])
                i += 1
            }
        }
        flush()
        return blocks
    }

    private final class InlineBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    private static let inlineCache: NSCache<NSString, InlineBox> = {
        let cache = NSCache<NSString, InlineBox>()
        cache.countLimit = 120
        return cache
    }()

    static func inline(_ text: String, size: CGFloat) -> AttributedString {
        let key = "\(size)|\(text)" as NSString
        if let hit = inlineCache.object(forKey: key) { return hit.value }
        let value = renderInline(text, size: size)
        inlineCache.setObject(InlineBox(value), forKey: key)
        return value
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
                    result += renderer.render(MathParser.parse(maths[k]), fs: size)
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
        }
        .joined(separator: "\n")
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
        guard text.contains("\\") || text.contains("$") || text.contains("^") || text.contains("_") else { return (text, []) }
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
            let usable = !word.contains("://") && !word.contains("@") && !word.contains("`")
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

    static func spacing(_ items: [MathNode], leadingOrd: Bool = false, script: Bool = false) -> [CGFloat] {
        var prev: MathClass? = leadingOrd ? .ord : nil
        var result: [CGFloat] = []
        for item in items {
            if case .space = item {
                result.append(0)
                continue
            }
            var cls = mathClass(item)
            if cls == .bin, prev == nil || [.bin, .op, .rel, .open, .punct].contains(prev!) { cls = .ord }
            let value = space(prev, cls)
            result.append(script && cls != .op && prev != .op ? 0 : value)
            prev = cls
        }
        return result
    }

    private static func space(_ prev: MathClass?, _ cls: MathClass) -> CGFloat {
        guard let prev else { return 0 }
        switch (prev, cls) {
        case (.ord, .op), (.op, .ord), (.op, .op), (.close, .op): return 0.17
        case (.ord, .bin), (.close, .bin): return 0.22
        case (.bin, .ord), (.bin, .op), (.bin, .open): return 0.22
        case (.rel, .rel), (.open, .rel): return 0
        case (_, .rel): return 0.28
        case (.rel, .close), (.rel, .punct): return 0
        case (.rel, _): return 0.28
        case (.punct, _): return 0.17
        default: return 0
        }
    }

    static func mathClass(_ node: MathNode) -> MathClass {
        switch node {
        case let .atom(_, kind):
            switch kind {
            case .bin: return .bin
            case .rel: return .rel
            case .open: return .open
            case .close: return .close
            case .punct: return .punct
            case .fn, .largeOp: return .op
            default: return .ord
            }
        case let .scripts(base, _, _): return mathClass(base)
        case .limits: return .op
        case let .row(items) where items.count == 1: return mathClass(items[0])
        default: return .ord
        }
    }

    static func height(_ node: MathNode) -> CGFloat {
        switch node {
        case let .row(items): return items.map(height).max() ?? 1
        case let .frac(a, b, _): return (height(a) + height(b)) * 0.86 + 0.25
        case let .sqrt(a, _): return height(a) + 0.15
        case let .scripts(base, sup, sub): return height(base) + (sup == nil ? 0 : 0.3) + (sub == nil ? 0 : 0.25)
        case let .limits(base, over, under): return height(base) * 1.3 + (over == nil ? 0 : 0.6) + (under == nil ? 0 : 0.6)
        case let .fenced(_, inner, _): return height(inner)
        case let .accent(base, _): return height(base) + 0.15
        case let .table(rows, _): return rows.reduce(0) { $0 + ($1.map(height).max() ?? 1) } + CGFloat(max(rows.count - 1, 0)) * 0.3
        default: return 1
        }
    }

    static func superscript(_ s: String) -> String? { map(s, superMap) }
    static func `subscript`(_ s: String) -> String? { map(s, subMap) }

    private static func map(_ s: String, _ table: [Character: Character]) -> String? {
        var out = ""
        for ch in s {
            guard let m = table[ch] else { return nil }
            out.append(m)
        }
        return out.isEmpty ? nil : out
    }

    private static let superMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "k": "ᵏ", "m": "ᵐ", "t": "ᵗ", "T": "ᵀ", "′": "′", ",": ",",
    ]
    private static let subMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "n": "ₙ", "m": "ₘ", "x": "ₓ", "t": "ₜ", "o": "ₒ", "p": "ₚ", "s": "ₛ", "r": "ᵣ", ",": ",",
    ]
}

private extension Array where Element == Character {
    func has(_ s: String, at i: Int) -> Bool {
        var k = i
        for ch in s {
            guard k < count, self[k] == ch else { return false }
            k += 1
        }
        return true
    }

    func find(_ s: String, from: Int) -> Int? {
        guard from <= count else { return nil }
        var i = from
        while i < count {
            if has(s, at: i) { return i }
            i += 1
        }
        return nil
    }
}

struct MathParser {
    private let c: [Character]
    private var i = 0

    private init(_ s: String) { c = Array(s) }

    static func parse(_ latex: String) -> MathNode {
        var parser = MathParser(latex)
        return parser.table(parser.parseTable(), kind: .aligned)
    }

    private func table(_ rows: [[MathNode]], kind: MathTable) -> MathNode {
        var rows = rows
        while rows.count > 1, let last = rows.last, last.count == 1, isEmpty(last[0]) { rows.removeLast() }
        if kind == .aligned, rows.count == 1, rows[0].count == 1 { return rows[0][0] }
        return .table(rows, kind)
    }

    private func isEmpty(_ node: MathNode) -> Bool {
        if case let .row(items) = node { return items.allSatisfy { if case .space = $0 { return true }; return false } }
        return false
    }

    private var atEnd: Bool { i >= c.count }

    private func peek(_ offset: Int = 0) -> Character? {
        i + offset < c.count ? c[i + offset] : nil
    }

    private func isCommand(_ name: String) -> Bool {
        guard peek() == "\\" else { return false }
        var k = i + 1
        for ch in name {
            guard k < c.count, c[k] == ch else { return false }
            k += 1
        }
        return k >= c.count || !c[k].isLetter
    }

    private mutating func skipSpaces() {
        while let ch = peek(), ch.isWhitespace { i += 1 }
    }

    private mutating func parseTable() -> [[MathNode]] {
        var rows: [[MathNode]] = []
        var cells: [MathNode] = []
        while true {
            cells.append(parseRow(brace: false, right: false, cell: true))
            if atEnd {
                rows.append(cells)
                break
            }
            if peek() == "&" {
                i += 1
            } else if peek() == "\\", peek(1) == "\\" {
                i += 2
                skipSpaces()
                if peek() == "[" { _ = readBracket() }
                rows.append(cells)
                cells = []
            } else if isCommand("end") {
                i += 4
                _ = readRawGroup()
                rows.append(cells)
                break
            } else {
                i += 1
            }
        }
        return rows
    }

    private mutating func parseRow(brace: Bool, right: Bool, cell: Bool) -> MathNode {
        var items: [MathNode] = []
        while let ch = peek() {
            if ch == "}" {
                if brace { break }
                i += 1
                continue
            }
            if ch == "&" {
                if cell { break }
                i += 1
                continue
            }
            if ch == "\\", peek(1) == "\\" {
                if cell { break }
                i += 2
                items.append(.space(0.5))
                continue
            }
            if isCommand("end") {
                if cell { break }
                i += 4
                _ = readRawGroup()
                continue
            }
            if isCommand("right") {
                if right { break }
                i += 6
                _ = readDelimiter()
                continue
            }
            if ch.isWhitespace {
                i += 1
                continue
            }
            if let node = parseScripted() { items.append(node) }
        }
        return items.count == 1 ? items[0] : .row(items)
    }

    private mutating func parseScripted() -> MathNode? {
        guard let (base, usesLimits) = parsePrimary() else { return nil }
        var limits = usesLimits
        var sup: MathNode?
        var sub: MathNode?
        while true {
            let save = i
            skipSpaces()
            if peek() == "^" {
                i += 1
                let arg = parseScriptArg()
                if let existing = sup { sup = .row([existing, arg]) } else { sup = arg }
            } else if peek() == "_" {
                i += 1
                sub = parseScriptArg()
            } else if peek() == "'" {
                var primes = ""
                while peek() == "'" {
                    primes += "′"
                    i += 1
                }
                let p = MathNode.atom(primes, .symbol)
                if let existing = sup { sup = .row([existing, p]) } else { sup = p }
            } else if isCommand("limits") {
                i += 7
                limits = true
            } else if isCommand("nolimits") {
                i += 9
                limits = false
            } else {
                i = save
                break
            }
        }
        if sup == nil, sub == nil { return base }
        return limits ? .limits(base, over: sup, under: sub) : .scripts(base, sup: sup, sub: sub)
    }

    private mutating func parseScriptArg() -> MathNode {
        skipSpaces()
        guard let ch = peek() else { return .empty }
        if ch == "{" { return parseGroup() }
        if ch == "\\" { return parsePrimary()?.0 ?? .empty }
        if ch.isNumber {
            var s = ""
            while let d = peek(), d.isNumber {
                s.append(d)
                i += 1
            }
            return .atom(s, .number)
        }
        return parsePrimary()?.0 ?? .empty
    }

    private mutating func parseGroup() -> MathNode {
        guard peek() == "{" else { return parseScriptArg() }
        i += 1
        let node = parseRow(brace: true, right: false, cell: false)
        if peek() == "}" { i += 1 }
        return node
    }

    private mutating func parseArg() -> MathNode {
        skipSpaces()
        if peek() == "{" { return parseGroup() }
        return parsePrimary()?.0 ?? .empty
    }

    private mutating func readRawGroup() -> String {
        skipSpaces()
        guard peek() == "{" else {
            if let ch = peek() {
                i += 1
                return String(ch)
            }
            return ""
        }
        i += 1
        var depth = 1
        var s = ""
        while let ch = peek() {
            i += 1
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            s.append(ch)
        }
        return s
    }

    private mutating func readBracket() -> String {
        guard peek() == "[" else { return "" }
        i += 1
        var depth = 1
        var s = ""
        while let ch = peek() {
            i += 1
            if ch == "[" { depth += 1 }
            if ch == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            s.append(ch)
        }
        return s
    }

    private mutating func readDelimiter() -> String {
        skipSpaces()
        guard let ch = peek() else { return "" }
        i += 1
        if ch == "." { return "" }
        guard ch == "\\" else { return String(ch) }
        guard let next = peek() else { return "" }
        if !next.isLetter {
            i += 1
            return next == "|" ? "‖" : String(next)
        }
        let name = readName()
        return Self.delimiters[name] ?? Self.symbols[name]?.0 ?? ""
    }

    private mutating func readName() -> String {
        var name = ""
        while let ch = peek(), ch.isLetter, ch.isASCII {
            name.append(ch)
            i += 1
        }
        if peek() == "*" {
            name.append("*")
            i += 1
        }
        return name
    }

    private mutating func parsePrimary() -> (MathNode, Bool)? {
        guard let ch = peek() else { return nil }
        if ch == "{" { return (parseGroup(), false) }
        if ch == "\\" { return parseCommand() }
        i += 1

        if ch.isNumber {
            var s = String(ch)
            while let d = peek() {
                if d.isNumber {
                    s.append(d)
                    i += 1
                } else if d == ".", let n = peek(1), n.isNumber {
                    s.append(d)
                    i += 1
                } else {
                    break
                }
            }
            return (.atom(s, .number), false)
        }
        if ch.isLetter {
            if ch.isASCII || Self.isGreekLower(ch) { return (.atom(String(ch), .ident), false) }
            if Self.isGreek(ch) { return (.atom(String(ch), .symbol), false) }
            var word = String(ch)
            while let n = peek(), n.isLetter, !n.isASCII, !Self.isGreek(n) {
                word.append(n)
                i += 1
            }
            return (.text(word, bold: false), false)
        }
        switch ch {
        case "-": return (.atom("−", .bin), false)
        case "*": return (.atom("∗", .bin), false)
        case "+": return (.atom("+", .bin), false)
        case "=", "<", ">", ":": return (.atom(String(ch), .rel), false)
        case ",", ";": return (.atom(String(ch), .punct), false)
        case "(", "[": return (.atom(String(ch), .open), false)
        case ")", "]": return (.atom(String(ch), .close), false)
        case "~": return (.space(0.3), false)
        case "'": return (.atom("′", .symbol), false)
        case "^", "_": return (.empty, false)
        default:
            if Self.relChars.contains(ch) { return (.atom(String(ch), .rel), false) }
            if Self.binChars.contains(ch) { return (.atom(String(ch), .bin), false) }
            if Self.openChars.contains(ch) { return (.atom(String(ch), .open), false) }
            if Self.closeChars.contains(ch) { return (.atom(String(ch), .close), false) }
            if Self.limitOpChars.contains(ch) { return (.atom(String(ch), .largeOp), true) }
            if Self.integralChars.contains(ch) { return (.atom(String(ch), .largeOp), false) }
            return (.atom(String(ch), .symbol), false)
        }
    }

    private mutating func parseCommand() -> (MathNode, Bool)? {
        i += 1
        guard let first = peek() else { return (.atom("\\", .symbol), false) }
        if !first.isLetter || !first.isASCII {
            i += 1
            switch first {
            case ",": return (.space(0.17), false)
            case ":", ">": return (.space(0.22), false)
            case ";": return (.space(0.28), false)
            case " ": return (.space(0.25), false)
            case "!": return (.space(0), false)
            case "{": return (.atom("{", .open), false)
            case "}": return (.atom("}", .close), false)
            case "|": return (.atom("‖", .symbol), false)
            default: return (.atom(String(first), .symbol), false)
            }
        }
        let name = readName()

        switch name {
        case "frac", "dfrac", "tfrac", "cfrac":
            let a = parseArg()
            let b = parseArg()
            return (.frac(a, b, bar: true), false)
        case "binom", "dbinom", "tbinom":
            let a = parseArg()
            let b = parseArg()
            return (.fenced("(", .frac(a, b, bar: false), ")"), false)
        case "sqrt":
            skipSpaces()
            let index = peek() == "[" ? MathParser.parse(readBracket()) : nil
            return (.sqrt(parseArg(), index: index), false)
        case "text", "textrm", "textnormal", "mbox", "textit", "textsf", "texttt", "hbox", "textup":
            return (.text(readRawGroup().replacingOccurrences(of: "$", with: ""), bold: false), false)
        case "textbf":
            return (.text(readRawGroup().replacingOccurrences(of: "$", with: ""), bold: true), false)
        case "mathrm", "mathsf", "mathtt", "mathit", "mathnormal":
            let raw = readRawGroup()
            if raw.contains("\\") || raw.contains("^") || raw.contains("_") { return (MathParser.parse(raw), false) }
            return (name == "mathit" ? .atom(raw, .ident) : .text(raw, bold: false), false)
        case "operatorname", "operatorname*":
            return (.atom(readRawGroup(), .fn), name.hasSuffix("*"))
        case "mathbf", "bm", "boldsymbol", "mathbfit", "pmb":
            let raw = readRawGroup()
            if raw.contains("\\") || raw.contains("^") || raw.contains("_") { return (MathParser.parse(raw), false) }
            return (.text(raw, bold: true), false)
        case "mathbb", "Bbb":
            let raw = readRawGroup()
            return (.text(String(raw.map { Self.doubleStruck[$0] ?? $0 }), bold: !raw.allSatisfy { Self.doubleStruck[$0] != nil }), false)
        case "mathcal", "mathscr":
            let raw = readRawGroup()
            if raw.allSatisfy({ Self.script[$0] != nil }) { return (.atom(String(raw.map { Self.script[$0]! }), .symbol), false) }
            return (.atom(raw, .ident), false)
        case "mathfrak":
            return (.atom(readRawGroup(), .ident), false)
        case "left":
            let l = readDelimiter()
            let body = parseRow(brace: true, right: true, cell: false)
            var r = ""
            if isCommand("right") {
                i += 6
                r = readDelimiter()
            }
            return (.fenced(l, body, r), false)
        case "right":
            _ = readDelimiter()
            return nil
        case "middle":
            return (.atom(readDelimiter(), .rel), false)
        case "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr", "Biggl", "Biggr", "bigm", "Bigm":
            let d = readDelimiter()
            let kind: MathAtom = name.hasSuffix("l") ? .open : name.hasSuffix("r") ? .close : (Self.openChars.contains(d.first ?? " ") || d == "(" || d == "[") ? .open : .close
            return (.atom(d, kind), false)
        case "begin":
            let env = readRawGroup()
            if env == "array" || env == "tabular" { _ = readRawGroup() }
            let rows = parseTable()
            let kind: MathTable
            switch env {
            case "pmatrix": kind = .matrix("(", ")")
            case "bmatrix": kind = .matrix("[", "]")
            case "Bmatrix": kind = .matrix("{", "}")
            case "vmatrix": kind = .matrix("|", "|")
            case "Vmatrix": kind = .matrix("‖", "‖")
            case "matrix", "smallmatrix", "array", "tabular": kind = .matrix("", "")
            case "cases", "dcases", "rcases", "cases*": kind = .cases
            default: kind = .aligned
            }
            return (table(rows, kind: kind), false)
        case "end":
            _ = readRawGroup()
            return nil
        case "vec", "overrightarrow": return (.accent(parseArg(), .vec), false)
        case "hat", "widehat": return (.accent(parseArg(), .hat), false)
        case "bar": return (.accent(parseArg(), .bar), false)
        case "overline": return (.accent(parseArg(), .overline), false)
        case "underline": return (.accent(parseArg(), .underline), false)
        case "dot": return (.accent(parseArg(), .dot), false)
        case "ddot": return (.accent(parseArg(), .ddot), false)
        case "tilde", "widetilde": return (.accent(parseArg(), .tilde), false)
        case "overbrace", "underbrace": return (parseArg(), true)
        case "overset", "stackrel":
            let a = parseArg()
            let b = parseArg()
            return (.limits(b, over: a, under: nil), false)
        case "underset":
            let a = parseArg()
            let b = parseArg()
            return (.limits(b, over: nil, under: a), false)
        case "boxed", "fbox", "displaylines": return (parseArg(), false)
        case "phantom", "hphantom", "vphantom":
            _ = parseArg()
            return (.space(0.5), false)
        case "color":
            _ = readRawGroup()
            return nil
        case "textcolor", "colorbox":
            _ = readRawGroup()
            return (parseArg(), false)
        case "hspace", "hspace*", "kern", "mkern":
            _ = readRawGroup()
            return (.space(0.5), false)
        case "quad": return (.space(1), false)
        case "qquad": return (.space(2), false)
        case "enspace": return (.space(0.5), false)
        case "thinspace": return (.space(0.17), false)
        case "medspace": return (.space(0.22), false)
        case "thickspace": return (.space(0.28), false)
        case "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle", "limits", "nolimits", "nonumber", "notag", "label", "tag":
            if name == "label" || name == "tag" { _ = readRawGroup() }
            return nil
        case "not":
            skipSpaces()
            guard let (next, _) = parsePrimary() else { return nil }
            if case let .atom(s, kind) = next {
                let negated = ["=": "≠", "∈": "∉", "<": "≮", ">": "≯", "≤": "≰", "≥": "≱", "⊂": "⊄", "⊆": "⊈", "≡": "≢", "∼": "≁", "≈": "≉"][s]
                return (.atom(negated ?? s + "\u{0338}", kind), false)
            }
            return (next, false)
        case "pmod":
            let arg = parseArg()
            return (.row([.space(0.5), .atom("(", .open), .atom("mod", .fn), .space(0.3), arg, .atom(")", .close)]), false)
        case "bmod", "mod":
            return (.atom("mod", .bin), false)
        default:
            if let (symbol, kind) = Self.symbols[name] {
                let limits = kind == .largeOp ? Self.limitOpChars.contains(symbol.first ?? " ") : (kind == .fn && Self.limitFns.contains(name))
                return (.atom(symbol, kind), limits)
            }
            return (.text(name, bold: false), false)
        }
    }

    private static func isGreekLower(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x03B1...0x03C9).contains(v) || [0x03D1, 0x03D5, 0x03D6, 0x03F5, 0x03F1].contains(v)
    }

    private static func isGreek(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x0391...0x03F5).contains(v)
    }

    static let relChars: Set<Character> = Set("=<>≤≥≠≈≡∼≃≅∝→←↔⇒⇐⇔↦∈∉∋⊂⊃⊆⊇∣∥⊥≪≫≺≻⊢⊨≔⟶⟵⟹⟸⟺↑↓≜≐")
    static let binChars: Set<Character> = Set("+−±∓×÷·∗∘∪∩∧∨⊕⊗⊖∖⋅•⋆")
    static let openChars: Set<Character> = Set("([⟨⌊⌈")
    static let closeChars: Set<Character> = Set(")]⟩⌋⌉")
    static let limitOpChars: Set<Character> = Set("∑∏∐⋃⋂⨁⨂⋁⋀")
    static let integralChars: Set<Character> = Set("∫∬∭∮")
    static let limitFns: Set<String> = ["lim", "limsup", "liminf", "max", "min", "sup", "inf", "det", "gcd", "Pr", "argmax", "argmin"]

    static let delimiters: [String: String] = [
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
        "lvert": "|", "rvert": "|", "vert": "|", "lVert": "‖", "rVert": "‖", "Vert": "‖",
        "lbrace": "{", "rbrace": "}", "lbrack": "[", "rbrack": "]",
    ]

    static let doubleStruck: [Character: Character] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ", "1": "𝟙",
    ]

    static let script: [Character: Character] = [
        "L": "ℒ", "F": "ℱ", "H": "ℋ", "E": "ℰ", "B": "ℬ", "M": "ℳ", "R": "ℛ", "I": "ℐ", "l": "ℓ", "e": "ℯ", "o": "ℴ", "g": "ℊ",
    ]

    static let symbols: [String: (String, MathAtom)] = {
        var map: [String: (String, MathAtom)] = [:]
        let greek: [(String, String)] = [
            ("alpha", "α"), ("beta", "β"), ("gamma", "γ"), ("delta", "δ"), ("epsilon", "ϵ"), ("varepsilon", "ε"),
            ("zeta", "ζ"), ("eta", "η"), ("theta", "θ"), ("vartheta", "ϑ"), ("iota", "ι"), ("kappa", "κ"),
            ("lambda", "λ"), ("mu", "μ"), ("nu", "ν"), ("xi", "ξ"), ("omicron", "ο"), ("pi", "π"), ("varpi", "ϖ"),
            ("rho", "ρ"), ("varrho", "ϱ"), ("sigma", "σ"), ("varsigma", "ς"), ("tau", "τ"), ("upsilon", "υ"),
            ("phi", "ϕ"), ("varphi", "φ"), ("chi", "χ"), ("psi", "ψ"), ("omega", "ω"),
        ]
        for (k, v) in greek { map[k] = (v, .ident) }
        let capitals: [(String, String)] = [
            ("Gamma", "Γ"), ("Delta", "Δ"), ("Theta", "Θ"), ("Lambda", "Λ"), ("Xi", "Ξ"), ("Pi", "Π"),
            ("Sigma", "Σ"), ("Upsilon", "Υ"), ("Phi", "Φ"), ("Psi", "Ψ"), ("Omega", "Ω"),
        ]
        for (k, v) in capitals { map[k] = (v, .symbol) }
        let bins: [(String, String)] = [
            ("cdot", "·"), ("times", "×"), ("div", "÷"), ("pm", "±"), ("mp", "∓"), ("ast", "∗"), ("star", "⋆"),
            ("circ", "∘"), ("bullet", "•"), ("oplus", "⊕"), ("otimes", "⊗"), ("ominus", "⊖"), ("setminus", "∖"),
            ("wedge", "∧"), ("vee", "∨"), ("land", "∧"), ("lor", "∨"), ("cup", "∪"), ("cap", "∩"),
        ]
        for (k, v) in bins { map[k] = (v, .bin) }
        let rels: [(String, String)] = [
            ("leq", "≤"), ("le", "≤"), ("leqslant", "⩽"), ("geq", "≥"), ("ge", "≥"), ("geqslant", "⩾"),
            ("neq", "≠"), ("ne", "≠"), ("approx", "≈"), ("equiv", "≡"), ("sim", "∼"), ("simeq", "≃"),
            ("cong", "≅"), ("propto", "∝"), ("to", "→"), ("rightarrow", "→"), ("leftarrow", "←"),
            ("gets", "←"), ("leftrightarrow", "↔"), ("Rightarrow", "⇒"), ("Leftarrow", "⇐"),
            ("Leftrightarrow", "⇔"), ("implies", "⟹"), ("impliedby", "⟸"), ("iff", "⟺"), ("mapsto", "↦"),
            ("longrightarrow", "⟶"), ("longleftarrow", "⟵"), ("Longrightarrow", "⟹"), ("Longleftarrow", "⟸"),
            ("Longleftrightarrow", "⟺"), ("uparrow", "↑"), ("downarrow", "↓"), ("in", "∈"), ("notin", "∉"),
            ("ni", "∋"), ("subset", "⊂"), ("supset", "⊃"), ("subseteq", "⊆"), ("supseteq", "⊇"), ("mid", "∣"),
            ("parallel", "∥"), ("perp", "⊥"), ("ll", "≪"), ("gg", "≫"), ("prec", "≺"), ("succ", "≻"),
            ("vdash", "⊢"), ("models", "⊨"), ("coloneqq", "≔"), ("triangleq", "≜"), ("doteq", "≐"),
            ("approxeq", "≊"), ("asymp", "≍"),
        ]
        for (k, v) in rels { map[k] = (v, .rel) }
        let ords: [(String, String)] = [
            ("infty", "∞"), ("partial", "∂"), ("nabla", "∇"), ("forall", "∀"), ("exists", "∃"), ("nexists", "∄"),
            ("emptyset", "∅"), ("varnothing", "∅"), ("neg", "¬"), ("lnot", "¬"), ("angle", "∠"), ("triangle", "△"),
            ("hbar", "ħ"), ("ell", "ℓ"), ("Re", "ℜ"), ("Im", "ℑ"), ("aleph", "ℵ"), ("degree", "°"), ("ldots", "…"),
            ("dots", "…"), ("cdots", "⋯"), ("vdots", "⋮"), ("ddots", "⋱"), ("prime", "′"), ("dagger", "†"),
            ("checkmark", "✓"), ("square", "□"), ("Box", "□"), ("top", "⊤"), ("bot", "⊥"), ("flat", "♭"),
            ("sharp", "♯"), ("backslash", "∖"), ("%", "%"), ("surd", "√"), ("therefore", "∴"), ("because", "∵"),
            ("dotsc", "…"), ("dotsb", "⋯"), ("lbrace", "{"), ("rbrace", "}"), ("vert", "|"), ("Vert", "‖"),
        ]
        for (k, v) in ords { map[k] = (v, .symbol) }
        for (k, v) in [("langle", "⟨"), ("lfloor", "⌊"), ("lceil", "⌈"), ("lvert", "|"), ("lVert", "‖")] { map[k] = (v, .open) }
        for (k, v) in [("rangle", "⟩"), ("rfloor", "⌋"), ("rceil", "⌉"), ("rvert", "|"), ("rVert", "‖")] { map[k] = (v, .close) }
        let ops: [(String, String)] = [
            ("sum", "∑"), ("prod", "∏"), ("coprod", "∐"), ("bigcup", "⋃"), ("bigcap", "⋂"), ("bigoplus", "⨁"),
            ("bigotimes", "⨂"), ("bigvee", "⋁"), ("bigwedge", "⋀"), ("int", "∫"), ("iint", "∬"), ("iiint", "∭"),
            ("oint", "∮"),
        ]
        for (k, v) in ops { map[k] = (v, .largeOp) }
        let fns = [
            "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "arccot", "sinh", "cosh", "tanh",
            "coth", "ln", "lg", "log", "exp", "deg", "dim", "ker", "arg", "hom", "lim", "limsup", "liminf", "max",
            "min", "sup", "inf", "det", "gcd", "Pr", "tg", "ctg", "arctg", "arcctg", "sh", "ch", "th", "cth", "sgn",
            "argmax", "argmin", "rank", "tr", "lcm", "Var", "Cov", "erf",
        ]
        for f in fns { map[f] = (f, .fn) }
        map["lim"] = ("lim", .fn)
        map["liminf"] = ("lim inf", .fn)
        map["limsup"] = ("lim sup", .fn)
        map["argmax"] = ("arg max", .fn)
        map["argmin"] = ("arg min", .fn)
        return map
    }()
}

struct InlineMathRenderer {
    func render(_ node: MathNode, fs: CGFloat, offset: CGFloat = 0, script: Bool = false) -> AttributedString {
        switch node {
        case let .row(items):
            var out = AttributedString()
            let spaces = MathFormat.spacing(items, script: script)
            for (k, item) in items.enumerated() {
                out += gap(spaces[k], fs: fs)
                out += render(item, fs: fs, offset: offset, script: script)
            }
            return out
        case let .atom(s, kind):
            switch kind {
            case .ident: return piece(s, font: .system(size: fs, design: .serif).italic(), offset: offset)
            case .largeOp: return piece(s, font: .system(size: fs * 1.12, design: .serif), offset: offset - fs * 0.04)
            default: return piece(s, font: .system(size: fs, design: .serif), offset: offset)
            }
        case let .text(s, bold):
            return piece(s, font: .system(size: fs, weight: bold ? .bold : .regular), offset: offset)
        case let .frac(num, den, bar):
            if bar, isNumber(num), isNumber(den) {
                let small = scriptSize(fs)
                return render(num, fs: small, offset: offset + fs * 0.34, script: true)
                    + piece("⁄", font: .system(size: fs, design: .serif), offset: offset)
                    + render(den, fs: small, offset: offset, script: true)
            }
            let slash = bar ? "/" : "\u{2009}"
            return wrapped(num, fs: fs, offset: offset, script: script, parens: needsParens(num, denominator: false))
                + piece(slash, font: .system(size: fs, design: .serif), offset: offset)
                + wrapped(den, fs: fs, offset: offset, script: script, parens: needsParens(den, denominator: true))
        case let .sqrt(inner, index):
            var out = AttributedString()
            if let index { out += render(index, fs: scriptSize(fs) * 0.9, offset: offset + fs * 0.42, script: true) }
            out += piece("√", font: .system(size: fs, design: .serif), offset: offset)
            out += wrapped(inner, fs: fs, offset: offset, script: script, parens: !isSimple(inner))
            return out
        case let .scripts(base, sup, sub), let .limits(base, sup, sub):
            var out = render(base, fs: fs, offset: offset, script: script)
            let small = scriptSize(fs)
            if let sub { out += render(sub, fs: small, offset: offset - fs * 0.2, script: true) }
            if let sup { out += render(sup, fs: small, offset: offset + fs * 0.4, script: true) }
            return out
        case let .fenced(l, inner, r):
            let font = Font.system(size: fs, design: .serif)
            return piece(l, font: font, offset: offset) + render(inner, fs: fs, offset: offset, script: script) + piece(r, font: font, offset: offset)
        case let .accent(base, accent):
            var out = render(base, fs: fs, offset: offset, script: script)
            let chars = String(out.characters)
            let mark = Self.combining(accent)
            if accent == .overline || accent == .underline || chars.count > 1 && (accent == .bar) {
                var marked = AttributedString()
                for run in out.runs {
                    var s = ""
                    for ch in String(out[run.range].characters) {
                        s.append(ch)
                        if !ch.isWhitespace { s += mark }
                    }
                    var p = AttributedString(s)
                    p.setAttributes(run.attributes)
                    marked += p
                }
                return marked
            }
            if let last = out.runs.last {
                var p = AttributedString(mark)
                p.setAttributes(last.attributes)
                out += p
            }
            return out
        case let .table(rows, kind):
            let font = Font.system(size: fs, design: .serif)
            var out = AttributedString()
            switch kind {
            case let .matrix(l, r): out += piece(l.isEmpty ? "(" : l, font: font, offset: offset)
            case .cases: out += piece("{ ", font: font, offset: offset)
            case .aligned: break
            }
            for (k, row) in rows.enumerated() {
                if k > 0 { out += piece(kind == .aligned ? ";\u{2003}" : "; ", font: font, offset: offset) }
                for (j, cell) in row.enumerated() {
                    if j > 0, kind != .aligned { out += piece(kind == .cases ? ",\u{2004}" : "\u{2004}", font: font, offset: offset) }
                    out += render(cell, fs: fs, offset: offset, script: script)
                }
            }
            if case let .matrix(l, r) = kind { out += piece(l.isEmpty ? ")" : r, font: font, offset: offset) }
            return out
        case let .space(em):
            return gap(em, fs: fs)
        }
    }

    private func scriptSize(_ fs: CGFloat) -> CGFloat { max(8, fs * 0.72) }

    private func wrapped(_ node: MathNode, fs: CGFloat, offset: CGFloat, script: Bool, parens: Bool) -> AttributedString {
        let inner = render(node, fs: fs, offset: offset, script: script)
        guard parens else { return inner }
        let font = Font.system(size: fs, design: .serif)
        return piece("(", font: font, offset: offset) + inner + piece(")", font: font, offset: offset)
    }

    private func isSimple(_ node: MathNode) -> Bool {
        switch node {
        case let .atom(_, kind): return kind == .ident || kind == .number || kind == .symbol
        case let .row(items): return items.count == 1 && isSimple(items[0])
        case .text: return true
        case let .scripts(base, _, _): return isSimple(base)
        default: return false
        }
    }

    private func isNumber(_ node: MathNode) -> Bool {
        switch node {
        case let .atom(_, kind): return kind == .number
        case let .row(items): return items.count == 1 && isNumber(items[0])
        default: return false
        }
    }

    private func needsParens(_ node: MathNode, denominator: Bool) -> Bool {
        PlainMath.needsParens(node, denominator: denominator)
    }

    private func piece(_ s: String, font: Font, offset: CGFloat) -> AttributedString {
        guard !s.isEmpty else { return AttributedString() }
        var a = AttributedString(s.replacingOccurrences(of: "/", with: "\u{2060}/\u{2060}"))
        var container = AttributeContainer()
        container[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = font
        if offset != 0 { container[AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute.self] = offset }
        a.mergeAttributes(container)
        return a
    }

    private func gap(_ em: CGFloat, fs: CGFloat) -> AttributedString {
        let s: String
        switch em {
        case 1.5...: s = "\u{2003}\u{2003}"
        case 0.8...: s = "\u{2003}"
        case 0.4...: s = "\u{2002}"
        case 0.26...: s = "\u{2004}"
        case 0.2...: s = "\u{2005}"
        case 0.12...: s = "\u{2006}"
        default: return AttributedString()
        }
        return piece(s, font: .system(size: fs), offset: 0)
    }

    static func combining(_ accent: MathAccent) -> String {
        switch accent {
        case .vec: return "\u{20D7}"
        case .hat: return "\u{0302}"
        case .bar: return "\u{0304}"
        case .overline: return "\u{0305}"
        case .underline: return "\u{0332}"
        case .dot: return "\u{0307}"
        case .ddot: return "\u{0308}"
        case .tilde: return "\u{0303}"
        }
    }
}

enum PlainMath {
    static func render(_ node: MathNode) -> String {
        switch node {
        case let .row(items):
            let spaces = MathFormat.spacing(items)
            return items.enumerated().map { (spaces[$0.offset] >= 0.15 ? " " : "") + render($0.element) }.joined()
        case let .atom(s, _): return s
        case let .text(s, _): return s
        case let .frac(num, den, bar):
            return wrap(num) + (bar ? "/" : " ") + wrap(den, denominator: true)
        case let .sqrt(inner, index):
            return (index.map { MathFormat.superscript(render($0)) ?? "" } ?? "") + "√" + wrap(inner)
        case let .scripts(base, sup, sub), let .limits(base, sup, sub):
            var out = render(base)
            if let sub {
                let s = render(sub)
                out += MathFormat.subscript(s.replacingOccurrences(of: " ", with: "")) ?? "_" + (s.count == 1 ? s : "(\(s))")
            }
            if let sup {
                let s = render(sup)
                out += MathFormat.superscript(s.replacingOccurrences(of: " ", with: "")) ?? "^" + (s.count == 1 ? s : "(\(s))")
            }
            return out
        case let .fenced(l, inner, r): return l + render(inner) + r
        case let .accent(base, accent): return render(base) + InlineMathRenderer.combining(accent)
        case let .table(rows, kind):
            let lines = rows.map { $0.map(render).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
            switch kind {
            case let .matrix(l, r): return (l.isEmpty ? "(" : l) + lines.joined(separator: "; ") + (r.isEmpty ? ")" : r)
            case .cases: return lines.joined(separator: "; ")
            case .aligned: return lines.joined(separator: "\n")
            }
        case let .space(em): return em >= 0.15 ? " " : ""
        }
    }

    static func needsParens(_ node: MathNode, denominator: Bool = false) -> Bool {
        switch node {
        case let .row(items):
            let meaningful = items.filter { if case .space = $0 { return false }; return true }
            if meaningful.count == 1 { return needsParens(meaningful[0], denominator: denominator) }
            if denominator, !meaningful.allSatisfy(isLetter) { return true }
            return meaningful.contains { [.bin, .rel].contains(MathFormat.mathClass($0)) || needsParens($0) }
        case .frac: return true
        default: return false
        }
    }

    private static func isLetter(_ node: MathNode) -> Bool {
        switch node {
        case let .atom(_, kind): return kind == .ident
        case let .scripts(base, _, _): return isLetter(base)
        default: return false
        }
    }

    private static func wrap(_ node: MathNode, denominator: Bool = false) -> String {
        let s = render(node)
        return needsParens(node, denominator: denominator) ? "(\(s))" : s
    }
}

struct MathRichText: View {
    let text: String
    let fontSize: CGFloat
    let font: Font

    var body: some View {
        let blocks = MathFormat.blocks(text)
        if blocks.count == 1, case let .text(t) = blocks[0] {
            Text(MathFormat.inline(t, size: fontSize))
                .font(font)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case let .text(t):
                        Text(MathFormat.inline(t, size: fontSize))
                            .font(font)
                    case let .math(latex):
                        DisplayMath(latex: latex, fontSize: fontSize)
                    }
                }
            }
        }
    }
}

struct DisplayMath: View {
    let node: MathNode
    let fontSize: CGFloat

    init(latex: String, fontSize: CGFloat) {
        node = MathParser.parse(latex)
        self.fontSize = fontSize
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            MathView(node: node, fs: fontSize * 1.08)
            MathView(node: node, fs: fontSize * 0.92)
            MathView(node: node, fs: fontSize * 0.8)
            ScrollView(.horizontal, showsIndicators: false) {
                MathView(node: node, fs: fontSize * 0.86)
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

struct MathView: View {
    let node: MathNode
    let fs: CGFloat

    var body: some View {
        MathDraw.view(node, fs: fs, display: true)
            .fixedSize()
    }
}

private enum MathDraw {
    static let axis: CGFloat = 0.26

    static func line(_ fs: CGFloat) -> CGFloat { max(0.9, fs * 0.055) }

    static func scriptSize(_ fs: CGFloat) -> CGFloat { max(8, fs * 0.72) }

    static func serif(_ fs: CGFloat) -> Font { .system(size: fs, design: .serif) }

    static func view(_ node: MathNode, fs: CGFloat, display: Bool, script: Bool = false, leadingOrd: Bool = false) -> AnyView {
        switch node {
        case let .row(items):
            if items.isEmpty { return AnyView(Text(" ").font(serif(fs))) }
            let spaces = MathFormat.spacing(items, leadingOrd: leadingOrd, script: script)
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(items.indices, id: \.self) { k in
                        view(items[k], fs: fs, display: display, script: script)
                            .padding(.leading, spaces[k] * fs)
                    }
                }
            )

        case let .atom(s, kind):
            switch kind {
            case .ident:
                return AnyView(Text(s).font(serif(fs).italic()))
            case .largeOp:
                let integral = MathParser.integralChars.contains(s.first ?? " ")
                let size = display ? fs * (integral ? 1.75 : 1.5) : fs * 1.15
                return AnyView(
                    Text(s)
                        .font(serif(size))
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + fs * axis }
                )
            default:
                return AnyView(Text(s).font(serif(fs)))
            }

        case let .text(s, bold):
            return AnyView(Text(s).font(.system(size: fs, weight: bold ? .bold : .regular)))

        case let .frac(num, den, bar):
            let inner = display ? fs * 0.9 : max(8, fs * 0.8)
            let thickness = bar ? line(fs) : 0
            return AnyView(
                FractionLayout(gap: fs * 0.1, thickness: thickness, axis: fs * axis, pad: fs * 0.16) {
                    view(num, fs: inner, display: false, script: script)
                    Rectangle().opacity(bar ? 1 : 0)
                    view(den, fs: inner, display: false, script: script)
                }
            )

        case let .sqrt(inner, index):
            let lw = line(fs)
            let width = fs * 0.55
            let body = view(inner, fs: fs, display: display, script: script)
                .padding(.top, fs * 0.14 + lw)
                .padding(.leading, width + fs * 0.06)
                .padding(.trailing, fs * 0.06)
                .overlay(
                    RadicalShape(radicalWidth: width, lineWidth: lw)
                        .stroke(style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                )
            guard let index else { return AnyView(body) }
            return AnyView(
                RadicalIndexLayout(fs: fs) {
                    view(index, fs: max(7, fs * 0.55), display: false, script: true)
                    body
                }
            )

        case let .scripts(base, sup, sub):
            let small = scriptSize(fs)
            return AnyView(
                ScriptLayout(hasSup: sup != nil, hasSub: sub != nil, fs: fs) {
                    view(base, fs: fs, display: display, script: script)
                    if let sup { view(sup, fs: small, display: false, script: true) }
                    if let sub { view(sub, fs: small, display: false, script: true) }
                }
            )

        case let .limits(base, over, under):
            guard display else { return view(.scripts(base, sup: over, sub: under), fs: fs, display: false, script: script) }
            let small = scriptSize(fs)
            return AnyView(
                UnderOverLayout(hasOver: over != nil, hasUnder: under != nil, gap: -fs * 0.06) {
                    view(base, fs: fs, display: display, script: script)
                    if let over { view(over, fs: small, display: false, script: true) }
                    if let under { view(under, fs: small, display: false, script: true) }
                }
            )

        case let .fenced(l, inner, r):
            let content = view(inner, fs: fs, display: display, script: script)
            if MathFormat.height(inner) <= 1.45 {
                return AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: fs * 0.04) {
                        if !l.isEmpty { Text(l).font(serif(fs)) }
                        content
                        if !r.isEmpty { Text(r).font(serif(fs)) }
                    }
                )
            }
            return AnyView(stretched(content, l: l, r: r, fs: fs))

        case let .accent(base, accent):
            let content = view(base, fs: fs, display: display, script: script)
            let lw = line(fs)
            switch accent {
            case .overline:
                return AnyView(
                    content
                        .padding(.top, fs * 0.12 + lw)
                        .overlay(alignment: .top) { Rectangle().frame(height: lw) }
                )
            case .underline:
                return AnyView(
                    content
                        .padding(.bottom, fs * 0.08 + lw)
                        .overlay(alignment: .bottom) { Rectangle().frame(height: lw) }
                )
            default:
                let (glyph, size, raise) = accentGlyph(accent, fs: fs)
                return AnyView(
                    AccentLayout(raise: raise, skew: fs * 0.06) {
                        content
                        Text(glyph).font(serif(size))
                    }
                )
            }

        case let .table(rows, kind):
            let cellSize = display ? fs * 0.95 : fs * 0.85
            let columns = rows.map(\.count).max() ?? 0
            let spacing: CGFloat
            switch kind {
            case .aligned: spacing = 0
            case .cases: spacing = fs * 0.9
            case .matrix: spacing = fs * 0.8
            }
            let grid = Grid(alignment: .center, horizontalSpacing: spacing, verticalSpacing: fs * 0.3) {
                ForEach(rows.indices, id: \.self) { r in
                    GridRow(alignment: .firstTextBaseline) {
                        ForEach(0..<columns, id: \.self) { k in
                            let cell = k < rows[r].count ? rows[r][k] : MathNode.empty
                            view(cell, fs: cellSize, display: display, script: script, leadingOrd: kind == .aligned && k % 2 == 1)
                                .padding(.leading, kind == .aligned && k > 0 && k % 2 == 0 ? fs : 0)
                                .gridColumnAlignment(columnAlignment(kind, column: k, columns: columns))
                        }
                    }
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + fs * axis }

            switch kind {
            case let .matrix(l, r):
                return AnyView(stretched(AnyView(grid), l: l, r: r, fs: fs))
            case .cases:
                return AnyView(stretched(AnyView(grid), l: "{", r: "", fs: fs))
            case .aligned:
                return AnyView(grid)
            }

        case let .space(em):
            return AnyView(Color.clear.frame(width: max(0, em * fs), height: 0))
        }
    }

    private static func columnAlignment(_ kind: MathTable, column: Int, columns: Int) -> HorizontalAlignment {
        switch kind {
        case .aligned:
            if columns == 1 { return .center }
            return column % 2 == 0 ? .trailing : .leading
        case .cases: return .leading
        case .matrix: return .center
        }
    }

    private static func accentGlyph(_ accent: MathAccent, fs: CGFloat) -> (String, CGFloat, CGFloat) {
        switch accent {
        case .vec: return ("→", fs * 0.7, fs * 0.66)
        case .hat: return ("ˆ", fs, fs * 0.3)
        case .bar: return ("¯", fs, fs * 0.28)
        case .dot: return ("˙", fs, fs * 0.3)
        case .ddot: return ("¨", fs, fs * 0.3)
        case .tilde: return ("˜", fs, fs * 0.3)
        case .overline, .underline: return ("", fs, 0)
        }
    }

    private static func stretched(_ content: AnyView, l: String, r: String, fs: CGFloat) -> some View {
        let lw = line(fs)
        let width = fs * 0.34
        return content
            .padding(.vertical, fs * 0.06)
            .padding(.leading, l.isEmpty ? 0 : width + fs * 0.1)
            .padding(.trailing, r.isEmpty ? 0 : width + fs * 0.1)
            .overlay {
                HStack(spacing: 0) {
                    DelimiterShape(symbol: l, left: true)
                        .stroke(style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round))
                        .frame(width: width)
                    Spacer(minLength: 0)
                    DelimiterShape(symbol: r, left: false)
                        .stroke(style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round))
                        .frame(width: width)
                }
            }
    }
}

private struct RadicalShape: Shape {
    var radicalWidth: CGFloat
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = rect.minY + lineWidth / 2
        let w = radicalWidth
        p.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + rect.height * 0.62))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.26, y: rect.minY + rect.height * 0.54))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.52, y: rect.maxY - lineWidth / 2))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: top))
        return p
    }
}

private struct DelimiterShape: Shape {
    var symbol: String
    var left: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height
        let inset = rect.width * 0.2
        let near = left ? rect.maxX - inset : rect.minX + inset
        let far = left ? rect.minX + inset : rect.maxX - inset
        let mid = rect.midX
        switch symbol {
        case "(", ")":
            p.move(to: CGPoint(x: near, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: near, y: rect.maxY), control: CGPoint(x: far - (near - far) * 0.55, y: rect.midY))
        case "[", "]", "⌊", "⌋", "⌈", "⌉":
            let topBar = symbol != "⌊" && symbol != "⌋"
            let bottomBar = symbol != "⌈" && symbol != "⌉"
            p.move(to: CGPoint(x: topBar ? near : far, y: rect.minY))
            p.addLine(to: CGPoint(x: far, y: rect.minY))
            p.addLine(to: CGPoint(x: far, y: rect.maxY))
            if bottomBar { p.addLine(to: CGPoint(x: near, y: rect.maxY)) }
        case "{", "}":
            let tip = left ? rect.minX + inset * 0.3 : rect.maxX - inset * 0.3
            p.move(to: CGPoint(x: near, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: mid, y: rect.minY + h * 0.12), control: CGPoint(x: mid, y: rect.minY))
            p.addLine(to: CGPoint(x: mid, y: rect.midY - h * 0.08))
            p.addQuadCurve(to: CGPoint(x: tip, y: rect.midY), control: CGPoint(x: mid, y: rect.midY))
            p.addQuadCurve(to: CGPoint(x: mid, y: rect.midY + h * 0.08), control: CGPoint(x: mid, y: rect.midY))
            p.addLine(to: CGPoint(x: mid, y: rect.maxY - h * 0.12))
            p.addQuadCurve(to: CGPoint(x: near, y: rect.maxY), control: CGPoint(x: mid, y: rect.maxY))
        case "|":
            p.move(to: CGPoint(x: mid, y: rect.minY))
            p.addLine(to: CGPoint(x: mid, y: rect.maxY))
        case "‖":
            for x in [mid - rect.width * 0.15, mid + rect.width * 0.15] {
                p.move(to: CGPoint(x: x, y: rect.minY))
                p.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        case "⟨", "⟩":
            p.move(to: CGPoint(x: near, y: rect.minY))
            p.addLine(to: CGPoint(x: far, y: rect.midY))
            p.addLine(to: CGPoint(x: near, y: rect.maxY))
        default:
            break
        }
        return p
    }
}

private struct FractionLayout: Layout {
    var gap: CGFloat
    var thickness: CGFloat
    var axis: CGFloat
    var pad: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let n = subviews[0].sizeThatFits(.unspecified)
        let d = subviews[2].sizeThatFits(.unspecified)
        return CGSize(width: max(n.width, d.width) + pad * 2, height: n.height + d.height + gap * 2 + thickness)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = subviews[0].sizeThatFits(.unspecified)
        let d = subviews[2].sizeThatFits(.unspecified)
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(n))
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + n.height + gap),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: thickness)
        )
        subviews[2].place(at: CGPoint(x: bounds.midX, y: bounds.minY + n.height + gap * 2 + thickness), anchor: .top, proposal: ProposedViewSize(d))
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let n = subviews[0].sizeThatFits(.unspecified)
        return bounds.minY + n.height + gap + thickness / 2 + axis
    }
}

private struct PlacedFrames {
    var frames: [CGRect]
    var size: CGSize
    var baseline: CGFloat

    init(_ raw: [CGRect], baseline: CGFloat) {
        let minY = raw.map(\.minY).min() ?? 0
        let minX = raw.map(\.minX).min() ?? 0
        frames = raw.map { $0.offsetBy(dx: -minX, dy: -minY) }
        size = CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
        self.baseline = baseline - minY
    }
}

private protocol FramedLayout: Layout where Cache == () {
    func frames(_ subviews: Subviews) -> PlacedFrames
}

extension FramedLayout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = frames(subviews)
        for (k, frame) in placed.frames.enumerated() where k < subviews.count {
            subviews[k].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        return bounds.minY + frames(subviews).baseline
    }
}

private struct ScriptLayout: FramedLayout {
    var hasSup: Bool
    var hasSub: Bool
    var fs: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let b = subviews[0].dimensions(in: .unspecified)
        let baseBaseline = b[VerticalAlignment.firstTextBaseline]
        var raw = [CGRect(x: 0, y: 0, width: b.width, height: b.height)]
        let x = b.width + fs * 0.05
        var k = 1
        if hasSup, k < subviews.count {
            let s = subviews[k].dimensions(in: .unspecified)
            let sBase = s[VerticalAlignment.firstTextBaseline]
            let y = min(baseBaseline - fs * 0.42, sBase * 0.72) - sBase
            raw.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            k += 1
        }
        if hasSub, k < subviews.count {
            let s = subviews[k].dimensions(in: .unspecified)
            let sBase = s[VerticalAlignment.firstTextBaseline]
            let y = max(baseBaseline + fs * 0.2, b.height - s.height * 0.3) - sBase
            raw.append(CGRect(x: x - (hasSup ? 0 : fs * 0.02), y: y, width: s.width, height: s.height))
        }
        return PlacedFrames(raw, baseline: baseBaseline)
    }
}

private struct UnderOverLayout: FramedLayout {
    var hasOver: Bool
    var hasUnder: Bool
    var gap: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let b = subviews[0].dimensions(in: .unspecified)
        var k = 1
        let over = hasOver && k < subviews.count ? subviews[k].dimensions(in: .unspecified) : nil
        if hasOver { k += 1 }
        let under = hasUnder && k < subviews.count ? subviews[k].dimensions(in: .unspecified) : nil
        let width = max(b.width, over?.width ?? 0, under?.width ?? 0)
        let baseY = over.map { $0.height + gap } ?? 0
        var raw = [CGRect(x: (width - b.width) / 2, y: baseY, width: b.width, height: b.height)]
        if let over { raw.append(CGRect(x: (width - over.width) / 2, y: 0, width: over.width, height: over.height)) }
        if let under { raw.append(CGRect(x: (width - under.width) / 2, y: baseY + b.height + gap, width: under.width, height: under.height)) }
        return PlacedFrames(raw, baseline: baseY + b[VerticalAlignment.firstTextBaseline])
    }
}

private struct AccentLayout: FramedLayout {
    var raise: CGFloat
    var skew: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let b = subviews[0].dimensions(in: .unspecified)
        let a = subviews[1].dimensions(in: .unspecified)
        let baseBaseline = b[VerticalAlignment.firstTextBaseline]
        let accentTop = baseBaseline - raise - a[VerticalAlignment.firstTextBaseline]
        return PlacedFrames([
            CGRect(x: 0, y: 0, width: b.width, height: b.height),
            CGRect(x: (b.width - a.width) / 2 + skew, y: accentTop, width: a.width, height: a.height),
        ], baseline: baseBaseline)
    }
}

private struct RadicalIndexLayout: FramedLayout {
    var fs: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let index = subviews[0].dimensions(in: .unspecified)
        let body = subviews[1].dimensions(in: .unspecified)
        let bodyX = max(0, index.width - fs * 0.3)
        let indexX = bodyX + fs * 0.3 - index.width
        let indexY = body.height * 0.5 - index.height
        return PlacedFrames([
            CGRect(x: indexX, y: indexY, width: index.width, height: index.height),
            CGRect(x: bodyX, y: 0, width: body.width, height: body.height),
        ], baseline: body[VerticalAlignment.firstTextBaseline])
    }
}
