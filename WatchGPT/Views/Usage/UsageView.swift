import Charts
import SwiftUI

struct UsageView: View {
    @Environment(ChatStore.self) private var store
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let usage = store.usage, usage.primary != nil || usage.secondary != nil {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                if let w = usage.primary { WindowGauge(window: w, now: context.date) }
                                if let w = usage.secondary { WindowGauge(window: w, now: context.date) }
                            }
                            VStack(spacing: 3) {
                                if let w = usage.primary { resetLine(w, now: context.date) }
                                if let w = usage.secondary { resetLine(w, now: context.date) }
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                    if let window = usage.secondary ?? usage.primary {
                        UsageHistoryChart(
                            days: store.usageHistory.recent(7),
                            weekly: usage.secondary != nil,
                            windowLabel: window.longLabel
                        )
                    }
                    if let plan = usage.planLabel {
                        Text("ChatGPT \(plan)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let error = store.usageError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView().padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .navigationTitle("Лимиты")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        refreshing = true
                        await store.refreshUsage()
                        refreshing = false
                    }
                } label: {
                    if refreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white)
                    }
                }
                .disabled(refreshing)
                .accessibilityLabel("Обновить")
            }
        }
        .tint(Theme.control)
        .task { await store.refreshUsage() }
    }

    private func resetLine(_ window: UsageWindow, now: Date) -> some View {
        HStack {
            Text(window.longLabel)
            Spacer()
            if let reset = window.resetAt, reset > now {
                Text("сброс \(reset.formatted(.relative(presentation: .numeric)))")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("сброшен").foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct WindowGauge: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        let left = window.remainingPercent(at: now)
        VStack(spacing: 4) {
            ZStack {
                UsageRing(remaining: left, lineWidth: 6, showsText: false)
                Text(Theme.percent(left))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 70, height: 70)
            Text(window.shortLabel)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.longLabel): осталось \(Theme.percent(left))")
    }
}
