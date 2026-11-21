import SwiftUI

enum VoiceMode: Equatable {
    case listening, paused, processing
}

struct VoiceOrb: View {
    let mode: VoiceMode
    let level: () -> Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var motion = VoiceOrbMotion()

    var body: some View {
        Group {
            if reduceMotion || isLuminanceReduced {
                dial(frame: .init())
            } else if mode == .paused {
                dial(frame: motion.frame)
            } else {
                LiveTimeline(role: .feedback, fps: 20) { date in
                    dial(frame: motion.update(at: date, level: mode == .listening ? level() : 0))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func dial(frame: VoiceOrbMotion.Frame) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            VoiceDial(mode: mode, frame: frame).draw(in: context, size: size)
        }
    }
}

private final class VoiceOrbMotion {
    struct Frame {
        var samples = Array(repeating: 0.0, count: 24)
        var time = 0.0
    }

    private(set) var frame = Frame()
    private var lastDate: Date?

    func update(at date: Date, level: Double) -> Frame {
        let elapsed = lastDate.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        lastDate = date
        guard elapsed > 0 else { return frame }
        let target = pow(max(0, min(1, (level - 0.08) / 0.68)), 0.75)
        let previous = frame.samples[0]
        let rate = target > previous ? 22.0 : 11.0
        let value = previous + (target - previous) * (1 - exp(-elapsed * rate))
        frame.samples.removeLast()
        frame.samples.insert(value, at: 0)
        frame.time += elapsed
        return frame
    }
}

private struct VoiceDial {
    let mode: VoiceMode
    let frame: VoiceOrbMotion.Frame

    func draw(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.39
        guard radius > 0 else { return }

        let halo = radius * 1.3
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: 2 * halo, height: 2 * halo)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(mode == .paused ? 0.045 : 0.10), .clear]),
                center: center, startRadius: radius * 0.37, endRadius: halo
            )
        )

        let half = frame.samples.count - 1
        for index in -half...half {
            let angle = Double(index) * (.pi / Double(half + 1)) - .pi / 2
            let distance = Double(abs(index)) / Double(half)
            let sample = frame.samples[abs(index)] * (1 - distance * 0.68)
            let sweep = pow(max(0, cos(angle - frame.time * 3.6)), 13)
            let response = mode == .processing ? sweep : sample
            let accent = index.isMultiple(of: 6)
            let length = (accent ? 4.0 : 2.6) + (mode == .processing ? 4 : 17) * response
            let opacity = mode == .paused ? 0.22 + sample * 0.19 : 0.26 + response * 0.70
            let x = cos(angle)
            let y = sin(angle)
            let inner = radius - length * 0.26
            let outer = radius + length * 0.74

            var mark = Path()
            mark.move(to: CGPoint(x: center.x + x * inner, y: center.y + y * inner))
            mark.addLine(to: CGPoint(x: center.x + x * outer, y: center.y + y * outer))
            context.stroke(
                mark, with: .color(.white.opacity(opacity)),
                style: StrokeStyle(lineWidth: 1.1 + response * 0.65, lineCap: .round)
            )
        }
    }
}
