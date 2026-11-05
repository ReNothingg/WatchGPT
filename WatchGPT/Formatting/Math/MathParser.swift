import SwiftUI

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
        if let ch = peek(), ch.isNumber {
            i += 1
            return .atom(String(ch), .number)
        }
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
}
