import SwiftUI

struct GPTHistorySections: View {
    @Environment(ChatStore.self) private var store
    let appeared: Bool

    private var history: GPTHistory { store.gptHistory }

    var body: some View {
        if history.chats.isEmpty {
            Section {
                placeholder
                    .listRowBackground(Color.clear)
            }
        } else {
            if let error = history.errorMessage {
                Section {
                    HistoryErrorView(message: error, compact: true) { refresh() }
                        .listRowBackground(Color.clear)
                }
            }

            let localCopies = store.localGPTChatIDs
            Section {
                ForEach(Array(history.chats.enumerated()), id: \.element.id) { index, chat in
                    GPTChatRow(chat: chat, hasCopy: localCopies.contains(ChatThread.gptID(chat.id))) {
                        WKHaptics.click()
                        store.path.append(.gptChat(id: chat.id, title: chat.title))
                    }
                    .modifier(Entrance(index: index, appeared: appeared))
                    .onAppear {
                        if index >= history.chats.count - 3 {
                            Task { await history.loadMore() }
                        }
                    }
                }

                if history.isLoadingMore {
                    Spinner(size: 18, lineWidth: 2)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if let error = history.loadMoreError {
                    Button {
                        Task { await history.loadMore() }
                    } label: {
                        Label(error, systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Button(action: refresh) {
                    Label("Обновить", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(history.isLoading ? Theme.secondaryText : Theme.accent)
                }
                .disabled(history.isLoading)
                .listRowBackground(Color.clear)
            } footer: {
                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var footerText: String {
        let note = "Продолжение на часах сохраняется только на часах."
        guard let syncedAt = history.syncedAt else { return note }
        return "Обновлено \(ChatDate.short(syncedAt).lowercased()). \(note)"
    }

    @ViewBuilder
    private var placeholder: some View {
        if let error = history.errorMessage {
            HistoryErrorView(message: error) { refresh() }
        } else if history.isLoading || history.syncedAt == nil {
            VStack(spacing: 10) {
                Spinner(size: 30, lineWidth: 3)
                Text("Загружаю чаты ChatGPT…")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            EmptyHistory(icon: "sparkles", title: "Пока пусто", subtitle: "В аккаунте ChatGPT ещё нет чатов")
        }
    }

    private func refresh() {
        WKHaptics.click()
        Task { await history.refresh(force: true) }
    }
}

struct GPTChatRow: View {
    let chat: RemoteChat
    let hasCopy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if chat.updatedAt > .distantPast {
                        Text(ChatDate.short(chat.updatedAt))
                    }
                    if hasCopy {
                        Image(systemName: "applewatch")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Есть копия на часах")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }
}
