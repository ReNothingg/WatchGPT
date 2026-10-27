import SwiftUI

/// Ring showing how much of the plan limit is left.
struct UsageRing: View {
    var remaining: Double?
    var lineWidth: CGFloat = 3
    var showsText = true

    var body: some View {
        let value = remaining ?? 0
        let color = remaining.map(Theme.usageColor) ?? .gray
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, value / 100))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsText {
                Text(remaining.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
            }
        }
        .animation(.easeInOut, value: value)
    }
}

/// "82% · 5ч   64% · нед" — compact summary of both windows.
struct UsageLine: View {
    let usage: UsageSnapshot?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 10) {
                if let usage, usage.primary != nil || usage.secondary != nil {
                    ForEach(Array([usage.primary, usage.secondary].compactMap { $0 }.enumerated()), id: \.offset) { _, window in
                        let left = window.remainingPercent(at: context.date)
                        HStack(spacing: 3) {
                            Circle().fill(Theme.usageColor(left)).frame(width: 6, height: 6)
                            Text(Theme.percent(left)).monospacedDigit()
                            Text(window.shortLabel).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Лимиты загружаются…").foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }
}

struct ThinkingIndicator: View {
    var label: String
    var searching = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                if searching {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    PulseOrb()
                        .frame(width: 12, height: 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 16, height: 16)
            ShimmerText(text: label)
                .id(label)
                .transition(.opacity.combined(with: .offset(y: 4)))
        }
        .animation(.snappy(duration: 0.3), value: searching)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

struct ShimmerText: View {
    var text: String
    var font: Font = .footnote
    var base: Color = Theme.secondaryText
    var period: Double = 1.6

    var body: some View {
        LiveTimeline(role: .status) { date in
            let p = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let x = -0.6 + p * 2.2
            Text(text)
                .font(font)
                .foregroundStyle(base)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.95), location: 0.5),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        startPoint: UnitPoint(x: x - 0.35, y: 0.5),
                        endPoint: UnitPoint(x: x + 0.35, y: 0.5)
                    )
                    .mask(Text(text).font(font))
                }
        }
    }
}

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

extension View {
    @ViewBuilder
    func doubleTapAction(isEnabled: Bool = true) -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction, isEnabled: isEnabled)
        } else {
            self
        }
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
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

/// The main mic button. Tap → record → OpenAI speech-to-text → question is sent.
/// With the "Apple" engine it opens the system dictation instead.
struct AskButton: View {
    @Environment(ChatStore.self) private var store
    var size: CGFloat = 44
    var halo = false

    var body: some View {
        ZStack {
            if store.isBusy {
                Button {
                    store.stop()
                    WKHaptics.click()
                } label: {
                    BusyCircle(size: size)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Остановить")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else if store.usesCloudVoice {
                Button {
                    store.startVoice()
                } label: {
                    MicCircle(size: size, halo: halo)
                }
                .buttonStyle(PressableStyle())
                .doubleTapAction(isEnabled: !store.isVoiceSheetPresented)
                .accessibilityLabel("Спросить голосом")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                TextFieldLink(prompt: Text("Спросите что угодно")) {
                    MicCircle(size: size, halo: halo)
                } onSubmit: { text in
                    store.send(text)
                }
                .buttonStyle(PressableStyle())
                .doubleTapAction(isEnabled: !store.isVoiceSheetPresented)
                .accessibilityLabel("Спросить")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: store.isBusy)
    }
}

struct MicCircle: View {
    let size: CGFloat
    let halo: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.80, blue: 0.62), Theme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Theme.accent.opacity(halo ? 0.55 : 0.3), radius: halo ? size * 0.16 : 4)
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.black)
        }
        .frame(width: size, height: size)
        .background {
            if halo { HaloRings(size: size) }
        }
        .contentShape(Circle())
    }
}

private struct HaloRings: View {
    let size: CGFloat

    var body: some View {
        LiveTimeline(role: .decorative, idleAfter: .seconds(8)) { date in
            let t = date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { k in
                    let p = (t / 2.6 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Theme.accent.opacity(0.5 * pow(1 - p, 1.6)), lineWidth: 1.5)
                        .frame(width: size, height: size)
                        .scaleEffect(1 + p * 0.42)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BusyCircle: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Color.clear.glassBackground(Circle(), fill: Theme.raised)
            LiveTimeline(role: .status) { date in
                let t = date.timeIntervalSinceReferenceDate
                Circle()
                    .trim(from: 0, to: 0.28 + 0.12 * sin(t * 2.4))
                    .stroke(
                        AngularGradient(colors: [Theme.accent.opacity(0), Theme.accent], center: .center),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.radians(t * 4))
                    .padding(1.5)
            }
            Image(systemName: "stop.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// Renders inline markdown (bold, italic, code, links) and keeps line breaks.
struct MarkdownText: View {
    let text: String
    var style: Font.TextStyle = .body
    var scale: Double = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let base = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
        if scale == 1 {
            MathRichText(text: text, fontSize: base, font: .system(style))
        } else {
            let size = (base * scale).rounded()
            MathRichText(text: text, fontSize: size, font: .system(size: size))
        }
    }

    private var uiStyle: UIFont.TextStyle {
        switch style {
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        default: return .body
        }
    }
}

private struct ScrollChromeMetrics: Equatable {
    var offset: CGFloat
    var remaining: CGFloat
}

@available(watchOS 11.0, *)
private struct ScrollChromeModifier: ViewModifier {
    @Binding var visible: Bool
    @State private var lastOffset: CGFloat?
    @State private var travel: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollChromeMetrics.self) { geo in
                ScrollChromeMetrics(
                    offset: geo.contentOffset.y,
                    remaining: geo.contentSize.height - geo.visibleRect.maxY
                )
            } action: { _, metrics in
                update(metrics)
            }
    }

    private func update(_ metrics: ScrollChromeMetrics) {
        defer { lastOffset = metrics.offset }
        if metrics.remaining < 48 {
            travel = 0
            set(true)
            return
        }
        guard let lastOffset else { return }
        let delta = metrics.offset - lastOffset
        guard abs(delta) > 0.5 else { return }
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel > 28 {
            set(false)
        } else if travel < -28 {
            set(true)
        }
    }

    private func set(_ value: Bool) {
        guard visible != value else { return }
        withAnimation(.snappy(duration: 0.25)) { visible = value }
    }
}

extension View {
    @ViewBuilder
    func autoHidesChrome(_ visible: Binding<Bool>) -> some View {
        if #available(watchOS 11.0, *) {
            modifier(ScrollChromeModifier(visible: visible))
        } else {
            self
        }
    }

    func chromeVisibility(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.6)
            .allowsHitTesting(visible)
    }
}

extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(
        _ shape: S,
        fill: Color = Theme.surface,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(watchOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(shape.fill(fill))
        }
    }
}
