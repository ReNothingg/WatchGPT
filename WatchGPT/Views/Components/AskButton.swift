import SwiftUI

struct AskButton: View {
    @Environment(ChatStore.self) private var store
    var size: CGFloat = 44
    var halo = false
    var showsUsage = false
    var showsUsageBadge = false
    @State private var longPressAt: Date?

    private var ringWidth: CGFloat { max(2.5, (size * 0.05).rounded()) }
    private var ringGap: CGFloat { max(2.5, (size * 0.045).rounded()) }
    private var core: CGFloat { showsUsage ? size - 2 * (ringWidth + ringGap) : size }
    private var haloActive: Bool { halo && !store.isBusy && store.voicePhase == .idle }

    var body: some View {
        ZStack {
            if store.isBusy {
                Button {
                    store.stop()
                    WKHaptics.click()
                } label: {
                    fitted(BusyCircle(size: core))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Остановить")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else if store.usesCloudVoice {
                Button {
                    if let longPressAt, Date.now.timeIntervalSince(longPressAt) < 2 {
                        self.longPressAt = nil
                        return
                    }
                    store.startVoice()
                } label: {
                    fitted(MicCircle(size: core, halo: !showsUsage && haloActive))
                }
                .buttonStyle(PressableStyle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        longPressAt = .now
                        store.typeQuestion()
                    }
                )
                .doubleTapAction(isEnabled: store.voicePhase == .idle)
                .accessibilityLabel("Спросить голосом")
                .accessibilityHint("Удерживайте, чтобы ввести текст")
                .accessibilityAction(named: "Ввести текст") { store.typeQuestion() }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                TextFieldLink(prompt: Text("Спросите что угодно")) {
                    fitted(MicCircle(size: core, halo: !showsUsage && haloActive))
                } onSubmit: { text in
                    store.send(text)
                }
                .buttonStyle(PressableStyle())
                .doubleTapAction(isEnabled: store.voicePhase == .idle)
                .accessibilityLabel("Спросить")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .background {
            if showsUsage, haloActive {
                HaloRings(size: size)
                    .transition(.opacity)
            }
        }
        .overlay {
            if showsUsage {
                UsageArc(lineWidth: ringWidth)
            }
        }
        .overlay(alignment: .bottom) {
            if showsUsage, showsUsageBadge {
                UsageBadge()
                    .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
            }
        }
        .modifier(UsageAccessibility(isEnabled: showsUsage))
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: store.isBusy)
        .animation(.smooth(duration: 0.3), value: haloActive)
    }

    private func fitted(_ content: some View) -> some View {
        content
            .frame(width: size, height: size)
            .contentShape(Circle())
    }
}

private struct UsageAccessibility: ViewModifier {
    @Environment(ChatStore.self) private var store
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .accessibilityValue(UsageArc.label(store.usage))
                .accessibilityAction(named: "Лимиты") { store.path.append(.usage) }
        } else {
            content
        }
    }
}

struct UsageArc: View {
    @Environment(ChatStore.self) private var store
    let lineWidth: CGFloat
    @State private var filled = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let left = store.usage?.tightest(at: context.date)?.remainingPercent(at: context.date)
            let color = left.map(Theme.usageColor) ?? Theme.track
            let ring = Circle().inset(by: lineWidth / 2)
            ZStack {
                ring.stroke(Theme.track.opacity(0.55), lineWidth: lineWidth)
                if let left {
                    ring
                        .trim(from: 0, to: filled ? max(0.004, left / 100) : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(left < 20 ? 0.6 : 0.3), radius: lineWidth * 1.2)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.9, dampingFraction: 0.85), value: left)
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.82).delay(0.2)) { filled = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func label(_ usage: UsageSnapshot?) -> String {
        guard let left = usage?.tightest()?.remainingPercent() else { return "Лимиты загружаются" }
        return "Лимиты, осталось \(Theme.percent(left))"
    }
}

private struct UsageBadge: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let window = store.usage?.tightest(at: context.date) {
                let left = window.remainingPercent(at: context.date)
                let color = Theme.usageColor(left)
                NavigationLink(value: Route.usage) {
                    HStack(spacing: 2) {
                        Text("\(Int(left.rounded()))")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        + Text("%")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                        Text(window.shortLabel)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(left < 50 ? color : .white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(Color.black))
                    .overlay(Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1))
                    .contentShape(Capsule().inset(by: -6))
                }
                .buttonStyle(PressableStyle())
                .contentTransition(.numericText(value: left))
                .animation(.smooth, value: left)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .accessibilityLabel(UsageArc.label(store.usage))
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
                        colors: [.white, Color(red: 0.82, green: 0.82, blue: 0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Theme.accent.opacity(halo ? 0.3 : 0.15), radius: halo ? size * 0.16 : 4)
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
        }
        .frame(width: size, height: size)
        .background {
            if halo { HaloRings(size: size) }
        }
        .contentShape(Circle())
        .animation(.smooth(duration: 0.3), value: halo)
    }
}

struct HaloRings: View {
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

struct BusyCircle: View {
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
                    .rotationEffect(.radians(t * 3))
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
