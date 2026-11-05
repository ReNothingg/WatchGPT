import SwiftUI

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
