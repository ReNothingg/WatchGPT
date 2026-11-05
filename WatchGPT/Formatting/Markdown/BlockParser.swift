import SwiftUI

extension MathFormat {
    static func blocks(_ text: String) -> [Block] {
        guard text.containsBytes("```") || text.containsBytes("~~~") || text.containsAnyByte("|") || hasLineMarkers(text) else {
            return mathBlocks(text)
        }
        return structural(text)
    }

    private static func hasLineMarkers(_ text: String) -> Bool {
        let b = Array(text.utf8)
        var i = 0
        while i < b.count {
            while i < b.count, b[i] == 32 || b[i] == 9 { i += 1 }
            guard i < b.count else { return false }
            let c = b[i]
            if c == UInt8(ascii: ">") { return true }
            if c == UInt8(ascii: "-") || c == UInt8(ascii: "*") || c == UInt8(ascii: "+") {
                if i + 1 < b.count, b[i + 1] == 32 { return true }
            } else if c >= 48, c <= 57 {
                var j = i
                while j < b.count, b[j] >= 48, b[j] <= 57 { j += 1 }
                if j + 1 < b.count, b[j] == UInt8(ascii: ".") || b[j] == UInt8(ascii: ")"), b[j + 1] == 32 { return true }
            }
            while i < b.count, b[i] != 10 { i += 1 }
            i += 1
        }
        return false
    }

    private static func listMatch(_ line: String) -> (indent: Int, marker: ListMarker, text: String)? {
        var indent = 0
        var rest = Substring(line)
        while let ch = rest.first, ch == " " || ch == "\t" {
            indent += ch == "\t" ? 4 : 1
            rest = rest.dropFirst()
        }
        guard let first = rest.first else { return nil }
        var marker: ListMarker
        var body: Substring
        if first == "-" || first == "*" || first == "+" {
            guard rest.dropFirst().first == " " else { return nil }
            if rest.allSatisfy({ $0 == first || $0 == " " }), rest.filter({ $0 == first }).count >= 3 { return nil }
            marker = .bullet
            body = rest.dropFirst(2)
        } else if first.isASCII, first.isNumber {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard digits.count <= 9 else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let punct = after.first, punct == "." || punct == ")", after.dropFirst().first == " " else { return nil }
            marker = .number(String(digits) + ".")
            body = after.dropFirst(2)
        } else {
            return nil
        }
        body = body.drop { $0 == " " }
        if case .bullet = marker, body.count >= 3, body.first == "[", body.dropFirst(2).first == "]" {
            let mark = body.dropFirst().first
            if mark == " " || mark == "x" || mark == "X" {
                marker = .task(mark != " ")
                body = body.dropFirst(3).drop { $0 == " " }
            }
        }
        let text = body.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (indent, marker, text)
    }

    private static func quoteContent(_ line: String) -> String? {
        let t = line.drop { $0 == " " || $0 == "\t" }
        guard t.first == ">" else { return nil }
        var rest = t.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    private static func leadingIndent(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func insideMath(_ lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        let s = lines.joined(separator: "\n")
        func count(_ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }
        if count("$$") % 2 == 1 { return true }
        if count("\\[") > count("\\]") { return true }
        return count("\\begin{") > count("\\end{")
    }

    private static func structural(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var out: [Block] = []
        var buffer: [String] = []
        var i = 0

        func flush() {
            let s = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            buffer.removeAll()
            if !s.trimmingCharacters(in: .whitespaces).isEmpty { out.append(contentsOf: mathBlocks(s)) }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = fenceRun(trimmed) {
                flush()
                let lang = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                let indent = line.prefix { $0 == " " }.count
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let close = fenceRun(t), close.first == fence.first, close.count >= fence.count, t.count == close.count {
                        i += 1
                        break
                    }
                    var l = Substring(lines[i])
                    var n = 0
                    while n < indent, l.first == " " { l = l.dropFirst(); n += 1 }
                    body.append(String(l))
                    i += 1
                }
                out.append(.code(lang, body.joined(separator: "\n")))
                continue
            }
            if trimmed.contains("|"), i + 1 < lines.count, let aligns = tableSeparator(lines[i + 1]) {
                let header = tableCells(trimmed)
                if header.count == aligns.count || (header.count > 1 && aligns.count > 1) {
                    flush()
                    let width = max(header.count, aligns.count)
                    func pad(_ row: [String]) -> [String] {
                        row.count >= width ? Array(row.prefix(width)) : row + Array(repeating: "", count: width - row.count)
                    }
                    var rows = [pad(header)]
                    i += 2
                    while i < lines.count {
                        let t = lines[i].trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, t.contains("|") else { break }
                        rows.append(pad(tableCells(t)))
                        i += 1
                    }
                    let fullAligns = aligns.count >= width ? Array(aligns.prefix(width)) : aligns + Array(repeating: .leading, count: width - aligns.count)
                    out.append(.table(rows, fullAligns))
                    continue
                }
            }
            if quoteContent(line) != nil, !insideMath(buffer) {
                flush()
                var body: [String] = []
                while i < lines.count, let q = quoteContent(lines[i]) {
                    body.append(q)
                    i += 1
                }
                out.append(.quote(body.joined(separator: "\n")))
                continue
            }
            if listMatch(line) != nil, !insideMath(buffer) {
                flush()
                var items: [ListItem] = []
                var stack: [Int] = []
                while i < lines.count {
                    if let m = listMatch(lines[i]) {
                        while let top = stack.last, top > m.indent { stack.removeLast() }
                        if stack.last.map({ $0 < m.indent }) ?? true { stack.append(m.indent) }
                        items.append(ListItem(level: stack.count - 1, marker: m.marker, text: m.text))
                        i += 1
                        continue
                    }
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        var j = i
                        while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                        guard j < lines.count, listMatch(lines[j]) != nil else { break }
                        i = j
                        continue
                    }
                    guard leadingIndent(lines[i]) >= 2, fenceRun(t) == nil, quoteContent(lines[i]) == nil, !items.isEmpty else { break }
                    items[items.count - 1].text += "\n" + t
                    i += 1
                }
                out.append(.list(items))
                continue
            }
            buffer.append(line)
            i += 1
        }
        flush()
        return out
    }

