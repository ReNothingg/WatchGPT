import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var chromeVisible = true

    var body: some View {
        Group {
            if store.messages.isEmpty {
                HomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.messages) { message in
                                MessageRow(message: message, isLast: message.id == store.messages.last?.id, fontScale: store.answerFontScale)
                                    .equatable()
                                    .id(message.id)
                                    .transition(message.role == .user ? .userBubble : .reply)
                            }
                        }
                        .padding(.bottom, 56)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: MessageListShape(store.messages))
                    }
                    .autoHidesChrome($chromeVisible)
                    .onChange(of: store.scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                    .onAppear {
                        if let target = store.scrollTarget { proxy.scrollTo(target, anchor: .top) }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: store.messages.isEmpty)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.usage) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        UsageRing(
                            remaining: store.usage?.tightest(at: context.date)?.remainingPercent(at: context.date),
                            lineWidth: 2.5,
                            textSize: 10,
                            showsPercentSign: true
                        )
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                    }
                }
                .accessibilityLabel(limitsLabel)
            }
            if store.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.quickPrompts) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Быстрые вопросы")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        WKHaptics.click()
                        store.newChat()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                    .disabled(store.isBusy)
                    .accessibilityLabel("Новый чат")
                }
                ToolbarItem(placement: .bottomBar) {
                    AskButton(size: 46)
                        .chromeVisibility(chromeVisible || store.isBusy)
                }
            }
        }
        .tint(Theme.control)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .settings: SettingsView()
            case .models: ModelPickerView()
            case .usage: UsageView()
            case .voice: VoiceSettingsView()
            case .history: HistoryView()
            case .diagnostics: DiagnosticsView()
            case .clientVersion: ClientVersionView()
            case .quickPrompts: QuickPromptsView()
            case .claude: ClaudeSettingsView()
            case .places: PlacesView()
            case let .gptChat(id, title): GPTChatView(chatID: id, title: title)
            }
        }
        .fullScreenCover(isPresented: Bindable(store).isVoiceSheetPresented) {
            RecordView()
        }
        .handoffActivity(
            isActive: store.codeHandoff != nil || (store.handoff && store.path.isEmpty && !store.isBusy && store.lastAnswer != nil),
            title: store.codeHandoff != nil ? "Код из WatchGPT" : "Чат WatchGPT"
        ) {
            store.codeHandoff ?? Handoff.url(conversationID: store.conversationID, messages: store.messages, claude: store.provider == .claude)
        }
        .onChange(of: store.pendingAsk) { _, pending in
            if pending { openDictationFromWidget() }
        }
        .onAppear {
            if store.pendingAsk { openDictationFromWidget() }
        }
    }

    private var limitsLabel: String {
        guard let left = store.usage?.tightest()?.remainingPercent() else { return "Лимиты" }
        return "Лимиты, осталось \(Theme.percent(left))"
    }

    private func openDictationFromWidget() {
        store.pendingAsk = false
        guard !store.isBusy else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if store.usesCloudVoice {
                store.startVoice()
            } else {
                Dictation.present { store.send($0) }
            }
        }
    }
}
