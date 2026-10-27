import SwiftUI

struct GPTChatView: View {
    let chatID: String
    let title: String

    @Environment(ChatStore.self) private var store
    @State private var conversation: RemoteConversation?
    @State private var loadError: String?
    @State private var isRefreshing = false
    @State private var visibleCount = Self.pageSize
    @State private var didScroll = false
    @State private var chromeVisible = true
    @State private var streamFailed = false
    @Environment(\.scenePhase) private var scenePhase

    private static let pageSize = 30

    var body: some View {
        Group {
            if let conversation {
                transcript(conversation)
                    .transition(.opacity)
            } else if let loadError {
                ScrollView {
                    HistoryErrorView(message: loadError) {
                        Task { await load() }
                    }
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 10) {
                    Spinner(size: 30, lineWidth: 3)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: conversation == nil)
        .navigationTitle("ChatGPT")
        .toolbar {
            if let conversation, !conversation.messages.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        continueChat(conversation, ask: true)
                    } label: {
                        MicCircle(size: 46, halo: false)
                    }
                    .buttonStyle(PressableStyle())
                    .chromeVisibility(chromeVisible)
                    .disabled(store.isBusy)
                    .accessibilityLabel("Продолжить голосом на часах")
                }
            }
        }
        .task {
            if conversation == nil { conversation = store.gptHistory.cached(chatID) }
            await load()
        }
        .task(id: PollKey(live: conversation?.live != nil, phase: scenePhase)) {
            guard conversation?.live != nil, scenePhase != .background else { return }
            var tick = 0
            while !Task.isCancelled {
                let pause: Double = streamFailed ? 10 : (PowerMonitor.shared.isLowPower ? 4 : 2)
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { return }
                tick += 1
                if tick % 3 == 0 || streamFailed {
                    let state = await store.gptHistory.streamState(chatID)
                    guard !Task.isCancelled else { return }
                    streamFailed = state == .failed
                }
                await load(quiet: true)
            }
        }
        .handoffActivity(isActive: store.handoff, title: title) {
            Handoff.url(remoteChatID: chatID)
        }
    }

    private func transcript(_ conversation: RemoteConversation) -> some View {
        let messages = conversation.messages
        let hidden = max(0, messages.count - visibleCount)
        let shown = Array(messages.dropFirst(hidden))

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header(conversation)

                    if hidden > 0 {
                        Button {
                            WKHaptics.click()
                            visibleCount += Self.pageSize
                        } label: {
                            Label("Ранее: \(ChatDate.messages(hidden))", systemImage: "arrow.up")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .glassBackground(Capsule(), interactive: true)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .frame(maxWidth: .infinity)
                    }

                    if messages.isEmpty {
                        Text("В этом чате нет текстовых сообщений.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    ForEach(shown) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            if message.role == .assistant, let reasoning = conversation.reasoning[message.id] {
                                ReasoningSummary(reasoning: reasoning)
                            }
                            HistoryBubble(
                                message: message,
                                images: conversation.images[message.id] ?? [],
                                conversationID: conversation.id
                            )
                        }
                        .id(message.id)
                    }

                    if let live = conversation.live {
                        LiveTurnCard(live: live, failed: streamFailed)
                            .id("live")
                            .transition(.opacity)
                    }

                    footer(conversation)
                }
                .padding(.bottom, 56)
            }
            .autoHidesChrome($chromeVisible)
            .onAppear {
                guard !didScroll, let target = messages.last(where: { $0.role == .user })?.id else { return }
                didScroll = true
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private func header(_ conversation: RemoteConversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(ChatDate.short(conversation.updatedAt))
                Text("·")
                Text(ChatDate.messages(conversation.messages.count))
                if isRefreshing {
                    Spinner(size: 9, lineWidth: 1.5)
                        .padding(.leading, 2)
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.bottom, 2)
    }

    private func footer(_ conversation: RemoteConversation) -> some View {
        VStack(spacing: 6) {
            Button {
                continueChat(conversation, ask: false)
            } label: {
                Label("Продолжить на часах", systemImage: "applewatch")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .glassBackground(Capsule(), fill: Theme.accent, tint: Theme.accent, interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .disabled(store.isBusy || conversation.messages.isEmpty)
            .opacity(store.isBusy || conversation.messages.isEmpty ? 0.5 : 1)

            Text("Новые сообщения сохранятся на часах, в ChatGPT они не появятся.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private func continueChat(_ conversation: RemoteConversation, ask: Bool) {
        WKHaptics.click()
        store.continueGPTChat(conversation, ask: ask)
    }

    private func load(quiet: Bool = false) async {
        if !quiet {
            loadError = nil
            isRefreshing = true
        }
        defer { if !quiet { isRefreshing = false } }
        do {
            let fresh = try await store.gptHistory.conversation(chatID)
            let wasLive = conversation?.live != nil
            if fresh != conversation {
                withAnimation(.smooth(duration: 0.3)) { conversation = fresh }
            }
            if wasLive, fresh.live == nil { WKHaptics.success() }
        } catch {
            guard !GPTHistory.isCancellation(error) else { return }
            if conversation == nil { loadError = ChatStore.describe(error) }
        }
    }
}

private struct PollKey: Equatable {
    var live: Bool
    var phase: ScenePhase
}

private struct HistoryBubble: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    var images: [RemoteImage] = []
    var conversationID: String

    private var text: String {
        images.isEmpty ? message.text : HistoryText.withoutImageLabel(message.text)
    }

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 4) {
                if !images.isEmpty {
                    HStack {
                        Spacer(minLength: images.count == 1 ? 36 : 20)
                        gallery
                    }
                }
                if !text.isEmpty {
                    HStack {
                        Spacer(minLength: 28)
                        MarkdownText(text: text, style: .footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous), fill: Theme.bubble)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if !images.isEmpty { gallery }
                if !text.isEmpty {
                    MarkdownText(text: text, scale: store.answerFontScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) { store.speaker.toggle(text) }
                }
            }
        }
    }

    @ViewBuilder private var gallery: some View {
        if images.count == 1 {
            RemoteImageView(image: images[0], conversationID: conversationID)
        } else {
            let rows = stride(from: 0, to: images.count, by: 2).map { Array(images[$0..<min($0 + 2, images.count)]) }
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row) { image in
                            RemoteImageView(image: image, conversationID: conversationID, square: true)
                        }
                        if row.count == 1 {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
    }
}

private struct RemoteImageView: View {
    @Environment(ChatStore.self) private var store
    let image: RemoteImage
    let conversationID: String
    var square = false

    @State private var picture: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var showsFull = false

    var body: some View {
        Color.clear
            .aspectRatio(square ? 1 : image.aspect, contentMode: .fit)
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                        Text("Нажмите, чтобы повторить")
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(6)
                } else {
                    Spinner(size: 18, lineWidth: 2)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                if picture != nil {
                    showsFull = true
                } else if failed {
                    failed = false
                    attempt += 1
                }
            }
            .task(id: attempt) { await load() }
            .sheet(isPresented: $showsFull) {
                if let picture {
                    ScrollView {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: picture != nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Изображение")
    }

    private func load() async {
        if let cached = store.gptHistory.cachedImage(image) {
            picture = cached
            return
        }
        do {
            picture = try await store.gptHistory.image(image, conversationID: conversationID)
        } catch {
            guard !GPTHistory.isCancellation(error) else { return }
            failed = true
        }
    }
}

private struct ReasoningSummary: View {
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

private struct ThinkingHeader<Label: View>: View {
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

private struct ReasoningSteps: View {
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

private struct ThoughtRow: View {
    let step: ReasoningStep
    var collapsedLines: Int
    @State private var open = false

    private var title: String { step.title.replacingOccurrences(of: "**", with: "") }
    private var detail: String { step.detail.replacingOccurrences(of: "**", with: "") }
    private var canOpen: Bool { detail.count > collapsedLines * 28 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ReasoningPalette.title)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
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

private struct ToolRow: View {
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

private enum ReasoningPalette {
    static let title = Color(white: 0.74)
    static let text = Theme.secondaryText
    static let faint = Color(white: 0.42)
}

private struct LiveTurnCard: View {
    let live: LiveTurn
    var failed = false
    @State private var expanded = false

    private var steps: [ReasoningStep] { live.reasoning.steps }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if failed {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Ответ прервался")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                ThinkingHeader(expandable: steps.count > 1, expanded: $expanded) {
                    ShimmerText(text: live.stage, font: .footnote)
                        .id(live.stage)
                        .transition(.opacity)
                    Text("·")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text(timerInterval: live.startedAt...Date.distantFuture, countsDown: false)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
                .animation(.smooth(duration: 0.3), value: live.stage)
            }

            if expanded {
                ReasoningSteps(steps: steps)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            } else if let last = steps.last {
                ReasoningSteps(steps: [last], collapsedLines: 3)
                    .id(last.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.35), value: steps.last?.id)
        .accessibilityElement(children: .combine)
    }
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

struct HistoryErrorView: View {
    let message: String
    var compact = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            if !compact {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.orange)
            }
            Text(message)
                .font(compact ? .caption2 : .footnote)
                .foregroundStyle(compact ? .orange : .white)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Повторить")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .glassBackground(Capsule(), interactive: true)
            }
            .buttonStyle(PressableStyle(scale: 0.95))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, compact ? 2 : 10)
        .frame(maxWidth: .infinity)
    }
}
