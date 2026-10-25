import SwiftUI

enum HistorySource: String, CaseIterable, Identifiable {
    case gpt, watch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpt: return "ChatGPT"
        case .watch: return "Часы"
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
                HistorySourcePicker(source: $source)
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
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistorySource.allCases) { item in
                let selected = item == source
                Button {
                    guard !selected else { return }
                    WKHaptics.click()
                    withAnimation(.snappy(duration: 0.3)) { source = item }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Color.black : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accent)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityLabel(item == .gpt ? "История ChatGPT" : "История на часах")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .padding(.bottom, 4)
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

            Section {
                ForEach(Array(history.chats.enumerated()), id: \.element.id) { index, chat in
                    GPTChatRow(chat: chat, hasCopy: store.hasLocalCopy(ofGPTChat: chat.id)) {
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
            } header: {
                SyncHeader(syncedAt: history.syncedAt, loading: history.isLoading)
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
                Text("Чаты из вашего аккаунта ChatGPT. Продолжение на часах сохраняется только на часах.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
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

private struct SyncHeader: View {
    let syncedAt: Date?
    let loading: Bool

    var body: some View {
        HStack(spacing: 5) {
            if loading {
                Spinner(size: 9, lineWidth: 1.5)
                SectionTitle(text: "Обновляю…")
            } else if let syncedAt {
                SectionTitle(text: "Обновлено \(ChatDate.short(syncedAt).lowercased())")
            } else {
                SectionTitle(text: "Чаты ChatGPT")
            }
        }
        .animation(.snappy(duration: 0.25), value: loading)
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

private struct Entrance: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        let delay = Double(min(index, 8)) * 0.045
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .scaleEffect(appeared ? 1 : 0.94)
            .animation(.spring(duration: 0.5, bounce: 0.28).delay(delay), value: appeared)
    }
}

private struct LatestChatCard: View {
    let chat: ChatThread
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    LiveDot(active: isOpen)
                    Text(isOpen ? "Открыт сейчас" : "Последний")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer(minLength: 4)
                    Text(ChatDate.short(chat.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }

                Text(chat.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if !chat.preview.isEmpty {
                    Text(chat.preview)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(chat.messageCount)")
                        .monospacedDigit()
                    if chat.isFromGPT {
                        GPTBadge()
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: 4)
                    Text(isOpen ? "Открыть" : "Продолжить")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(ChatDate.messages(chat.messageCount))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground())
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .padding(.bottom, 6)
    }
}

private struct CardBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        LiveTimeline(role: .decorative, fps: 20, idleAfter: .seconds(8)) { date in
            let t = date.timeIntervalSinceReferenceDate
            let x = 0.5 + 0.5 * cos(t * 0.5)
            let y = 0.5 * sin(t * 0.4)
            shape
                .fill(Theme.surface)
                .overlay(
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.38), Theme.accent.opacity(0.0)],
                        center: UnitPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: 150
                    )
                    .clipShape(shape)
                )
                .overlay(
                    shape.strokeBorder(
                        AngularGradient(
                            colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.1), Theme.accent.opacity(0.6), Theme.accent.opacity(0.1), Theme.accent.opacity(0.9)],
                            center: .center,
                            angle: .radians(t * 0.8)
                        ),
                        lineWidth: 1.2
                    )
                )
        }
    }
}

private struct LiveDot: View {
    let active: Bool

    var body: some View {
        LiveTimeline(role: .status, fps: 20, isActive: active) { date in
            let p = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                if active {
                    Circle()
                        .stroke(Theme.accent.opacity(0.7 * (1 - p)), lineWidth: 1)
                        .scaleEffect(1 + p * 1.4)
                }
                Circle().fill(Theme.accent)
            }
            .frame(width: 6, height: 6)
        }
        .frame(width: 10, height: 10)
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
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: pulse)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .onAppear { pulse.toggle() }
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
