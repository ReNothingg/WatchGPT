import SwiftUI
import WidgetKit

struct AnswerEntry: TimelineEntry {
    let date: Date
    let answer: WidgetAnswer?
    let signedIn: Bool
    var pending: WidgetPending?
    var relevance: TimelineEntryRelevance?
}

struct AnswerProvider: TimelineProvider {
    private static let freshFor: TimeInterval = 15 * 60
    private static let pendingFor: TimeInterval = 10 * 60

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
        if let pending = snap.pending, pending.startedAt.addingTimeInterval(Self.pendingFor) > now {
            let staleAt = pending.startedAt.addingTimeInterval(Self.pendingFor)
            entries.append(AnswerEntry(
                date: now,
                answer: snap.lastAnswer,
                signedIn: snap.signedIn,
                pending: pending,
                relevance: TimelineEntryRelevance(score: 100, duration: staleAt.timeIntervalSince(now))
            ))
            entries.append(AnswerEntry(date: staleAt, answer: snap.lastAnswer, signedIn: snap.signedIn, relevance: TimelineEntryRelevance(score: 1)))
        } else if let answer = snap.lastAnswer, answer.date.addingTimeInterval(Self.freshFor) > now {
            let staleAt = answer.date.addingTimeInterval(Self.freshFor)
            entries.append(AnswerEntry(
                date: now,
                answer: answer,
                signedIn: snap.signedIn,
                relevance: TimelineEntryRelevance(score: 80, duration: staleAt.timeIntervalSince(now))
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
                .widgetURL(link(entry))
        }
        .configurationDisplayName("Ответ")
        .description("Показывает, что ответ готовится, а затем сам ответ. Поднимается в Smart Stack, пока ответ свежий.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

func link(_ entry: AnswerEntry) -> URL {
    if let pending = entry.pending, !pending.chatID.isEmpty { return SharedStore.deepLink(chatID: pending.chatID) }
    return entry.answer.map { SharedStore.deepLink(chatID: $0.chatID) } ?? SharedStore.deepLinkAsk
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

    private var pending: WidgetPending? {
        entry.signedIn ? entry.pending : nil
    }

    private var rectangular: some View {
        Group {
            if let pending {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: pending.preview == nil ? "ellipsis.bubble.fill" : "text.bubble.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(pending.preview == nil ? "Готовлю ответ" : "Пишу ответ")
                        Spacer(minLength: 2)
                        Text(pending.startedAt, style: .timer)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 40, alignment: .trailing)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RingPalette.mint)
                    .widgetAccentable()

                    Text(pending.preview ?? pending.question)
                        .font(.system(size: 14))
                        .foregroundStyle(pending.preview == nil ? .secondary : .primary)
                        .lineLimit(pending.preview == nil ? 2 : 3)
                        .privacySensitive()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let answer = shown {
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
            if let pending {
                Label {
                    Text(pending.preview == nil ? "Готовлю ответ…" : pending.preview ?? "")
                        .privacySensitive()
                } icon: {
                    Image(systemName: "ellipsis.bubble.fill")
                }
            } else if let answer = shown {
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
