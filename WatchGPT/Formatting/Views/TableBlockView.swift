import SwiftUI

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
        .contentShape(Rectangle())
        .pressPop(longPress)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ForEach(bodyRows, id: \.self) { r in
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
