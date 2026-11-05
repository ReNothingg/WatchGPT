import SwiftUI
import WatchKit

struct ClientVersionView: View {
    @Environment(ChatStore.self) private var store
    @State private var draft = ""
    @State private var checking = false
    @State private var status: String?
    @State private var revision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ClientVersion.current)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text(ClientVersion.source.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    if let last = ClientVersion.lastCheck {
                        Text("Проверено \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .id(revision)

                Button {
                    Task { await check() }
                } label: {
                    HStack(spacing: 6) {
                        if checking {
                            Spinner(size: 12, lineWidth: 2)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Проверить GitHub")
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                }
                .disabled(checking)

                if let status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }

                TextField("Своя версия, напр. 0.170.0", text: $draft)
                    .font(.footnote)
                    .onSubmit { applyManual() }

                if ClientVersion.manual != nil {
                    Button(role: .destructive) {
                        ClientVersion.setManual(nil)
                        status = "Своя версия сброшена."
                        changed()
                    } label: {
                        Text("Сбросить свою версию")
                            .font(.footnote)
                            .frame(maxWidth: .infinity)
                    }
                }

                Text("Сервер ChatGPT иногда перестаёт пускать старые версии Codex. Приложение раз в сутки и после такой ошибки само берёт номер последнего релиза openai/codex с GitHub.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .navigationTitle("Codex")
    }

    private func check() async {
        checking = true
        defer { checking = false }
        switch await ClientVersion.refresh(minInterval: 0) {
        case let .updated(version):
            status = "Обновлено до \(version)."
            WKHaptics.success()
            changed()
        case .upToDate:
            status = ClientVersion.manual != nil
                ? "На GitHub \(ClientVersion.fetched ?? ClientVersion.bundled), но используется своя версия."
                : "Уже последняя версия."
            revision += 1
        case .failed, .skipped:
            status = "Не удалось связаться с GitHub."
            revision += 1
        }
    }

    private func applyManual() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if ClientVersion.setManual(text) {
            draft = ""
            status = "Используется \(ClientVersion.current)."
            WKHaptics.success()
            changed()
        } else {
            status = "Нужен номер вида 0.170.0."
        }
    }

    private func changed() {
        revision += 1
        Task { await store.refreshModels() }
    }
}
