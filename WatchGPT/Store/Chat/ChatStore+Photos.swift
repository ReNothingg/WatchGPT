import Foundation
import PhotosUI
import SwiftUI
import WatchKit

extension ChatStore {
    func loadPhotos(_ items: [PhotosPickerItem]) {
        photoTask?.cancel()
        guard !items.isEmpty else {
            photoTask = nil
            loadingPhotos = false
            discardPendingImages()
            return
        }
        loadingPhotos = true
        photoTask = Task { [weak self] in
            var names: [String] = []
            for item in items.prefix(Attachments.maxCount) {
                guard !Task.isCancelled else { break }
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let name = await Task.detached(priority: .userInitiated) { Attachments.save(data) }.value
                if let name { names.append(name) }
            }
            guard let self, !Task.isCancelled else {
                Attachments.remove(names)
                return
            }
            Attachments.remove(pendingImages)
            pendingImages = names
            loadingPhotos = false
            photoTask = nil
            if names.isEmpty {
                photoSelection = []
                WKInterfaceDevice.current().play(.failure)
                DiagnosticsLog.shared.record(.answer, message: "Не удалось загрузить фото", detail: "\(items.count) шт.")
            } else {
                WKHaptics.success()
            }
        }
    }

    func discardPendingImages() {
        let names = pendingImages
        pendingImages = []
        Attachments.remove(names)
        if !photoSelection.isEmpty { photoSelection = [] }
    }

    func takePendingImages() -> [String]? {
        photoTask?.cancel()
        photoTask = nil
        loadingPhotos = false
        let names = pendingImages
        pendingImages = []
        if !photoSelection.isEmpty { photoSelection = [] }
        return names.isEmpty ? nil : names
    }

    func pruneAttachments() {
        guard historyLoaded, photoTask == nil else { return }
        var keep = Set(pendingImages)
        for message in messages { keep.formUnion(message.allImages) }
        for chat in chats {
            for message in chat.messages { keep.formUnion(message.allImages) }
        }
        let names = keep
        Task.detached(priority: .utility) { Attachments.prune(keeping: names) }
    }
}
