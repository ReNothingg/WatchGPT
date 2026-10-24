import SwiftUI

/// Ring showing how much of the plan limit is left.
struct UsageRing: View {
    var remaining: Double?
    var lineWidth: CGFloat = 3
    var showsText = true

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
                Text(remaining.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
            }
        }
        .animation(.easeInOut, value: value)
    }
}

/// "82% · 5ч   64% · нед" — compact summary of both windows.
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

/// Animated "typing" dots.
struct ThinkingDots: View {
    var label: String

    var body: some View {
        HStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 0.25)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate * 4) % 4
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                            .opacity(i < step ? 1 : 0.25)
                    }
                }
            }
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// The main mic button. Tap → record → OpenAI speech-to-text → question is sent.
/// With the "Apple" engine it opens the system dictation instead.
struct AskButton: View {
    @Environment(ChatStore.self) private var store
    var size: CGFloat = 44

    var body: some View {
        if store.isBusy {
            Button {
                store.stop()
            } label: {
                circle(icon: "stop.fill", fill: Color.white.opacity(0.2), iconColor: .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Остановить")
        } else if store.usesCloudVoice {
            Button {
                store.startVoice()
            } label: {
                circle(icon: "mic.fill", fill: Theme.accent, iconColor: .black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Спросить голосом")
        } else {
            TextFieldLink(prompt: Text("Спросите что угодно")) {
                circle(icon: "mic.fill", fill: Theme.accent, iconColor: .black)
            } onSubmit: { text in
                store.send(text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Спросить")
        }
    }

    private func circle(icon: String, fill: Color, iconColor: Color) -> some View {
        ZStack {
            Circle().fill(fill)
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// Renders inline markdown (bold, italic, code, links) and keeps line breaks.
struct MarkdownText: View {
    let text: String

    var body: some View {
        let pretty = MathFormat.prettify(text)
        if let attributed = try? AttributedString(
            markdown: pretty,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        ) {
            Text(attributed)
        } else {
            Text(pretty)
        }
    }
}
