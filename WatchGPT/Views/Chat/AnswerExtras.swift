import SwiftUI

struct StopNoteView: View {
    @Environment(ChatStore.self) private var store
    let note: ChatMessage.StopNote
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(note.label, systemImage: "scissors")
                .font(.caption2)
                .foregroundStyle(.orange)
            if isLast && note.canContinue && !store.isBusy {
                Button {
                    WKHaptics.click()
                    store.continueAnswer()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.forward")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Продолжить")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .glassBackground(Capsule(), interactive: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SourcesButton: View {
    let sources: [ChatMessage.Source]
    @State private var shown = false

    var body: some View {
        Button {
            WKHaptics.click()
            shown = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                Text("Источники · \(sources.count)")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glassBackground(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .sheet(isPresented: $shown) {
            SourcesSheet(sources: sources)
        }
    }
}

private struct SourcesSheet: View {
    let sources: [ChatMessage.Source]
    @State private var opened: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Источники")
                    .font(.footnote.weight(.semibold))
                ForEach(sources) { source in
                    Button {
                        WKHaptics.click()
                        withAnimation(.snappy(duration: 0.25)) {
                            opened = opened == source.id ? nil : source.id
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: source.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(verbatim: source.host)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                            if opened == source.id {
                                QRCodeView(text: source.url)
                                    .frame(width: 96, height: 96)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 4)
                                Text("Наведите камеру iPhone, чтобы открыть.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .glassBackground(RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
    }
}
