import SwiftUI

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .textCase(nil)
    }
}

struct SpinningIcon: View {
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 10, weight: .bold))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
            }
            .accessibilityLabel("Обновляю")
    }
}

struct GPTBadge: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Из ChatGPT")
    }
}

struct ClaudeBadge: View {
    var body: some View {
        Image(systemName: "asterisk")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.claude)
            .accessibilityLabel("Claude")
    }
}

struct Entrance: ViewModifier {
    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        let delay = Double(min(index, 8)) * 0.03
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .animation(.easeOut(duration: 0.3).delay(delay), value: appeared)
    }
}
