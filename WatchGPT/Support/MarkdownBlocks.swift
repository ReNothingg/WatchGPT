import SwiftUI

struct CodeBlockView: View {
    let language: String
    let code: String
    let fontSize: CGFloat
    @State private var expanded = false

    private var lineCount: Int {
        code.isEmpty ? 0 : code.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private var title: String {
        let name = language.isEmpty ? "Код" : language
        return "\(name) · \(lineCount) \(Self.linesWord(lineCount))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: fontSize * 0.7, weight: .semibold))
                    Text(title)
                        .font(.system(size: fontSize * 0.78, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: fontSize * 0.65, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle()
                    .fill(Theme.track)
                    .frame(height: 0.5)
                HorizontalPan {
                    Text(CodeHighlighter.highlight(code, language: language))
                        .font(.system(size: (fontSize * 0.74).rounded(), design: .monospaced))
                        .fixedSize()
                        .padding(8)
                }
            }
        }
        .background(Theme.surfaceDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.track, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private static func linesWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1, mod100 != 11 { return "строка" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "строки" }
        return "строк"
    }
}

struct TableBlockView: View {
    let rows: [[String]]
    let aligns: [MathFormat.TableAlign]
    let fontSize: CGFloat
    @Environment(\.tableLongPress) private var longPress

    private var columns: Range<Int> { 0..<(rows.first?.count ?? 0) }
    private var bodyRows: [Int] { Array(rows.indices.dropFirst()) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(size: (fontSize * 0.86).rounded())
            grid(size: (fontSize * 0.74).rounded())
            stacked(size: (fontSize * 0.86).rounded())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) { longPress?() }
        .accessibilityAction(named: "Переписать без таблиц") { longPress?() }
    }

    private func grid(size: CGFloat) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                ForEach(columns, id: \.self) { c in
                    cell(rows[0][c], column: c, size: size, header: true)
                }
            }
            line(strong: true)
            ForEach(bodyRows, id: \.self) { r in
                GridRow {
                    ForEach(columns, id: \.self) { c in
                        cell(rows[r][c], column: c, size: size, header: false)
                    }
                }
                if r != bodyRows.last {
                    line(strong: false)
                }
            }
        }
        .fixedSize()
    }

    private func cell(_ text: String, column: Int, size: CGFloat, header: Bool) -> some View {
        let fs = header ? (size * 0.86).rounded() : size
        return CappedWidth(cap: size * 8) {
            Text(MathFormat.inline(text, size: fs))
                .font(.system(size: fs, weight: header ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(header ? Theme.secondaryText : Theme.accent)
                .multilineTextAlignment(textAlignment(column))
        }
        .padding(.vertical, header ? 3 : 5)
        .gridColumnAlignment(columnAlignment(column))
    }

    private func line(strong: Bool) -> some View {
        Rectangle()
            .fill(strong ? Theme.track : Theme.track.opacity(0.5))
            .frame(height: 0.5)
    }

    private func stacked(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(bodyRows.isEmpty ? [0] : bodyRows, id: \.self) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(MathFormat.inline(rows[r][0], size: size))
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    ForEach(Array(columns.dropFirst()), id: \.self) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(MathFormat.inline(rows[0][c], size: size * 0.86))
                                .font(.system(size: (size * 0.86).rounded()))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer(minLength: 4)
                            Text(MathFormat.inline(rows[r][c], size: size))
                                .font(.system(size: size))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .padding(.vertical, 5)
                if r != bodyRows.last && !bodyRows.isEmpty {
                    line(strong: false)
                }
            }
        }
    }

    private func align(_ c: Int) -> MathFormat.TableAlign {
        c < aligns.count ? aligns[c] : .leading
    }

    private func columnAlignment(_ c: Int) -> HorizontalAlignment {
        switch align(c) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(_ c: Int) -> TextAlignment {
        switch align(c) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct ListBlockView: View {
    let items: [MathFormat.ListItem]
    let fontSize: CGFloat
    let font: Font
    var cached = true

    private var indentStep: CGFloat { (fontSize * 0.8).rounded() }
    private var markerWidth: CGFloat { (fontSize * 0.75).rounded() }

    private var numberWidth: CGFloat {
        let longest = items.reduce(0) { result, item in
            if case let .number(n) = item.marker { return max(result, n.count) }
            return result
        }
        return max(markerWidth, CGFloat(longest) * fontSize * 0.56)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: (fontSize * 0.25).rounded()) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: MathFormat.ListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: (fontSize * 0.3).rounded()) {
            marker(item)
            Text(MathFormat.inline(item.text, size: fontSize, cached: cached))
                .font(font)
                .strikethrough(isDone(item), color: Theme.secondaryText)
                .opacity(isDone(item) ? 0.55 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(min(item.level, 4)) * indentStep)
    }

    @ViewBuilder
    private func marker(_ item: MathFormat.ListItem) -> some View {
        switch item.marker {
        case .bullet:
            Text(Self.bullets[item.level % Self.bullets.count])
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: markerWidth)
        case let .number(n):
            Text(n)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: numberWidth, alignment: .trailing)
        case let .task(done):
            Text(Image(systemName: done ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: fontSize * 0.85))
                .foregroundStyle(done ? Theme.accent : Theme.secondaryText)
                .frame(width: markerWidth)
        }
    }

    private func isDone(_ item: MathFormat.ListItem) -> Bool {
        if case .task(true) = item.marker { return true }
        return false
    }

    private static let bullets = ["•", "◦", "▪︎"]
}

struct QuoteBlockView: View {
    let text: String
    let fontSize: CGFloat
    let font: Font
    var live = false

    var body: some View {
        HStack(alignment: .top, spacing: (fontSize * 0.45).rounded()) {
            Capsule()
                .fill(Theme.secondaryText.opacity(0.55))
                .frame(width: 2.5)
            MathRichText(text: text, fontSize: fontSize, font: font, live: live)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
    }
}

private struct TableLongPressKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var tableLongPress: (() -> Void)? {
        get { self[TableLongPressKey.self] }
        set { self[TableLongPressKey.self] = newValue }
    }
}

struct HorizontalPan<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat?
    @State private var contentWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0

    private var maxOffset: CGFloat { max(0, contentWidth - visibleWidth) }

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            .offset(x: -offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            .clipped()
            .overlay(alignment: .trailing) {
                if offset < maxOffset - 1 {
                    LinearGradient(colors: [Theme.surfaceDim.opacity(0), Theme.surfaceDim], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 14)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        guard maxOffset > 0 else { return }
                        if start == nil {
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            start = offset
                        }
                        offset = min(max(0, (start ?? offset) - value.translation.width), maxOffset)
                    }
                    .onEnded { _ in start = nil }
            )
    }
}

struct CappedWidth: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? cap, cap)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

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