    private static func fenceRun(_ trimmed: String) -> String? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix { $0 == first }
        guard run.count >= 3 else { return nil }
        if first == "`", trimmed.dropFirst(run.count).contains("`") { return nil }
        return String(run)
    }

    private static func tableSeparator(_ line: String) -> [TableAlign]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.contains(":") else { return nil }
        var aligns: [TableAlign] = []
        for raw in tableCells(t) {
            let cell = raw.replacingOccurrences(of: " ", with: "")
            guard !cell.isEmpty else { return nil }
            let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }
            aligns.append(left && right ? .center : right ? .trailing : .leading)
        }
        return aligns.isEmpty ? nil : aligns
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = Substring(line.trimmingCharacters(in: .whitespaces))
        if t.hasPrefix("|") { t = t.dropFirst() }
        if t.hasSuffix("|"), !t.hasSuffix("\\|") { t = t.dropLast() }
        var cells: [String] = []
        var cell = ""
        var inCode = false
        var escaped = false
        for ch in t {
            if escaped {
                if ch != "|" { cell.append("\\") }
                cell.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "`" {
                inCode.toggle()
                cell.append(ch)
            } else if ch == "|", !inCode {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(ch)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func mathBlocks(_ text: String) -> [Block] {
        guard text.containsBytes("$$") || text.containsBytes("\\[") || text.containsBytes("\\begin{") else { return [.text(text)] }
        let c = Array(text.utf8)
        var blocks: [Block] = []
        var segment = 0
        var i = 0

        func string(_ from: Int, _ to: Int) -> String {
            String(decoding: c[from..<to], as: UTF8.self)
        }

        func flush(upTo end: Int) {
            let s = string(segment, end).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { blocks.append(.text(s)) }
        }

        while i < c.count {
            if c.has("```", at: i) {
                i = c.find("```", from: i + 3).map { $0 + 3 } ?? c.count
            } else if c[i] == UInt8(ascii: "`") {
                i = c.find("`", from: i + 1).map { $0 + 1 } ?? c.count
            } else if c.has("\\(", at: i) {
                i = c.find("\\)", from: i + 2).map { $0 + 2 } ?? c.count
            } else if c.has("$$", at: i) {
                let close = c.find("$$", from: i + 2)
                flush(upTo: i)
                blocks.append(.math(string(i + 2, close ?? c.count)))
                i = close.map { $0 + 2 } ?? c.count
                segment = i
            } else if c.has("\\[", at: i) {
                let close = c.find("\\]", from: i + 2)
                flush(upTo: i)
                blocks.append(.math(string(i + 2, close ?? c.count)))
                i = close.map { $0 + 2 } ?? c.count
                segment = i
            } else if c.has("\\begin{", at: i), let nameEnd = c.find("}", from: i + 7) {
                let endTag = Array("\\end{".utf8) + c[(i + 7)..<nameEnd] + [UInt8(ascii: "}")]
                let close = c.find(endTag, from: nameEnd)
                flush(upTo: i)
                let end = close.map { $0 + endTag.count } ?? c.count
                blocks.append(.math(string(i, end)))
                i = end
                segment = i
            } else {
                i += 1
            }
        }
        flush(upTo: c.count)
        return blocks
    }
}
