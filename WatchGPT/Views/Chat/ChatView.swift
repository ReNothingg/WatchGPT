import SwiftUI
import WatchKit

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @State private var chromeVisible = true
    @State private var visibleLimit = Self.pageSize

    private static let pageSize = 16

    var body: some View {
        Group {
            if store.messages.isEmpty {
                HomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if store.messages.count > visibleLimit {
                                EarlierButton { visibleLimit += Self.pageSize }
                            }
                            ForEach(store.messages.suffix(visibleLimit)) { message in
                                MessageRow(message: message, isLast: message.id == store.messages.last?.id, fontScale: store.answerFontScale)
                                    .equatable()
                                    .id(message.id)
                                    .transition(message.role == .user ? .userBubble : .reply)
                            }
                        }
                        .padding(.bottom, store.isBusy ? 8 : 56)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: MessageListShape(store.messages))
                    }
                    .autoHidesChrome($chromeVisible)
                    .onChange(of: store.scrollTarget) { _, target in
                        guard let target else { return }
                        reveal(target)
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                    .onChange(of: store.conversationID) { _, _ in
                        visibleLimit = Self.pageSize
                    }
                    .onAppear {
                        if let target = store.scrollTarget {
                            reveal(target)
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: store.messages.isEmpty)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Настройки")
            }
            if store.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.quickPrompts) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Быстрые вопросы")
                }
            } else if store.isBusy {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.stop()
                        WKHaptics.click()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Остановить ответ")
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
                    .accessibilityLabel("Новый чат")
                }
                ToolbarItem(placement: .bottomBar) {
                    chatActions
                        .chromeVisibility(chromeVisible || !store.pendingImages.isEmpty)
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
            case .privacy: PrivacyView()
            case let .gptChat(id, title): GPTChatView(chatID: id, title: title)
            }
        }
        .fullScreenCover(isPresented: Bindable(store).isVoiceSheetPresented) {
            RecordView()
        }
        .handoffActivity(
            isActive: store.codeHandoff != nil || (store.handoff && store.path.isEmpty && !store.isBusy && store.lastAnswer != nil),
            title: store.codeHandoff != nil ? String(localized: "Код из WatchGPT") : String(localized: "Чат WatchGPT")
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

    private var photoOnRight: Bool {
        WKInterfaceDevice.current().wristLocation == .left
    }

    private var chatActions: some View {
        HStack(spacing: 14) {
            if photoOnRight {
                Color.clear.frame(width: 32, height: 32)
            } else {
                PhotoAttachButton(size: 32)
            }
            AskButton(size: 52, showsUsage: true)
            if photoOnRight {
                PhotoAttachButton(size: 32)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }
        }
    }

    private func reveal(_ id: UUID) {
        guard let index = store.messages.firstIndex(where: { $0.id == id }) else { return }
        let needed = store.messages.count - index
        if needed > visibleLimit { visibleLimit = needed }
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

private struct EarlierButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text("Ранние сообщения")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .glassBackground(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
