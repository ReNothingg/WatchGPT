import SwiftUI

enum VoiceMode: Equatable { case listening, paused, processing }

struct VoiceBlob: View {
    var mode: VoiceMode
    var coreRatio: CGFloat = 0.5
    var level: () -> Double
    @State private var engine = BlobEngine()

    var body: some View {
        LiveTimeline(role: .feedback) { date in
            let current = level()
            Canvas { ctx, size in
                engine.step(to: date, level: current, mode: mode)
                BlobPainter(state: engine, coreRatio: coreRatio).draw(in: &ctx, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

final class BlobEngine {
    var level = 0.0
    var listening = 1.0
    var paused = 0.0
    var processing = 0.0
    var phase = 0.0
    var spin = 0.0
    var ripple = 0.0
    var appear = 0.0
    private var lastTime: Double?

    func step(to date: Date, level target: Double, mode: VoiceMode) {
        let now = date.timeIntervalSinceReferenceDate
        let dt = lastTime.map { min(0.1, max(0, now - $0)) } ?? 0
        lastTime = now

        let clamped = pow(min(1, max(0, target)), 0.7)
        let rate = clamped > level ? 16.0 : 5.0
        level += (clamped - level) * (1 - exp(-dt * rate))

        let blend = 1 - exp(-dt * 5)
        listening += ((mode == .listening ? 1 : 0) - listening) * blend
        paused += ((mode == .paused ? 1 : 0) - paused) * blend
        processing += ((mode == .processing ? 1 : 0) - processing) * blend
        appear += (1 - appear) * (1 - exp(-dt * 4))

        let voice = level * listening
        phase += dt * (0.9 + voice * 2.8 + processing * 1.6 - paused * 0.6)
        spin += dt * (0.3 + processing * 3.4 + voice * 0.9)
        ripple += dt * (0.4 + voice * 0.9)
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
    static let mint = RGB(r: 0.16, g: 0.80, b: 0.62)
    static let accent = RGB(r: 0.063, g: 0.639, b: 0.498)
    static let teal = RGB(r: 0.10, g: 0.78, b: 0.86)
    static let blue = RGB(r: 0.25, g: 0.48, b: 1.0)
    static let violet = RGB(r: 0.55, g: 0.36, b: 1.0)
    static let gray = RGB(r: 0.36, g: 0.36, b: 0.39)
    static let grayLight = RGB(r: 0.55, g: 0.55, b: 0.58)
}

private struct BlobPainter {
    let state: BlobEngine
    let coreRatio: CGFloat

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unit = min(size.width, size.height) / 2
        let voice = state.level * state.listening
        let calm = state.paused
        let busy = state.processing
        let appear = easeOut(state.appear)

        let core = unit * coreRatio * (0.6 + 0.4 * appear) * CGFloat(1 + 0.12 * voice - 0.08 * busy - 0.05 * calm)

        drawGlow(&ctx, center: center, radius: core, strength: 0.22 + voice * 0.5 + busy * 0.18 - calm * 0.16)
        drawRipples(&ctx, center: center, radius: core, strength: state.listening * (0.08 + voice * 0.9))

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            let auras: [(RGB, Double, Double, Double)] = [
                (.teal, 1.3, 1.0, 0.42),
                (.blue, 3.7, -1.0, 0.34),
                (.violet, 5.1, 0.6, 0.22),
            ]
            for (color, seed, direction, opacity) in auras {
                let reach = core * CGFloat(1.06 + 0.10 * busy + 0.32 * voice + 0.02 * sin(state.phase + seed))
                let path = blob(
                    center: center,
                    radius: reach,
                    amp: 0.08 + 0.26 * voice + 0.05 * busy,
                    seed: seed,
                    twist: state.spin * direction
                )
                let tinted = tint(color)
                layer.fill(
                    path,
                    with: .radialGradient(
                        Gradient(colors: [tinted.color(0), tinted.color(opacity * (0.85 + 0.7 * voice + 0.3 * busy)), tinted.color(0)]),
                        center: center,
                        startRadius: core * 0.7,
                        endRadius: reach * 1.12
                    )
                )
            }
        }

        if busy > 0.01 {
            drawSpinner(&ctx, center: center, radius: core * 1.16, strength: busy)
        }

        let body = blob(center: center, radius: core, amp: 0.02 + 0.08 * voice + 0.03 * busy, seed: 0.4, twist: state.spin * 0.5)
        let top = tint(.mint)
        let bottom = tint(RGB.mix(.accent, .teal, busy * 0.35))
        ctx.fill(
            body,
            with: .linearGradient(
                Gradient(colors: [top.color(), bottom.color()]),
                startPoint: CGPoint(x: center.x - core, y: center.y - core),
                endPoint: CGPoint(x: center.x + core, y: center.y + core)
            )
        )
        ctx.drawLayer { layer in
            layer.clip(to: body)
            let sweep = state.spin * 0.8
            let shine = CGPoint(x: center.x + cos(sweep) * core * 0.45, y: center.y + sin(sweep) * core * 0.45)
            layer.fill(
                body,
                with: .radialGradient(
                    Gradient(colors: [RGB.teal.color(0.28 + 0.3 * voice), RGB.teal.color(0)]),
                    center: shine,
                    startRadius: 0,
                    endRadius: core * 0.9
                )
            )
            layer.fill(
                body,
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.22 - calm * 0.12), Color.white.opacity(0)]),
                    center: CGPoint(x: center.x - core * 0.4, y: center.y - core * 0.5),
                    startRadius: 0,
                    endRadius: core * 0.8
                )
            )
        }
    }

