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

struct HistorySourcePicker: View {
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
