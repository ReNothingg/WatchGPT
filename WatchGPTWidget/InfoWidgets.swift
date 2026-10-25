import SwiftUI
import WidgetKit

// MARK: Last answer

struct AnswerEntry: TimelineEntry {
    let date: Date
    let answer: WidgetAnswer?
    let signedIn: Bool
    var relevance: TimelineEntryRelevance?
}

struct AnswerProvider: TimelineProvider {
    private static let freshFor: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> AnswerEntry {
        AnswerEntry(date: .now, answer: .preview, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AnswerEntry) -> Void) {
        let snap = SharedStore.load()
        if context.isPreview, snap.lastAnswer == nil {
            completion(AnswerEntry(date: .now, answer: .preview, signedIn: true))
        } else {
            completion(AnswerEntry(date: .now, answer: snap.lastAnswer, signedIn: snap.signedIn))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnswerEntry>) -> Void) {
        let snap = SharedStore.load()
        let now = Date.now
        var entries: [AnswerEntry] = []
        if let answer = snap.lastAnswer, answer.date.addingTimeInterval(Self.freshFor) > now {
            let staleAt = answer.date.addingTimeInterval(Self.freshFor)
            entries.append(AnswerEntry(
                date: now,
                answer: answer,
                signedIn: snap.signedIn,
                relevance: TimelineEntryRelevance(score: 50, duration: staleAt.timeIntervalSince(now))
            ))
            entries.append(AnswerEntry(date: staleAt, answer: answer, signedIn: snap.signedIn, relevance: TimelineEntryRelevance(score: 1)))
        } else {
            entries.append(AnswerEntry(date: now, answer: snap.lastAnswer, signedIn: snap.signedIn, relevance: TimelineEntryRelevance(score: 1)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct AnswerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.answerWidgetKind, provider: AnswerProvider()) { entry in
            AnswerWidgetView(entry: entry)
                .widgetURL(entry.answer.map { SharedStore.deepLink(chatID: $0.chatID) } ?? SharedStore.deepLinkAsk)
        }
        .configurationDisplayName("Последний ответ")
        .description("Последний ответ ChatGPT на циферблате. Нажмите, чтобы открыть чат.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct AnswerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AnswerEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var shown: WidgetAnswer? {
        entry.signedIn ? entry.answer : nil
    }

    private var rectangular: some View {
        Group {
            if let answer = shown {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text(answer.question.isEmpty ? "ChatGPT" : answer.question)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RingPalette.mint)
                    .widgetAccentable()

                    Text(answer.answer)
                        .font(.system(size: 14))
                        .lineLimit(3)
                        .privacySensitive()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(RingPalette.violet)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.signedIn ? "Пока нет ответов" : "ChatGPT")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(entry.signedIn ? "Спросите голосом" : "Войдите в приложении")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    private var inline: some View {
        Group {
            if let answer = shown {
                Label {
                    Text(answer.answer).privacySensitive()
                } icon: {
                    Image(systemName: "sparkles")
                }
            } else {
                Label("Спросить ChatGPT", systemImage: "mic.fill")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

extension WidgetAnswer {
    static let preview = WidgetAnswer(
        question: "Сколько будет 15% от 240?",
        answer: "36. Чтобы найти 15%, умножьте 240 на 0,15.",
        date: .now,
        chatID: ""
    )
}

// MARK: Limits

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
