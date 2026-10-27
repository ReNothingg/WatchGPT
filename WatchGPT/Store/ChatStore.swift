import Foundation
import Observation
import WatchKit
import WidgetKit

@MainActor
@Observable
final class ChatStore {
    enum Status: Equatable { case idle, waitingForNetwork, thinking, searching, streaming }

    let auth: AuthService
    let speaker = Speaker()
    let gptHistory: GPTHistory
    private let keepAlive = KeepAlive()

    var path: [Route] = []

    private(set) var messages: [ChatMessage] = []
    private(set) var chats: [ChatThread] = []
    private(set) var status: Status = .idle {
        didSet { if status != oldValue { updateKeepAlive() } }
    }
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
            if !gptModel.efforts.isEmpty, !gptModel.efforts.contains(gptEffort) {
                gptEffort = gptModel.defaultEffort ?? gptModel.efforts.first ?? "low"
            }
            publishWidget()
        }
    }
    var gptEffort: String { didSet { defaults.set(gptEffort, forKey: Keys.effort) } }
    var provider: Provider { didSet { defaults.set(provider.rawValue, forKey: Keys.provider) } }
    private(set) var claudeModels: [ModelOption] = ModelOption.claudeFallback
    var claudeModelSlug: String {
        didSet {
            defaults.set(claudeModelSlug, forKey: Keys.claudeModel)
            if !claudeModel.efforts.isEmpty, !claudeModel.efforts.contains(claudeEffort) {
                claudeEffort = claudeModel.defaultEffort ?? claudeModel.efforts.first ?? "low"
            }
        }
    }
    var claudeEffort: String { didSet { defaults.set(claudeEffort, forKey: Keys.claudeEffort) } }

    var effort: String {
        get { provider == .claude ? claudeEffort : gptEffort }
        set {
            if provider == .claude { claudeEffort = newValue } else { gptEffort = newValue }
        }
    }
    var webSearch: Bool { didSet { defaults.set(webSearch, forKey: Keys.webSearch) } }
    var autoSpeak: Bool { didSet { defaults.set(autoSpeak, forKey: Keys.autoSpeak) } }
    var conciseAnswers: Bool { didSet { defaults.set(conciseAnswers, forKey: Keys.concise) } }
    var fastMode: Bool { didSet { defaults.set(fastMode, forKey: Keys.fast) } }
    var handoff: Bool { didSet { defaults.set(handoff, forKey: Handoff.defaultsKey) } }
    var answerFontScale: Double { didSet { defaults.set(answerFontScale, forKey: Keys.answerFontScale) } }
    var quickPrompts: [QuickPrompt] {
        didSet {
            if let data = try? JSONEncoder().encode(quickPrompts) { defaults.set(data, forKey: Keys.quickPrompts) }
        }
    }
    private(set) var voicePrompt: QuickPrompt?
    let usageHistory = UsageHistory()

    static let answerFontScales: [Double] = [0.8, 0.9, 1.0, 1.15, 1.3, 1.5]

    // Voice input
    enum VoicePhase: Equatable { case idle, recording, transcribing, failed(String) }
    let recorder = AudioRecorder()
    let playback = RecordingPlayer()
    private(set) var voicePhase: VoicePhase = .idle {
        didSet { if voicePhase != oldValue { updateKeepAlive() } }
    }
    private(set) var lastVoiceLabel: String?
    private(set) var lastRecording: URL?
    private(set) var lastTranscript: String?
    var voiceEngine: VoiceEngine {
        didSet {
            defaults.set(voiceEngine.rawValue, forKey: Keys.voiceEngine)
            if voiceEngine == .chatgpt || voiceEngine == .auto { Transcriber.resetChatGPTAvailability() }
        }
    }
    var transcribeModel: TranscribeModel { didSet { defaults.set(transcribeModel.rawValue, forKey: Keys.transcribeModel) } }
    var voiceLanguage: String { didSet { defaults.set(voiceLanguage, forKey: Keys.voiceLanguage) } }
    var whisperMode: Bool { didSet { defaults.set(whisperMode, forKey: Keys.whisperMode) } }
    @ObservationIgnored private var voiceTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRecording: URL?
    private(set) var voiceGivingUp = false
    @ObservationIgnored private var voiceFailures = 0
    @ObservationIgnored private var voiceCloseTask: Task<Void, Never>?
    private static let maxVoiceFailures = 3

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
    @ObservationIgnored private var siriRequest = false
    @ObservationIgnored private var lastMetaRefresh: Date?
    @ObservationIgnored private var publishedWidget: WidgetSnapshot?
    @ObservationIgnored private var historyLoaded = false
    @ObservationIgnored private var deletedBeforeLoad: Set<String> = []
    @ObservationIgnored private var clearedBeforeLoad = false
    @ObservationIgnored private var pendingOpenChatID: String?
    @ObservationIgnored private var widgetAnswer: WidgetAnswer?
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
        static let whisperMode = "settings.whisperMode"
        static let answerFontScale = "settings.answerFontScale"
        static let quickPrompts = "settings.quickPrompts"
        static let models = "cache.models"
        static let modelsFetchedAt = "cache.modelsFetchedAt"
        static let effortOverrides = "cache.effortOverrides"
        static let usage = "cache.usage"
        static let provider = "settings.provider"
        static let claudeModel = "settings.claudeModel"
        static let claudeEffort = "settings.claudeEffort"
        static let claudeModels = "cache.claudeModels"
        static let claudeModelsFetchedAt = "cache.claudeModelsFetchedAt"
    }

    init(auth: AuthService) {
        self.auth = auth
        gptHistory = GPTHistory(auth: auth)
        let d = UserDefaults.standard
        selectedModelSlug = d.string(forKey: Keys.model) ?? ModelOption.fallback[0].slug
        gptEffort = d.string(forKey: Keys.effort) ?? "low"
        let savedProvider = d.string(forKey: Keys.provider).flatMap(Provider.init(rawValue:)) ?? .chatgpt
        provider = savedProvider == .claude && !auth.hasClaudeKey ? .chatgpt : savedProvider
        claudeModelSlug = d.string(forKey: Keys.claudeModel) ?? ModelOption.claudeFallback[0].slug
        claudeEffort = d.string(forKey: Keys.claudeEffort) ?? "low"
        webSearch = d.object(forKey: Keys.webSearch) as? Bool ?? true
        autoSpeak = d.object(forKey: Keys.autoSpeak) as? Bool ?? false
        conciseAnswers = d.object(forKey: Keys.concise) as? Bool ?? true
        fastMode = d.object(forKey: Keys.fast) as? Bool ?? false
        handoff = d.object(forKey: Handoff.defaultsKey) as? Bool ?? true
        voiceEngine = d.string(forKey: Keys.voiceEngine).flatMap(VoiceEngine.init(rawValue:)) ?? .auto
        transcribeModel = d.string(forKey: Keys.transcribeModel).flatMap(TranscribeModel.init(rawValue:)) ?? .best
        voiceLanguage = d.string(forKey: Keys.voiceLanguage) ?? "auto"
        whisperMode = d.object(forKey: Keys.whisperMode) as? Bool ?? false
        answerFontScale = d.object(forKey: Keys.answerFontScale) as? Double ?? 1.0
        quickPrompts = d.data(forKey: Keys.quickPrompts).flatMap { try? JSONDecoder().decode([QuickPrompt].self, from: $0) }
            ?? QuickPrompt.defaults
        Transcriber.resetChatGPTAvailability()

        effortOverrides = (d.dictionary(forKey: Keys.effortOverrides) as? [String: [String]]) ?? [:]
        if let data = d.data(forKey: Keys.models),
           let cached = try? JSONDecoder().decode([ModelOption].self, from: data), !cached.isEmpty {
            models = cached
        }
        models = applyEffortOverrides(models)
        if !gptModel.efforts.isEmpty, !gptModel.efforts.contains(gptEffort) {
            gptEffort = gptModel.defaultEffort ?? gptModel.efforts.first ?? "low"
        }
        if let data = d.data(forKey: Keys.claudeModels),
           let cached = try? JSONDecoder().decode([ModelOption].self, from: data), !cached.isEmpty {
            claudeModels = cached
        }
        if !claudeModel.efforts.isEmpty, !claudeModel.efforts.contains(claudeEffort) {
            claudeEffort = claudeModel.defaultEffort ?? claudeModel.efforts.first ?? "low"
        }
        if let data = d.data(forKey: Keys.usage) {
            usage = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        }
        if let usage, usageHistory.isEmpty { usageHistory.record(usage) }
        loadConversation()
        let shared = SharedStore.load()
        publishedWidget = shared
        widgetAnswer = shared.lastAnswer
    }

    var gptModel: ModelOption {
        models.first { $0.slug == selectedModelSlug } ?? models.first ?? ModelOption.fallback[0]
    }

    var claudeModel: ModelOption {
        claudeModels.first { $0.slug == claudeModelSlug } ?? claudeModels.first ?? ModelOption.claudeFallback[0]
    }

    var selectedModel: ModelOption { provider == .claude ? claudeModel : gptModel }

    func select(_ model: ModelOption, provider: Provider) {
        if provider == .claude {
            claudeModelSlug = model.slug
        } else {
            selectedModelSlug = model.slug
        }
        self.provider = provider
        publishWidget()
    }

    func isSelected(_ model: ModelOption, provider: Provider) -> Bool {
        self.provider == provider && model.slug == (provider == .claude ? claudeModelSlug : selectedModelSlug)
    }

    var isBusy: Bool { status != .idle }

    var lastAnswer: ChatMessage? {
        messages.last { $0.role == .assistant && !$0.isError && !$0.text.isEmpty }
    }

    // MARK: Voice

    /// Whether the mic button should record with OpenAI speech-to-text (vs. Apple dictation).
    var usesCloudVoice: Bool { voiceEngine != .apple }

    func startVoice() {
        guard !isBusy, !voiceGivingUp, voicePhase == .idle || isFailedVoice else { return }
        speaker.stop()
        playback.stop()
        pendingRecording = nil
        voicePhase = .recording
        voiceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.recorder.start(whisper: self.whisperMode)
                guard !Task.isCancelled, self.voicePhase == .recording else {
                    self.recorder.cancel()
                    return
                }
                WKInterfaceDevice.current().play(.start)
            } catch {
                guard !Task.isCancelled else { return }
                DiagnosticsLog.shared.record(.voice, error)
                self.failVoice(Self.describe(error))
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
                failVoice(Self.describe(error))
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
            failVoice("Слишком короткая запись. Нажмите и говорите.")
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
        voiceCloseTask?.cancel()
        voiceCloseTask = nil
        voiceFailures = 0
        voiceGivingUp = false
        if recorder.isActive { recorder.cancel() }
        pendingRecording = nil
        voicePrompt = nil
        voicePhase = .idle
    }

    /// Text from the Apple dictation fallback on the error screen.
    func sendFromFallback(_ text: String) {
        let message = withVoicePrompt(text)
        cancelVoice()
        send(message)
    }

    func runQuickPrompt(_ prompt: QuickPrompt) {
        guard !isBusy, voicePhase == .idle else { return }
        let wasNavigated = !path.isEmpty
        path = []
        guard prompt.asksVoice else {
            send(prompt.text)
            return
        }
        Task { @MainActor [weak self] in
            if wasNavigated { try? await Task.sleep(for: .milliseconds(450)) }
            guard let self, !self.isBusy, self.voicePhase == .idle else { return }
            if self.usesCloudVoice {
                self.startVoice()
                if self.voicePhase == .recording { self.voicePrompt = prompt }
            } else {
                Dictation.present { [weak self] text in self?.send(prompt.message(with: text)) }
            }
        }
    }

    private func withVoicePrompt(_ text: String) -> String {
        guard let prompt = voicePrompt else { return text }
        voicePrompt = nil
        return prompt.message(with: text)
    }

    private func failVoice(_ message: String) {
        voiceFailures += 1
        voicePhase = .failed(message)
        WKInterfaceDevice.current().play(.failure)
        guard voiceFailures >= Self.maxVoiceFailures else { return }
        voiceGivingUp = true
        voiceCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.voiceGivingUp else { return }
            self.cancelVoice()
        }
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
            var file = url
            if AudioBoost.needsBoost(file) {
                file = await AudioBoost.prepare(file)
                guard !Task.isCancelled else { return }
                self.pendingRecording = file
            }
            self.keepLastRecording(file)
            do {
                let result = try await Transcriber.transcribe(
                    fileURL: file,
                    engine: self.voiceEngine,
                    model: self.transcribeModel,
                    language: self.voiceLanguage,
                    whisper: self.whisperMode,
                    context: self.voiceContext,
                    auth: self.auth
                )
                guard !Task.isCancelled else { return }
                self.lastVoiceLabel = result.label
                self.lastTranscript = result.text
                self.pendingRecording = nil
                self.voiceFailures = 0
                let message = self.withVoicePrompt(result.text)
                self.voicePhase = .idle
                self.send(message)
            } catch {
                guard !Task.isCancelled else { return }
                DiagnosticsLog.shared.record(.voice, error)
                self.failVoice(Self.describe(error))
            }
        }
    }

    private func keepLastRecording(_ file: URL) {
        playback.stop()
        let manager = FileManager.default
        let copy = manager.temporaryDirectory.appending(path: "last-dictation.\(file.pathExtension)")
        if let lastRecording { try? manager.removeItem(at: lastRecording) }
        try? manager.removeItem(at: copy)
        lastTranscript = nil
        lastRecording = (try? manager.copyItem(at: file, to: copy)) != nil ? copy : nil
    }

    private var voiceContext: String? {
        let recent = messages.filter { !$0.isError && !$0.text.isEmpty }.suffix(4)
        guard !recent.isEmpty else { return nil }
        return recent.map { message in
            let who = message.role == .user ? "User" : "Assistant"
            let text = message.text.replacingOccurrences(of: "\n", with: " ")
            return "\(who): \(text.prefix(240))"
        }.joined(separator: "\n")
    }

    // MARK: Sending

    func send(_ raw: String) {
        didAutoResume = false
        submit(raw)
    }

    func askFromSiri(_ raw: String) async throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SiriAskError.empty }
        guard auth.isSignedIn else { throw SiriAskError.signedOut }
        guard !isBusy, voicePhase == .idle else { throw SiriAskError.busy }

        newChat()
        siriRequest = true
        didAutoResume = true
        defer { siriRequest = false }
        submit(text)
        let task = sendTask
        await task?.value

        guard let reply = messages.last, reply.role == .assistant, !reply.text.isEmpty else {
            throw SiriAskError.failed("Ответ не получен. Попробуйте ещё раз.")
        }
        if reply.isError { throw SiriAskError.failed(reply.text) }
        return reply.text
    }

    func refine(_ kind: ChatMessage.Refinement) {
        guard lastAnswer != nil, messages.last?.isError != true else { return }
        didAutoResume = false
        submit(kind.label, refine: kind)
    }

    var canRefine: Bool {
        !isBusy && messages.last.map { $0.role == .assistant && !$0.isError && !$0.text.isEmpty } == true
    }

    private func submit(_ raw: String, refine: ChatMessage.Refinement? = nil) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        speaker.stop()
        interruptedInBackground = isInBackground
        resumeOnActive = false
        lastStreamActivity = .now

        let question = ChatMessage(role: .user, text: text, refine: refine)
        let reply = ChatMessage(role: .assistant, text: "", claude: provider == .claude ? true : nil)
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
        let question = messages[lastUser]
        messages.removeSubrange(lastUser...)
        submit(question.text, refine: question.refine)
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
        updateKeepAlive()
        if isBusy {
            guard interruptedInBackground, !didAutoResume,
                  Date.now.timeIntervalSince(lastStreamActivity) > 15 else { return }
            resumeOnActive = true
            sendTask?.cancel()
        } else {
            resumePendingIfNeeded()
        }
    }

    private func resumeInterrupted() {
        resumeOnActive = false
        interruptedInBackground = false
        guard !didAutoResume, !isInBackground else { return }
        didAutoResume = true
        resend()
    }

    private func updateKeepAlive() {
        let working = status != .idle || voicePhase == .recording || voicePhase == .transcribing
        if working {
            keepAlive.hold()
        } else {
            let looking = WKApplication.shared().applicationState == .active
            keepAlive.release(after: looking ? .seconds(2) : .seconds(120))
        }
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
        if let answer = chat.messages.last(where: { $0.role == .assistant && !$0.isError }) {
            let answeredBy: Provider = answer.claude == true ? .claude : .chatgpt
            if answeredBy == .chatgpt || auth.hasClaudeKey { provider = answeredBy }
        }
        publishWidget()
    }

    var localGPTChatIDs: Set<String> {
        Set(chats.lazy.filter(\.isFromGPT).map(\.id))
    }

    func continueGPTChat(_ conversation: RemoteConversation, ask: Bool) {
        guard !isBusy else { return }
        let localID = ChatThread.gptID(conversation.id)
        let local = localID == conversationID ? messages : chats.first { $0.id == localID }?.messages ?? []
        let watchOnly = local.filter { $0.fromGPT != true && !$0.isError && !$0.text.isEmpty }
        let merged = (conversation.messages + watchOnly).sorted { $0.date < $1.date }

        speaker.stop()
        if conversationID != localID { saveConversation() }
        conversationID = localID
        messages = Array(merged.suffix(Self.importLimit))
        scrollTarget = messages.last(where: { $0.role == .user })?.id
        saveConversation(title: conversation.title)
        provider = .chatgpt
        publishWidget()
        path = []
        if ask { pendingAsk = true }
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
        if !historyLoaded { deletedBeforeLoad.insert(id) }
        if widgetAnswer?.chatID == id { widgetAnswer = nil }
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
        widgetAnswer = nil
        if !historyLoaded {
            clearedBeforeLoad = true
            deletedBeforeLoad = []
            DiskWriter.shared.writeJSON([ChatThread](), to: Self.chatsURL)
        }
        writeChats()
        publishWidget()
    }

    private func generate(replyID: UUID) async {
        var didRetryAuth = false
        var didFixEffort = false
        var didUpgradeClient = false
        let chatID = conversationID
        let useClaude = provider == .claude
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
                let history = messages.filter { $0.id != replyID }
                let stream: AsyncThrowingStream<ChatGPTClient.StreamEvent, Error>
                if useClaude {
                    guard let key = auth.claudeKey?.key else { throw AnthropicClient.APIError.noKey }
                    stream = AnthropicClient(apiKey: key).stream(messages: history, options: claudeOptions())
                } else {
                    let tokens = try await auth.validTokens()
                    stream = ChatGPTClient(tokens: tokens).stream(messages: history, options: requestOptions())
                }

                var pending = ""
                var lastFlush = ContinuousClock.now - .seconds(1)
                func flushInterval() -> Duration {
                    if WKApplication.shared().applicationState != .active { return .seconds(1) }
                    return PowerMonitor.shared.isLowPower ? .milliseconds(250) : .milliseconds(120)
                }
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
                        case .waitingForNetwork:
                            if siriRequest { throw URLError(.notConnectedToInternet) }
                            if status == .thinking { status = .waitingForNetwork }
                        case .responseStarted:
                            if status == .waitingForNetwork { status = .thinking }
                        case let .textDelta(delta):
                            if status != .streaming { status = .streaming }
                            pending += delta
                            if ContinuousClock.now - lastFlush >= flushInterval() { flush() }
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
                    DiagnosticsLog.shared.markSuccess()
                    widgetAnswer = makeWidgetAnswer(replyID: replyID, chatID: chatID) ?? widgetAnswer
                    WKInterfaceDevice.current().play(.success)
                    if autoSpeak && !siriRequest { speaker.speak(text(of: replyID)) }
                }
                return
            } catch where !useClaude && !didFixEffort && text(of: replyID).isEmpty && fixUnsupportedEffort(error) {
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
                if !useClaude, !didUpgradeClient, text(of: replyID).isEmpty, await ClientVersion.refreshAfterError(error) {
                    didUpgradeClient = true
                    continue
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
        DiagnosticsLog.shared.record(.answer, error)
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
        let model = gptModel
        let refine = messages.last { $0.role == .user }?.refine
        var verbosity = refine?.verbosity ?? (conciseAnswers ? "low" : "medium")
        if siriRequest { verbosity = "low" }
        return ChatGPTClient.Options(
            model: model.slug,
            effort: requestEffort(model, selected: gptEffort),
            webSearch: webSearch,
            verbosity: model.supportsVerbosity ? verbosity : nil,
            fast: fastMode && model.supportsFast == true,
            instructions: instructions(assistant: "ChatGPT"),
            context: requestContext(),
            conversationID: conversationID
        )
    }

    private func claudeOptions() -> AnthropicClient.Options {
        let model = claudeModel
        return AnthropicClient.Options(
            model: model.slug,
            effort: requestEffort(model, selected: claudeEffort),
            thinking: model.thinking == true,
            webSearch: webSearch,
            fast: fastMode && model.supportsFast == true,
            instructions: instructions(assistant: "Claude"),
            context: requestContext()
        )
    }

    private func requestEffort(_ model: ModelOption, selected: String) -> String? {
        guard !model.efforts.isEmpty else { return nil }
        if siriRequest {
            return model.efforts.min { ModelOption.effortRank($0) < ModelOption.effortRank($1) }
        }
        return model.efforts.contains(selected) ? selected : model.defaultEffort
    }

    private func requestContext() -> String {
        var context = "Current date and time: \(Date.now.formatted(date: .complete, time: .shortened))."
        if siriRequest {
            context += " Siri will read this answer aloud: reply in one to three short spoken sentences, without lists, formulas or markdown."
        }
        return context
    }

    private func instructions(assistant: String) -> String {
        let style = conciseAnswers
            ? "Be brief: lead with the answer, then at most 2–4 short sentences or a compact list. Expand only if the user explicitly asks for detail."
            : "Be clear and well structured, but keep in mind the screen is small; avoid filler."
        return """
        You are \(assistant) running on the user's Apple Watch. The user speaks to you through dictation, \
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
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func text(of id: UUID) -> String {
        messages.last { $0.id == id }?.text ?? ""
    }

    // MARK: Usage & models

    func handle(url: URL) {
        guard url.scheme == "watchgpt" else { return }
        switch url.host {
        case "ask":
            pendingAsk = true
        case "open":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let chatID = components?.queryItems?.first(where: { $0.name == "chat" })?.value {
                openFromLink(chatID)
            }
        case "usage":
            guard auth.isSignedIn, voicePhase == .idle else { return }
            path = [.usage]
        default:
            break
        }
    }

    private func openFromLink(_ id: String) {
        guard auth.isSignedIn, voicePhase == .idle else { return }
        path = []
        guard id != conversationID, !isBusy else { return }
        if chats.contains(where: { $0.id == id }) {
            openChat(id)
        } else if !historyLoaded {
            pendingOpenChatID = id
        }
    }

    private static let usageMaxAge: TimeInterval = 120
    private static let modelsMaxAge: TimeInterval = 6 * 3600

    /// Refreshes limits and the model list (throttled unless forced).
    func refreshMeta(force: Bool = false) async {
        guard auth.isSignedIn else { return }
        let now = Date.now
        if !force, let last = lastMetaRefresh, now.timeIntervalSince(last) < 60 { return }
        lastMetaRefresh = now
        let usageStale = force || usage.map { now.timeIntervalSince($0.updatedAt) >= Self.usageMaxAge } ?? true
        let modelsStale = modelsAreStale(maxAge: Self.modelsMaxAge)
        let claudeStale = auth.hasClaudeKey && claudeModelsAreStale(maxAge: Self.modelsMaxAge)
        await withTaskGroup(of: Void.self) { group in
            if usageStale { group.addTask { await self.refreshUsage() } }
            if modelsStale { group.addTask { await self.refreshModels() } }
            if claudeStale { group.addTask { await self.refreshClaudeModels() } }
            group.addTask { await self.refreshClientVersion() }
        }
    }

    func refreshModels(ifOlderThan maxAge: TimeInterval) async {
        guard auth.isSignedIn, modelsAreStale(maxAge: maxAge) else { return }
        await refreshModels()
    }

    func refreshClaudeModels(ifOlderThan maxAge: TimeInterval) async {
        guard auth.hasClaudeKey, claudeModelsAreStale(maxAge: maxAge) else { return }
        await refreshClaudeModels()
    }

    func refreshClaudeModels() async {
        guard let key = auth.claudeKey?.key else { return }
        do {
            let fetched = try await AnthropicClient(apiKey: key).fetchModels()
            guard auth.claudeKey?.key == key, !fetched.isEmpty else { return }
            defaults.set(Date.now, forKey: Keys.claudeModelsFetchedAt)
            if fetched != claudeModels { claudeModels = fetched }
            if let data = try? JSONEncoder().encode(fetched) { defaults.set(data, forKey: Keys.claudeModels) }
            if !fetched.contains(where: { $0.slug == claudeModelSlug }) {
                claudeModelSlug = fetched.first { $0.slug == ModelOption.claudeFallback[0].slug }?.slug ?? fetched[0].slug
            }
        } catch {
            if GPTHistory.isCancellation(error) { return }
            DiagnosticsLog.shared.record(.models, error)
        }
    }

    func claudeKeyChanged() {
        defaults.removeObject(forKey: Keys.claudeModelsFetchedAt)
        if auth.hasClaudeKey {
            Task { await refreshClaudeModels() }
        } else {
            provider = .chatgpt
            claudeModels = ModelOption.claudeFallback
            defaults.removeObject(forKey: Keys.claudeModels)
        }
    }

    private func claudeModelsAreStale(maxAge: TimeInterval) -> Bool {
        guard let fetchedAt = defaults.object(forKey: Keys.claudeModelsFetchedAt) as? Date else { return true }
        return Date.now.timeIntervalSince(fetchedAt) >= maxAge
    }

    private func modelsAreStale(maxAge: TimeInterval) -> Bool {
        guard let fetchedAt = defaults.object(forKey: Keys.modelsFetchedAt) as? Date else { return true }
        return Date.now.timeIntervalSince(fetchedAt) >= maxAge
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
            DiagnosticsLog.shared.record(.usage, error)
        }
    }

    func refreshClientVersion() async {
        guard auth.isSignedIn else { return }
        if case .updated = await ClientVersion.refresh() { await refreshModels() }
    }

    func refreshModels() async {
        guard let tokens = try? await auth.validTokens() else { return }
        var fetched: [ModelOption] = []
        var didUpgradeClient = false
        while true {
            do {
                fetched = try await ChatGPTClient(tokens: tokens).fetchModels()
                break
            } catch {
                if GPTHistory.isCancellation(error) { return }
                if !didUpgradeClient, await ClientVersion.refreshAfterError(error) {
                    didUpgradeClient = true
                    continue
                }
                DiagnosticsLog.shared.record(.models, error)
                return
            }
        }
        guard !fetched.isEmpty else { return }
        defaults.set(Date.now, forKey: Keys.modelsFetchedAt)
        let adjusted = applyEffortOverrides(fetched)
        if adjusted != models { models = adjusted }
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
        guard let parsed = Self.parseUnsupportedValue(message), parsed.invalid == gptEffort else { return false }
        let model = gptModel
        let supported = parsed.supported
        effortOverrides[model.slug] = supported
        defaults.set(effortOverrides, forKey: Keys.effortOverrides)
        models = applyEffortOverrides(models)

        let rank = ModelOption.effortRank(parsed.invalid)
        let efforts = gptModel.efforts
        gptEffort = efforts.last { ModelOption.effortRank($0) < rank } ?? gptModel.defaultEffort ?? efforts.first ?? "low"
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
        let contentChanged = merged.ignoringTimestamp != usage?.ignoringTimestamp
        usage = merged
        if contentChanged { usageHistory.record(merged) }
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: Keys.usage) }
        guard contentChanged else { return }
        LimitReminder.update(for: merged)
        publishWidget()
    }

    func signedOut() {
        deleteAllChats()
        gptHistory.clear()
        path = []
        usage = nil
        usageHistory.clear()
        defaults.removeObject(forKey: Keys.usage)
        defaults.removeObject(forKey: Keys.modelsFetchedAt)
        LimitReminder.update(for: nil)
        publishWidget()
    }

    // MARK: Widget

    func publishWidget() {
        let snapshot = WidgetSnapshot(
            signedIn: auth.isSignedIn,
            usage: usage?.forWidget,
            lastAnswer: auth.isSignedIn ? widgetAnswer : nil
        )
        let previous = publishedWidget ?? SharedStore.load()
        publishedWidget = snapshot
        guard snapshot != previous else { return }
        SharedStore.save(snapshot)

        var kinds: Set<String> = []
        if snapshot.signedIn != previous.signedIn || snapshot.usage != previous.usage {
            kinds.formUnion([SharedStore.askWidgetKind, SharedStore.limitsWidgetKind])
        }
        if snapshot.signedIn != previous.signedIn || snapshot.lastAnswer != previous.lastAnswer {
            kinds.insert(SharedStore.answerWidgetKind)
        }
        for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    private func makeWidgetAnswer(replyID: UUID, chatID: String) -> WidgetAnswer? {
        guard let index = messages.lastIndex(where: { $0.id == replyID }) else { return nil }
        let answer = Self.widgetText(messages[index].text, limit: 300)
        guard !answer.isEmpty else { return nil }
        let question = messages[..<index].last { $0.role == .user && $0.refine == nil }?.text ?? ""
        return WidgetAnswer(question: Self.widgetText(question, limit: 80), answer: answer, date: .now, chatID: chatID)
    }

    private static func widgetText(_ text: String, limit: Int) -> String {
        let flat = Speaker.plain(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    // MARK: Persistence

    private static let historyLimit = 60
    private static let importLimit = 50
    private static let restoreWindow: TimeInterval = 6 * 3600

    private static let chatsURL = AppFiles.url("chats.json")
    private static let latestChatURL = AppFiles.url("latest-chat.json")
    private static let legacyConversationURL = AppFiles.url("conversation.json")

    private struct LegacyConversation: Codable {
        var id: String
        var messages: [ChatMessage]
    }

    nonisolated private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func loadConversation() {
        if let latest = Self.read(ChatThread.self, from: Self.latestChatURL) {
            chats = [latest]
            restore(latest)
            Task { await loadHistory() }
            return
        }
        historyLoaded = true
        if let saved = Self.read([ChatThread].self, from: Self.chatsURL) {
            chats = saved.sorted { $0.updatedAt > $1.updatedAt }
            if let latest = chats.first { DiskWriter.shared.writeJSON(latest, to: Self.latestChatURL) }
        } else if let legacy = Self.read(LegacyConversation.self, from: Self.legacyConversationURL),
                  let thread = ChatThread(id: legacy.id, messages: legacy.messages) {
            chats = [thread]
            writeChats()
            try? FileManager.default.removeItem(at: Self.legacyConversationURL)
        }
        if let latest = chats.first { restore(latest) }
    }

    private func restore(_ latest: ChatThread) {
        guard Date.now.timeIntervalSince(latest.updatedAt) <= Self.restoreWindow else { return }
        conversationID = latest.id
        messages = latest.messages
        scrollTarget = messages.last(where: { $0.role == .user })?.id
        if let last = messages.last, last.role == .user, last.fromGPT != true,
           Date.now.timeIntervalSince(last.date) <= 3600 {
            resumeOnActive = true
        }
    }

    private func loadHistory() async {
        let url = Self.chatsURL
        let saved = await Task.detached(priority: .userInitiated) {
            ChatStore.read([ChatThread].self, from: url) ?? []
        }.value

        var merged = clearedBeforeLoad ? [] : saved.filter { !deletedBeforeLoad.contains($0.id) }
        for thread in chats {
            if let index = merged.firstIndex(where: { $0.id == thread.id }) {
                merged[index] = thread
            } else {
                merged.append(thread)
            }
        }
        merged.sort { $0.updatedAt > $1.updatedAt }
        if merged.count > Self.historyLimit { merged.removeLast(merged.count - Self.historyLimit) }

        historyLoaded = true
        deletedBeforeLoad = []
        clearedBeforeLoad = false
        chats = merged
        if merged != saved { writeChats() }
        if let id = pendingOpenChatID {
            pendingOpenChatID = nil
            openFromLink(id)
        }
    }

    func resumePendingIfNeeded() {
        guard resumeOnActive, !isBusy, !isInBackground, auth.isSignedIn else { return }
        resumeInterrupted()
    }

    private func saveConversation(title: String? = nil) {
        let kept = messages.filter { !$0.text.isEmpty }
        let index = chats.firstIndex { $0.id == conversationID }
        if let index, title == nil, chats[index].messages == kept { return }
        let keptTitle = title ?? index.flatMap { chats[$0].isFromGPT ? chats[$0].title : nil }
        let thread = ChatThread(id: conversationID, messages: kept, title: keptTitle)
        if index == nil, thread == nil { return }
        if let index { chats.remove(at: index) }
        if let thread {
            chats.insert(thread, at: 0)
            chats.sort { $0.updatedAt > $1.updatedAt }
            if chats.count > Self.historyLimit { chats.removeLast(chats.count - Self.historyLimit) }
        }
        writeChats()
    }

    private func writeChats() {
        if let latest = chats.first {
            DiskWriter.shared.writeJSON(latest, to: Self.latestChatURL)
        } else {
            DiskWriter.shared.remove(Self.latestChatURL)
        }
        guard historyLoaded else { return }
        DiskWriter.shared.writeJSON(chats, to: Self.chatsURL)
    }
}
