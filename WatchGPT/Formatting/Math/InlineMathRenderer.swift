import SwiftUI

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
