import SwiftUI

struct RadicalShape: Shape {
    var radicalWidth: CGFloat
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = rect.minY + lineWidth / 2
        let w = radicalWidth
        p.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + rect.height * 0.62))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.26, y: rect.minY + rect.height * 0.54))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.52, y: rect.maxY - lineWidth / 2))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: top))
        return p
    }
}

struct DelimiterShape: Shape {
    var symbol: String
    var left: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = rect.height
        let inset = rect.width * 0.2
        let near = left ? rect.maxX - inset : rect.minX + inset
        let far = left ? rect.minX + inset : rect.maxX - inset
        let mid = rect.midX
        switch symbol {
        case "(", ")":
            p.move(to: CGPoint(x: near, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: near, y: rect.maxY), control: CGPoint(x: far - (near - far) * 0.55, y: rect.midY))
        case "[", "]", "⌊", "⌋", "⌈", "⌉":
            let topBar = symbol != "⌊" && symbol != "⌋"
            let bottomBar = symbol != "⌈" && symbol != "⌉"
            p.move(to: CGPoint(x: topBar ? near : far, y: rect.minY))
            p.addLine(to: CGPoint(x: far, y: rect.minY))
            p.addLine(to: CGPoint(x: far, y: rect.maxY))
            if bottomBar { p.addLine(to: CGPoint(x: near, y: rect.maxY)) }
        case "{", "}":
            let tip = left ? rect.minX + inset * 0.3 : rect.maxX - inset * 0.3
            p.move(to: CGPoint(x: near, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: mid, y: rect.minY + h * 0.12), control: CGPoint(x: mid, y: rect.minY))
            p.addLine(to: CGPoint(x: mid, y: rect.midY - h * 0.08))
            p.addQuadCurve(to: CGPoint(x: tip, y: rect.midY), control: CGPoint(x: mid, y: rect.midY))
            p.addQuadCurve(to: CGPoint(x: mid, y: rect.midY + h * 0.08), control: CGPoint(x: mid, y: rect.midY))
            p.addLine(to: CGPoint(x: mid, y: rect.maxY - h * 0.12))
            p.addQuadCurve(to: CGPoint(x: near, y: rect.maxY), control: CGPoint(x: mid, y: rect.maxY))
        case "|":
            p.move(to: CGPoint(x: mid, y: rect.minY))
            p.addLine(to: CGPoint(x: mid, y: rect.maxY))
        case "‖":
            for x in [mid - rect.width * 0.15, mid + rect.width * 0.15] {
                p.move(to: CGPoint(x: x, y: rect.minY))
                p.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        case "⟨", "⟩":
            p.move(to: CGPoint(x: near, y: rect.minY))
            p.addLine(to: CGPoint(x: far, y: rect.midY))
            p.addLine(to: CGPoint(x: near, y: rect.maxY))
        default:
            break
        }
        return p
    }
}

struct FractionLayout: Layout {
    var gap: CGFloat
    var thickness: CGFloat
    var axis: CGFloat
    var pad: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let n = subviews[0].sizeThatFits(.unspecified)
        let d = subviews[2].sizeThatFits(.unspecified)
        return CGSize(width: max(n.width, d.width) + pad * 2, height: n.height + d.height + gap * 2 + thickness)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = subviews[0].sizeThatFits(.unspecified)
        let d = subviews[2].sizeThatFits(.unspecified)
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(n))
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + n.height + gap),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: thickness)
        )
        subviews[2].place(at: CGPoint(x: bounds.midX, y: bounds.minY + n.height + gap * 2 + thickness), anchor: .top, proposal: ProposedViewSize(d))
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let n = subviews[0].sizeThatFits(.unspecified)
        return bounds.minY + n.height + gap + thickness / 2 + axis
    }
}

struct PlacedFrames {
    var frames: [CGRect]
    var size: CGSize
    var baseline: CGFloat

    init(_ raw: [CGRect], baseline: CGFloat) {
        let minY = raw.map(\.minY).min() ?? 0
        let minX = raw.map(\.minX).min() ?? 0
        frames = raw.map { $0.offsetBy(dx: -minX, dy: -minY) }
        size = CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
        self.baseline = baseline - minY
    }
}

