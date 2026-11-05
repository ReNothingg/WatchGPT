import SwiftUI

enum CodeHighlighter {
    private enum Kind {
        case plain, keyword, string, number, comment, type, function
    }

    private static func color(_ kind: Kind) -> Color {
        switch kind {
        case .plain: return Theme.accent
        case .keyword: return Color(red: 0.99, green: 0.42, blue: 0.66)
        case .string: return Color(red: 0.99, green: 0.53, blue: 0.45)
        case .number: return Color(red: 0.85, green: 0.78, blue: 0.47)
        case .comment: return Color(red: 0.47, green: 0.53, blue: 0.59)
        case .type: return Color(red: 0.45, green: 0.83, blue: 0.96)
        case .function: return Color(red: 0.51, green: 0.80, blue: 0.70)
        }
    }

    private static let hashLanguages: Set<String> = [
        "python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "console", "yaml", "yml", "toml",
        "r", "perl", "pl", "dockerfile", "makefile", "make", "elixir", "ex", "nim", "powershell", "ps1", "ini", "conf",
    ]
    private static let dashLanguages: Set<String> = ["sql", "lua", "haskell", "hs", "elm", "ada"]

    private static let keywords: Set<String> = [
        "let", "var", "const", "func", "function", "def", "class", "struct", "enum", "protocol", "interface",
        "extends", "implements", "import", "from", "export", "return", "if", "else", "elif", "for", "while",
        "do", "switch", "case", "break", "continue", "default", "in", "of", "is", "as", "try", "catch",
        "finally", "throw", "throws", "rethrows", "async", "await", "yield", "new", "delete", "this", "self",
        "Self", "super", "null", "nil", "None", "true", "false", "True", "False", "void", "public", "private",
        "protected", "internal", "static", "final", "override", "fileprivate", "open", "guard", "defer",
        "where", "typealias", "extension", "init", "deinit", "inout", "some", "any", "package", "fn", "mut",
        "pub", "use", "mod", "impl", "trait", "match", "loop", "crate", "dyn", "ref", "type", "lambda", "with",
        "pass", "raise", "except", "global", "nonlocal", "and", "or", "not", "echo", "then", "fi", "done",
        "esac", "local", "readonly", "int", "float", "double", "char", "bool", "boolean", "string", "long",
        "short", "unsigned", "auto", "namespace", "using", "template", "typename", "val", "object", "fun",
        "when", "go", "chan", "range", "map", "goto", "undefined", "typeof", "instanceof", "abstract",
        "sealed", "data", "suspend", "lazy", "weak", "unowned", "mutating", "operator", "volatile", "extern",
        "sizeof", "elseif", "end", "begin", "unless", "until", "module", "require", "include", "debugger",
        "select", "insert", "update", "into", "values", "set", "create", "table", "drop", "alter", "join",
        "left", "right", "inner", "outer", "on", "group", "by", "order", "limit", "having", "distinct",
        "union", "primary", "key", "references", "index", "view", "asc", "desc", "count", "like", "between",
    ]

    static func highlight(_ code: String, language: String) -> AttributedString {
        let lang = language.lowercased()
        let hashComments = hashLanguages.contains(lang)
        let dashComments = dashLanguages.contains(lang)
        let slashComments = !hashComments && !dashComments || lang == "sql"
        let caseInsensitive = lang == "sql"
        let singleQuoteStrings = !["swift", "rust", "rs", "lisp", "clojure"].contains(lang)

        let c = Array(code)
        var result = AttributedString()
        var pending = ""
        var pendingKind = Kind.plain

        func emit(_ s: String, _ kind: Kind) {
            if kind != pendingKind, !pending.isEmpty {
                var piece = AttributedString(pending)
                piece.foregroundColor = color(pendingKind)
                result += piece
                pending = ""
            }
            pendingKind = kind
            pending += s
        }

        func isIdentStart(_ ch: Character) -> Bool { ch.isLetter || ch == "_" || ch == "$" }
        func isIdent(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "_" || ch == "$" }

        func has(_ s: String, at i: Int) -> Bool {
            var k = i
            for ch in s {
                guard k < c.count, c[k] == ch else { return false }
                k += 1
            }
            return true
        }

        func lineEnd(from i: Int) -> Int {
            var k = i
            while k < c.count, c[k] != "\n" { k += 1 }
            return k
        }

        var i = 0
        while i < c.count {
            let ch = c[i]
            if (slashComments && has("//", at: i)) || (hashComments && ch == "#") || (dashComments && has("--", at: i)) {
                let end = lineEnd(from: i)
                emit(String(c[i..<end]), .comment)
                i = end
            } else if slashComments, has("/*", at: i) {
                var end = i + 2
                while end < c.count, !has("*/", at: end) { end += 1 }
                end = min(c.count, end + 2)
                emit(String(c[i..<end]), .comment)
                i = end
            } else if ch == "\"" || ch == "`" || (ch == "'" && singleQuoteStrings) {
                let triple = has(String(repeating: ch, count: 3), at: i)
                let quote = triple ? String(repeating: ch, count: 3) : String(ch)
                var end = i + quote.count
                while end < c.count {
                    if c[end] == "\\" { end += 2; continue }
                    if has(quote, at: end) { end += quote.count; break }
                    if c[end] == "\n", !triple, ch != "`" { break }
                    end += 1
                }
                end = min(end, c.count)
                emit(String(c[i..<end]), .string)
                i = end
            } else if ch.isNumber, i == 0 || !isIdent(c[i - 1]) {
                var end = i + 1
                while end < c.count, c[end].isHexDigit || c[end] == "." || c[end] == "_" || c[end] == "x" || c[end] == "X" {
                    if c[end] == ".", end + 1 < c.count, !c[end + 1].isNumber { break }
                    end += 1
                }
                emit(String(c[i..<end]), .number)
                i = end
            } else if isIdentStart(ch) || (ch == "@" && i + 1 < c.count && isIdentStart(c[i + 1])) {
                var end = i + 1
                while end < c.count, isIdent(c[end]) { end += 1 }
                let word = String(c[i..<end])
                var next = end
                while next < c.count, c[next] == " " { next += 1 }
                let kind: Kind
                if ch == "@" {
                    kind = .keyword
                } else if keywords.contains(word) || (caseInsensitive && keywords.contains(word.lowercased())) {
                    kind = .keyword
                } else if next < c.count, c[next] == "(" {
                    kind = .function
                } else if ch.isUppercase, word.count > 1 {
                    kind = .type
                } else {
                    kind = .plain
                }
                emit(word, kind)
                i = end
            } else {
                emit(String(ch), .plain)
                i += 1
            }
        }
        emit("", .plain)
        if !pending.isEmpty {
            var piece = AttributedString(pending)
            piece.foregroundColor = color(pendingKind)
            result += piece
        }
        return result
    }
}
