import Charts
import SwiftUI

struct ToggleTile: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var onColor: Color = Theme.accent
    var onText: Color = Theme.onAccent

    var body: some View {
        if #available(watchOS 26.0, *) {
            styled(glassButton)
        } else {
            styled(
                button
                    .buttonStyle(.plain)
            )
        }
    }

    private func styled(_ content: some View) -> some View {
        content
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "включено" : "выключено")
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @available(watchOS 26.0, *)
    @ViewBuilder
    private var glassButton: some View {
        if isOn {
            Button(action: toggle) { glassLabel }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(onColor)
        } else {
            Button(action: toggle) { glassLabel }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(Theme.raised)
        }
    }

    private var glassLabel: some View {
        label(glass: true)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
    }

    private var button: some View {
        Button(action: toggle) {
            label(glass: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isOn ? onColor.opacity(0.22) : Theme.surface)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
        WKHaptics.click()
    }

    private func label(glass: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? (glass ? onText : onColor) : Theme.secondaryText)
            Spacer(minLength: 4)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isOn && glass ? onText : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .glassBackground(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.footnote)
            Spacer(minLength: 4)
            trailing
                .font(.caption2)
                .lineLimit(1)
            Chevron()
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 42)
        .contentShape(Rectangle())
    }
}

struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.raised)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}
