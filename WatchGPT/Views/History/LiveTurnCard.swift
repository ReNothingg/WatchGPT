import SwiftUI

struct LiveTurnCard: View {
    let live: LiveTurn
    var failed = false
    @State private var expanded = false

    private var steps: [ReasoningStep] { live.reasoning.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if failed {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Ответ прервался")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                ThinkingHeader(expandable: steps.count > 1, expanded: $expanded) {
                    ShimmerText(text: live.stage, font: .footnote)
                        .id(live.stage)
                        .transition(.opacity)
                    Text("·")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text(timerInterval: live.startedAt...Date.distantFuture, countsDown: false)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
                .animation(.smooth(duration: 0.3), value: live.stage)
            }

            if expanded {
                ReasoningSteps(steps: steps)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            } else if let last = steps.last {
                ReasoningSteps(steps: [last], collapsedLines: 3)
                    .id(last.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.35), value: steps.last?.id)
        .accessibilityElement(children: .combine)
    }
}
