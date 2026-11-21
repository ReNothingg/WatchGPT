import SwiftUI

struct PulseOrb: View {
    var color: Color = Theme.accent

    var body: some View {
        LiveTimeline(role: .status) { date in
            let t = date.timeIntervalSinceReferenceDate
            let beat = 0.5 + 0.5 * sin(t * 4.2)
            ZStack {
                Circle()
                    .fill(color.opacity(0.35 * (1 - beat)))
                    .scaleEffect(1.2 + 0.6 * beat)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.9), color, color.opacity(0.8)],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .scaleEffect(0.78 + 0.22 * beat)
            }
        }
        .accessibilityHidden(true)
    }
}

struct StreamingDot: View {
    var body: some View {
        PulseOrb()
            .frame(width: 8, height: 8)
            .padding(.leading, 2)
    }
}

struct Spinner: View {
    var size: CGFloat = 48
    var lineWidth: CGFloat = 4
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.raised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
        }
        .accessibilityHidden(true)
    }
}
