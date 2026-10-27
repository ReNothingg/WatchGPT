import SwiftUI

/// Full-screen recorder: live waveform while you talk, then "Распознаю…", then the question is sent.
struct RecordView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        NavigationStack {
            content
        }
        .interactiveDismissDisabled()
    }

    private var isFailed: Bool {
        if case .failed = store.voicePhase { return true }
        return false
    }

    private var content: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !isFailed {
                LiveGlow()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            Group {
                if case let .failed(message) = store.voicePhase {
                    FailedContent(message: message)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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

private struct LiveGlow: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        EdgeGlow(mode: store.voiceMode) { [recorder = store.recorder] in recorder.level }
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
                .foregroundStyle(recorder.isPaused ? Theme.accent : .white)
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(!recorder.isActive)
        .animation(.snappy(duration: 0.25), value: recorder.isPaused)
        .accessibilityLabel(recorder.isPaused ? "Продолжить" : "Пауза")
    }
}

private struct LiveContent: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let processing = store.voicePhase == .transcribing
        VStack(spacing: 0) {
            LiveSendButton(processing: processing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, -36)
                .padding(.horizontal, -10)

            if let prompt = store.voicePrompt {
                Text("\(prompt.text)…")
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
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    RecordingStatus(recorder: store.recorder)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .frame(height: 34)
        }
        .padding(.bottom, 2)
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
    let processing: Bool
    @State private var swipe = SwipeGuard()

    var body: some View {
        Button {
            guard !swipe.recentlySwiped else { return }
            store.finishVoice()
        } label: {
            ZStack {
                VoiceBlob(mode: store.voiceMode, coreRatio: 0.5) { [recorder = store.recorder] in recorder.level }
                ZStack {
                    if processing {
                        Image(systemName: "waveform")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.62), value: processing)
            }
            .contentShape(Circle().scale(0.6))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { [swipe] _ in swipe.lastMove = .now }
        )
        .doubleTapAction(isEnabled: store.recorder.isActive && !processing)
        .allowsHitTesting(store.recorder.isActive && !processing)
        .accessibilityLabel("Отправить")
    }
}

private struct RecordingStatus: View {
    let recorder: AudioRecorder

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if recorder.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.fast)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.danger)
                        .symbolEffect(.pulse, isActive: recorder.isRecording)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 10)
            Text(timeString(recorder.elapsed))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .contentTransition(.opacity)
        }
        .animation(.snappy(duration: 0.3), value: recorder.elapsed)
        .animation(.snappy(duration: 0.3), value: statusText)
    }

    private var statusText: String {
        if recorder.isPaused { return "пауза" }
        return recorder.heardSpeech ? "слушаю" : "говорите"
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
            ShimmerText(text: "Распознаю", font: .system(size: 15, weight: .semibold, design: .rounded), base: .white.opacity(0.75))
            Text(engineHint)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
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
