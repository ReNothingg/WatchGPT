import AppIntents

struct WatchGPTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskChatGPTIntent(),
            phrases: [
                "Спроси \(.applicationName)",
                "Спросить \(.applicationName)",
                "Вопрос в \(.applicationName)",
                "Открой \(.applicationName)",
                "Ask \(.applicationName)",
            ],
            shortTitle: "Спросить ChatGPT",
            systemImageName: "mic.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .teal }
}
