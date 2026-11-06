import SwiftUI

struct MathRichText: View {
    let text: String
    let fontSize: CGFloat
    let font: Font
    var live = false

    var body: some View {
        let blocks = live ? Self.parse(text) : Self.cachedBlocks(text)
        if blocks.count == 1, case let .text(t) = blocks[0] {
            InlineMathText(text: t, fontSize: fontSize, font: font, cached: !live)
        } else {
            VStack(alignment: .leading, spacing: (fontSize * 0.4).rounded()) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case let .text(t):
                        InlineMathText(text: t, fontSize: fontSize, font: font, cached: !live || index < blocks.count - 1)
                            .equatable()
                    case let .math(latex):
                        DisplayMathBlock(latex: latex, fontSize: fontSize)
                            .equatable()
                    case let .code(lang, code):
                        CodeBlockView(language: lang, code: code, fontSize: fontSize)
                    case let .table(rows, aligns):
                        TableBlockView(rows: rows, aligns: aligns, fontSize: fontSize)
                    case let .list(items):
                        ListBlockView(items: items, fontSize: fontSize, font: font, cached: !live || index < blocks.count - 1)
                    case let .quote(inner):
                        QuoteBlockView(text: inner, fontSize: fontSize, font: font, live: live && index == blocks.count - 1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
    }

    private final class BlocksBox {
        let value: [MathFormat.Block]
        init(_ value: [MathFormat.Block]) { self.value = value }
    }

    private static let blocksCache: NSCache<NSString, BlocksBox> = {
        let cache = NSCache<NSString, BlocksBox>()
        cache.countLimit = 80
        return cache
    }()

    private static func parse(_ text: String) -> [MathFormat.Block] {
        MathFormat.blocks(text).flatMap(paragraphs)
    }

    private static func cachedBlocks(_ text: String) -> [MathFormat.Block] {
        let key = text as NSString
        if let hit = blocksCache.object(forKey: key) { return hit.value }
        let value = parse(text)
        blocksCache.setObject(BlocksBox(value), forKey: key)
        return value
    }

    private static func paragraphs(_ block: MathFormat.Block) -> [MathFormat.Block] {
        guard case let .text(t) = block, t.containsAnyByte("\n"), !t.containsBytes("```") else { return [block] }
        let bytes = t.utf8
        var parts: [MathFormat.Block] = []
        var start = bytes.startIndex
        var i = bytes.startIndex
        func add(upTo end: String.Index) {
            let part = t[start..<end].trimmingCharacters(in: .newlines)
            if !part.isEmpty { parts.append(.text(part)) }
        }
        while i < bytes.endIndex {
            if bytes[i] == 10, let end = blankRunEnd(bytes, after: bytes.index(after: i)) {
                add(upTo: i)
                start = end
                i = end
            } else {
                i = bytes.index(after: i)
            }
        }
        add(upTo: bytes.endIndex)
        return parts.isEmpty ? [block] : parts
    }

    private static func blankRunEnd(_ bytes: String.UTF8View, after: String.Index) -> String.Index? {
        var end: String.Index?
        var j = after
        while true {
            var k = j
            while k < bytes.endIndex, bytes[k] == 32 || bytes[k] == 9 { k = bytes.index(after: k) }
            guard k < bytes.endIndex, bytes[k] == 10 else { return end }
            j = bytes.index(after: k)
            end = j
        }
    }
}

private struct InlineMathText: View, Equatable {
    let text: String
    let fontSize: CGFloat
    let font: Font
    var cached = true

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.fontSize == rhs.fontSize && lhs.font == rhs.font
    }

    var body: some View {
        Text(MathFormat.inline(text, size: fontSize, cached: cached))
            .font(font)
    }
}

private struct DisplayMathBlock: View, Equatable {
    let latex: String
    let fontSize: CGFloat

    var body: some View {
        DisplayMath(latex: latex, fontSize: fontSize)
    }
}
