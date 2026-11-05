import SwiftUI

struct HomeView: View {
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = 34
            let gap: CGFloat = 10
            let mic = min(84, max(56, geo.size.height - 82), geo.size.width - 2 * (side + gap) - 8)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: gap) {
                    HomeSideButton(icon: "clock.arrow.circlepath", route: .history, label: "История", size: side)
                        .offset(x: appeared ? 0 : 24)
                        .opacity(appeared ? 1 : 0)
                    AskButton(size: mic, halo: true)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)
                    HomeSideButton(icon: "gearshape", route: .settings, label: "Настройки", size: side)
                        .offset(x: appeared ? 0 : -24)
                        .opacity(appeared ? 1 : 0)
                }
                Spacer(minLength: 8)
                ModelCard(crownControlsEffort: true)
                    .offset(y: appeared ? 0 : 30)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
        }
    }
}

struct HomeSideButton: View {
    let icon: String
    let route: Route
    let label: String
    let size: CGFloat

    var body: some View {
        NavigationLink(value: route) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .glassBackground(Circle(), fill: Theme.raised, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
