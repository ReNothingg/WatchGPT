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
    private(set) var chats: [ChatThread] = []
    private(set) var status: Status = .idle
    private(set) var usage: UsageSnapshot?
    private(set) var models: [ModelOption] = ModelOption.fallback
    @ObservationIgnored private var effortOverrides: [String: [String]] = [:]
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
    var fastMode: Bool { didSet { defaults.set(fastMode, forKey: Keys.fast) } }

    // Voice input
    enum VoicePhase: Equatable { case idle, recording, transcribing, failed(String) }
    let recorder = AudioRecorder()
    private(set) var voicePhase: VoicePhase = .idle
    private(set) var lastVoiceLabel: String?
    var voiceEngine: VoiceEngine {
        didSet {
            defaults.set(voiceEngine.rawValue, forKey: Keys.voiceEngine)
            if voiceEngine == .chatgpt || voiceEngine == .auto { Transcriber.resetChatGPTAvailability() }
        }
    }
    var transcribeModel: TranscribeModel { didSet { defaults.set(transcribeModel.rawValue, forKey: Keys.transcribeModel) } }
    var voiceLanguage: String { didSet { defaults.set(voiceLanguage, forKey: Keys.voiceLanguage) } }
    @ObservationIgnored private var voiceTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRecording: URL?

    /// Drives the full-screen recorder.
    var isVoiceSheetPresented: Bool {
        get { voicePhase != .idle }
        set { if !newValue { cancelVoice() } }
    }

    private(set) var conversationID = UUID().uuidString
    private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var isInBackground = false
    @ObservationIgnored private var interruptedInBackground = false
    @ObservationIgnored private var resumeOnActive = false
    @ObservationIgnored private var didAutoResume = false
    @ObservationIgnored private var lastStreamActivity = Date.now
    private var lastMetaRefresh: Date?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let model = "settings.model"
        static let effort = "settings.effort"
        static let webSearch = "settings.webSearch"
        static let autoSpeak = "settings.autoSpeak"
        static let concise = "settings.concise"
        static let fast = "settings.fast"
        static let voiceEngine = "settings.voiceEngine"
        static let transcribeModel = "settings.transcribeModel"
        static let voiceLanguage = "settings.voiceLanguage"
        static let models = "cache.models"
        static let effortOverrides = "cache.effortOverrides"
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
        fastMode = d.object(forKey: Keys.fast) as? Bool ?? false
        voiceEngine = d.string(forKey: Keys.voiceEngine).flatMap(VoiceEngine.init(rawValue:)) ?? .auto
        transcribeModel = d.string(forKey: Keys.transcribeModel).flatMap(TranscribeModel.init(rawValue:)) ?? .best
        voiceLanguage = d.string(forKey: Keys.voiceLanguage) ?? "auto"
        Transcriber.resetChatGPTAvailability()

        effortOverrides = (d.dictionary(forKey: Keys.effortOverrides) as? [String: [String]]) ?? [:]
        if let data = d.data(forKey: Keys.models),
           let cached = try? JSONDecoder().decode([ModelOption].self, from: data), !cached.isEmpty {
            models = cached
        }
        models = applyEffortOverrides(models)
        if !selectedModel.efforts.isEmpty, !selectedModel.efforts.contains(effort) {
            effort = selectedModel.defaultEffort ?? selectedModel.efforts.first ?? "low"
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

    // MARK: Voice

    /// Whether the mic button should record with OpenAI speech-to-text (vs. Apple dictation).
    var usesCloudVoice: Bool { voiceEngine != .apple }

    func startVoice() {
        guard !isBusy, voicePhase == .idle || isFailedVoice else { return }
        speaker.stop()
        pendingRecording = nil
        voicePhase = .recording
        voiceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.recorder.start()
                WKInterfaceDevice.current().play(.start)
            } catch {
                self.voicePhase = .failed(Self.describe(error))
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    func toggleVoicePause() {
        guard voicePhase == .recording else { return }
        if recorder.isPaused {
            do {
                try recorder.resume()
                WKInterfaceDevice.current().play(.start)
            } catch {
                voicePhase = .failed(Self.describe(error))
                WKInterfaceDevice.current().play(.failure)
            }
        } else if recorder.isRecording {
            recorder.pause()
            WKInterfaceDevice.current().play(.stop)
        }
    }

    /// Stop recording → transcribe → send.
    func finishVoice() {
        guard voicePhase == .recording else { return }
        guard let url = recorder.stop() else {
            voicePhase = .failed("Слишком короткая запись. Нажмите и говорите.")
            return
        }
        WKInterfaceDevice.current().play(.click)
        pendingRecording = url
        transcribePending()
    }

    func retryTranscription() {
        guard pendingRecording != nil else { startVoice(); return }
        transcribePending()
    }

    func cancelVoice() {
        voiceTask?.cancel()
        voiceTask = nil
        if recorder.isActive { recorder.cancel() }
        pendingRecording = nil
        voicePhase = .idle
    }

    /// Text from the Apple dictation fallback on the error screen.
    func sendFromFallback(_ text: String) {
        cancelVoice()
        send(text)
    }

    private var isFailedVoice: Bool {
        if case .failed = voicePhase { return true }
        return false
    }

    private func transcribePending() {
        guard let url = pendingRecording else { return }
        voicePhase = .transcribing
        voiceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Transcriber.transcribe(
                    fileURL: url,
                    engine: self.voiceEngine,
                    model: self.transcribeModel,
                    language: self.voiceLanguage,
                    auth: self.auth
                )
                guard !Task.isCancelled else { return }
                self.lastVoiceLabel = result.label
                self.pendingRecording = nil
                self.voicePhase = .idle
                self.send(result.text)
            } catch {
                guard !Task.isCancelled else { return }
                self.voicePhase = .failed(Self.describe(error))
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    // MARK: Sending

    func send(_ raw: String) {
        didAutoResume = false
        submit(raw)
    }

    private func submit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        speaker.stop()
        interruptedInBackground = isInBackground
        resumeOnActive = false
        lastStreamActivity = .now

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
        didAutoResume = false
        resend()
    }

    private func resend() {
        guard !isBusy, let lastUser = messages.lastIndex(where: { $0.role == .user }) else { return }
        let text = messages[lastUser].text
        messages.removeSubrange(lastUser...)
        submit(text)
    }

    func stop() {
        resumeOnActive = false
        sendTask?.cancel()
        sendTask = nil
    }

    // MARK: Background

    func sceneEnteredBackground() {
        isInBackground = true
        if isBusy { interruptedInBackground = true }
    }

    func sceneBecameActive() {
        isInBackground = false
        if isBusy {
            guard interruptedInBackground, !didAutoResume,
                  Date.now.timeIntervalSince(lastStreamActivity) > 15 else { return }
            resumeOnActive = true
            sendTask?.cancel()
        } else if resumeOnActive {
            resumeInterrupted()
        }
    }

    private func resumeInterrupted() {
        resumeOnActive = false
        interruptedInBackground = false
        guard !didAutoResume, !isInBackground else { return }
        didAutoResume = true
        resend()
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        return (error as NSError).domain == NSPOSIXErrorDomain
    }

    func newChat() {
        stop()
        speaker.stop()
        saveConversation()
        messages = []
        conversationID = UUID().uuidString
        scrollTarget = nil
        publishWidget()
    }

    func openChat(_ id: String) {
        guard let chat = chats.first(where: { $0.id == id }) else { return }
        guard id != conversationID || messages.isEmpty else { return }
        stop()
        speaker.stop()
        saveConversation()
        conversationID = chat.id
        messages = chat.messages
        scrollTarget = messages.last(where: { $0.role == .user })?.id
        publishWidget()
    }

    func deleteChat(_ id: String) {
        if id == conversationID {
            stop()
            speaker.stop()
            messages = []
            conversationID = UUID().uuidString
            scrollTarget = nil
        }
        chats.removeAll { $0.id == id }
        writeChats()
        publishWidget()
    }

    func deleteAllChats() {
        stop()
        speaker.stop()
        messages = []
        conversationID = UUID().uuidString
        scrollTarget = nil
        chats = []
        writeChats()
        publishWidget()
    }

    private func generate(replyID: UUID) async {
        var didRetryAuth = false
        var didFixEffort = false
        let chatID = conversationID
        defer {
            status = .idle
            sendTask = nil
            if conversationID == chatID { saveConversation() }
            publishWidget()
            if resumeOnActive {
                if !isInBackground {
                    Task { @MainActor [weak self] in self?.resumeInterrupted() }
                }
            } else {
                interruptedInBackground = false
            }
        }

        while true {
            do {
                let tokens = try await auth.validTokens()
                let client = ChatGPTClient(tokens: tokens)
                let history = messages.filter { $0.id != replyID }
                let stream = client.stream(messages: history, options: requestOptions())

                var pending = ""
                var lastFlush = ContinuousClock.now - .seconds(1)
                func flush() {
                    guard !pending.isEmpty else { return }
                    let chunk = pending
                    pending = ""
                    lastFlush = .now
                    update(replyID) { $0.text += chunk }
                }

                do {
                    for try await event in stream {
                        lastStreamActivity = .now
                        switch event {
                        case let .textDelta(delta):
                            if status != .streaming { status = .streaming }
                            pending += delta
                            if ContinuousClock.now - lastFlush >= .milliseconds(120) { flush() }
                        case .searching:
                            if status != .streaming && status != .searching { status = .searching }
                        case let .usage(snapshot):
                            applyUsage(snapshot)
                        case .completed:
                            break
                        }
                    }
                    flush()
                } catch {
                    flush()
                    throw error
                }

                if text(of: replyID).isEmpty {
                    update(replyID) { $0.text = "Пустой ответ. Попробуйте ещё раз."; $0.isError = true }
                    WKInterfaceDevice.current().play(.failure)
                } else {
                    WKInterfaceDevice.current().play(.success)
                    if autoSpeak { speaker.speak(text(of: replyID)) }
                }
                return
            } catch where !didFixEffort && text(of: replyID).isEmpty && fixUnsupportedEffort(error) {
                didFixEffort = true
                continue
            } catch ChatGPTClient.APIError.unauthorized where !didRetryAuth {
                didRetryAuth = true
                do { try await auth.refresh() } catch { fail(replyID, error); return }
                continue
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    if text(of: replyID).isEmpty { messages.removeAll { $0.id == replyID } }
                    return
                }
                if (isInBackground || interruptedInBackground) && !didAutoResume && Self.isTransient(error) {
                    resumeOnActive = true
                    return
                }
                fail(replyID, error)
                if case let ChatGPTClient.APIError.usageLimit(resetAt) = error {
                    if let resetAt { LimitReminder.schedule(at: resetAt) }
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
            fast: fastMode && model.supportsFast == true,
            instructions: instructions(),
            context: "Current date and time: \(Date.now.formatted(date: .complete, time: .shortened)).",
            conversationID: conversationID
        )
    }

    private func instructions() -> String {
        let style = conciseAnswers
            ? "Be brief: lead with the answer, then at most 2–4 short sentences or a compact list. Expand only if the user explicitly asks for detail."
            : "Be clear and well structured, but keep in mind the screen is small; avoid filler."
        return """
        You are ChatGPT running on the user's Apple Watch. The user speaks to you through dictation, \
        so their message may contain speech-recognition mistakes — infer what they meant. \
        Always reply in the language of the user's message. \(style) \
        Write plain text that is easy to read on a tiny screen and to read aloud: no tables, no headings, \
        no code blocks unless essential; simple **bold** and short bullet lists are fine. \
        Math: write formulas in LaTeX. Short inline math goes in \\( … \\); every important formula goes \
        on its own line in \\[ … \\]. The screen is about 180 points wide, so keep each displayed formula short: \
        split long derivations into several \\[ … \\] lines, avoid wide matrices, never put formulas in code blocks. \
        Simple chemistry like H₂O can stay as plain text. \
        Locale: \(Locale.current.identifier).
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
        models = applyEffortOverrides(fetched)
        if let data = try? JSONEncoder().encode(fetched) { defaults.set(data, forKey: Keys.models) }
        if !fetched.contains(where: { $0.slug == selectedModelSlug }) {
            selectedModelSlug = fetched[0].slug
        }
    }

    private func applyEffortOverrides(_ list: [ModelOption]) -> [ModelOption] {
        list.map { model in
            guard let supported = effortOverrides[model.slug] else { return model }
            var fixed = model
            let kept = model.efforts.filter { supported.contains($0) }
            fixed.efforts = kept.isEmpty ? supported : kept
            if let current = fixed.defaultEffort, !fixed.efforts.contains(current) {
                fixed.defaultEffort = fixed.efforts.last { ModelOption.effortRank($0) <= ModelOption.effortRank(current) } ?? fixed.efforts.first
            }
            return fixed
        }
    }

    private func fixUnsupportedEffort(_ error: Error) -> Bool {
        let message: String
        switch error {
        case let ChatGPTClient.APIError.stream(m): message = m
        case let ChatGPTClient.APIError.http(_, m): message = m
        default: return false
        }
        guard let parsed = Self.parseUnsupportedValue(message), parsed.invalid == effort else { return false }
        let model = selectedModel
        let supported = parsed.supported
        effortOverrides[model.slug] = supported
        defaults.set(effortOverrides, forKey: Keys.effortOverrides)
        models = applyEffortOverrides(models)

        let rank = ModelOption.effortRank(parsed.invalid)
        let efforts = selectedModel.efforts
        effort = efforts.last { ModelOption.effortRank($0) < rank } ?? selectedModel.defaultEffort ?? efforts.first ?? "low"
        return true
    }

    static func parseUnsupportedValue(_ message: String) -> (invalid: String, supported: [String])? {
        guard let marker = message.range(of: "Supported values are", options: .caseInsensitive) else { return nil }
        func quoted(_ s: Substring) -> [String] {
            var out: [String] = []
            var rest = s
            while let open = rest.firstIndex(of: "'") {
                let after = rest.index(after: open)
                guard let close = rest[after...].firstIndex(of: "'") else { break }
                out.append(String(rest[after..<close]))
                rest = rest[rest.index(after: close)...]
            }
            return out
        }
        guard let invalid = quoted(message[..<marker.lowerBound]).last else { return nil }
        let supported = quoted(message[marker.upperBound...])
        return supported.isEmpty ? nil : (invalid, supported)
    }

    private func applyUsage(_ snapshot: UsageSnapshot) {
        var merged = usage.map { $0.merged(with: snapshot) } ?? snapshot
        if merged.planType == nil { merged.planType = auth.tokens?.planType }
        guard merged != usage else { return }
        usage = merged
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: Keys.usage) }
        LimitReminder.update(for: merged)
        publishWidget()
    }

    func signedOut() {
        deleteAllChats()
        usage = nil
        defaults.removeObject(forKey: Keys.usage)
        LimitReminder.update(for: nil)
        publishWidget()
    }

    // MARK: Widget

    func publishWidget() {
        let snapshot = WidgetSnapshot(
            signedIn: auth.isSignedIn,
            usage: usage,
            modelName: selectedModel.displayName,
            lastAnswer: lastAnswer.map { String(MathFormat.plain($0.text).prefix(240)) }
        )
        guard snapshot != SharedStore.load() else { return }
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Persistence

    private static let historyLimit = 60

    private var storeDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var chatsURL: URL { storeDirectory.appending(path: "chats.json") }
    private var legacyConversationURL: URL { storeDirectory.appending(path: "conversation.json") }

    private struct LegacyConversation: Codable {
        var id: String
        var messages: [ChatMessage]
    }

    private func loadConversation() {
        if let data = try? Data(contentsOf: chatsURL),
           let saved = try? JSONDecoder().decode([ChatThread].self, from: data) {
            chats = saved.sorted { $0.updatedAt > $1.updatedAt }
        } else if let data = try? Data(contentsOf: legacyConversationURL),
                  let legacy = try? JSONDecoder().decode(LegacyConversation.self, from: data),
                  let thread = ChatThread(id: legacy.id, messages: legacy.messages) {
            chats = [thread]
            writeChats()
            try? FileManager.default.removeItem(at: legacyConversationURL)
        }
        guard let latest = chats.first, Date.now.timeIntervalSince(latest.updatedAt) <= 6 * 3600 else { return }
        conversationID = latest.id
        messages = latest.messages
        scrollTarget = messages.last(where: { $0.role == .user })?.id
    }

    private func saveConversation() {
        let kept = messages.filter { !$0.text.isEmpty }
        chats.removeAll { $0.id == conversationID }
        if let thread = ChatThread(id: conversationID, messages: kept) {
            chats.insert(thread, at: 0)
            chats.sort { $0.updatedAt > $1.updatedAt }
            if chats.count > Self.historyLimit { chats.removeLast(chats.count - Self.historyLimit) }
        }
        writeChats()
    }

    private func writeChats() {
        if let data = try? JSONEncoder().encode(chats) {
            try? data.write(to: chatsURL, options: .atomic)
        }
    }
}
