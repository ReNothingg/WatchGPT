import SwiftUI

struct VoiceOrb: View {
    enum Mode: Equatable { case listening, paused, processing }

    var mode: Mode
    var level: Double
    @State private var engine = OrbEngine()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, size in
                engine.step(to: context.date, level: level, mode: mode)
                OrbPainter(state: engine).draw(in: &ctx, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

final class OrbEngine {
    var level = 0.0
    var listening = 1.0
    var paused = 0.0
    var processing = 0.0
    var phase = 0.0
    var spin = 0.0
    var ripple = 0.0
    var appear = 0.0
    private var lastTime: Double?

    func step(to date: Date, level target: Double, mode: VoiceOrb.Mode) {
        let now = date.timeIntervalSinceReferenceDate
        let dt = lastTime.map { min(0.1, max(0, now - $0)) } ?? 0
        lastTime = now

        let clamped = min(1, max(0, target))
        let rate = clamped > level ? 16.0 : 5.0
        level += (clamped - level) * (1 - exp(-dt * rate))

        let blend = 1 - exp(-dt * 5)
        listening += ((mode == .listening ? 1 : 0) - listening) * blend
        paused += ((mode == .paused ? 1 : 0) - paused) * blend
        processing += ((mode == .processing ? 1 : 0) - processing) * blend
        appear += (1 - appear) * (1 - exp(-dt * 4))

        let voice = level * listening
        phase += dt * (0.9 + voice * 2.6 + processing * 1.4 - paused * 0.6)
        spin += dt * (0.35 + processing * 3.2 + voice * 0.8)
        ripple += dt * (0.45 + voice * 0.9)
    }
}

private struct RGB {
    var r: Double, g: Double, b: Double

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    func color(_ opacity: Double = 1) -> Color {
        Color(red: r, green: g, blue: b).opacity(opacity)
    }

    static let green = RGB(r: 0.063, g: 0.80, b: 0.55)
    static let teal = RGB(r: 0.10, g: 0.78, b: 0.86)
    static let blue = RGB(r: 0.25, g: 0.48, b: 1.0)
    static let violet = RGB(r: 0.55, g: 0.36, b: 1.0)
    static let gray = RGB(r: 0.36, g: 0.36, b: 0.39)
    static let grayLight = RGB(r: 0.55, g: 0.55, b: 0.58)
}

private struct OrbPainter {
    let state: OrbEngine

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = min(size.width, size.height) / 2
        let voice = state.level * state.listening
        let calm = state.paused
        let busy = state.processing

        let scale = (0.62 + 0.38 * easeOut(state.appear))
            * (state.listening * (0.80 + 0.22 * state.level)
               + calm * (0.70 + 0.03 * sin(state.phase * 2.2))
               + busy * (0.74 + 0.03 * sin(state.phase * 3)))
            / max(0.001, state.listening + calm + busy)
        let radius = unit * 0.66 * scale

        let primary = tint(RGB.mix(.green, .teal, busy * 0.5))
        let secondary = tint(RGB.mix(.teal, .blue, busy * 0.6))
        let tertiary = tint(RGB.mix(.blue, .violet, busy))

        drawGlow(&ctx, center: center, radius: radius, color: primary, strength: 0.32 + voice * 0.45 + busy * 0.15 - calm * 0.2)
        drawRipples(&ctx, center: center, radius: radius, color: primary, strength: state.listening * (0.18 + voice * 0.9))
        drawOrbit(&ctx, center: center, radius: radius, unit: unit, strength: busy)

        let amp = 0.035 + voice * 0.20 + busy * 0.05 + calm * 0.01
        let wobble = radius * (0.04 + voice * 0.10)
        let layers: [(RGB, RGB, Double, Double)] = [
            (primary, secondary, 0.0, 1.0),
            (secondary, tertiary, 2.1, 0.86),
            (tertiary, primary, 4.2, 0.74),
        ]

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for (inner, outer, seed, size) in layers {
                let drift = CGPoint(
                    x: center.x + cos(state.phase * 0.9 + seed) * wobble,
                    y: center.y + sin(state.phase * 1.1 + seed * 1.3) * wobble
                )
                let path = blob(center: drift, radius: radius * size, amp: amp, seed: seed)
                layer.fill(
                    path,
                    with: .radialGradient(
                        Gradient(colors: [inner.color(0.95), outer.color(0.55), outer.color(0.05)]),
                        center: CGPoint(x: drift.x - radius * 0.25, y: drift.y - radius * 0.3),
                        startRadius: 0,
                        endRadius: radius * size * 1.35
                    )
                )
            }
        }

        let highlight = CGRect(
            x: center.x - radius * 0.62,
            y: center.y - radius * 0.70,
            width: radius * 0.9,
            height: radius * 0.75
        )
        ctx.fill(
            Path(ellipseIn: highlight),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.42 - calm * 0.2), .white.opacity(0)]),
                center: CGPoint(x: highlight.midX, y: highlight.midY),
                startRadius: 0,
                endRadius: radius * 0.45
            )
        )
    }

    private func tint(_ color: RGB) -> RGB {
        RGB.mix(color, RGB.mix(.gray, .grayLight, 0.3), state.paused * 0.85)
    }

    private func blob(center: CGPoint, radius: CGFloat, amp: Double, seed: Double) -> Path {
        var path = Path()
        let steps = 72
        let t = state.phase
        let twist = state.spin * 0.6
        for i in 0...steps {
            let theta = Double(i) / Double(steps) * 2 * .pi
            let a = theta + twist
            let d = sin(3 * a + t * 1.7 + seed) * 0.50
                + sin(5 * a - t * 2.3 + seed * 1.7) * 0.28
                + sin(2 * a + t * 1.1 + seed * 2.3) * 0.36
            let r = radius * CGFloat(1 + amp * d)
            let point = CGPoint(x: center.x + r * CGFloat(cos(theta)), y: center.y + r * CGFloat(sin(theta)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawGlow(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: RGB, strength: Double) {
        let glow = radius * 2.1
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [color.color(max(0, strength)), color.color(0)]),
                center: center,
                startRadius: radius * 0.5,
                endRadius: glow
            )
        )
    }

    private func drawRipples(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: RGB, strength: Double) {
        guard strength > 0.01 else { return }
        for k in 0..<3 {
            let p = (state.ripple + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let r = radius * CGFloat(1.02 + p * 0.95)
            let alpha = pow(1 - p, 2) * min(1, strength)
            ctx.stroke(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(color.color(alpha * 0.8)),
                lineWidth: 1.2 + 1.3 * (1 - p)
            )
        }
    }

    private func drawOrbit(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, unit: CGFloat, strength: Double) {
        guard strength > 0.01 else { return }
        let r = min(unit * 0.92, radius * 1.45)
        let start = state.spin
        var arc = Path()
        arc.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(start + 2.2), clockwise: false)
        ctx.stroke(
            arc,
            with: .conicGradient(
                Gradient(colors: [RGB.teal.color(0), RGB.teal.color(strength), RGB.green.color(strength)]),
                center: center,
                angle: .radians(start)
            ),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )
        for k in 0..<3 {
            let angle = -state.spin * 0.7 + Double(k) * 2 * .pi / 3
            let orbit = r * 0.82
            let dot = CGPoint(x: center.x + orbit * CGFloat(cos(angle)), y: center.y + orbit * CGFloat(sin(angle)))
            let size: CGFloat = 3.2
            ctx.fill(
                Path(ellipseIn: CGRect(x: dot.x - size / 2, y: dot.y - size / 2, width: size, height: size)),
                with: .color(RGB.blue.color(strength * 0.9))
            )
        }
    }

    private func easeOut(_ x: Double) -> Double {
        1 - pow(1 - min(1, max(0, x)), 3)
    }
}

