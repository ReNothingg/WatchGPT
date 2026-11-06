import Foundation
import WatchKit

extension ChatStore {
    func edit(_ id: UUID, to raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy,
              let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }) else { return }
        let head = messages[index]
        var versions = head.versions ?? []
        let branch = Self.branchSnapshot(Array(messages[index...]))
        if versions.isEmpty {
            versions = [branch]
        } else {
            versions[min(head.versionIndex ?? 0, versions.count - 1)] = branch
        }
        versions.append([])
        didAutoResume = false
        messages.removeSubrange(index...)
        submit(text, versions: versions, versionIndex: versions.count - 1, images: head.images)
    }

    static let reportedPlaceholder = "Ответ скрыт по вашей жалобе."

    func reportAnswer(_ id: UUID) {
        guard !isBusy, let index = messages.firstIndex(where: { $0.id == id && $0.role == .assistant }) else { return }
        speaker.stop()
        if widgetAnswer?.answer == Self.widgetText(messages[index].text, limit: 300) { widgetAnswer = nil }
        messages[index].text = Self.reportedPlaceholder
        saveConversation()
        publishWidget()
        DiagnosticsLog.shared.record(.answer, message: "Пользователь пожаловался на ответ", detail: messages[index].claude == true ? "Claude" : "ChatGPT")
    }

    func switchVersion(_ id: UUID, by step: Int) {
        guard !isBusy, voicePhase == .idle,
              let index = messages.firstIndex(where: { $0.id == id && $0.role == .user }),
              let versions = messages[index].versions else { return }
        let current = min(messages[index].versionIndex ?? 0, versions.count - 1)
        let target = current + step
        guard versions.indices.contains(target), !versions[target].isEmpty else { return }
        var updated = versions
        updated[current] = Self.branchSnapshot(Array(messages[index...]))
        var branch = updated[target]
        branch[0].versions = updated
        branch[0].versionIndex = target
        speaker.stop()
        WKHaptics.click()
        messages.replaceSubrange(index..., with: branch)
        scrollTarget = branch[0].id
        saveConversation()
    }

    static func branchSnapshot(_ branch: [ChatMessage]) -> [ChatMessage] {
        guard var head = branch.first else { return branch }
        head.versions = nil
        head.versionIndex = nil
        return [head] + branch.dropFirst()
    }

    func handOffCode(_ code: String, language: String) {
        guard let url = Handoff.url(code: code, language: language, claude: provider == .claude) else { return }
        WKHaptics.success()
        codeHandoff = url
        codeHandoffTask?.cancel()
        codeHandoffTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled else { return }
            self?.codeHandoff = nil
        }
    }
}
