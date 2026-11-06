import SwiftUI

struct RefineBar: View {
    @Environment(ChatStore.self) private var store
    @State private var confirmReport = false
    @State private var showReported = false

    var body: some View {
        HStack(spacing: 6) {
            chip(.shorter)
            chip(.longer)
            SmallCircleButton(icon: "flag", label: "Пожаловаться на ответ") {
                confirmReport = true
            }
        }
        .glassGroup(spacing: 6)
        .confirmationDialog("Пожаловаться на ответ?", isPresented: $confirmReport) {
            Button("Скрыть ответ", role: .destructive) { report() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Ответ будет скрыт на часах, а затем можно написать в поддержку.")
        }
        .sheet(isPresented: $showReported) {
            ReportSheet()
        }
    }

    private func report() {
        guard let answer = store.messages.last, answer.role == .assistant else { return }
        store.reportAnswer(answer.id)
        WKHaptics.success()
        showReported = true
    }

    private func chip(_ kind: ChatMessage.Refinement) -> some View {
        Button {
            WKHaptics.click()
            store.refine(kind)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(kind.label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .glassBackground(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(kind == .shorter ? "Ответить короче" : "Ответить подробнее")
    }
}

private struct ReportSheet: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("Ответ скрыт")
                    .font(.footnote.weight(.semibold))
                Text("Если ответ был оскорбительным или опасным, напишите в поддержку: мы разберёмся и ответим.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                QRCodeView(text: AIConsent.supportURL.absoluteString)
                    .frame(width: 96, height: 96)
                Link(destination: AIConsent.supportURL) {
                    Label("Написать в поддержку", systemImage: "envelope")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
    }
}
