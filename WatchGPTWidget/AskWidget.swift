import SwiftUI
import WidgetKit

struct AskEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var remaining: Double? { snapshot.usage?.tightest(at: date)?.remainingPercent(at: date) }
    var window: UsageWindow? { snapshot.usage?.tightest(at: date) }

    static func timeline(for snapshot: WidgetSnapshot, now: Date = .now) -> Timeline<AskEntry> {
        var dates = [now]
        for window in [snapshot.usage?.primary, snapshot.usage?.secondary].compactMap({ $0 }) {
            if let reset = window.resetAt, reset > now, reset < now.addingTimeInterval(8 * 24 * 3600) {
                dates.append(reset.addingTimeInterval(1))
            }
        }
        return Timeline(entries: dates.sorted().map { AskEntry(date: $0, snapshot: snapshot) }, policy: .never)
    }
}

struct AskProvider: TimelineProvider {
    func placeholder(in context: Context) -> AskEntry {
        AskEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (AskEntry) -> Void) {
        let snap = SharedStore.load()
        completion(AskEntry(date: .now, snapshot: context.isPreview && snap.usage == nil ? .preview : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AskEntry>) -> Void) {
        completion(AskEntry.timeline(for: SharedStore.load()))
    }
}

struct AskIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AskEntry {
        AskEntry(date: .now, snapshot: .preview)
    }

    func snapshot(for configuration: AskWidgetIntent, in context: Context) async -> AskEntry {
        let snap = SharedStore.load()
        return AskEntry(date: .now, snapshot: context.isPreview && snap.usage == nil ? .preview : snap)
    }

    func timeline(for configuration: AskWidgetIntent, in context: Context) async -> Timeline<AskEntry> {
        AskEntry.timeline(for: SharedStore.load())
    }

    func recommendations() -> [AppIntentRecommendation<AskWidgetIntent>] {
        [AppIntentRecommendation(intent: AskWidgetIntent(), description: "Спросить ChatGPT")]
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        signedIn: true,
        usage: UsageSnapshot(
            primary: UsageWindow(usedPercent: 18, windowMinutes: 300, resetAt: .now.addingTimeInterval(7200)),
            secondary: UsageWindow(usedPercent: 36, windowMinutes: 10080, resetAt: .now.addingTimeInterval(3 * 86400)),
            planType: "plus"
        )
    )
}

struct AskWidget: Widget {
    let kind = SharedStore.askWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AskWidgetIntent.self, provider: AskIntentProvider()) { entry in
            AskWidgetView(entry: entry)
                .widgetURL(SharedStore.deepLinkAsk)
        }
        .configurationDisplayName("Спросить ChatGPT")
        .description("Нажмите и сразу диктуйте вопрос. Показывает остаток лимита.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct AskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AskEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var rectangular: some View {
        let usage = entry.snapshot.usage
        let rings = [usage?.primary, usage?.secondary].compactMap { $0 }.prefix(2).enumerated().map { index, window in
            ActivityRing(fraction: window.remainingPercent(at: entry.date) / 100, color: RingPalette.color(index, window.remainingPercent(at: entry.date)))
        }

        return HStack(spacing: 10) {
            ActivityRings(rings: Array(rings), placeholderCount: entry.snapshot.signedIn ? 1 : 2)
                .frame(width: 58, height: 58)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 0) {
                if !entry.snapshot.signedIn {
                    StatLine(value: "ChatGPT", unit: nil, color: RingPalette.mint)
                    StatLine(value: "Войдите", unit: nil, color: RingPalette.cyan)
                } else if usage?.primary == nil && usage?.secondary == nil {
                    StatLine(value: "ChatGPT", unit: nil, color: RingPalette.mint)
                } else {
                    ForEach(Array([usage?.primary, usage?.secondary].compactMap { $0 }.prefix(2).enumerated()), id: \.offset) { index, window in
                        let left = window.remainingPercent(at: entry.date)
                        StatLine(value: Theme.percent(left), unit: window.shortLabel, color: RingPalette.color(index, left))
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Спросить")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(RingPalette.violet)
                .widgetAccentable()
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    private var circular: some View {
        Group {
            if let left = entry.remaining {
                Gauge(value: left, in: 0...100) {
                    Image(systemName: "mic.fill")
                } currentValueLabel: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.usageColor(left))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }

    private var corner: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 20, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                if let left = entry.remaining {
                    Gauge(value: left, in: 0...100) {
                        Text("GPT")
                    } currentValueLabel: {
                        Text(Theme.percent(left))
                    }
                    .tint(Theme.usageColor(left))
                } else {
                    Text("ChatGPT")
                }
            }
            .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Group {
            if let left = entry.remaining {
                Label("ChatGPT · \(Theme.percent(left))", systemImage: "mic.fill")
            } else {
                Label("Спросить ChatGPT", systemImage: "mic.fill")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
