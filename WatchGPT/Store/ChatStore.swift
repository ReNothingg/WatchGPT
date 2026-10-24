import Foundation
import Observation
import WatchKit
import WidgetKit

@MainActor
@Observable
final class ChatStore {
    enum Status: Equatable { case idle, thinking, searching, streaming }

    let auth: AuthService
    let speaker = Speaker()

    private(set) var messages: [ChatMessage] = []
    private(set) var status: Status = .idle
    private(set) var usage: UsageSnapshot?
    private(set) var models: [ModelOption] = ModelOption.fallback
    private(set) var usageError: String?

    /// Set by the widget deep link — the chat screen opens dictation right away.
    var pendingAsk = false
    /// Id of the message the chat should scroll to (the latest question).
    private(set) var scrollTarget: UUID?

    var selectedModelSlug: String {
        didSet {
            defaults.set(selectedModelSlug, forKey: Keys.model)
            if !selectedModel.efforts.isEmpty, !selectedModel.efforts.contains(effort) {
                effort = selectedModel.defaultEffort ?? selectedModel.efforts.first ?? "low"
            }
            publishWidget()
        }
    }
    var effort: String { didSet { defaults.set(effort, forKey: Keys.effort) } }
    var webSearch: Bool { didSet { defaults.set(webSearch, forKey: Keys.webSearch) } }
    var autoSpeak: Bool { didSet { defaults.set(autoSpeak, forKey: Keys.autoSpeak) } }
    var conciseAnswers: Bool { didSet { defaults.set(conciseAnswers, forKey: Keys.concise) } }

