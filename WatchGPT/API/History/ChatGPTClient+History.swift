import Foundation

extension ChatGPTClient {
    enum HistoryError: LocalizedError {
        case notAllowed(Int)
        case notFound
        case unreadable

        var errorDescription: String? {
            switch self {
            case let .notAllowed(code):
                return "ChatGPT не открыл историю для этого входа (\(code)). Возможно, OpenAI закрыл к ней доступ для Codex."
            case .notFound:
                return "Чат не найден: возможно, его удалили или перенесли в архив."
            case .unreadable:
                return "Не удалось прочитать историю ChatGPT."
            }
        }
    }

    struct ChatPage: Sendable {
        var items: [RemoteChat]
        var nextOffset: Int?
        var nextCursor: String?

        var hasMore: Bool { nextOffset != nil || nextCursor != nil }
    }

    func fetchChats(offset: Int = 0, cursor: String? = nil, limit: Int = 28) async throws -> ChatPage {
        var components = URLComponents(url: Self.baseURL.appending(path: "conversations"), resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: "updated"),
            URLQueryItem(name: "is_archived", value: "false"),
        ]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        } else {
            query.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        components.queryItems = query

        let obj = try await getJSON(components.url!)
        let raw = obj["items"] as? [[String: Any]] ?? []
        let items = raw.compactMap { item -> RemoteChat? in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let updated = Self.date(item["update_time"]) ?? Self.date(item["create_time"]) ?? .distantPast
            return RemoteChat(id: id, title: title.isEmpty ? "Без названия" : title, updatedAt: updated)
        }

        let nextCursor = (obj["cursor"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var nextOffset: Int?
        if nextCursor == nil, cursor == nil, raw.count >= limit {
            let next = offset + raw.count
            let total = Self.number(obj["total"]).map { Int($0) } ?? 0
            if total <= 0 || next < total { nextOffset = next }
        }
        return ChatPage(items: items, nextOffset: nextOffset, nextCursor: nextCursor)
    }

    enum StreamState: Sendable {
        case streaming, complete, failed, unknown
    }

    func streamState(id: String) async -> StreamState {
        let url = Self.baseURL.appending(path: "conversation").appending(path: id).appending(path: "stream_status")
        guard let obj = try? await getJSON(url) else { return .unknown }
        switch obj["status"] as? String {
        case "IS_STREAMING": return .streaming
        case "COMPLETE": return .complete
        case "FAILURE": return .failed
        default: return .unknown
        }
    }

    func fetchConversation(id: String) async throws -> RemoteConversation {
        let obj = try await getJSON(Self.baseURL.appending(path: "conversation").appending(path: id))
        return try Self.conversation(from: obj, id: id)
    }

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        var request = makeRequest(url, method: "GET")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        switch status {
        case 200..<300:
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw HistoryError.unreadable
            }
            return obj
        case 401:
            throw APIError.unauthorized
        case 403:
            throw Self.networkBlock(body: data, response: http) ?? HistoryError.notAllowed(403)
        case 404:
            throw HistoryError.notFound
        default:
            throw Self.error(status: status, body: data, response: http)
        }
    }

    func imageData(pointer: String, conversationID: String) async throws -> Data {
        guard let separator = pointer.range(of: "://") else { throw HistoryError.unreadable }
        let scheme = pointer[..<separator.lowerBound]
        let fileID = String(pointer[separator.upperBound...])
        guard !fileID.isEmpty else { throw HistoryError.unreadable }

        let infoURL: URL
        if scheme == "sediment" {
            var components = URLComponents(url: Self.baseURL.appending(path: "files/download").appending(path: fileID), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "conversation_id", value: conversationID),
                URLQueryItem(name: "inline", value: "false"),
            ]
            infoURL = components.url!
        } else {
            infoURL = Self.baseURL.appending(path: "files").appending(path: fileID).appending(path: "download")
        }

        let info = try await getJSON(infoURL)
        guard let link = info["download_url"] as? String,
              let url = URL(string: link, relativeTo: URL(string: "https://chatgpt.com")!)?.absoluteURL else {
            throw HistoryError.unreadable
        }

        var request = (url.host == "chatgpt.com" || url.host?.hasSuffix(".chatgpt.com") == true) == true ? makeRequest(url, method: "GET") : URLRequest(url: url)
        request.timeoutInterval = 40
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), !data.isEmpty else {
            throw APIError.http(status, "Картинка не загрузилась (\(status)).")
        }
        return data
    }
}
