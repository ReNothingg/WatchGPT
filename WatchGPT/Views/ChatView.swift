import SwiftUI

enum Route: Hashable {
    case settings, models, usage, voice, history
}

struct ChatView: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        Group {
            if store.messages.isEmpty {
                HomeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.messages) { message in
                                MessageRow(message: message, isLast: message.id == store.messages.last?.id)
                                    .equatable()
                                    .id(message.id)
                                    .transition(message.role == .user ? .userBubble : .reply)
                            }
                        }
                        .padding(.bottom, 56)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: store.messages.map(\.id))
                    }
                    .onChange(of: store.scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                    .onAppear {
                        if let target = store.scrollTarget { proxy.scrollTo(target, anchor: .top) }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: store.messages.isEmpty)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.usage) {
                    UsageRing(remaining: store.usage?.tightest()?.remainingPercent(), lineWidth: 2.5, showsText: false)
                        .frame(width: 17, height: 17)
                }
                .accessibilityLabel("Лимиты")
            }
            if !store.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        WKHaptics.click()
                        store.newChat()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                    .disabled(store.isBusy)
                    .accessibilityLabel("Новый чат")
                }
                ToolbarItem(placement: .bottomBar) {
                    AskButton(size: 46)
                }
            }
        }
        .tint(Theme.control)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .settings: SettingsView()
            case .models: ModelPickerView()
            case .usage: UsageView()
            case .voice: VoiceSettingsView()
            case .history: HistoryView()
            }
        }
        .fullScreenCover(isPresented: Bindable(store).isVoiceSheetPresented) {
            RecordView()
        }
        .onChange(of: store.pendingAsk) { _, pending in
            if pending { openDictationFromWidget() }
        }
        .onAppear {
            if store.pendingAsk { openDictationFromWidget() }
        }
    }

    private func openDictationFromWidget() {
        store.pendingAsk = false
        guard !store.isBusy else { return }
        // Give the UI a moment to settle after launch, then start listening.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if store.usesCloudVoice {
                store.startVoice()
            } else {
                Dictation.present { store.send($0) }
            }
        }
    }
}

/// Empty state: one big button. Tap → speak → answer.
private struct HomeView: View {
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = 34
            let gap: CGFloat = 10
            let mic = min(84, max(56, geo.size.height - 82), geo.size.width - 2 * (side + gap) - 8)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: gap) {
                    HomeSideButton(icon: "clock.arrow.circlepath", route: .history, label: "История", size: side)
                        .offset(x: appeared ? 0 : 24)
                        .opacity(appeared ? 1 : 0)
                    AskButton(size: mic, halo: true)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)
                    HomeSideButton(icon: "gearshape", route: .settings, label: "Настройки", size: side)
                        .offset(x: appeared ? 0 : -24)
                        .opacity(appeared ? 1 : 0)
                }
                Spacer(minLength: 8)
                ModelCard(crownControlsEffort: true)
                    .offset(y: appeared ? 0 : 30)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
        }
    }
}

private struct HomeSideButton: View {
    let icon: String
    let route: Route
    let label: String
    let size: CGFloat

    var body: some View {
        NavigationLink(value: route) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.raised))
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

private extension AnyTransition {
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

private struct MessageRow: View, Equatable {
    @Environment(ChatStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let message: ChatMessage
    let isLast: Bool

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.isLast == rhs.isLast && lhs.message == rhs.message
    }

    var body: some View {
        content
            .animation(.easeOut(duration: 0.3), value: message.text.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 28)
                MarkdownText(text: message.text, style: .footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.bubble))
            }
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
                            .background(Capsule().fill(Theme.surface))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isBusy)
                    }
                }
            } else if message.text.isEmpty && isLast && store.isBusy {
                let searching = store.status == .searching
                if isLuminanceReduced {
                    Label(searching ? "Ищу в интернете…" : "Готовлю ответ…", systemImage: searching ? "globe" : "ellipsis")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ThinkingIndicator(label: searching ? "Ищу в интернете" : "Думаю", searching: searching)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownText(text: message.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.25), value: isLast && store.status == .streaming)
            }
        }
    }
}
