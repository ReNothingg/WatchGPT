import Foundation

/// Turns LaTeX-ish math into compact Unicode that reads well on a tiny screen:
/// `\frac{a+b}{2}` → `(a+b)/2`, `x^{2}` → `x²`, `\sqrt{x}` → `√x`, `\alpha` → `α`, `$…$` delimiters removed.
enum MathFormat {
    static func prettify(_ text: String) -> String {
        guard text.contains("\\") || text.contains("$") || text.contains("^") || text.contains("_{") else { return text }
        var s = text

        // Display / inline math delimiters.
        for (a, b) in [("\\[", ""), ("\\]", ""), ("\\(", ""), ("\\)", ""), ("$$", "")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        s = s.replacingOccurrences(of: #"\$([^$\n]+)\$"#, with: "$1", options: .regularExpression)

        for (k, v) in [("R", "ℝ"), ("N", "ℕ"), ("Z", "ℤ"), ("Q", "ℚ"), ("C", "ℂ")] {
            s = s.replacingOccurrences(of: "\\mathbb{\(k)}", with: v)
        }

        // Formatting commands that just wrap content.
        s = s.replacingOccurrences(of: #"\\(?:text|mathrm|mathbf|mathit|operatorname|textbf|boxed|mathbb)\{([^{}]*)\}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\(?:left|right|displaystyle|,|;|!|quad|qquad)"#, with: " ", options: .regularExpression)

        // Fractions and roots (repeat for simple nesting).
        for _ in 0..<4 {
            let before = s
            s = replace(s, #"\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}"#) { g in
                "\(wrap(g[1]))/\(wrap(g[2]))"
            }
            s = replace(s, #"\\sqrt\[([^\]]*)\]\{([^{}]*)\}"#) { g in
                "\(superscript(g[1]) ?? "^" + g[1])√\(wrap(g[2]))"
            }
            s = replace(s, #"\\sqrt\{([^{}]*)\}"#) { g in "√\(wrap(g[1]))" }
            if s == before { break }
        }

        // Symbols.
        for (k, v) in symbols {
            s = s.replacingOccurrences(of: "\\\\" + k + "(?![A-Za-z])", with: v, options: .regularExpression)
        }

        // Super/subscripts.
        s = replace(s, #"\^\{([^{}]*)\}"#) { g in superscript(g[1]) ?? "^(\(g[1]))" }
        s = replace(s, #"\^([A-Za-z0-9+\-=()])"#) { g in superscript(g[1]) ?? "^" + g[1] }
        s = replace(s, #"_\{([^{}]*)\}"#) { g in `subscript`(g[1]) ?? "_(\(g[1]))" }
        s = replace(s, #"(?<=[A-Za-z0-9)∫∑∏])_([A-Za-z0-9])"#) { g in `subscript`(g[1]) ?? "_" + g[1] }

        // Leftover braces / spacing.
        s = s.replacingOccurrences(of: #"\\\{"#, with: "{", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\\}"#, with: "}", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<!\\)[{}]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return s
    }

    private static func wrap(_ x: String) -> String {
        let t = x.trimmingCharacters(in: .whitespaces)
        let simple = t.range(of: #"^([0-9.]+|√?[A-Za-zα-ωΑ-Ωπ][²³¹⁰⁴⁵⁶⁷⁸⁹ⁿ]*)$"#, options: .regularExpression) != nil
        return simple ? t : "(\(t))"
    }

    private static func replace(_ s: String, _ pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        let ns = s as NSString
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            let range = Range(match.range, in: result)!
            result.replaceSubrange(range, with: transform(groups))
        }
        return result
    }

    private static let superMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "k": "ᵏ", "m": "ᵐ", "t": "ᵗ", "T": "ᵀ", " ": " ",
    ]
    private static let subMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "n": "ₙ", "m": "ₘ", "x": "ₓ", "t": "ₜ", " ": " ",
    ]

    static func superscript(_ s: String) -> String? { map(s, superMap) }
    static func `subscript`(_ s: String) -> String? { map(s, subMap) }

    private static func map(_ s: String, _ table: [Character: Character]) -> String? {
        var out = ""
        for c in s {
            guard let m = table[c] else { return nil }
            out.append(m)
        }
        return out.isEmpty ? nil : out
    }

    /// Longest names first so `\leq` wins over `\le`.
    private static let symbols: [(String, String)] = [
        ("alpha", "α"), ("beta", "β"), ("gamma", "γ"), ("delta", "δ"), ("epsilon", "ε"), ("varepsilon", "ε"),
        ("zeta", "ζ"), ("eta", "η"), ("theta", "θ"), ("vartheta", "ϑ"), ("iota", "ι"), ("kappa", "κ"),
        ("lambda", "λ"), ("mu", "μ"), ("nu", "ν"), ("xi", "ξ"), ("pi", "π"), ("rho", "ρ"), ("sigma", "σ"),
        ("tau", "τ"), ("upsilon", "υ"), ("phi", "φ"), ("varphi", "φ"), ("chi", "χ"), ("psi", "ψ"), ("omega", "ω"),
        ("Gamma", "Γ"), ("Delta", "Δ"), ("Theta", "Θ"), ("Lambda", "Λ"), ("Xi", "Ξ"), ("Pi", "Π"),
        ("Sigma", "Σ"), ("Phi", "Φ"), ("Psi", "Ψ"), ("Omega", "Ω"),
        ("cdot", "·"), ("times", "×"), ("div", "÷"), ("pm", "±"), ("mp", "∓"),
        ("leq", "≤"), ("geq", "≥"), ("le", "≤"), ("ge", "≥"), ("neq", "≠"), ("ne", "≠"),
        ("approx", "≈"), ("equiv", "≡"), ("sim", "∼"), ("propto", "∝"),
        ("infty", "∞"), ("partial", "∂"), ("nabla", "∇"), ("iiint", "∭"), ("iint", "∬"), ("oint", "∮"), ("int", "∫"),
        ("sum", "∑"), ("prod", "∏"), ("lim", "lim"), ("log", "log"), ("ln", "ln"), ("sin", "sin"), ("cos", "cos"),
        ("tan", "tan"), ("cot", "cot"), ("arcsin", "arcsin"), ("arccos", "arccos"), ("arctan", "arctan"),
        ("exp", "exp"), ("max", "max"), ("min", "min"), ("det", "det"),
        ("Rightarrow", "⇒"), ("Leftarrow", "⇐"), ("Leftrightarrow", "⇔"), ("iff", "⇔"), ("implies", "⇒"),
        ("rightarrow", "→"), ("leftarrow", "←"), ("leftrightarrow", "↔"), ("to", "→"), ("mapsto", "↦"),
        ("in", "∈"), ("notin", "∉"), ("subseteq", "⊆"), ("subset", "⊂"), ("cup", "∪"), ("cap", "∩"),
        ("emptyset", "∅"), ("varnothing", "∅"), ("forall", "∀"), ("exists", "∃"), ("neg", "¬"),
        ("land", "∧"), ("lor", "∨"), ("angle", "∠"), ("perp", "⊥"), ("parallel", "∥"), ("circ", "°"),
        ("degree", "°"), ("ldots", "…"), ("cdots", "⋯"), ("dots", "…"), ("hbar", "ħ"),
    ].sorted { $0.0.count > $1.0.count }
}
