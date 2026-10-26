import SwiftUI

struct QuickPromptsView: View {
    @Environment(ChatStore.self) private var store
    @State private var adding = false

    var body: some View {
        List {
            if store.quickPrompts.isEmpty {
                Section {
                    Text("Добавьте вопросы, которые задаёте чаще всего.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(store.quickPrompts) { prompt in
                        Button {
                            WKHaptics.click()
                            store.runQuickPrompt(prompt)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: prompt.asksVoice ? "mic.fill" : "paperplane.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 16)
                                Text(prompt.text)
                                    .font(.footnote)
                                    .lineLimit(2)
                            }
                        }
                        .disabled(store.isBusy)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.quickPrompts.removeAll { $0.id == prompt.id }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .accessibilityLabel(prompt.asksVoice ? "\(prompt.text), затем продиктовать" : prompt.text)
                    }
                    .onMove { store.quickPrompts.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Section {
                if store.quickPrompts.count < QuickPrompt.limit {
                    Button {
                        adding = true
                    } label: {
                        Label("Добавить", systemImage: "plus")
                            .font(.footnote)
                    }
                }
            } footer: {
                Text("🎙 — после нажатия продиктуйте продолжение. Смахните влево, чтобы удалить.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Быстрые")
        .sheet(isPresented: $adding) {
            AddQuickPromptView { store.quickPrompts.append($0) }
        }
    }
}

private struct AddQuickPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var asksVoice = true
    let onSave: (QuickPrompt) -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TextField("Например: переведи на английский", text: $text)
                    .font(.footnote)
                Toggle(isOn: $asksVoice) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Дописать голосом")
                            .font(.footnote)
                        Text(asksVoice ? "Откроется диктовка" : "Отправится сразу")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .tint(Theme.accent)
                Button {
                    onSave(QuickPrompt(text: trimmed, asksVoice: asksVoice))
                    WKHaptics.success()
                    dismiss()
                } label: {
                    Text("Сохранить")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Theme.accent)
                .disabled(trimmed.isEmpty)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Новый")
    }
}
