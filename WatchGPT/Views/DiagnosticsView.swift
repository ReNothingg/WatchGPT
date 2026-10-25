import SwiftUI
import WatchKit

struct DiagnosticsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var check: CheckState = .idle
    @State private var confirmClear = false

    private var log: DiagnosticsLog { DiagnosticsLog.shared }

    enum CheckState: Equatable {
        case idle
        case running
        case ok(Int)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                checkCard
                infoCard
                errorsSection
                ShareLink(item: report()) {
                    Label("Отправить отчёт", systemImage: "square.and.arrow.up")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .tint(Theme.control)
                if !log.entries.isEmpty {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Text("Очистить журнал")
                            .font(.footnote)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .navigationTitle("Диагностика")
        .confirmationDialog("Очистить журнал ошибок?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { log.clear() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var checkCard: some View {
        Button {
            Task { await runCheck() }
        } label: {
            HStack(spacing: 8) {
                Group {
                    switch check {
                    case .idle:
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Theme.accent)
                    case .running:
                        Spinner(size: 14, lineWidth: 2)
                    case .ok:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    case .failed:
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(Theme.danger)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Проверить связь")
                        .font(.footnote.weight(.medium))
                    Text(checkSubtitle)
                        .font(.caption2)
                        .foregroundStyle(checkSubtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(check == .running || !auth.isSignedIn)
    }

    private var checkSubtitle: String {
        switch check {
        case .idle: return "Запрос лимитов к серверу ChatGPT"
        case .running: return "Проверяю…"
        case let .ok(ms): return "Сервер отвечает · \(ms) мс"
        case let .failed(message): return message
        }
    }

    private var checkSubtitleColor: Color {
        if case .failed = check { return .orange }
        return Theme.secondaryText
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(infoRows().enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(Theme.raised).frame(height: 1).padding(.leading, 12)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 4)
                    Text(row.value)
                        .font(.caption2.weight(.medium))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    @ViewBuilder
    private var errorsSection: some View {
        Text(log.entries.isEmpty ? "Ошибок нет" : "Последние ошибки")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.leading, 6)
            .padding(.top, 4)
        ForEach(log.entries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.source.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(entry.date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Text(entry.message)
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }

    private struct InfoRow {
        var title: String
        var value: String
    }

    private func infoRows() -> [InfoRow] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let device = WKInterfaceDevice.current()
        var rows = [
            InfoRow(title: "Приложение", value: "\(version) (\(build))"),
            InfoRow(title: "watchOS", value: device.systemVersion),
            InfoRow(title: "Codex client", value: ChatGPTClient.clientVersion),
            InfoRow(title: "Модель", value: store.selectedModelSlug),
            InfoRow(title: "Последний ответ", value: log.lastSuccess.map { $0.formatted(.relative(presentation: .named)) } ?? "—"),
        ]
        if let tokens = auth.tokens {
            rows.append(InfoRow(title: "Тариф", value: store.usage?.planLabel ?? tokens.planType?.capitalized ?? "—"))
            if let expiry = tokens.accessTokenExpiry {
                let value = expiry > .now ? "до \(expiry.formatted(date: .abbreviated, time: .shortened))" : "истёк, обновится сам"
                rows.append(InfoRow(title: "Токен", value: value))
            }
            rows.append(InfoRow(title: "Обновлён", value: tokens.lastRefresh.formatted(.relative(presentation: .named))))
        } else {
            rows.append(InfoRow(title: "Аккаунт", value: "не подключён"))
        }
        let key: String
        if let apiKey = auth.apiKey { key = apiKey.isManual ? "свой" : "из входа" } else { key = "нет" }
        rows.append(InfoRow(title: "API-ключ", value: key))
        rows.append(InfoRow(title: "Энергосбережение", value: PowerMonitor.shared.isLowPower ? "вкл" : "выкл"))
        return rows
    }

    private func report() -> String {
        var lines = ["WatchGPT — диагностика", "Создан: \(Date.now.formatted(date: .abbreviated, time: .standard))", ""]
        lines += infoRows().map { "\($0.title): \($0.value)" }
        lines.append("")
        if log.entries.isEmpty {
            lines.append("Ошибок нет.")
        } else {
            lines.append("Ошибки:")
            for entry in log.entries {
                let time = entry.date.formatted(date: .abbreviated, time: .standard)
                let detail = entry.detail.map { " [\($0)]" } ?? ""
                lines.append("• \(time) · \(entry.source.rawValue): \(entry.message)\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func runCheck() async {
        check = .running
        let started = ContinuousClock.now
        do {
            let tokens = try await auth.validTokens()
            _ = try await ChatGPTClient(tokens: tokens).fetchUsage()
            let elapsed = ContinuousClock.now - started
            let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            check = .ok(ms)
            WKHaptics.success()
        } catch {
            DiagnosticsLog.shared.record(.check, error)
            check = .failed(ChatStore.describe(error))
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
