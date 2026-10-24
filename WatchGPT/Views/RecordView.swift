import SwiftUI

/// Full-screen recorder: live waveform while you talk, then "Распознаю…", then the question is sent.
struct RecordView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            switch store.voicePhase {
            case .recording, .idle:
                RecordingContent()
            case .transcribing:
                TranscribingContent()
            case let .failed(message):
                FailedContent(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.cancelVoice()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Отмена")
            }
        }
    }
}

private struct RecordingContent: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        let recorder = store.recorder
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Waveform(levels: recorder.levels, active: recorder.isRecording)
                .frame(height: 54)
                .padding(.horizontal, 6)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(recorder.isRecording ? 1 : 0.3)
                Text(timeString(recorder.elapsed))
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .monospacedDigit()
                Text(recorder.heardSpeech ? "слушаю" : "говорите")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                store.finishVoice()
            } label: {
                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .disabled(!recorder.isRecording)
            .accessibilityLabel("Отправить")

            Text(store.autoStopOnSilence ? "Отправлю сам, когда замолчите" : "Нажмите, когда закончите")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

private struct Waveform: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let level = CGFloat(levels[i])
                    Capsule()
                        .fill(Theme.accent.opacity(active ? 0.45 + 0.55 * level : 0.3))
                        .frame(width: width, height: max(width, geo.size.height * (0.08 + 0.92 * level)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.linear(duration: 0.06), value: levels)
        }
    }
}

private struct TranscribingContent: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Распознаю…")
                .font(.headline)
            Text(engineHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var engineHint: String {
        switch store.voiceEngine {
        case .chatgpt: return "ChatGPT"
        case .openai: return "OpenAI · \(store.transcribeModel.rawValue)"
        case .auto: return store.lastVoiceLabel ?? "OpenAI"
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
