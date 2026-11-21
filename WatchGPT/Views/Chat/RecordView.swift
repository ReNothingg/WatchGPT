import SwiftUI

struct RecordView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            content
        }
        .interactiveDismissDisabled()
    }

    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if case let .failed(message) = store.voicePhase {
                    FailedContent(message: message)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    LiveContent()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.smooth(duration: 0.45), value: store.voicePhase)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.cancelVoice()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Отмена")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if store.voicePhase == .recording {
                    PauseButton(recorder: store.recorder)
                }
            }
        }
        .tint(Theme.control)
    }
}

private extension ChatStore {
    var voiceMode: VoiceMode {
        if voicePhase == .transcribing { return .processing }
        return recorder.isPaused ? .paused : .listening
    }
}

private struct PauseButton: View {
    @Environment(ChatStore.self) private var store
    let recorder: AudioRecorder

    var body: some View {
        Button {
            store.toggleVoicePause()
            WKHaptics.click()
        } label: {
            Image(systemName: recorder.isPaused ? "mic.fill" : "pause.fill")
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(!recorder.isActive)
        .animation(.snappy(duration: 0.25), value: recorder.isPaused)
        .accessibilityLabel(recorder.isPaused ? "Продолжить" : "Пауза")
    }
}

private struct LiveContent: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let processing = store.voicePhase == .transcribing
        let mode = store.voiceMode
        VStack(spacing: 4) {
            ZStack {
                VoiceOrb(mode: mode) { [recorder = store.recorder] in recorder.level }
                LiveSendButton(mode: mode)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, -22)

            if let prompt = store.voicePrompt {
                Text(prompt.text)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }

            ZStack {
                if processing {
                    TranscribingLabel()
                        .transition(.opacity)
                } else {
                    RecordingStatus(recorder: store.recorder)
                        .transition(.opacity)
                }
            }
            .frame(minHeight: 30)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: mode)
        }
        .padding(.bottom, 4)
    }
}

private final class SwipeGuard {
    var lastMove: Date?

    var recentlySwiped: Bool {
        lastMove.map { Date.now.timeIntervalSince($0) < 0.5 } ?? false
    }
}

private struct LiveSendButton: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mode: VoiceMode
    @State private var swipe = SwipeGuard()

    var body: some View {
        let processing = mode == .processing
        Button {
            guard !swipe.recentlySwiped else { return }
            store.finishVoice()
        } label: {
            ZStack {
                if processing {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .glassBackground(Circle(), fill: Theme.raised)
                        .transition(.opacity)
                } else {
                    MicCircle(size: 56, halo: false, icon: "arrow.up")
                        .transition(.opacity)
                }
            }
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: mode)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { [swipe] _ in swipe.lastMove = .now }
        )
        .doubleTapAction(isEnabled: store.recorder.isActive && !processing)
        .disabled(!store.recorder.isActive || processing)
        .accessibilityLabel("Отправить запись")
        .accessibilityHidden(processing)
    }
}

private struct RecordingStatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recorder: AudioRecorder

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: recorder.isPaused ? "pause.fill" : "mic.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(recorder.isPaused ? Theme.secondaryText : Theme.accent)
                .frame(width: 10)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            if recorder.isActive {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 10)
                Text(timeString(recorder.elapsed))
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(recorder.isPaused ? Theme.secondaryText : Theme.accent)
                    .fixedSize()
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: recorder.elapsed)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if recorder.isPaused { return String(localized: "Пауза") }
        if !recorder.isRecording { return String(localized: "Включаю микрофон…") }
        return recorder.heardSpeech ? String(localized: "Слушаю") : String(localized: "Говорите")
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

private struct TranscribingLabel: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        VStack(spacing: 1) {
            Text("Распознаю речь")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(engineHint)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var engineHint: String {
        switch store.voiceEngine {
        case .chatgpt: return "ChatGPT"
        case .openai: return "OpenAI · \(store.transcribeModel.rawValue)"
        case .auto: return store.lastVoiceLabel ?? "ChatGPT"
        case .apple: return "Apple"
        }
    }
}

private struct FailedContent: View {
    @Environment(ChatStore.self) private var store
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: message)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)

                if store.voiceGivingUp {
                    Text("Закрываю…")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Button {
                        store.retryTranscription()
                    } label: {
                        Label("Повторить", systemImage: "arrow.clockwise")
                    }
                    .tint(Theme.accent)
                    .doubleTapAction()

                    TextFieldLink(prompt: Text("Спросите что угодно")) {
                        Label("Диктовка Apple", systemImage: "mic")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    } onSubmit: { text in
                        store.sendFromFallback(text)
                    }
                    .tint(.white)
                }
            }
            .padding(.top, 4)
        }
    }
}
