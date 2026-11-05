import SwiftUI

enum MathDraw {
    static let axis: CGFloat = 0.26

    static func line(_ fs: CGFloat) -> CGFloat { max(0.9, fs * 0.055) }

    static func scriptSize(_ fs: CGFloat) -> CGFloat { max(8, fs * 0.72) }

    static func serif(_ fs: CGFloat) -> Font { .system(size: fs, design: .serif) }

    static func view(_ node: MathNode, fs: CGFloat, display: Bool, script: Bool = false, leadingOrd: Bool = false) -> AnyView {
        switch node {
        case let .row(items):
            if items.isEmpty { return AnyView(Text(" ").font(serif(fs))) }
            let spaces = MathFormat.spacing(items, leadingOrd: leadingOrd, script: script)
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    ForEach(items.indices, id: \.self) { k in
                        view(items[k], fs: fs, display: display, script: script)
                            .padding(.leading, spaces[k] * fs)
                    }
                }
            )

        case let .atom(s, kind):
            switch kind {
            case .ident:
                return AnyView(Text(s).font(serif(fs).italic()))
            case .largeOp:
                let integral = MathParser.integralChars.contains(s.first ?? " ")
                let size = display ? fs * (integral ? 1.75 : 1.5) : fs * 1.15
                return AnyView(
                    Text(s)
                        .font(serif(size))
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + fs * axis }
                )
            default:
                return AnyView(Text(s).font(serif(fs)))
            }

        case let .text(s, bold):
            return AnyView(Text(s).font(.system(size: fs, weight: bold ? .bold : .regular)))

        case let .frac(num, den, bar):
            let inner = display ? fs * 0.9 : max(8, fs * 0.8)
            let thickness = bar ? line(fs) : 0
            return AnyView(
                FractionLayout(gap: fs * 0.1, thickness: thickness, axis: fs * axis, pad: fs * 0.16) {
                    view(num, fs: inner, display: false, script: script)
                    Rectangle().opacity(bar ? 1 : 0)
                    view(den, fs: inner, display: false, script: script)
                }
            )

        case let .sqrt(inner, index):
            let lw = line(fs)
            let width = fs * 0.55
            let body = view(inner, fs: fs, display: display, script: script)
                .padding(.top, fs * 0.14 + lw)
                .padding(.leading, width + fs * 0.06)
                .padding(.trailing, fs * 0.06)
                .overlay(
                    RadicalShape(radicalWidth: width, lineWidth: lw)
                        .stroke(style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                )
            guard let index else { return AnyView(body) }
            return AnyView(
                RadicalIndexLayout(fs: fs) {
                    view(index, fs: max(7, fs * 0.55), display: false, script: true)
                    body
                }
            )

        case let .scripts(base, sup, sub):
            let small = scriptSize(fs)
            return AnyView(
                ScriptLayout(hasSup: sup != nil, hasSub: sub != nil, fs: fs) {
                    view(base, fs: fs, display: display, script: script)
                    if let sup { view(sup, fs: small, display: false, script: true) }
                    if let sub { view(sub, fs: small, display: false, script: true) }
                }
            )

        case let .limits(base, over, under):
            guard display else { return view(.scripts(base, sup: over, sub: under), fs: fs, display: false, script: script) }
            let small = scriptSize(fs)
            return AnyView(
                UnderOverLayout(hasOver: over != nil, hasUnder: under != nil, gap: -fs * 0.06) {
                    view(base, fs: fs, display: display, script: script)
                    if let over { view(over, fs: small, display: false, script: true) }
                    if let under { view(under, fs: small, display: false, script: true) }
                }
            )

        case let .fenced(l, inner, r):
            let content = view(inner, fs: fs, display: display, script: script)
            if MathFormat.height(inner) <= 1.45 {
                return AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: fs * 0.04) {
                        if !l.isEmpty { Text(l).font(serif(fs)) }
                        content
                        if !r.isEmpty { Text(r).font(serif(fs)) }
                    }
                )
            }
            return AnyView(stretched(content, l: l, r: r, fs: fs))

        case let .accent(base, accent):
            let content = view(base, fs: fs, display: display, script: script)
            let lw = line(fs)
            switch accent {
            case .overline:
                return AnyView(
                    content
                        .padding(.top, fs * 0.12 + lw)
                        .overlay(alignment: .top) { Rectangle().frame(height: lw) }
                )
            case .underline:
                return AnyView(
                    content
                        .padding(.bottom, fs * 0.08 + lw)
                        .overlay(alignment: .bottom) { Rectangle().frame(height: lw) }
                )
            default:
                let (glyph, size, raise) = accentGlyph(accent, fs: fs)
                return AnyView(
                    AccentLayout(raise: raise, skew: fs * 0.06) {
                        content
                        Text(glyph).font(serif(size))
                    }
                )
            }

        case let .table(rows, kind):
            let cellSize = display ? fs * 0.95 : fs * 0.85
            let columns = rows.map(\.count).max() ?? 0
            let spacing: CGFloat
            switch kind {
            case .aligned: spacing = 0
            case .cases: spacing = fs * 0.9
            case .matrix: spacing = fs * 0.8
            }
            let grid = Grid(alignment: .center, horizontalSpacing: spacing, verticalSpacing: fs * 0.3) {
                ForEach(rows.indices, id: \.self) { r in
                    GridRow(alignment: .firstTextBaseline) {
                        ForEach(0..<columns, id: \.self) { k in
                            let cell = k < rows[r].count ? rows[r][k] : MathNode.empty
                            view(cell, fs: cellSize, display: display, script: script, leadingOrd: kind == .aligned && k % 2 == 1)
                                .padding(.leading, kind == .aligned && k > 0 && k % 2 == 0 ? fs : 0)
                                .gridColumnAlignment(columnAlignment(kind, column: k, columns: columns))
                        }
                    }
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + fs * axis }

            switch kind {
            case let .matrix(l, r):
                return AnyView(stretched(AnyView(grid), l: l, r: r, fs: fs))
            case .cases:
                return AnyView(stretched(AnyView(grid), l: "{", r: "", fs: fs))
            case .aligned:
                return AnyView(grid)
            }

        case let .space(em):
            return AnyView(Color.clear.frame(width: max(0, em * fs), height: 0))
        }
    }

    private static func columnAlignment(_ kind: MathTable, column: Int, columns: Int) -> HorizontalAlignment {
        switch kind {
        case .aligned:
            if columns == 1 { return .center }
            return column % 2 == 0 ? .trailing : .leading
        case .cases: return .leading
        case .matrix: return .center
        }
    }

    private static func accentGlyph(_ accent: MathAccent, fs: CGFloat) -> (String, CGFloat, CGFloat) {
        switch accent {
        case .vec: return ("→", fs * 0.7, fs * 0.66)
        case .hat: return ("ˆ", fs, fs * 0.3)
        case .bar: return ("¯", fs, fs * 0.28)
        case .dot: return ("˙", fs, fs * 0.3)
        case .ddot: return ("¨", fs, fs * 0.3)
        case .tilde: return ("˜", fs, fs * 0.3)
        case .overline, .underline: return ("", fs, 0)
        }
    }

    private static func stretched(_ content: AnyView, l: String, r: String, fs: CGFloat) -> some View {
        let lw = line(fs)
        let width = fs * 0.34
        return content
            .padding(.vertical, fs * 0.06)
            .padding(.leading, l.isEmpty ? 0 : width + fs * 0.1)
            .padding(.trailing, r.isEmpty ? 0 : width + fs * 0.1)
            .overlay {
                HStack(spacing: 0) {
                    DelimiterShape(symbol: l, left: true)
                        .stroke(style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round))
                        .frame(width: width)
                    Spacer(minLength: 0)
                    DelimiterShape(symbol: r, left: false)
                        .stroke(style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round))
                        .frame(width: width)
                }
            }
    }
}
