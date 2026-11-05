import SwiftUI

struct GPTChatView: View {
    let chatID: String
    let title: String

    @Environment(ChatStore.self) private var store
    @State private var conversation: RemoteConversation?
    @State private var loadError: String?
    @State private var isRefreshing = false
    @State private var visibleCount = Self.pageSize
    @State private var didScroll = false
    @State private var chromeVisible = true
    @State private var streamFailed = false
    @Environment(\.scenePhase) private var scenePhase

    private static let pageSize = 30

    var body: some View {
        Group {
            if let conversation {
                transcript(conversation)
                    .transition(.opacity)
            } else if let loadError {
                ScrollView {
                    HistoryErrorView(message: loadError) {
                        Task { await load() }
                    }
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 10) {
                    Spinner(size: 30, lineWidth: 3)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: conversation == nil)
        .navigationTitle("ChatGPT")
        .toolbar {
            if let conversation, !conversation.messages.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        continueChat(conversation, ask: true)
                    } label: {
                        MicCircle(size: 46, halo: false)
                    }
                    .buttonStyle(PressableStyle())
                    .chromeVisibility(chromeVisible)
                    .disabled(store.isBusy)
                    .accessibilityLabel("Продолжить голосом на часах")
                }
            }
        }
        .task {
            if conversation == nil { conversation = store.gptHistory.cached(chatID) }
            await load()
        }
        .task(id: PollKey(live: conversation?.live != nil, phase: scenePhase)) {
            guard conversation?.live != nil, scenePhase != .background else { return }
            var tick = 0
            while !Task.isCancelled {
                let pause: Double = streamFailed ? 10 : (PowerMonitor.shared.isLowPower ? 4 : 2)
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { return }
                tick += 1
                if tick % 3 == 0 || streamFailed {
                    let state = await store.gptHistory.streamState(chatID)
                    guard !Task.isCancelled else { return }
                    streamFailed = state == .failed
                }
                await load(quiet: true)
            }
        }
        .handoffActivity(isActive: store.handoff, title: title) {
            Handoff.url(remoteChatID: chatID)
        }
    }

    private func transcript(_ conversation: RemoteConversation) -> some View {
        let messages = conversation.messages
        let hidden = max(0, messages.count - visibleCount)
        let shown = Array(messages.dropFirst(hidden))

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header(conversation)

                    if hidden > 0 {
                        Button {
                            WKHaptics.click()
                            visibleCount += Self.pageSize
                        } label: {
                            Label("Ранее: \(ChatDate.messages(hidden))", systemImage: "arrow.up")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .glassBackground(Capsule(), interactive: true)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .frame(maxWidth: .infinity)
                    }

                    if messages.isEmpty {
                        Text("В этом чате нет текстовых сообщений.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    ForEach(shown) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            if message.role == .assistant, let reasoning = conversation.reasoning[message.id] {
                                ReasoningSummary(reasoning: reasoning)
                            }
                            HistoryBubble(
                                message: message,
                                images: conversation.images[message.id] ?? [],
                                conversationID: conversation.id
                            )
                        }
                        .id(message.id)
                    }

                    if let live = conversation.live {
                        LiveTurnCard(live: live, failed: streamFailed)
                            .id("live")
                            .transition(.opacity)
                    }

                    footer(conversation)
                }
                .padding(.bottom, 56)
            }
            .autoHidesChrome($chromeVisible)
            .onAppear {
                guard !didScroll, let target = messages.last(where: { $0.role == .user })?.id else { return }
                didScroll = true
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private func header(_ conversation: RemoteConversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(ChatDate.short(conversation.updatedAt))
                Text("·")
                Text(ChatDate.messages(conversation.messages.count))
                if isRefreshing {
                    Spinner(size: 9, lineWidth: 1.5)
                        .padding(.leading, 2)
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.bottom, 2)
    }

    private func footer(_ conversation: RemoteConversation) -> some View {
        VStack(spacing: 6) {
            Button {
                continueChat(conversation, ask: false)
            } label: {
                Label("Продолжить на часах", systemImage: "applewatch")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .glassBackground(Capsule(), fill: Theme.accent, tint: Theme.accent, interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .disabled(store.isBusy || conversation.messages.isEmpty)
            .opacity(store.isBusy || conversation.messages.isEmpty ? 0.5 : 1)

            Text("Новые сообщения сохранятся на часах, в ChatGPT они не появятся.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func continueChat(_ conversation: RemoteConversation, ask: Bool) {
        WKHaptics.click()
        store.continueGPTChat(conversation, ask: ask)
    }

    private func load(quiet: Bool = false) async {
        if !quiet {
            loadError = nil
            isRefreshing = true
        }
        defer { if !quiet { isRefreshing = false } }
        do {
            let fresh = try await store.gptHistory.conversation(chatID)
            let wasLive = conversation?.live != nil
            if fresh != conversation {
                withAnimation(.smooth(duration: 0.3)) { conversation = fresh }
            }
            if wasLive, fresh.live == nil { WKHaptics.success() }
        } catch {
            guard !GPTHistory.isCancellation(error) else { return }
            if conversation == nil { loadError = ChatStore.describe(error) }
        }
    }
}

struct PollKey: Equatable {
    var live: Bool
    var phase: ScenePhase
}