    private var conversationID = UUID().uuidString
    private var sendTask: Task<Void, Never>?
    private var lastMetaRefresh: Date?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let model = "settings.model"
        static let effort = "settings.effort"
        static let webSearch = "settings.webSearch"
        static let autoSpeak = "settings.autoSpeak"
        static let concise = "settings.concise"
        static let models = "cache.models"
        static let usage = "cache.usage"
    }

    init(auth: AuthService) {
        self.auth = auth
        let d = UserDefaults.standard
        selectedModelSlug = d.string(forKey: Keys.model) ?? ModelOption.fallback[0].slug
        effort = d.string(forKey: Keys.effort) ?? "low"
        webSearch = d.object(forKey: Keys.webSearch) as? Bool ?? true
        autoSpeak = d.object(forKey: Keys.autoSpeak) as? Bool ?? false
        conciseAnswers = d.object(forKey: Keys.concise) as? Bool ?? true

        if let data = d.data(forKey: Keys.models),
           let cached = try? JSONDecoder().decode([ModelOption].self, from: data), !cached.isEmpty {
            models = cached
        }
        if let data = d.data(forKey: Keys.usage) {
            usage = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        }
        loadConversation()
    }

    var selectedModel: ModelOption {
        models.first { $0.slug == selectedModelSlug } ?? models.first ?? ModelOption.fallback[0]
    }

    var isBusy: Bool { status != .idle }

    var lastAnswer: ChatMessage? {
        messages.last { $0.role == .assistant && !$0.isError && !$0.text.isEmpty }
    }

    // MARK: Sending

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        speaker.stop()

        let question = ChatMessage(role: .user, text: text)
        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(question)
        messages.append(reply)
        scrollTarget = question.id
        status = .thinking
        WKInterfaceDevice.current().play(.start)

        sendTask = Task { [weak self] in
            await self?.generate(replyID: reply.id)
        }
    }

    /// Re-asks the last question (after an error).
    func retry() {
        guard !isBusy, let lastUser = messages.lastIndex(where: { $0.role == .user }) else { return }
        let text = messages[lastUser].text
        messages.removeSubrange(lastUser...)
        send(text)
    }

    func stop() {
        sendTask?.cancel()
        sendTask = nil
    }

    func newChat() {
        stop()
        speaker.stop()
        messages = []
        conversationID = UUID().uuidString
        scrollTarget = nil
        saveConversation()
        publishWidget()
    }

    private func generate(replyID: UUID) async {
        var didRetryAuth = false
        defer {
            status = .idle
            sendTask = nil
            saveConversation()
            publishWidget()
        }

        while true {
            do {
                let tokens = try await auth.validTokens()
                let client = ChatGPTClient(tokens: tokens)
                let history = messages.filter { $0.id != replyID }
                let stream = client.stream(messages: history, options: requestOptions())

                for try await event in stream {
                    switch event {
                    case let .textDelta(delta):
                        status = .streaming
                        update(replyID) { $0.text += delta }
                    case .searching:
                        if status != .streaming { status = .searching }
                    case let .usage(snapshot):
                        applyUsage(snapshot)
                    case .completed:
                        break
                    }
                }

                if text(of: replyID).isEmpty {
                    update(replyID) { $0.text = "Пустой ответ. Попробуйте ещё раз."; $0.isError = true }
                    WKInterfaceDevice.current().play(.failure)
                } else {
                    WKInterfaceDevice.current().play(.success)
                    if autoSpeak { speaker.speak(text(of: replyID)) }
                }
                return
            } catch ChatGPTClient.APIError.unauthorized where !didRetryAuth {
                didRetryAuth = true
                do { try await auth.refresh() } catch { fail(replyID, error); return }
                continue
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    if text(of: replyID).isEmpty { messages.removeAll { $0.id == replyID } }
                    return
                }
                fail(replyID, error)
                if case ChatGPTClient.APIError.usageLimit = error {
                    Task { await refreshUsage() }
                }
                return
            }
        }
    }

    private func fail(_ replyID: UUID, _ error: Error) {
        let message = Self.describe(error)
        if text(of: replyID).isEmpty {
            update(replyID) { $0.text = message; $0.isError = true }
        } else {
            messages.append(ChatMessage(role: .assistant, text: message, isError: true))
        }
        WKInterfaceDevice.current().play(.failure)
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Нет интернета. Проверьте связь с iPhone или Wi‑Fi."
            case .timedOut:
                return "Сервер долго не отвечает. Попробуйте ещё раз."
            default:
                return "Ошибка сети: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    private func requestOptions() -> ChatGPTClient.Options {
        let model = selectedModel
        let effortValue: String? = model.efforts.isEmpty ? nil : (model.efforts.contains(effort) ? effort : model.defaultEffort)
        return ChatGPTClient.Options(
            model: model.slug,
            effort: effortValue,
            webSearch: webSearch,
            verbosity: model.supportsVerbosity ? (conciseAnswers ? "low" : "medium") : nil,
            instructions: instructions(),
            conversationID: conversationID
        )
    }

    private func instructions() -> String {
        let now = Date.now.formatted(date: .complete, time: .shortened)
        let style = conciseAnswers
            ? "Be brief: lead with the answer, then at most 2–4 short sentences or a compact list. Expand only if the user explicitly asks for detail."
            : "Be clear and well structured, but keep in mind the screen is small; avoid filler."
        return """
        You are ChatGPT running on the user's Apple Watch. The user speaks to you through dictation, \
        so their message may contain speech-recognition mistakes — infer what they meant. \
        Always reply in the language of the user's message. \(style) \
        Write plain text that is easy to read on a tiny screen and to read aloud: no tables, no headings, \
        no code blocks unless essential; simple **bold** and short bullet lists are fine. \
        Current date and time: \(now). Locale: \(Locale.current.identifier).
        """
    }

    private func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func text(of id: UUID) -> String {
        messages.first { $0.id == id }?.text ?? ""
    }

    // MARK: Usage & models

    func handle(url: URL) {
        guard url.scheme == "watchgpt" else { return }
        if url.host == "ask" { pendingAsk = true }
    }

    /// Refreshes limits and the model list (throttled unless forced).
    func refreshMeta(force: Bool = false) async {
        guard auth.isSignedIn else { return }
        if !force, let last = lastMetaRefresh, Date.now.timeIntervalSince(last) < 60 { return }
        lastMetaRefresh = .now
        async let usageTask: Void = refreshUsage()
        async let modelsTask: Void = refreshModels()
        _ = await (usageTask, modelsTask)
    }

    func refreshUsage() async {
        do {
            let tokens = try await auth.validTokens()
            let snapshot = try await ChatGPTClient(tokens: tokens).fetchUsage()
            usageError = nil
            applyUsage(snapshot)
        } catch ChatGPTClient.APIError.unauthorized {
            if (try? await auth.refresh()) != nil, let tokens = auth.tokens,
               let snapshot = try? await ChatGPTClient(tokens: tokens).fetchUsage() {
                applyUsage(snapshot)
            }
        } catch {
            usageError = Self.describe(error)
        }
    }

    private func refreshModels() async {
        guard let tokens = try? await auth.validTokens(),
              let fetched = try? await ChatGPTClient(tokens: tokens).fetchModels(),
              !fetched.isEmpty else { return }
        models = fetched
        if let data = try? JSONEncoder().encode(fetched) { defaults.set(data, forKey: Keys.models) }
        if !fetched.contains(where: { $0.slug == selectedModelSlug }) {
            selectedModelSlug = fetched[0].slug
        }
    }

    private func applyUsage(_ snapshot: UsageSnapshot) {
        var merged = usage.map { $0.merged(with: snapshot) } ?? snapshot
        if merged.planType == nil { merged.planType = auth.tokens?.planType }
        guard merged != usage else { return }
        usage = merged
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: Keys.usage) }
        publishWidget()
    }

    func signedOut() {
        newChat()
        usage = nil
        defaults.removeObject(forKey: Keys.usage)
        publishWidget()
    }

    // MARK: Widget

    func publishWidget() {
        let snapshot = WidgetSnapshot(
            signedIn: auth.isSignedIn,
            usage: usage,
            modelName: selectedModel.displayName,
            lastAnswer: lastAnswer.map { String($0.text.prefix(240)) }
        )
        guard snapshot != SharedStore.load() else { return }
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Persistence

    private struct SavedConversation: Codable {
        var id: String
        var messages: [ChatMessage]
    }

    private var conversationURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "conversation.json")
    }

    private func loadConversation() {
        guard let data = try? Data(contentsOf: conversationURL),
              let saved = try? JSONDecoder().decode(SavedConversation.self, from: data) else { return }
        // Start fresh if the last chat is older than 6 hours.
        if let last = saved.messages.last, Date.now.timeIntervalSince(last.date) > 6 * 3600 { return }
        conversationID = saved.id
        messages = saved.messages.filter { !$0.text.isEmpty }
        scrollTarget = messages.last(where: { $0.role == .user })?.id
    }

    private func saveConversation() {
        let saved = SavedConversation(id: conversationID, messages: messages.filter { !$0.text.isEmpty })
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: conversationURL, options: .atomic)
        }
    }
}
