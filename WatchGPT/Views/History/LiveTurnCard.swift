import SwiftUI

struct LiveTurnCard: View {
    @Environment(ChatStore.self) private var store
    @State private var showingDetails = false
    let live: LiveTurn
    var failed = false

    var body: some View {
        ReasoningDisclosure(
            title: failed ? String(localized: "Ответ прервался") : live.stage,
            icon: failed ? "exclamationmark.triangle.fill" : live.icon,
            steps: live.reasoning.steps,
            fontScale: store.answerFontScale,
            showsLatest: true,
            isActive: !failed,
            startedAt: failed ? nil : min(live.startedAt, .now)
        ) {
            showingDetails = true
        }
        .sheet(isPresented: $showingDetails) {
            ReasoningReader(steps: live.reasoning.steps, fontScale: store.answerFontScale, isActive: !failed)
        }
    }
}
