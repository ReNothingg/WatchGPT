import SwiftUI

struct VoiceEditControls: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            SmallCircleButton(icon: "xmark", label: "Отменить") {
                WKHaptics.click()
                store.cancelVoice()
            }
            switch store.voicePhase {
            case .recording:
                SmallCircleButton(icon: "checkmark", prominent: true, doubleTap: true, label: "Отправить") {
                    store.finishVoice()
                }
                .transition(.scale.combined(with: .opacity))
            case .failed:
                if !store.voiceGivingUp {
                    SmallCircleButton(icon: "arrow.clockwise", prominent: true, doubleTap: true, label: "Повторить") {
                        store.retryTranscription()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.voicePhase)
    }
}

struct VoiceEditBubble: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isRecording: Bool { store.voicePhase == .recording }

    private var showsBorder: Bool {
        !isLuminanceReduced && (store.voicePhase == .recording || store.voicePhase == .transcribing)
    }

    var body: some View {
        content
            .frame(minWidth: 96, minHeight: 34)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bubble))
            .overlay {
                if showsBorder {
                    LiveBorder(recorder: store.recorder, active: isRecording)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { if isRecording { store.finishVoice() } }
            .animation(.smooth(duration: 0.3), value: store.voicePhase)
    }

    @ViewBuilder
    private var content: some View {
        switch store.voicePhase {
        case .recording:
            HStack(spacing: 8) {
                LiveBars(recorder: store.recorder, paused: store.recorder.isPaused)
                    .frame(width: 58, height: 20)
                Text(Self.time(store.recorder.elapsed))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.numericText())
            }
            .transition(.opacity)
        case .transcribing:
            HStack(spacing: 6) {
                ThinkingDots()
                Text("Распознаю")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .transition(.opacity)
        case let .failed(message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(3)
                .padding(.vertical, 6)
                .transition(.opacity)
        case .idle:
            EmptyView()
        }
    }

    private static func time(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct LiveBars: View {
    let recorder: AudioRecorder
    let paused: Bool
    private static let count = 11

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = paused ? 0 : recorder.level
            Canvas { ctx, size in
                let n = Self.count
                let gap: CGFloat = 2.5
                let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                for i in 0..<n {
                    let x = CGFloat(i) * (w + gap)
                    let center = abs(Double(i) - Double(n - 1) / 2) / (Double(n - 1) / 2)
                    let envelope = 1 - center * center * 0.6
                    let wave = 0.55 + 0.45 * sin(t * 7.5 + Double(i) * 0.85)
                    let amount = 0.12 + 0.88 * min(1, level * 1.25) * envelope * wave
                    let h = max(w, size.height * amount)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
                    ctx.fill(Capsule().path(in: rect), with: .color(Theme.accent.opacity(0.55 + 0.45 * amount)))
                }
            }
        }
    }
}

struct LiveBorder: View {
    let recorder: AudioRecorder
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let level = active ? recorder.level : 0
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.9), Theme.accent.opacity(0)],
                        center: .center,
                        angle: .radians(t * (active ? 2.6 : 5))
                    ),
                    lineWidth: 1.2 + 1.3 * level
                )
                .shadow(color: Theme.accent.opacity(0.25 + 0.4 * level), radius: 3 + 5 * level)
        }
        .allowsHitTesting(false)
    }
}

struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 4, height: 4)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 5 - Double(i) * 0.7)))
                }
            }
        }
    }
}
