import SwiftUI

struct RefineBar: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            chip(.shorter)
            chip(.longer)
        }
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