    private func tint(_ color: RGB) -> RGB {
        RGB.mix(color, RGB.mix(.gray, .grayLight, 0.3), state.paused * 0.8)
    }

    private func blob(center: CGPoint, radius: CGFloat, amp: Double, seed: Double, twist: Double) -> Path {
        var path = Path()
        let steps = 72
        let t = state.phase
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

    private func drawGlow(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, strength: Double) {
        let glow = radius * 2.0
        let color = tint(.green)
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [color.color(max(0, strength)), color.color(0)]),
                center: center,
                startRadius: radius * 0.6,
                endRadius: glow
            )
        )
    }

    private func drawRipples(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, strength: Double) {
        guard strength > 0.01 else { return }
        let color = tint(.teal)
        for k in 0..<3 {
            let p = (state.ripple + Double(k) / 3).truncatingRemainder(dividingBy: 1)
            let r = radius * CGFloat(1.05 + p * 0.85)
            let alpha = pow(1 - p, 2) * min(1, strength)
            ctx.stroke(
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                with: .color(color.color(alpha * 0.7)),
                lineWidth: 1 + 1.2 * (1 - p)
            )
        }
    }

    private func drawSpinner(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, strength: Double) {
        let start = state.spin
        let length = 1.6 + 0.6 * sin(state.phase * 1.3)
        var arc = Path()
        arc.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(start + length), clockwise: false)
        ctx.stroke(
            arc,
            with: .conicGradient(
                Gradient(colors: [RGB.teal.color(0), RGB.teal.color(strength), RGB.green.color(strength)]),
                center: center,
                angle: .radians(start)
            ),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
    }

    private func easeOut(_ x: Double) -> Double {
        1 - pow(1 - min(1, max(0, x)), 3)
    }
}

struct EdgeGlow: View {
    var mode: VoiceMode
    var level: () -> Double
    @State private var engine = GlowEngine()

    var body: some View {
        LiveTimeline(role: .feedback) { date in
            let current = level()
            Canvas { ctx, size in
                engine.step(to: date, level: current, mode: mode)
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

    func step(to date: Date, level: Double, mode: VoiceMode) {
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
