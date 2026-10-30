import SwiftUI

enum HistorySource: String, CaseIterable, Identifiable {
    case watch, gpt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpt: return "ChatGPT"
        case .watch: return "На часах"
        }
    }

    var icon: String {
        switch self {
        case .gpt: return "sparkles"
        case .watch: return "applewatch"
        }
    }
}

struct HistoryView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("history.source") private var source: HistorySource = .watch
    @State private var confirmClear = false
    @State private var appeared = false

    var body: some View {
        List {
            Section {
                HistorySourcePicker(source: $source, loading: store.gptHistory.isLoading) { item in
                    if item == .gpt { Task { await store.gptHistory.refresh(force: true) } }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch source {
            case .watch:
                WatchHistorySections(appeared: appeared, onOpen: open) { confirmClear = true }
            case .gpt:
                GPTHistorySections(appeared: appeared)
            }
        }
        .listSectionSpacing(6)
        .animation(.snappy(duration: 0.3), value: store.chats.map(\.id))
        .animation(.snappy(duration: 0.3), value: store.gptHistory.chats.map(\.id))
        .navigationTitle(source == .gpt ? "ChatGPT" : "Чаты")
        .confirmationDialog("Удалить все чаты на часах?", isPresented: $confirmClear) {
            Button("Удалить", role: .destructive) {
                store.deleteAllChats()
                WKHaptics.click()
            }
            Button("Отмена", role: .cancel) {}
        }
        .task(id: source) {
            if source == .gpt { await store.gptHistory.refresh() }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }
        }
        .onChange(of: source) { _, _ in
            appeared = false
            Task { @MainActor in
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }
            }
        }
    }

    private func open(_ chat: ChatThread) {
        WKHaptics.click()
        store.openChat(chat.id)
        dismiss()
    }
}

private struct HistorySourcePicker: View {
    @Binding var source: HistorySource
    let loading: Bool
    let onTap: (HistorySource) -> Void
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HistorySource.allCases) { item in
                let selected = item == source
                Button {
                    WKHaptics.click()
                    if !selected {
                        withAnimation(.easeOut(duration: 0.25)) { source = item }
                    }
                    onTap(item)
                } label: {
                    HStack(spacing: 4) {
                        if item == .gpt && loading {
                            SpinningIcon()
                        }
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Color.white : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.track)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .gpt ? "История ChatGPT" : "История на часах")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.surface))
    }
}

private struct WatchHistorySections: View {
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

private struct GPTHistorySections: View {
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

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .textCase(nil)
    }
}

private struct SpinningIcon: View {
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 10, weight: .bold))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
            }
            .accessibilityLabel("Обновляю")
    }
}

private struct GPTChatRow: View {
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

private struct GPTBadge: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Из ChatGPT")
    }
}

private struct ClaudeBadge: View {
    var body: some View {
        Image(systemName: "asterisk")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.claude)
            .accessibilityLabel("Claude")
    }
}

private struct Entrance: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        let delay = Double(min(index, 8)) * 0.03
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .animation(.easeOut(duration: 0.3).delay(delay), value: appeared)
    }
}

private struct LatestChatCard: View {
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

private struct ChatRow: View {
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

private struct EmptyHistory: View {
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

enum ChatDate {
    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return weekday.prefix(1).uppercased() + weekday.dropFirst()
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func messages(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "сообщение"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "сообщения"
        } else {
            word = "сообщений"
        }
        return "\(count) \(word)"
    }
}
