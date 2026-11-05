import SwiftUI
import WidgetKit

struct LimitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.limitsWidgetKind, provider: AskProvider()) { entry in
            LimitsWidgetView(entry: entry)
                .widgetURL(SharedStore.deepLinkUsage)
        }
        .configurationDisplayName("Лимиты ChatGPT")
        .description("Сколько осталось в 5-часовом и недельном окне и когда сброс.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner])
    }
}

struct LimitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AskEntry

    private var windows: [UsageWindow] {
        [entry.snapshot.usage?.primary, entry.snapshot.usage?.secondary].compactMap { $0 }
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("Лимиты")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(RingPalette.mint)
                    .widgetAccentable()
                Spacer(minLength: 4)
                if let reset = entry.window?.resetAt, reset > entry.date {
                    Label(resetText(reset), systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if windows.isEmpty {
                Text(entry.snapshot.signedIn ? "Откройте приложение, чтобы загрузить лимиты" : "Войдите в приложении")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                ForEach(Array(windows.prefix(2).enumerated()), id: \.offset) { index, window in
                    let left = window.remainingPercent(at: entry.date)
                    HStack(spacing: 6) {
                        Text(window.shortLabel)
                            .frame(width: 30, alignment: .leading)
                        Gauge(value: left, in: 0...100) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(RingPalette.color(index, left))
                        Text(Theme.percent(left))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    private var circular: some View {
        Group {
            if let window = entry.window {
                let left = window.remainingPercent(at: entry.date)
                Gauge(value: left, in: 0...100) {
                    Text(window.shortLabel)
                } currentValueLabel: {
                    Text("\(Int(left.rounded()))")
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Theme.usageColor(left))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }

    private var corner: some View {
        Text(entry.remaining.map { Theme.percent($0) } ?? "–")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .widgetCurvesContent()
            .widgetAccentable()
            .widgetLabel {
                if let window = entry.window, let left = entry.remaining {
                    Gauge(value: left, in: 0...100) {
                        Text(window.shortLabel)
                    }
                    .tint(Theme.usageColor(left))
                } else {
                    Text("Лимиты")
                }
            }
            .containerBackground(for: .widget) { Color.clear }
    }

    private func resetText(_ date: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: entry.date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
