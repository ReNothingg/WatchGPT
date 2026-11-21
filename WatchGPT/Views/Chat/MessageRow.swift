import SwiftUI

struct MessageListShape: Equatable {
    let count: Int
    let lastID: UUID?

    init(_ messages: [ChatMessage]) {
        count = messages.count
        lastID = messages.last?.id
    }
}

extension AnyTransition {
    static var userBubble: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.6, anchor: .bottomTrailing)
                .combined(with: .opacity)
                .combined(with: .offset(y: 14)),
            removal: .opacity
        )
    }

    static var reply: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }
}

struct MessageRow: View, Equatable {
    @Environment(ChatStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var showingReasoning = false
    let message: ChatMessage
    let isLast: Bool
    let fontScale: Double

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.isLast == rhs.isLast && lhs.fontScale == rhs.fontScale && lhs.message == rhs.message
    }

    var body: some View {
        content
            .animation(.easeOut(duration: 0.3), value: message.text.isEmpty)
            .sheet(isPresented: $showingReasoning) {
                MessageReasoningReader(messageID: message.id)
            }
    }

    private var reasoningSteps: [ReasoningStep] {
        ReasoningFormat.steps(from: message.reasoning ?? "")
    }

    @ViewBuilder
    private var content: some View {
        switch message.role {
        case .user:
            UserMessageRow(message: message)
        case .assistant:
            if message.isError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    if isLast {
                        Button {
                            store.retry()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Повторить")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .glassBackground(Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isBusy)
                    }
                }
            } else if message.text.isEmpty && isLast && store.isBusy {
                let searching = store.status == .searching
                if store.status == .waitingForNetwork {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Нет сети", systemImage: "wifi.slash")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("Вопрос отправится сам, когда появится связь.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                } else if isLuminanceReduced {
                    Label(searching ? "Ищу в интернете…" : "Готовлю ответ…", systemImage: searching ? "globe" : "ellipsis")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ReasoningDisclosure(
                        title: searching ? String(localized: "Ищу в интернете") : String(localized: "Готовлю ответ"),
                        icon: searching ? "globe" : "sparkles",
                        steps: reasoningSteps,
                        fontScale: fontScale,
                        showsLatest: true,
                        isActive: true
                    ) {
                        showingReasoning = true
                    }
                    .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    let steps = reasoningSteps
                    if !steps.isEmpty {
                        ReasoningDisclosure(
                            title: ReasoningFormat.title(seconds: message.thinkingSeconds),
                            icon: "sparkles",
                            steps: steps,
                            fontScale: fontScale
                        ) {
                            showingReasoning = true
                        }
                    }
                    MarkdownText(text: message.text, scale: fontScale, live: isLast && store.status == .streaming)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.tableLongPress, rewriteWithoutTables)
                        .environment(\.codeLongPress) { code, language in store.handOffCode(code, language: language) }
                        .onTapGesture(count: 2) { store.speaker.toggle(message.text) }
                    if isLast && store.status == .streaming {
                        if isLuminanceReduced {
                            Text("Ответ ещё пишется…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            StreamingDot()
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                    let settled = !(isLast && store.isBusy)
                    if settled, let note = message.stop {
                        StopNoteView(note: note, isLast: isLast)
                            .padding(.top, 2)
                    }
                    if settled, let sources = message.sources, !sources.isEmpty {
                        SourcesButton(sources: sources)
                            .padding(.top, 2)
                    }
                    if isLast && store.canRefine {
                        RefineBar()
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.25), value: isLast && store.status == .streaming)
                .animation(.easeOut(duration: 0.25), value: isLast && store.canRefine)
            }
        }
    }
}

private struct MessageReasoningReader: View {
    @Environment(ChatStore.self) private var store
    let messageID: UUID

    var body: some View {
        let message = store.messages.first { $0.id == messageID }
        ReasoningReader(
            steps: ReasoningFormat.steps(from: message?.reasoning ?? ""),
            fontScale: store.answerFontScale,
            isActive: store.isBusy && store.messages.last?.id == messageID
        )
    }
}

extension MessageRow {
    func rewriteWithoutTables() {
        guard !store.isBusy else { return }
        WKHaptics.click()
        store.send(String(localized: "Перепиши без таблиц"))
    }
}
