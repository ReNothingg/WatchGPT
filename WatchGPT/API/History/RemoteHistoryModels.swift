import Foundation

struct RemoteChat: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var updatedAt: Date
}

struct RemoteConversation: Equatable, Sendable {
    var id: String
    var title: String
    var updatedAt: Date
    var messages: [ChatMessage]
    var images: [UUID: [RemoteImage]] = [:]
    var reasoning: [UUID: Reasoning] = [:]
    var live: LiveTurn?
}

struct RemoteImage: Equatable, Hashable, Identifiable, Sendable {
    var pointer: String
    var width: Int?
    var height: Int?

    var id: String { pointer }

    var aspect: Double {
        guard let width, let height, width > 0, height > 0 else { return 1 }
        return min(2, max(0.5, Double(width) / Double(height)))
    }
}

struct ReasoningStep: Equatable, Identifiable, Sendable {
    var id: Int
    var title: String
    var detail: String
    var icon: String?
}

struct Reasoning: Equatable, Sendable {
    var steps: [ReasoningStep] = []
    var seconds: Int?

    var isEmpty: Bool { steps.isEmpty && seconds == nil }

    static let maxSteps = 40

    mutating func add(title: String, detail: String, icon: String? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !detail.isEmpty else { return }
        if let index = steps.lastIndex(where: { $0.title == title && $0.icon == icon && Self.sameText($0.detail, detail) }) {
            if detail.count > steps[index].detail.count { steps[index].detail = detail }
            return
        }
        steps.append(ReasoningStep(id: (steps.last?.id ?? -1) + 1, title: title, detail: detail, icon: icon))
        if steps.count > Self.maxSteps { steps.removeFirst(steps.count - Self.maxSteps) }
    }

    private static func sameText(_ a: String, _ b: String) -> Bool {
        a.isEmpty || b.isEmpty || a.hasPrefix(b) || b.hasPrefix(a)
    }

    mutating func absorb(_ other: Reasoning) {
        for step in other.steps { add(title: step.title, detail: step.detail, icon: step.icon) }
        if let seconds = other.seconds { self.seconds = (self.seconds ?? 0) + seconds }
    }
}

struct LiveTurn: Equatable, Sendable {
    var startedAt: Date
    var stage: String
    var icon: String
    var reasoning: Reasoning
}
