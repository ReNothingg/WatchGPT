import SwiftUI
import WatchKit

struct ConsentView: View {
    let service: AIConsent.Service
    var onAccept: () -> Void
    @State private var declined = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.title3)
                    .foregroundStyle(service == .anthropic ? Theme.claude : Theme.accent)
                    .frame(maxWidth: .infinity)

                Text("Передача данных в \(service.company)")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Text("Ответы готовит сторонний ИИ-сервис \(service.product) компании \(service.company). Чтобы он ответил, WatchGPT отправит ему:")
                    .font(.caption2)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(service.sharedData, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("•")
                            Text(item)
                        }
                    }
                }
                .font(.caption2)

                Text("Данные уходят напрямую с часов в \(service.company) и обрабатываются по её политике конфиденциальности. Разработчик WatchGPT их не получает. Согласие можно отозвать: Настройки → Конфиденциальность.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)

                Link(destination: service.policyURL) {
                    Label("Политика \(service.company)", systemImage: "doc.text")
                        .font(.caption2)
                }
                Link(destination: AIConsent.privacyPolicyURL) {
                    Label("Политика WatchGPT", systemImage: "lock.shield")
                        .font(.caption2)
                }

                Button {
                    AIConsent.shared.grant(service)
                    WKHaptics.success()
                    onAccept()
                } label: {
                    Text("Разрешаю")
                        .frame(maxWidth: .infinity)
                }
                .tint(service == .anthropic ? Theme.claude : Theme.accent)
                .padding(.top, 4)

                Button {
                    declined = true
                } label: {
                    Text("Не разрешаю")
                        .frame(maxWidth: .infinity)
                }

                if declined {
                    Text("Без согласия \(service.product) недоступен: вопросы не будут отправляться. Решение можно изменить в любой момент.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle("Данные")
    }
}
