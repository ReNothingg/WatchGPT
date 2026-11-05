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
    let keepAlive = KeepAlive()

    var path: [Route] = []

    var messages: [ChatMessage] = []
    var chats: [ChatThread] = []
    var status: Status = .idle {
        didSet { if status != oldValue { updateKeepAlive() } }
    }
    var usage: UsageSnapshot?
    var models: [ModelOption] = ModelOption.fallback
    @ObservationIgnored var effortOverrides: [String: [String]] = [:]
    var usageError: String?

    var pendingAsk = false
    var scrollTarget: UUID?

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
    var claudeModels: [ModelOption] = ModelOption.claudeFallback
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
    var voicePrompt: QuickPrompt?
    var editingMessageID: UUID?
    var codeHandoff: URL?
    @ObservationIgnored var codeHandoffTask: Task<Void, Never>?
    @ObservationIgnored var widgetPending: WidgetPending?
    let usageHistory = UsageHistory()

    static let answerFontRange: ClosedRange<Double> = 0.7...1.5
    static let answerFontStep: Double = 0.05

    static func clampedFontScale(_ value: Double) -> Double {
        let stepped = (value / answerFontStep).rounded() * answerFontStep
        return min(max(stepped, answerFontRange.lowerBound), answerFontRange.upperBound)
    }

    enum VoicePhase: Equatable { case idle, recording, transcribing, failed(String) }
    let recorder = AudioRecorder()
    let playback = RecordingPlayer()
    var voicePhase: VoicePhase = .idle {
        didSet { if voicePhase != oldValue { updateKeepAlive() } }
    }
    var lastVoiceLabel: String?
    var lastRecording: URL?
    var lastTranscript: String?
    var voiceEngine: VoiceEngine {
        didSet {
            defaults.set(voiceEngine.rawValue, forKey: Keys.voiceEngine)
            if voiceEngine == .chatgpt || voiceEngine == .auto { Transcriber.resetChatGPTAvailability() }
        }
    }
    var transcribeModel: TranscribeModel { didSet { defaults.set(transcribeModel.rawValue, forKey: Keys.transcribeModel) } }
    var voiceLanguage: String { didSet { defaults.set(voiceLanguage, forKey: Keys.voiceLanguage) } }
    var whisperMode: Bool { didSet { defaults.set(whisperMode, forKey: Keys.whisperMode) } }
    @ObservationIgnored var voiceTask: Task<Void, Never>?
    @ObservationIgnored var pendingRecording: URL?
    var voiceGivingUp = false
    @ObservationIgnored var voiceFailures = 0
    @ObservationIgnored var voiceCloseTask: Task<Void, Never>?
    static let maxVoiceFailures = 3

    var isVoiceSheetPresented: Bool {
        get { voicePhase != .idle && editingMessageID == nil }
        set { if !newValue { cancelVoice() } }
    }

    var conversationID = UUID().uuidString
    var sendTask: Task<Void, Never>?
    @ObservationIgnored var isInBackground = false
    @ObservationIgnored var interruptedInBackground = false
    @ObservationIgnored var resumeOnActive = false
    @ObservationIgnored var didAutoResume = false
    @ObservationIgnored var lastStreamActivity = Date.now
    @ObservationIgnored var siriRequest = false
    @ObservationIgnored var lastMetaRefresh: Date?
    @ObservationIgnored var publishedWidget: WidgetSnapshot?
    @ObservationIgnored var historyLoaded = false
    @ObservationIgnored var deletedBeforeLoad: Set<String> = []
    @ObservationIgnored var clearedBeforeLoad = false
    @ObservationIgnored var pendingOpenChatID: String?
    @ObservationIgnored var widgetAnswer: WidgetAnswer?
    let defaults = UserDefaults.standard

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
        answerFontScale = Self.clampedFontScale(d.object(forKey: Keys.answerFontScale) as? Double ?? 1.0)
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

    var usesCloudVoice: Bool { voiceEngine != .apple }
}
