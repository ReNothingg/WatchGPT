import Charts
import SwiftUI

struct VoiceSettingsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var fetchingKey = false
    @State private var keyDraft = ""

    var body: some View {
        @Bindable var store = store

        List {
            Section {
                Picker("Распознавание", selection: $store.voiceEngine) {
                    ForEach(VoiceEngine.allCases, id: \.self) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                if store.voiceEngine != .apple {
                    Picker("Модель", selection: $store.transcribeModel) {
                        ForEach(TranscribeModel.allCases, id: \.self) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    Picker("Язык", selection: $store.voiceLanguage) {
                        ForEach(Transcriber.languages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }
            } footer: {
                Text(footer)
            }

            if store.voiceEngine != .apple {
                Section {
                    Toggle("Режим шёпота", isOn: $store.whisperMode)
                        .tint(Theme.toggleOn)
                } footer: {
                    Text("Для тихой речи: запись без потерь, усиление громкости и точная модель OpenAI, если есть API-ключ. Говорите, поднеся часы ко рту.")
                }
            }

            if let recording = store.lastRecording {
                Section {
                    Button {
                        store.playback.toggle(recording)
                    } label: {
                        Label(
                            store.playback.isPlaying ? "Остановить" : "Прослушать",
                            systemImage: store.playback.isPlaying ? "stop.fill" : "play.fill"
                        )
                    }
                    if let text = store.lastTranscript {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("Последняя запись")
                } footer: {
                    Text(store.lastVoiceLabel ?? "Так звучит то, что ушло на распознавание.")
                }
            }

            if store.voiceEngine == .auto || store.voiceEngine == .openai {
                Section {
                    HStack {
                        Text("API-ключ")
                        Spacer()
                        Text(keyStatus)
                            .foregroundStyle(auth.apiKey == nil ? .orange : Theme.accent)
                    }
                    .font(.footnote)

                    if let key = auth.apiKey?.key {
                        Text("\(key.prefix(8))…\(key.suffix(4)) · \(key.count) симв.")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                        KeyCheckRow(check: auth.keyCheck) { await auth.verifyAPIKey() }
                    }

                    Button {
                        Task {
                            fetchingKey = true
                            _ = try? await auth.obtainAPIKey()
                            fetchingKey = false
                        }
                    } label: {
                        if fetchingKey { ProgressView() } else { Label("Получить из аккаунта", systemImage: "key") }
                    }
                    .disabled(fetchingKey)

                    TextField("Вставить ключ sk-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: keyDraft) { _, value in
                            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            auth.setManualAPIKey(value)
                            keyDraft = ""
                        }

                    if auth.apiKey != nil {
                        Button(role: .destructive) {
                            auth.clearAPIKey()
                        } label: {
                            Label("Удалить ключ", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text(auth.apiKeyError ?? "Ключ берётся из вашего входа в ChatGPT. Распознавание оплачивается с API-баланса OpenAI: около $0.0045 за минуту (быстрая модель — $0.003).")
                }
            }
        }
        .navigationTitle("Голос")
        .onDisappear { store.playback.stop() }
    }

    private var keyStatus: String {
        guard let key = auth.apiKey else { return "нет" }
        return key.isManual ? "свой" : "из аккаунта"
    }

    private var footer: String {
        switch store.voiceEngine {
        case .auto: return "Сначала диктовка ChatGPT по подписке, если она недоступна — OpenAI gpt-transcribe. Понимает любые языки и формулы."
        case .chatgpt: return "Диктовка ChatGPT по подписке. Неофициально: может не работать."
        case .openai: return "OpenAI gpt-transcribe: любые языки, формулы записываются символами (x², √, ∫)."
        case .apple: return "Встроенная диктовка watchOS: бесплатно и офлайн, но хуже с формулами и смешанными языками."
        }
    }
}

struct KeyCheckRow: View {
    let check: AuthService.KeyCheck
    let verify: () async -> Void

    var body: some View {
        switch check {
        case .unknown:
            Button {
                Task { await verify() }
            } label: {
                Label("Проверить ключ", systemImage: "checkmark.shield")
            }
        case .checking:
            HStack {
                ProgressView().frame(width: 20)
                Text("Проверяю…").font(.footnote)
            }
        case .valid:
            Label("Ключ работает", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
        case let .invalid(message):
            Button {
                Task { await verify() }
            } label: {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
