import Foundation

enum ChatArchive {
    private static let chatsURL = AppFiles.url("chats.json")
    private static let latestChatURL = AppFiles.url("latest-chat.json")
    private static let legacyConversationURL = AppFiles.url("conversation.json")

    private struct LegacyConversation: Codable {
        var id: String
        var messages: [ChatMessage]
    }

    static func latest() -> ChatThread? {
        read(ChatThread.self, from: latestChatURL)
    }

    static func allChats() -> [ChatThread]? {
        read([ChatThread].self, from: chatsURL)
    }

    static func allChatsInBackground() async -> [ChatThread] {
        let url = chatsURL
        return await Task.detached(priority: .userInitiated) {
            read([ChatThread].self, from: url) ?? []
        }.value
    }

    static func legacyThread() -> ChatThread? {
        guard let legacy = read(LegacyConversation.self, from: legacyConversationURL) else { return nil }
        return ChatThread(id: legacy.id, messages: legacy.messages)
    }

    static func removeLegacy() {
        try? FileManager.default.removeItem(at: legacyConversationURL)
    }

    static func saveLatest(_ thread: ChatThread?) {
        if let thread {
            DiskWriter.shared.writeJSON(thread, to: latestChatURL)
        } else {
            DiskWriter.shared.remove(latestChatURL)
        }
    }

    static func saveAll(_ chats: [ChatThread]) {
        DiskWriter.shared.writeJSON(chats, to: chatsURL)
    }

    nonisolated private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }
}
