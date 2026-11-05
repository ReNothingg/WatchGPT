import Foundation
import WatchKit

extension ChatStore {
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
            ChatArchive.saveAll([])
        }
        writeChats()
        publishWidget()
    }

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

    func openFromLink(_ id: String) {
        guard auth.isSignedIn, voicePhase == .idle else { return }
        path = []
        guard id != conversationID, !isBusy else { return }
        if chats.contains(where: { $0.id == id }) {
            openChat(id)
        } else if !historyLoaded {
            pendingOpenChatID = id
        }
    }

    static let historyLimit = 60
    static let importLimit = 50
    static let restoreWindow: TimeInterval = 6 * 3600

    func loadConversation() {
        if let latest = ChatArchive.latest() {
            chats = [latest]
            restore(latest)
            Task { await loadHistory() }
            return
        }
        historyLoaded = true
        if let saved = ChatArchive.allChats() {
            chats = saved.sorted { $0.updatedAt > $1.updatedAt }
            if let latest = chats.first { ChatArchive.saveLatest(latest) }
        } else if let thread = ChatArchive.legacyThread() {
            chats = [thread]
            writeChats()
            ChatArchive.removeLegacy()
        }
        if let latest = chats.first { restore(latest) }
    }

    func restore(_ latest: ChatThread) {
        guard Date.now.timeIntervalSince(latest.updatedAt) <= Self.restoreWindow else { return }
        conversationID = latest.id
        messages = latest.messages
        scrollTarget = messages.last(where: { $0.role == .user })?.id
        if let last = messages.last, last.role == .user, last.fromGPT != true,
           Date.now.timeIntervalSince(last.date) <= 3600 {
            resumeOnActive = true
        }
    }

    func loadHistory() async {
        let saved = await ChatArchive.allChatsInBackground()

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

    func saveConversation(title: String? = nil) {
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

    func writeChats() {
        ChatArchive.saveLatest(chats.first)
        guard historyLoaded else { return }
        ChatArchive.saveAll(chats)
    }
}
