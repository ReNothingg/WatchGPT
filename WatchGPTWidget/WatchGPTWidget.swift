import SwiftUI
import WidgetKit

@main
struct WatchGPTWidgets: WidgetBundle {
    var body: some Widget {
        AskWidget()
        AnswerWidget()
        LimitsWidget()
        if #available(watchOS 26.0, *) {
            AskControl()
        }
    }
}

@available(watchOS 26.0, *)
struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "WatchGPTAskControl") {
            ControlWidgetButton(action: AskChatGPTIntent()) {
                Label("Спросить ChatGPT", systemImage: "mic.fill")
            }
            .tint(Theme.accent)
        }
        .displayName("Спросить ChatGPT")
        .description("Открывает WatchGPT и сразу включает диктовку.")
    }
}

// MARK: Timeline

struct AskEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var remaining: Double? { snapshot.usage?.tightest(at: date)?.remainingPercent(at: date) }
    var window: UsageWindow? { snapshot.usage?.tightest(at: date) }
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
        let snapshot = SharedStore.load()
        let now = Date.now
        var dates = [now]
        // Add an entry at each upcoming limit reset so the widget shows 100% on time.
        for window in [snapshot.usage?.primary, snapshot.usage?.secondary].compactMap({ $0 }) {
            if let reset = window.resetAt, reset > now, reset < now.addingTimeInterval(8 * 24 * 3600) {
                dates.append(reset.addingTimeInterval(1))
            }
        }
        let entries = dates.sorted().map { AskEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
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

// MARK: Widget

struct AskWidget: Widget {
    let kind = SharedStore.askWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AskProvider()) { entry in
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

enum RingPalette {
    static let mint = Color(red: 0.24, green: 0.92, blue: 0.68)
    static let cyan = Color(red: 0.30, green: 0.86, blue: 0.96)
    static let violet = Color(red: 0.70, green: 0.60, blue: 1.0)

    static func color(_ index: Int, _ remaining: Double) -> Color {
        if remaining < 20 { return Theme.usageColor(remaining) }
        return index == 0 ? mint : cyan
    }
}

struct ActivityRing {
    let fraction: Double
    let color: Color
}

private struct ActivityRings: View {
    let rings: [ActivityRing]
    var placeholderCount: Int = 1

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let items = rings.isEmpty
                ? Array(repeating: ActivityRing(fraction: 0, color: RingPalette.mint), count: placeholderCount)
                : rings
            let line = side * (items.count > 1 ? 0.17 : 0.2)
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { index, ring in
                    let inset = CGFloat(index) * (line + side * 0.03) + line / 2
                    Circle()
                        .inset(by: inset)
                        .stroke(ring.color.opacity(0.22), lineWidth: line)
                    if ring.fraction > 0 {
                        Circle()
                            .inset(by: inset)
                            .trim(from: 0, to: min(1, ring.fraction))
                            .stroke(ring.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StatLine: View {
    let value: String
    let unit: String?
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).smallCaps())
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .widgetAccentable()
    }
}
