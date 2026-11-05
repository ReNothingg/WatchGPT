import SwiftUI

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
