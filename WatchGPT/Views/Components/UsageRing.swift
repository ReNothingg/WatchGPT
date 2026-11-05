import SwiftUI

struct UsageRing: View {
    var remaining: Double?
    var lineWidth: CGFloat = 3
    var showsText = true
    var textSize: CGFloat = 11
    var showsPercentSign = false

    var body: some View {
        let value = remaining ?? 0
        let color = remaining.map(Theme.usageColor) ?? .gray
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, value / 100))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsText {
                label
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .monospacedDigit()
                    .padding(lineWidth + 1)
            }
        }
        .animation(.easeInOut, value: value)
    }

    private var label: Text {
        let font = Font.system(size: textSize, weight: .semibold, design: .rounded)
        guard let remaining else { return Text("–").font(font) }
        let number = Text("\(Int(remaining.rounded()))").font(font)
        guard showsPercentSign else { return number }
        return number + Text("%").font(.system(size: textSize * 0.7, weight: .semibold, design: .rounded))
    }
}

struct UsageLine: View {
    let usage: UsageSnapshot?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 10) {
                if let usage, usage.primary != nil || usage.secondary != nil {
                    ForEach(Array([usage.primary, usage.secondary].compactMap { $0 }.enumerated()), id: \.offset) { _, window in
                        let left = window.remainingPercent(at: context.date)
                        HStack(spacing: 3) {
                            Circle().fill(Theme.usageColor(left)).frame(width: 6, height: 6)
                            Text(Theme.percent(left)).monospacedDigit()
                            Text(window.shortLabel).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Лимиты загружаются…").foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }
}
