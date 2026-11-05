import SwiftUI

struct ReasoningSummary: View {
    let reasoning: Reasoning
    @State private var expanded = false

    private var label: String {
        if let seconds = reasoning.seconds { return "Думал \(ReasoningFormat.duration(seconds))" }
        let tools = reasoning.steps.filter { $0.icon != nil }
        if !tools.isEmpty, tools.count == reasoning.steps.count {
            var names: [String] = []
            for step in tools {
                let name = step.title.components(separatedBy: ":").first ?? step.title
                if !names.contains(name) { names.append(name) }
            }
            return tools.count == 1 ? tools[0].title : "Использовано: " + names.prefix(2).joined(separator: ", ")
        }
        return "Рассуждения"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThinkingHeader(expandable: !reasoning.steps.isEmpty, expanded: $expanded) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            if expanded {
                ReasoningSteps(steps: reasoning.steps)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }
}

struct ThinkingHeader<Label: View>: View {
    var expandable: Bool
    @Binding var expanded: Bool
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            guard expandable else { return }
            WKHaptics.click()
            withAnimation(.snappy(duration: 0.3)) { expanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                label()
                if expandable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .disabled(!expandable)
    }
}

struct ReasoningSteps: View {
    let steps: [ReasoningStep]
    var collapsedLines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(steps) { step in
                if step.icon != nil {
                    ToolRow(step: step)
                } else {
                    ThoughtRow(step: step, collapsedLines: collapsedLines)
                }
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Theme.track)
                .frame(width: 2)
                .padding(.vertical, 2)
        }
    }
}

struct ThoughtRow: View {
    let step: ReasoningStep
    var collapsedLines: Int
    @State private var open = false

    private var title: String { step.title.replacingOccurrences(of: "**", with: "") }

    private var paragraphs: [String] {
        step.detail.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canOpen: Bool {
        paragraphs.count > 1 || (paragraphs.first?.count ?? 0) > collapsedLines * 30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ReasoningPalette.title)
            }
            if let first = paragraphs.first {
                MarkdownText(text: open ? step.detail : first, style: .caption2)
                    .foregroundStyle(ReasoningPalette.text)
                    .lineLimit(open ? nil : collapsedLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpen else { return }
            WKHaptics.click()
            withAnimation(.snappy(duration: 0.25)) { open.toggle() }
        }
    }
}

struct ToolRow: View {
    let step: ReasoningStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: step.icon ?? "wrench.and.screwdriver")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                if !step.detail.isEmpty {
                    Text(step.detail.replacingOccurrences(of: "\n", with: " · "))
                        .font(.caption2)
                        .foregroundStyle(ReasoningPalette.faint)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(ReasoningPalette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ReasoningPalette {
    static let title = Color(white: 0.74)
    static let text = Theme.secondaryText
    static let faint = Color(white: 0.42)
}

enum ReasoningFormat {
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(max(1, seconds)) с" }
        if seconds < 3600 {
            let rest = seconds % 60
            return rest == 0 ? "\(seconds / 60) мин" : "\(seconds / 60) мин \(rest) с"
        }
        let minutes = (seconds % 3600) / 60
        return minutes == 0 ? "\(seconds / 3600) ч" : "\(seconds / 3600) ч \(minutes) мин"
    }

    static func steps(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "\(count) шаг" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(count) шага" }
        return "\(count) шагов"
    }
}
