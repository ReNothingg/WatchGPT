import SwiftUI

enum Route: Hashable {
    case settings, models, usage
}

struct ChatView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    HomeView()
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.messages) { message in
                            MessageRow(message: message, isLast: message.id == store.messages.last?.id)
                                .id(message.id)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .onChange(of: store.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
            .onAppear {
                if let target = store.scrollTarget { proxy.scrollTo(target, anchor: .top) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.usage) {
                    UsageRing(remaining: store.usage?.tightest()?.remainingPercent())
                        .frame(width: 26, height: 26)
                }
                .accessibilityLabel("Лимиты")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Настройки")
            }
            if !store.messages.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        store.newChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(store.isBusy)
                    .accessibilityLabel("Новый чат")

                    Spacer()
                    AskButton(size: 44)
                    Spacer()

                    Button {
                        if let answer = store.lastAnswer { store.speaker.toggle(answer.text) }
                    } label: {
                        Image(systemName: store.speaker.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .disabled(store.lastAnswer == nil)
                    .accessibilityLabel("Озвучить ответ")
                }
            }
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .settings: SettingsView()
            case .models: ModelPickerView()
            case .usage: UsageView()
            }
        }
        .onChange(of: store.pendingAsk) { _, pending in
            if pending { openDictationFromWidget() }
        }
        .onAppear {
            if store.pendingAsk { openDictationFromWidget() }
        }
    }

    private func openDictationFromWidget() {
        store.pendingAsk = false
        guard !store.isBusy else { return }
        // Give the UI a moment to settle after launch, then open dictation.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            Dictation.present { store.send($0) }
        }
    }
}

/// Empty state: one big button. Tap → speak → answer.
private struct HomeView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            AskButton(size: 86)
                .padding(.top, 4)

            Text("Спросить")
                .font(.headline)

            NavigationLink(value: Route.models) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                    Text(store.selectedModel.displayName)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.chip))
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.usage) {
                UsageLine(usage: store.usage)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MessageRow: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    let isLast: Bool

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 24)
                Text(message.text)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bubble))
            }
        case .assistant:
            if message.isError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    if isLast {
                        Button("Повторить") { store.retry() }
                            .font(.footnote)
                    }
                }
            } else if message.text.isEmpty && isLast && store.isBusy {
                ThinkingDots(label: store.status == .searching ? "Ищу в интернете" : "Думаю")
            } else {
                MarkdownText(text: message.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { store.speaker.toggle(message.text) }
            }
        }
    }
}
