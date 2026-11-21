import SwiftUI

struct VoiceEditControls: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            SmallCircleButton(icon: "xmark", label: String(localized: "Отменить")) {
                WKHaptics.click()
                store.cancelVoice()
            }
            switch store.voicePhase {
            case .recording:
                SmallCircleButton(icon: "checkmark", prominent: true, doubleTap: true, label: String(localized: "Отправить")) {
                    store.finishVoice()
                }
                .transition(.scale.combined(with: .opacity))
            case .failed:
                if !store.voiceGivingUp {
                    SmallCircleButton(icon: "arrow.clockwise", prominent: true, doubleTap: true, label: String(localized: "Повторить")) {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { store.voicePhase == .recording }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        content
            .frame(minWidth: 96, minHeight: 34)
            .padding(.horizontal, 10)
            .glassBackground(shape, fill: Theme.bubble)
            .contentShape(shape)
            .onTapGesture { if isRecording { store.finishVoice() } }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.voicePhase)
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
                    .foregroundStyle(Theme.accent)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            .transition(.opacity)
        case .transcribing:
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                Text("Распознаю")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
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

private struct LiveBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recorder: AudioRecorder
    let paused: Bool
    private static let count = 11

    var body: some View {
        LiveTimeline(role: .feedback, fps: 20, isActive: !paused && !reduceMotion) { date in
            let t = date.timeIntervalSinceReferenceDate
            let level = paused || reduceMotion ? 0 : recorder.level
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
                    ctx.fill(Capsule().path(in: rect), with: .color(Theme.accent.opacity(0.42 + 0.58 * amount)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
