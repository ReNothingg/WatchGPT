import Charts
import SwiftUI

struct ModelPickerView: View {
    @Environment(ChatStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Provider.allCases, id: \.self) { provider in
                    ProviderHeader(provider: provider)
                    if provider == .claude && !auth.hasClaudeKey {
                        NavigationLink(value: Route.claude) {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Добавить API-ключ")
                                        .font(.footnote)
                                    Text("Модели Claude по API Anthropic")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Spacer(minLength: 2)
                                Chevron()
                            }
                            .padding(.leading, 12)
                            .padding(.trailing, 10)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: Theme.surfaceDim, interactive: true)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(provider == .claude ? store.claudeModels : store.models) { option in
                            ModelRow(option: option, isSelected: store.isSelected(option, provider: provider)) {
                                store.select(option, provider: provider)
                                WKHaptics.click()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Модель")
        .task {
            async let gpt: Void = store.refreshModels(ifOlderThan: 600)
            async let claude: Void = store.refreshClaudeModels(ifOlderThan: 600)
            _ = await (gpt, claude)
        }
    }
}

struct ProviderHeader: View {
    let provider: Provider

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: provider == .claude ? "asterisk" : "sparkles")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(provider == .claude ? Theme.claude : Theme.accent)
            Text(provider.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, provider == .chatgpt ? 2 : 10)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ModelRow: View {
    let option: ModelOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(option.displayName)
                            .font(.footnote.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if option.supportsFast == true {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.fast)
                        }
                    }
                    if let summary = option.summary {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .glassBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
                fill: isSelected ? Theme.surface : Theme.surfaceDim,
                tint: isSelected ? Theme.accent.opacity(0.18) : nil,
                interactive: true
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
