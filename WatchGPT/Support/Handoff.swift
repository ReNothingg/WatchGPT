import Foundation
import SwiftUI

enum Handoff {
    static let activityType = "watchgpt.chat"
    static let defaultsKey = "settings.handoff"

    private static let base = URL(string: "https://chatgpt.com/")!
    private static let promptBudget = 2800
    private static let messageBudget = 1200

    static func url(remoteChatID: String) -> URL {
        base.appending(path: "c").appending(path: remoteChatID)
    }

    static func url(conversationID: String, messages: [ChatMessage]) -> URL? {
        if conversationID.hasPrefix(ChatThread.gptPrefix) {
            let remoteID = String(conversationID.dropFirst(ChatThread.gptPrefix.count))
            if !remoteID.isEmpty { return url(remoteChatID: remoteID) }
        }
        guard let prompt = prompt(for: messages) else { return nil }
        return url(prompt: prompt)
    }

    static func url(prompt: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        if let query = components.percentEncodedQuery {
            components.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url
    }

    static func prompt(for messages: [ChatMessage]) -> String? {
        let usable = messages.filter { !$0.isError && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return nil }

        var lines: [String] = []
        var used = 0
        var omitted = false
        for message in usable.reversed() {
            let speaker = message.role == .user ? "Я" : "ChatGPT"
            let line = "\(speaker): \(clip(message.text, messageBudget))"
            let size = line.utf8.count + 2
            if used + size > promptBudget {
                if !lines.isEmpty {
                    omitted = true
                    break
                }
            }
            lines.insert(line, at: 0)
            used += size
        }

        var parts = ["Продолжаю разговор, который начал на Apple Watch."]
        if omitted { parts.append("(Начало разговора пропущено.)") }
        parts.append(lines.joined(separator: "\n\n"))
        parts.append("Продолжим отсюда, с учётом этого контекста.")
        return parts.joined(separator: "\n\n")
    }

    private static func clip(_ text: String, _ byteLimit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count > byteLimit else { return trimmed }
        var result = ""
        var bytes = 0
        for character in trimmed {
            let size = character.utf8.count
            if bytes + size > byteLimit { break }
            result.append(character)
            bytes += size
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

extension View {
    func handoffActivity(isActive: Bool, title: String, url: @escaping () -> URL?) -> some View {
        userActivity(Handoff.activityType, isActive: isActive) { activity in
            guard let link = url() else {
                activity.isEligibleForHandoff = false
                return
            }
            activity.title = title
            activity.webpageURL = link
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
            activity.isEligibleForPrediction = false
        }
    }
}