struct EdgeGlow: View {
    var mode: VoiceOrb.Mode
    var level: Double
    @State private var engine = GlowEngine()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, size in
                engine.step(to: context.date, level: level, mode: mode)
                GlowPainter(state: engine).draw(in: &ctx, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

final class GlowEngine {
    var energy = 0.0
    var appear = 0.0
    var angleA = 0.0
    var angleB = 0.0
    var processing = 0.0
    private var lastTime: Double?

    func step(to date: Date, level: Double, mode: VoiceOrb.Mode) {
        let now = date.timeIntervalSinceReferenceDate
        let dt = lastTime.map { min(0.1, max(0, now - $0)) } ?? 0
        lastTime = now

        let target: Double
        switch mode {
        case .listening: target = 0.18 + 0.82 * min(1, max(0, level))
        case .paused: target = 0.04
        case .processing: target = 0.42 + 0.14 * sin(now * 3.2)
        }
        let rate = target > energy ? 12.0 : 4.0
        energy += (target - energy) * (1 - exp(-dt * rate))
        processing += ((mode == .processing ? 1 : 0) - processing) * (1 - exp(-dt * 4))
        appear += (1 - appear) * (1 - exp(-dt * 3))
        angleA += dt * (0.7 + energy * 1.8 + processing * 2.4)
        angleB -= dt * (0.45 + energy * 1.1 + processing * 1.2)
    }
}

private struct GlowPainter {
    let state: GlowEngine

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let corner = min(size.width, size.height) * 0.24
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let e = state.energy * state.appear

        let colorsA = Gradient(colors: [
            RGB.green.color(1), RGB.teal.color(0.25), RGB.blue.color(1),
            RGB.violet.color(0.35), RGB.teal.color(1), RGB.green.color(0.3), RGB.green.color(1),
        ])
        let colorsB = Gradient(colors: [
            RGB.blue.color(0.2), RGB.green.color(1), RGB.violet.color(0.2),
            RGB.teal.color(1), RGB.blue.color(0.2),
        ])

        let outer = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: corner, style: .continuous)

        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 9 + 9 * e))
            layer.opacity = 0.25 + 0.75 * e
            layer.blendMode = .plusLighter
            layer.stroke(outer, with: .conicGradient(colorsA, center: center, angle: .radians(state.angleA)), lineWidth: 8 + 22 * e)
            layer.stroke(outer, with: .conicGradient(colorsB, center: center, angle: .radians(state.angleB)), lineWidth: 6 + 16 * e)
        }

        ctx.drawLayer { layer in
            layer.opacity = 0.35 + 0.65 * e
            layer.blendMode = .plusLighter
            layer.stroke(outer, with: .conicGradient(colorsA, center: center, angle: .radians(state.angleA)), lineWidth: 1.5 + 2.5 * e)
        }
    }
}
