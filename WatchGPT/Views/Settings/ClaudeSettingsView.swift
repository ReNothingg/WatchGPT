import Charts
import SwiftUI

struct ClaudeSettingsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var keyDraft = ""
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                Toggle("Отвечает Claude", isOn: claudeMode)
                    .tint(Theme.claude)
                    .disabled(!auth.hasClaudeKey)
                if store.provider == .claude {
                    NavigationLink(value: Route.models) {
                        HStack {
                            Text("Модель")
                            Spacer()
                            Text(store.claudeModel.displayName)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .font(.footnote)
                    }
                }
            } footer: {
                Text(auth.hasClaudeKey
                     ? "Вопросы уходят в Claude вместо ChatGPT. Голос, история и лимиты ChatGPT остаются как были."
                     : "Сначала добавьте API-ключ Anthropic.")
            }

            Section {
                HStack {
                    Text("API-ключ")
                    Spacer()
                    Text(keyStatus)
                        .foregroundStyle(auth.hasClaudeKey ? Theme.claude : .orange)
                }
                .font(.footnote)

                if let key = auth.claudeKey?.key {
                    Text("\(key.prefix(10))…\(key.suffix(4)) · \(key.count) симв.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    KeyCheckRow(check: auth.claudeKeyCheck) { await auth.verifyClaudeKey() }
                }

                TextField("Вставить ключ sk-ant-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: keyDraft) { _, value in
                        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        auth.setManualClaudeKey(value)
                        keyDraft = ""
                    }

                if auth.hasClaudeKey {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Удалить ключ", systemImage: "trash")
                    }
                }
            } header: {
                Text("Anthropic")
            } footer: {
                Text("Ключ создаётся на console.anthropic.com → API Keys. Вставьте его в поле выше, он хранится только в Keychain часов. Ответы оплачиваются с API-баланса Anthropic, а не подпиской Claude Pro или Max. Дешевле всего Haiku, дороже Opus и Fable; поиск в интернете — около $10 за 1000 запросов. Режим Fast есть у Opus 5.5, Opus 5 и Opus 4.8: отвечает заметно быстрее, но стоит вдвое дороже.")
            }
        }
        .navigationTitle("Claude")
        .confirmationDialog("Удалить ключ Anthropic?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { auth.clearClaudeKey() }
            Button("Отмена", role: .cancel) {}
        }
        .task {
            if auth.hasClaudeKey, auth.claudeKeyCheck == .unknown { await auth.verifyClaudeKey() }
        }
    }

    private var claudeMode: Binding<Bool> {
        Binding(
            get: { store.provider == .claude },
            set: { on in
                store.provider = on ? .claude : .chatgpt
                store.publishWidget()
                WKHaptics.click()
            }
        )
    }

    private var keyStatus: String {
        guard let key = auth.claudeKey else { return "нет" }
        return key.isManual ? "свой" : "из аккаунта"
    }
}
