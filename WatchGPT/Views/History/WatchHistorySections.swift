import SwiftUI

struct WatchHistorySections: View {
    @Environment(ChatStore.self) private var store
    let appeared: Bool
    let onOpen: (ChatThread) -> Void
    let onClear: () -> Void

    var body: some View {
        if let latest = store.chats.first {
            Section {
                LatestChatCard(chat: latest, isOpen: isOpen(latest)) { onOpen(latest) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .swipeActions { deleteButton(latest) }
                    .modifier(Entrance(index: 0, appeared: appeared))
            }

            let rest = Array(store.chats.dropFirst())
            if !rest.isEmpty {
                Section {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { index, chat in
                        ChatRow(chat: chat, isOpen: isOpen(chat)) { onOpen(chat) }
                            .swipeActions { deleteButton(chat) }
                            .modifier(Entrance(index: index + 1, appeared: appeared))
                    }
                } header: {
                    SectionTitle(text: "Ранее")
                }
            }

            Section {
                Button(role: .destructive, action: onClear) {
                    Label("Очистить историю", systemImage: "trash")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                EmptyHistory(icon: "bubble.left.and.bubble.right", title: "Пока пусто", subtitle: "Здесь появятся разговоры с часов")
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func isOpen(_ chat: ChatThread) -> Bool {
        chat.id == store.conversationID && !store.messages.isEmpty
    }

    private func deleteButton(_ chat: ChatThread) -> some View {
        Button(role: .destructive) {
            store.deleteChat(chat.id)
        } label: {
            Image(systemName: "trash")
        }
    }
}

struct LatestChatCard: View {
    let chat: ChatThread
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(isOpen ? "Открыт сейчас" : "Последний")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 4)
                    Text(ChatDate.short(chat.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(chat.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !chat.preview.isEmpty {
                    Text(chat.preview)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 4) {
                    Text(ChatDate.messages(chat.messageCount))
                        .monospacedDigit()
                    if chat.isFromGPT {
                        GPTBadge()
                            .padding(.leading, 2)
                    } else if chat.isClaude {
                        ClaudeBadge()
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: 4)
                    Text(isOpen ? "Открыть" : "Продолжить")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .padding(.bottom, 4)
    }
}

struct ChatRow: View {
    let chat: ChatThread
    let isOpen: Bool
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
                    if isOpen {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    }
                    if chat.isFromGPT {
                        GPTBadge()
                    } else if chat.isClaude {
                        ClaudeBadge()
                    }
                    Text(ChatDate.short(chat.updatedAt))
                        .foregroundStyle(isOpen ? Theme.accent : Theme.secondaryText)
                    if !chat.preview.isEmpty {
                        Text("·")
                        Text(chat.preview)
                            .lineLimit(1)
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

struct EmptyHistory: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(.footnote.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
