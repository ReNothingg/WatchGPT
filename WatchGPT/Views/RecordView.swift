import SwiftUI

/// Full-screen recorder: live waveform while you talk, then "Распознаю…", then the question is sent.
struct RecordView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        NavigationStack {
            content
        }
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
        }
        .tint(Theme.control)
    }
}

private extension ChatStore {
    var orbMode: VoiceOrb.Mode {
        if voicePhase == .transcribing { return .processing }
        return recorder.isPaused ? .paused : .listening
    }

    var voiceLevel: Double {
        let recent = recorder.levels.suffix(3)
        guard !recent.isEmpty else { return 0 }
        return Double(recent.reduce(0, +)) / Double(recent.count)
    }
}

private struct LiveGlow: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        EdgeGlow(mode: store.orbMode, level: store.voiceLevel)
    }
}

private struct LiveOrb: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        VoiceOrb(mode: store.orbMode, level: store.voiceLevel)
    }
}

private struct LiveContent: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let processing = store.voicePhase == .transcribing
        VStack(spacing: 2) {
            LiveOrb()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, -46)
                .padding(.horizontal, -8)

            ZStack {
                if processing {
                    TranscribingLabel()
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    RecordingStatus(recorder: store.recorder)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .frame(height: 26)

            RecordingControls(recorder: store.recorder)
                .opacity(processing ? 0 : 1)
                .scaleEffect(processing ? 0.7 : 1)
                .blur(radius: processing ? 4 : 0)
                .allowsHitTesting(!processing)
        }
        .padding(.bottom, 2)
    }
}

private struct RecordingControls: View {
    @Environment(ChatStore.self) private var store
    let recorder: AudioRecorder

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.toggleVoicePause()
                WKHaptics.click()
            } label: {
                ZStack {
                    Circle().fill(Theme.raised)
                    Image(systemName: recorder.isPaused ? "mic.fill" : "pause.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 42, height: 42)
                .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!recorder.isActive)
            .accessibilityLabel(recorder.isPaused ? "Продолжить" : "Пауза")

            Button {
                store.finishVoice()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.16, green: 0.80, blue: 0.62), Theme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 58, height: 58)
                .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!recorder.isActive)
            .accessibilityLabel("Отправить")

            Color.clear.frame(width: 42, height: 42)
        }
        .animation(.snappy(duration: 0.25), value: recorder.isPaused)
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

                Button {
                    store.retryTranscription()
                } label: {
                    Label("Повторить", systemImage: "arrow.clockwise")
                }
                .tint(Theme.accent)

                TextFieldLink(prompt: Text("Спросите что угодно")) {
                    Label("Диктовка Apple", systemImage: "mic")
                        .frame(maxWidth: .infinity)
                } onSubmit: { text in
                    store.sendFromFallback(text)
                }
            }
            .padding(.top, 4)
        }
    }
}
