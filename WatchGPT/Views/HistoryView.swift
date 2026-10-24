import SwiftUI

struct HistoryView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var appeared = false

    var body: some View {
        Group {
            if let latest = store.chats.first {
                List {
                    Section {
                        LatestChatCard(chat: latest, isOpen: isOpen(latest)) { open(latest) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .swipeActions { deleteButton(latest) }
                            .modifier(Entrance(index: 0, appeared: appeared))
                    }

                    let rest = Array(store.chats.dropFirst())
                    if !rest.isEmpty {
                        Section {
                            ForEach(Array(rest.enumerated()), id: \.element.id) { index, chat in
                                ChatRow(chat: chat, isOpen: isOpen(chat)) { open(chat) }
                                    .swipeActions { deleteButton(chat) }
                                    .modifier(Entrance(index: index + 1, appeared: appeared))
                            }
                        } header: {
                            Text("Ранее")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                                .textCase(nil)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Очистить историю", systemImage: "trash")
                                .font(.footnote)
                                .foregroundStyle(Theme.danger)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .animation(.snappy(duration: 0.3), value: store.chats.map(\.id))
            } else {
                EmptyHistory()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .navigationTitle("Чаты")
        .animation(.smooth(duration: 0.35), value: store.chats.isEmpty)
        .confirmationDialog("Удалить все чаты?", isPresented: $confirmClear) {
            Button("Удалить", role: .destructive) {
                store.deleteAllChats()
                WKHaptics.click()
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true }
        }
    }

    private func isOpen(_ chat: ChatThread) -> Bool {
        chat.id == store.conversationID && !store.messages.isEmpty
    }

    private func open(_ chat: ChatThread) {
        WKHaptics.click()
        store.openChat(chat.id)
        dismiss()
    }

    private func deleteButton(_ chat: ChatThread) -> some View {
        Button(role: .destructive) {
            store.deleteChat(chat.id)
        } label: {
            Image(systemName: "trash")
        }
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
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
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
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active)) { context in
            let p = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
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
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: pulse)
            Text("Пока пусто")
                .font(.headline)
            Text("Здесь появятся ваши разговоры")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
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
