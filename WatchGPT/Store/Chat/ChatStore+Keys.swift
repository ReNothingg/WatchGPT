import Foundation

extension ChatStore {
    enum Keys {
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
        static let resumableChatID = "state.resumableChatID"
    }
}
