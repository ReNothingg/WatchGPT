import SwiftUI

extension MathParser {
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
