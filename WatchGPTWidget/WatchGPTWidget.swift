import SwiftUI
import WidgetKit

@main
struct WatchGPTWidgets: WidgetBundle {
    var body: some Widget {
        AskWidget()
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
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        signedIn: true,
        usage: UsageSnapshot(
            primary: UsageWindow(usedPercent: 18, windowMinutes: 300, resetAt: .now.addingTimeInterval(7200)),
            secondary: UsageWindow(usedPercent: 36, windowMinutes: 10080, resetAt: .now.addingTimeInterval(3 * 86400)),
            planType: "plus"
        ),
        modelName: "GPT-6.1-Sol"
    )
}

// MARK: Widget

struct AskWidget: Widget {
    let kind = "WatchGPTAsk"

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

    // Smart Stack / rectangular complication
    private var rectangular: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.accent)
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: 36, height: 36)
            .widgetAccentable()

            VStack(alignment: .leading, spacing: 2) {
                Text("Спросить")
                    .font(.headline)
                    .widgetAccentable()
                if !entry.snapshot.signedIn {
                    Text("Подключите ChatGPT")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let left = entry.remaining, let window = entry.window {
                    Text("Осталось \(Theme.percent(left)) · \(window.shortLabel)")
                        .font(.caption2)
                        .monospacedDigit()
                    ProgressView(value: left, total: 100)
                        .tint(Theme.usageColor(left))
                } else {
                    Text(entry.snapshot.modelName ?? "ChatGPT")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
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
