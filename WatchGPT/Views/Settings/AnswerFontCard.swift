import Charts
import SwiftUI

struct AnswerFontCard: View {
    @Binding var scale: Double

    private var isDefault: Bool { abs(scale - 1) < 0.001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Шрифт ответа")
                    .font(.footnote)
                Spacer(minLength: 4)
                Text(Theme.percent(scale * 100))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isDefault ? Theme.secondaryText : Theme.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard !isDefault else { return }
                withAnimation(.snappy(duration: 0.2)) { scale = 1 }
                WKHaptics.click()
            }
            MarkdownText(text: "Так будет выглядеть ответ.", scale: scale)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            FontScaleSlider(scale: $scale)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .animation(.snappy(duration: 0.2), value: scale)
    }
}

struct FontScaleSlider: View {
    @Binding var scale: Double

    private let range = ChatStore.answerFontRange
    private let step = ChatStore.answerFontStep

    private var fraction: Double {
        (scale - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        HStack(spacing: 6) {
            stepButton(icon: "textformat.size.smaller", label: "Уменьшить шрифт", delta: -step)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.raised)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(10, width * fraction))
                    Circle()
                        .fill(Theme.onAccent)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, width * fraction - 10))
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard width > 0 else { return }
                            let t = min(max(value.location.x / width, 0), 1)
                            set(range.lowerBound + t * (range.upperBound - range.lowerBound))
                        }
                )
            }
            .frame(height: 32)
            stepButton(icon: "textformat.size.larger", label: "Увеличить шрифт", delta: step)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Шрифт ответа")
        .accessibilityValue(Theme.percent(scale * 100))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(scale + step)
            case .decrement: set(scale - step)
            @unknown default: break
            }
        }
    }

    private func set(_ value: Double) {
        let next = ChatStore.clampedFontScale(value)
        guard abs(next - scale) > 0.001 else { return }
        scale = next
        WKHaptics.click()
    }

    private func stepButton(icon: String, label: String, delta: Double) -> some View {
        let enabled = range.contains(((scale + delta) * 100).rounded() / 100)
        return Button {
            set(scale + delta)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? .white : Theme.secondaryText.opacity(0.5))
                .frame(width: 32, height: 32)
                .glassBackground(Circle(), fill: Theme.raised, interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
