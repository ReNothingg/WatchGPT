import SwiftUI

struct AskButton: View {
    @Environment(ChatStore.self) private var store
    var size: CGFloat = 44
    var halo = false
    @State private var longPressAt: Date?

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
                    if let longPressAt, Date.now.timeIntervalSince(longPressAt) < 2 {
                        self.longPressAt = nil
                        return
                    }
                    store.startVoice()
                } label: {
                    MicCircle(size: size, halo: halo)
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
                    MicCircle(size: size, halo: halo)
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
