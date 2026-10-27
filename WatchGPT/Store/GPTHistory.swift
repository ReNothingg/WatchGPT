import Foundation
import ImageIO
import Observation
import UIKit

@MainActor
@Observable
final class GPTHistory {
    enum Phase: Equatable { case idle, loading, failed(String) }

    let auth: AuthService

    private(set) var chats: [RemoteChat] = []
    private(set) var phase: Phase = .idle
    private(set) var syncedAt: Date?
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?

    @ObservationIgnored private var nextOffset: Int?
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var blockedUntil: Date?
    @ObservationIgnored private var cache: [String: RemoteConversation] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private let pictures: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    private static let maxChats = 300
    private static let maxCached = 8

    private struct Snapshot: Codable, Sendable {
        var chats: [RemoteChat]
        var syncedAt: Date?
    }

    init(auth: AuthService) {
        self.auth = auth
        if let data = try? Data(contentsOf: Self.fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            chats = snapshot.chats
            syncedAt = snapshot.syncedAt
        }
    }

    var isLoading: Bool { phase == .loading }

    var errorMessage: String? {
        if case let .failed(message) = phase { return message }
        return nil
    }

    func refresh(force: Bool = false) async {
        guard auth.isSignedIn, phase != .loading else { return }
        if !force {
            if let syncedAt, Date.now.timeIntervalSince(syncedAt) < 30 { return }
            if let blockedUntil, blockedUntil > .now { return }
        }
        phase = .loading
        do {
            let page = try await withClient { try await $0.fetchChats() }
            guard auth.isSignedIn else {
                phase = .idle
                return
            }
            var seen = Set<String>()
            chats = page.items.filter { seen.insert($0.id).inserted }
            apply(page)
            loadMoreError = nil
            blockedUntil = nil
            syncedAt = .now
            phase = .idle
            save()
        } catch {
            if Self.isCancellation(error) {
                phase = .idle
                return
            }
            if error is ChatGPTClient.HistoryError { blockedUntil = .now.addingTimeInterval(10 * 60) }
            phase = .failed(ChatStore.describe(error))
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, phase != .loading else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }

        let offset = nextOffset ?? chats.count
        let cursor = nextCursor
        do {
            let page = try await withClient { try await $0.fetchChats(offset: offset, cursor: cursor) }
            guard auth.isSignedIn else { return }
            let known = Set(chats.map(\.id))
            let fresh = page.items.filter { !known.contains($0.id) }
            chats += fresh
            apply(page)
            if fresh.isEmpty || chats.count >= Self.maxChats { hasMore = false }
            save()
        } catch {
            guard !Self.isCancellation(error) else { return }
            loadMoreError = ChatStore.describe(error)
        }
    }

    func cached(_ id: String) -> RemoteConversation? {
        cache[id]
    }

    func conversation(_ id: String) async throws -> RemoteConversation {
        let conversation = try await withClient { try await $0.fetchConversation(id: id) }
        guard auth.isSignedIn else { throw AuthService.AuthError.signedOut }
        cache[id] = conversation
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        if cacheOrder.count > Self.maxCached {
            cache[cacheOrder.removeFirst()] = nil
        }
        if let index = chats.firstIndex(where: { $0.id == id }), chats[index].title != conversation.title {
            chats[index].title = conversation.title
            save()
        }
        return conversation
    }

    func cachedImage(_ image: RemoteImage) -> UIImage? {
        pictures.object(forKey: image.pointer as NSString)
    }

    func image(_ image: RemoteImage, conversationID: String) async throws -> UIImage {
        if let cached = cachedImage(image) { return cached }
        let data = try await withClient { try await $0.imageData(pointer: image.pointer, conversationID: conversationID) }
        let decoded = await Task.detached(priority: .userInitiated) { Self.thumbnail(data, maxPixel: 720) }.value
        guard let decoded else { throw ChatGPTClient.HistoryError.unreadable }
        let picture = UIImage(cgImage: decoded)
        pictures.setObject(picture, forKey: image.pointer as NSString, cost: decoded.bytesPerRow * decoded.height)
        return picture
    }

    nonisolated private static func thumbnail(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func clear() {
        chats = []
        phase = .idle
        syncedAt = nil
        hasMore = false
        loadMoreError = nil
        nextOffset = nil
        nextCursor = nil
        blockedUntil = nil
        cache = [:]
        cacheOrder = []
        pictures.removeAllObjects()
        DiskWriter.shared.remove(Self.fileURL)
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func apply(_ page: ChatGPTClient.ChatPage) {
        nextOffset = page.nextOffset
        nextCursor = page.nextCursor
        hasMore = page.hasMore && chats.count < Self.maxChats
    }

    private func withClient<T>(_ work: (ChatGPTClient) async throws -> T) async throws -> T {
        let tokens = try await auth.validTokens()
        do {
            return try await work(ChatGPTClient(tokens: tokens))
        } catch ChatGPTClient.APIError.unauthorized {
            let fresh = try await auth.refresh()
            do {
                return try await work(ChatGPTClient(tokens: fresh))
            } catch ChatGPTClient.APIError.unauthorized {
                throw ChatGPTClient.HistoryError.notAllowed(401)
            }
        }
    }

    private static let fileURL = AppFiles.url("gpt-chats.json")

    private func save() {
        DiskWriter.shared.writeJSON(Snapshot(chats: chats, syncedAt: syncedAt), to: Self.fileURL)
    }
}
