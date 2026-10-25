import Foundation

final class DiskWriter: @unchecked Sendable {
    static let shared = DiskWriter()

    private enum Job {
        case write(@Sendable () -> Data?)
        case remove
    }

    private let queue = DispatchQueue(label: "watchgpt.disk-writer", qos: .utility)
    private let lock = NSLock()
    private var pending: [URL: Job] = [:]

    func write(_ url: URL, _ makeData: @escaping @Sendable () -> Data?) {
        enqueue(.write(makeData), for: url)
    }

    func writeJSON<T: Encodable & Sendable>(_ value: T, to url: URL) {
        write(url) { try? JSONEncoder().encode(value) }
    }

    func remove(_ url: URL) {
        enqueue(.remove, for: url)
    }

    private func enqueue(_ job: Job, for url: URL) {
        lock.lock()
        let alreadyScheduled = pending[url] != nil
        pending[url] = job
        lock.unlock()
        guard !alreadyScheduled else { return }
        queue.async { [self] in
            lock.lock()
            let next = pending.removeValue(forKey: url)
            lock.unlock()
            switch next {
            case let .write(makeData):
                guard let data = makeData() else { return }
                try? data.write(to: url, options: .atomic)
            case .remove:
                try? FileManager.default.removeItem(at: url)
            case nil:
                break
            }
        }
    }
}

enum AppFiles {
    static let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(_ name: String) -> URL {
        directory.appending(path: name)
    }
}
