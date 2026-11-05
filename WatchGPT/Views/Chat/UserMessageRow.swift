import SwiftUI

struct UserMessageRow: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage

    private var isVoiceEditing: Bool {
        store.editingMessageID == message.id && store.voicePhase != .idle
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            row
            if let versions = message.versions, versions.count > 1 {
                VersionPager(message: message, count: versions.count)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var row: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Spacer(minLength: 0)
            Group {
                if isVoiceEditing {
                    VoiceEditControls()
                } else if !store.isBusy && store.voicePhase == .idle {
                    EditButtons(message: message)
                }
            }
            .fixedSize()
            .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            Group {
                if isVoiceEditing {
                    VoiceEditBubble()
                        .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
                } else {
                    MarkdownText(text: message.text, style: .footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: Theme.bubble)
                        .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
                }
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isVoiceEditing)
        .animation(.easeOut(duration: 0.2), value: store.isBusy)
    }
}

struct VersionPager: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    let count: Int

    private var index: Int { min(message.versionIndex ?? 0, count - 1) }
    private var enabled: Bool { !store.isBusy && store.voicePhase == .idle }

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", step: -1, label: "Предыдущая версия", available: canMove(-1))
            Text("\(index + 1)/\(count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .contentTransition(.numericText(value: Double(index)))
                .frame(minWidth: 26)
            arrow("chevron.right", step: 1, label: "Следующая версия", available: canMove(1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Версия \(index + 1) из \(count)")
    }

    private func canMove(_ step: Int) -> Bool {
        let target = index + step
        guard enabled, let versions = message.versions, versions.indices.contains(target) else { return false }
        return !versions[target].isEmpty
    }

    private func arrow(_ icon: String, step: Int, label: String, available: Bool) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { store.switchVersion(message.id, by: step) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .foregroundStyle(Theme.secondaryText)
        .opacity(available ? 1 : 0.3)
        .disabled(!available)
        .accessibilityLabel(label)
    }
}

struct EditButtons: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 4) {
            SmallCircleButton(icon: "mic.fill", label: "Изменить голосом") {
                store.editByVoice(message.id)
            }
            ZStack {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .frame(width: 26, height: 26)
                    .onSubmit(submit)
                    .accessibilityLabel("Изменить текстом")
                SmallCircle(icon: "keyboard")
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
        }
        .onAppear { draft = message.text }
        .onChange(of: message.text) { _, text in draft = text }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = message.text
        guard !text.isEmpty, text != message.text else { return }
        WKHaptics.click()
        store.edit(message.id, to: text)
    }
}
