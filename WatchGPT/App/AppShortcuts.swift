import AppIntents

struct WatchGPTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskQuestionIntent(),
            phrases: [
                "Спроси \(.applicationName)",
                "Спросить \(.applicationName)",
                "Вопрос \(.applicationName)",
                "Ask \(.applicationName)",
            ],
            shortTitle: "Вопрос голосом",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: AskChatGPTIntent(),
            phrases: [
                "Открой \(.applicationName)",
                "Диктовка в \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Спросить ChatGPT",
            systemImageName: "mic.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .teal }
}

struct AskQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "Задать вопрос ChatGPT"
    static let description = IntentDescription("Siri задаёт вопрос ChatGPT и зачитывает ответ, не открывая приложение.")
    static var openAppWhenRun: Bool { false }

    @available(watchOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Вопрос", requestValueDialog: IntentDialog("Что спросить у ChatGPT?"))
    var question: String

    @Dependency private var store: ChatStore

    static var parameterSummary: some ParameterSummary {
        Summary("Спросить ChatGPT: \(\.$question)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = try await store.askFromSiri(question)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: Speaker.plain(answer)))
    }
}

enum SiriAskError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut
    case busy
    case empty
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: return "Сначала подключите ChatGPT в приложении WatchGPT."
        case .busy: return "WatchGPT сейчас занят другим ответом. Попробуйте чуть позже."
        case .empty: return "Не получилось расслышать вопрос."
        case let .failed(message): return "\(message)"
        }
    }
}