protocol FramedLayout: Layout where Cache == () {
    func frames(_ subviews: Subviews) -> PlacedFrames
}

extension FramedLayout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = frames(subviews)
        for (k, frame) in placed.frames.enumerated() where k < subviews.count {
            subviews[k].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        return bounds.minY + frames(subviews).baseline
    }
}

struct ScriptLayout: FramedLayout {
    var hasSup: Bool
    var hasSub: Bool
    var fs: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let b = subviews[0].dimensions(in: .unspecified)
        let baseBaseline = b[VerticalAlignment.firstTextBaseline]
        var raw = [CGRect(x: 0, y: 0, width: b.width, height: b.height)]
        let x = b.width + fs * 0.05
        var k = 1
        if hasSup, k < subviews.count {
            let s = subviews[k].dimensions(in: .unspecified)
            let sBase = s[VerticalAlignment.firstTextBaseline]
            let y = min(baseBaseline - fs * 0.42, sBase * 0.72) - sBase
            raw.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            k += 1
        }
        if hasSub, k < subviews.count {
            let s = subviews[k].dimensions(in: .unspecified)
            let sBase = s[VerticalAlignment.firstTextBaseline]
            let y = max(baseBaseline + fs * 0.2, b.height - s.height * 0.3) - sBase
            raw.append(CGRect(x: x - (hasSup ? 0 : fs * 0.02), y: y, width: s.width, height: s.height))
        }
        return PlacedFrames(raw, baseline: baseBaseline)
    }
}

struct UnderOverLayout: FramedLayout {
    var hasOver: Bool
    var hasUnder: Bool
    var gap: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let b = subviews[0].dimensions(in: .unspecified)
        var k = 1
        let over = hasOver && k < subviews.count ? subviews[k].dimensions(in: .unspecified) : nil
        if hasOver { k += 1 }
        let under = hasUnder && k < subviews.count ? subviews[k].dimensions(in: .unspecified) : nil
        let width = max(b.width, over?.width ?? 0, under?.width ?? 0)
        let baseY = over.map { $0.height + gap } ?? 0
        var raw = [CGRect(x: (width - b.width) / 2, y: baseY, width: b.width, height: b.height)]
        if let over { raw.append(CGRect(x: (width - over.width) / 2, y: 0, width: over.width, height: over.height)) }
        if let under { raw.append(CGRect(x: (width - under.width) / 2, y: baseY + b.height + gap, width: under.width, height: under.height)) }
        return PlacedFrames(raw, baseline: baseY + b[VerticalAlignment.firstTextBaseline])
    }
}

struct AccentLayout: FramedLayout {
    var raise: CGFloat
    var skew: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let b = subviews[0].dimensions(in: .unspecified)
        let a = subviews[1].dimensions(in: .unspecified)
        let baseBaseline = b[VerticalAlignment.firstTextBaseline]
        let accentTop = baseBaseline - raise - a[VerticalAlignment.firstTextBaseline]
        return PlacedFrames([
            CGRect(x: 0, y: 0, width: b.width, height: b.height),
            CGRect(x: (b.width - a.width) / 2 + skew, y: accentTop, width: a.width, height: a.height),
        ], baseline: baseBaseline)
    }
}

struct RadicalIndexLayout: FramedLayout {
    var fs: CGFloat

    func frames(_ subviews: Subviews) -> PlacedFrames {
        let index = subviews[0].dimensions(in: .unspecified)
        let body = subviews[1].dimensions(in: .unspecified)
        let bodyX = max(0, index.width - fs * 0.3)
        let indexX = bodyX + fs * 0.3 - index.width
        let indexY = body.height * 0.5 - index.height
        return PlacedFrames([
            CGRect(x: indexX, y: indexY, width: index.width, height: index.height),
            CGRect(x: bodyX, y: 0, width: body.width, height: body.height),
        ], baseline: body[VerticalAlignment.firstTextBaseline])
    }
}
