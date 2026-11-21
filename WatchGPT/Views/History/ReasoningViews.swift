import SwiftUI

struct ReasoningSummary: View {
    @Environment(ChatStore.self) private var store
    @State private var showingDetails = false
    let reasoning: Reasoning

    var body: some View {
        let singleStep = reasoning.steps.count == 1 ? reasoning.steps.first : nil
        let tool = reasoning.seconds == nil && singleStep?.icon != nil ? singleStep : nil
        ReasoningDisclosure(
            title: tool?.title ?? ReasoningFormat.title(seconds: reasoning.seconds),
            icon: singleStep?.icon ?? "sparkles",
            steps: reasoning.steps,
            fontScale: store.answerFontScale
        ) {
            showingDetails = true
        }
        .sheet(isPresented: $showingDetails) {
            ReasoningReader(steps: reasoning.steps, fontScale: store.answerFontScale)
        }
    }
}

struct ReasoningDisclosure: View {
    let title: String
    let icon: String
    let steps: [ReasoningStep]
    let fontScale: Double
    var showsLatest = false
    var isActive = false
    var startedAt: Date?
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if steps.isEmpty {
                label
            } else {
                Button {
                    WKHaptics.click()
                    open()
                } label: {
                    label
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .accessibilityHint("Открывает все шаги ответа")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsLatest ? steps.last?.id : nil)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if showsLatest, let latest = steps.last {
                let text = latest.title.isEmpty || latest.title == title ? latest.detail : latest.title
                if let firstLine = text.split(whereSeparator: \.isNewline).first {
                    MarkdownText(text: String(firstLine), scale: fontScale, live: isActive)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 21)
                        .id(latest.id)
                        .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 15)
                .symbolEffect(.pulse, isActive: isActive && !reduceMotion)
                .accessibilityHidden(true)
            MarkdownText(text: title, scale: fontScale)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption2.monospacedDigit())
                    .fixedSize()
            }
            if !steps.isEmpty {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

struct ReasoningReader: View {
    let steps: [ReasoningStep]
    let fontScale: Double
    var isActive = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(steps) { step in
                        if step.id != steps.first?.id {
                            Divider()
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if !step.title.isEmpty {
                                MarkdownText(text: step.title, scale: fontScale)
                            }
                            if !step.detail.isEmpty {
                                MarkdownText(text: step.detail, scale: fontScale, live: isActive && step.id == steps.last?.id)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
            }
            .navigationTitle("Ход ответа")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть")
                }
            }
        }
        .presentationBackground(.black)
    }
}

enum ReasoningFormat {
    static func title(seconds: Int?) -> String {
        guard let seconds else { return String(localized: "Ход ответа") }
        return String(localized: "Думал \(duration(seconds))")
    }

    static func steps(from text: String) -> [ReasoningStep] {
        var steps: [ReasoningStep] = []
        var title = ""
        var lines: [Substring] = []
        var inCode = false

        func appendStep() {
            let detail = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty || !detail.isEmpty {
                steps.append(ReasoningStep(id: steps.count, title: title, detail: detail))
            }
            title = ""
            lines.removeAll(keepingCapacity: true)
        }

        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
            } else if !inCode {
                if let heading = heading(trimmed) {
                    appendStep()
                    title = heading
                    continue
                }
                if trimmed.isEmpty && title.isEmpty {
                    appendStep()
                    continue
                }
            }
            lines.append(line)
        }
        appendStep()
        return steps
    }

    private static func heading(_ text: String) -> String? {
        if text.count > 4, text.hasPrefix("**"), text.hasSuffix("**") {
            let title = text.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty && !title.contains("**") { return title }
        }
        let markers = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markers), text.dropFirst(markers).first == " " else { return nil }
        let title = text.dropFirst(markers).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return String(localized: "\(max(1, seconds)) с") }
        if seconds < 3600 {
            let rest = seconds % 60
            return rest == 0 ? String(localized: "\(seconds / 60) мин") : String(localized: "\(seconds / 60) мин \(rest) с")
        }
        let minutes = (seconds % 3600) / 60
        return minutes == 0 ? String(localized: "\(seconds / 3600) ч") : String(localized: "\(seconds / 3600) ч \(minutes) мин")
    }
}
