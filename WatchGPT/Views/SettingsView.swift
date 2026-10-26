import SwiftUI

struct SettingsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 8) {
                NavigationLink(value: Route.models) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Модель")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                            Text(store.selectedModel.displayName)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if store.selectedModel.efforts.count > 1 {
                                Text(ModelOption.effortLabel(store.effort))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer(minLength: 0)
                        Chevron()
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ToggleTile(title: "Поиск", icon: "globe", isOn: $store.webSearch)
                    if store.selectedModel.supportsFast == true {
                        ToggleTile(title: "Fast", icon: "bolt.fill", isOn: $store.fastMode, onColor: Theme.fast)
                    }
                    ToggleTile(title: "Кратко", icon: "text.alignleft", isOn: $store.conciseAnswers)
                    ToggleTile(title: "Вслух", icon: "speaker.wave.2.fill", isOn: $store.autoSpeak)
                    ToggleTile(title: "На iPhone", icon: "iphone.and.arrow.forward", isOn: $store.handoff)
                }

                AnswerFontCard(scale: $store.answerFontScale)

                SettingsCard {
                    NavigationLink(value: Route.voice) {
                        SettingsRow(title: "Голос") {
                            Text(store.voiceEngine == .apple ? "Apple" : "OpenAI · \(store.transcribeModel.title.lowercased())")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    CardDivider()
                    NavigationLink(value: Route.usage) {
                        SettingsRow(title: "Лимиты") {
                            if let left = store.usage?.tightest()?.remainingPercent() {
                                Text(Theme.percent(left))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.usageColor(left))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    CardDivider()
                    NavigationLink(value: Route.diagnostics) {
                        SettingsRow(title: "Диагностика") {
                            let count = DiagnosticsLog.shared.entries.filter { $0.date.timeIntervalSinceNow > -86_400 }.count
                            if count > 0 {
                                Text("\(count)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                SettingsCard {
                    if let email = auth.tokens?.email {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(email)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let plan = store.usage?.planLabel ?? auth.tokens?.planType?.capitalized {
                                Text("ChatGPT \(plan)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        CardDivider()
                    }
                    Button {
                        confirmSignOut = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Выйти")
                                .font(.footnote)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Отключить аккаунт ChatGPT?", isPresented: $confirmSignOut) {
            Button("Выйти", role: .destructive) { auth.signOut() }
            Button("Отмена", role: .cancel) {}
        }
    }
}

private struct ToggleTile: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var onColor: Color = Theme.accent

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
            WKHaptics.click()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? onColor : Theme.secondaryText)
                Spacer(minLength: 4)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 58)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? onColor.opacity(0.22) : Theme.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "включено" : "выключено")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

private struct AnswerFontCard: View {
    @Binding var scale: Double

    private let scales = ChatStore.answerFontScales
    private var index: Int {
        scales.firstIndex(of: scale) ?? scales.firstIndex(of: 1.0) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Шрифт ответа")
                    .font(.footnote)
                Spacer(minLength: 4)
                Text(Theme.percent(scale * 100))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(scale == 1 ? Theme.secondaryText : Theme.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            MarkdownText(text: "Так будет выглядеть ответ.", scale: scale)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            HStack(spacing: 6) {
                stepButton(icon: "textformat.size.smaller", label: "Уменьшить шрифт", delta: -1)
                stepButton(icon: "textformat.size.larger", label: "Увеличить шрифт", delta: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(icon: String, label: String, delta: Int) -> some View {
        let target = index + delta
        let enabled = scales.indices.contains(target)
        return Button {
            guard enabled else { return }
            withAnimation(.snappy(duration: 0.2)) { scale = scales[target] }
            WKHaptics.click()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? .white : Theme.secondaryText.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(Theme.raised))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.footnote)
            Spacer(minLength: 4)
            trailing
                .font(.caption2)
                .lineLimit(1)
            Chevron()
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 42)
        .contentShape(Rectangle())
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.raised)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}

struct ModelPickerView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(store.models) { option in
                    ModelRow(option: option, isSelected: option.slug == store.selectedModelSlug) {
                        store.selectedModelSlug = option.slug
                        WKHaptics.click()
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Модель")
        .task { await store.refreshModels(ifOlderThan: 600) }
    }
}

private struct ModelRow: View {
    let option: ModelOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(option.displayName)
                            .font(.footnote.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if option.supportsFast == true {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.fast)
                        }
                    }
                    if let summary = option.summary {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.surface : Theme.surfaceDim)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ModelCard: View {
    @Environment(ChatStore.self) private var store
    var crownControlsEffort = false

    var body: some View {
        @Bindable var store = store
        let model = store.selectedModel
        let hasEfforts = model.efforts.count > 1
        let defaultEffort = model.defaultEffort ?? model.efforts.first ?? store.effort

        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if model.supportsFast == true {
                    Button {
                        store.fastMode.toggle()
                        WKHaptics.click()
                    } label: {
                        Image(systemName: store.fastMode ? "bolt.fill" : "bolt")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(store.fastMode ? Theme.fast : Theme.secondaryText)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.fastMode ? "Fast включён" : "Fast выключен")
                } else {
                    Color.clear.frame(width: 30, height: 30)
                }

                NavigationLink(value: Route.models) {
                    VStack(spacing: 0) {
                        Text(hasEfforts ? ModelOption.effortLabel(store.effort) : model.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        HStack(spacing: 2) {
                            Text(hasEfforts ? model.displayName : "Сменить модель")
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Выбрать модель")

                Button {
                    withAnimation(.snappy(duration: 0.2)) { store.effort = defaultEffort }
                    WKHaptics.click()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hasEfforts && store.effort != defaultEffort ? 1 : 0)
                .disabled(!hasEfforts || store.effort == defaultEffort)
                .accessibilityLabel("Сбросить уровень")
            }

            if hasEfforts {
                EffortBar(efforts: model.efforts, selection: $store.effort, crownByDefault: crownControlsEffort)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 4)
        .padding(.bottom, hasEfforts ? 6 : 4)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surfaceDim))
    }
}

struct EffortBar: View {
    let efforts: [String]
    @Binding var selection: String
    var crownByDefault = false
    @State private var crown: Double = 0
    @FocusState private var focused: Bool

    private var index: Int { efforts.firstIndex(of: selection) ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let count = max(efforts.count, 1)
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Theme.accent : Theme.track)
                        .frame(height: 5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        focused = true
                        guard geo.size.width > 0 else { return }
                        let raw = value.location.x / geo.size.width * CGFloat(count)
                        select(Int(raw.rounded(.down)))
                    }
            )
        }
        .frame(height: 16)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .digitalCrownRotation(
            $crown,
            from: 0,
            through: Double(max(efforts.count - 1, 0)),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onAppear {
            crown = Double(index)
            if crownByDefault { focused = true }
        }
        .onChange(of: crown) { _, value in
            select(Int(value.rounded()))
        }
        .onChange(of: selection) { _, _ in
            if Int(crown.rounded()) != index { crown = Double(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Уровень рассуждений")
        .accessibilityValue(ModelOption.effortLabel(selection))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(index + 1)
            case .decrement: select(index - 1)
            @unknown default: break
            }
        }
    }

    private func select(_ i: Int) {
        guard !efforts.isEmpty else { return }
        let clamped = min(max(i, 0), efforts.count - 1)
        guard efforts[clamped] != selection else { return }
        withAnimation(.snappy(duration: 0.2)) { selection = efforts[clamped] }
        WKHaptics.click()
    }
}

struct UsageView: View {
    @Environment(ChatStore.self) private var store
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let usage = store.usage, usage.primary != nil || usage.secondary != nil {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                if let w = usage.primary { WindowGauge(window: w, now: context.date) }
                                if let w = usage.secondary { WindowGauge(window: w, now: context.date) }
                            }
                            VStack(spacing: 3) {
                                if let w = usage.primary { resetLine(w, now: context.date) }
                                if let w = usage.secondary { resetLine(w, now: context.date) }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                    if let plan = usage.planLabel {
                        Text("ChatGPT \(plan)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let error = store.usageError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView().padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .navigationTitle("Лимиты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        refreshing = true
                        await store.refreshUsage()
                        refreshing = false
                    }
                } label: {
                    if refreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white)
                    }
                }
                .disabled(refreshing)
                .accessibilityLabel("Обновить")
            }
        }
        .tint(Theme.control)
        .task { await store.refreshUsage() }
    }

    private func resetLine(_ window: UsageWindow, now: Date) -> some View {
        HStack {
            Text(window.longLabel)
            Spacer()
            if let reset = window.resetAt, reset > now {
                Text("сброс \(reset.formatted(.relative(presentation: .numeric)))")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("сброшен").foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct WindowGauge: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        let left = window.remainingPercent(at: now)
        VStack(spacing: 4) {
            ZStack {
                UsageRing(remaining: left, lineWidth: 6, showsText: false)
                Text(Theme.percent(left))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 70, height: 70)
            Text(window.shortLabel)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.longLabel): осталось \(Theme.percent(left))")
    }
}

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
                        .tint(Theme.accent)
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
                        keyCheckRow
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

    @ViewBuilder
    private var keyCheckRow: some View {
        switch auth.keyCheck {
        case .unknown:
            Button {
                Task { await auth.verifyAPIKey() }
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
                Task { await auth.verifyAPIKey() }
            } label: {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var keyStatus: String {
        guard let key = auth.apiKey else { return "нет" }
        if key.fromBuild == true { return "из сборки" }
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
