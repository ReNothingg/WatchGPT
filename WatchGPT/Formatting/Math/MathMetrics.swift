import SwiftUI

extension MathFormat {
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
