import SwiftUI
import WatchKit

struct PrivacyView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var consent = AIConsent.shared
    @State private var pendingRevoke: AIConsent.Service?
    @State private var confirmWipe = false
    @State private var showQR = false

    var body: some View {
        List {
            Section {
                Text("WatchGPT не собирает данные и не использует аналитику или рекламу. Чаты, настройки, места и журнал диагностики хранятся только на часах, ключи и токены — в Keychain.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(AIConsent.Service.allCases) { service in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.product)
                                .font(.footnote)
                            Text(consent.isGranted(service) ? "передача разрешена" : "передача запрещена")
                                .font(.caption2)
                                .foregroundStyle(consent.isGranted(service) ? Theme.secondaryText : .orange)
                        }
                        Spacer(minLength: 4)
                        if consent.isGranted(service) {
                            Button("Отозвать") { pendingRevoke = service }
                                .font(.caption2)
                                .foregroundStyle(Theme.danger)
                                .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Сторонний ИИ")
            } footer: {
                Text("Вопросы и голос уходят напрямую в OpenAI или Anthropic. После отзыва согласия WatchGPT отключит этот сервис на часах.")
            }

            Section {
                Link(destination: AIConsent.privacyPolicyURL) {
                    Label("Политика конфиденциальности", systemImage: "lock.shield")
                        .font(.footnote)
                }
                Button {
                    showQR = true
                } label: {
                    Label("Открыть на iPhone", systemImage: "qrcode")
                        .font(.footnote)
                }
                Link(destination: AIConsent.supportURL) {
                    Label("Поддержка", systemImage: "questionmark.bubble")
                        .font(.footnote)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmWipe = true
                } label: {
                    Label("Удалить все данные", systemImage: "trash")
                        .font(.footnote)
                }
            } footer: {
                Text("Удаляет чаты, ключи, токен входа, места и журнал с часов. Историю в аккаунте ChatGPT можно удалить на chatgpt.com.")
            }
        }
        .navigationTitle("Конфиденциальность")
        .confirmationDialog(
            pendingRevoke.map { "Запретить передачу данных в \($0.company)?" } ?? "",
            isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } })
        ) {
            Button("Запретить", role: .destructive) {
                if let service = pendingRevoke { revoke(service) }
                pendingRevoke = nil
            }
            Button("Отмена", role: .cancel) { pendingRevoke = nil }
        } message: {
            Text(pendingRevoke == .openAI ? "Аккаунт ChatGPT будет отключён от часов." : "Ключ Anthropic будет удалён с часов.")
        }
        .confirmationDialog("Удалить все данные WatchGPT с часов?", isPresented: $confirmWipe) {
            Button("Удалить", role: .destructive) { wipe() }
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $showQR) {
            VStack(spacing: 6) {
                QRCodeView(text: AIConsent.privacyPolicyURL.absoluteString)
                    .frame(width: 120, height: 120)
                Text("Сканируйте камерой iPhone")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func revoke(_ service: AIConsent.Service) {
        consent.revoke(service)
        switch service {
        case .openAI:
            auth.clearAPIKey()
            auth.signOut()
        case .anthropic:
            auth.clearClaudeKey()
            if store.provider == .claude {
                store.provider = .chatgpt
                store.publishWidget()
            }
        }
        WKHaptics.click()
    }

    private func wipe() {
        if store.provider == .claude { store.provider = .chatgpt }
        auth.clearClaudeKey()
        auth.clearAPIKey()
        auth.signOut()
        store.signedOut()
        for place in PlaceRelevance.shared.places { PlaceRelevance.shared.remove(place) }
        DiagnosticsLog.shared.clear()
        for service in AIConsent.Service.allCases { consent.revoke(service) }
        WKHaptics.success()
    }
}
