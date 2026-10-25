import AppIntents
import Foundation

extension Notification.Name {
    static let watchGPTAskRequested = Notification.Name("watchGPTAskRequested")
}

enum AskRequest {
    private static let key = "control.askRequestedAt"

    static func mark() {
        SharedStore.defaults.set(Date.now.timeIntervalSince1970, forKey: key)
    }

    static func consume(maxAge: TimeInterval = 15) -> Bool {
        let stamp = SharedStore.defaults.double(forKey: key)
        guard stamp > 0 else { return false }
        SharedStore.defaults.removeObject(forKey: key)
        return Date.now.timeIntervalSince1970 - stamp <= maxAge
    }
}

struct AskChatGPTIntent: AppIntent {
    static let title: LocalizedStringResource = "Спросить ChatGPT"
    static let description = IntentDescription("Открывает WatchGPT и сразу включает диктовку.")
    static var openAppWhenRun: Bool { true }

    @available(watchOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        AskRequest.mark()
        NotificationCenter.default.post(name: .watchGPTAskRequested, object: nil)
        return .result()
    }
}
