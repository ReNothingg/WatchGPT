import Foundation
import WidgetKit

extension ChatStore {
    func publishWidget() {
        let snapshot = WidgetSnapshot(
            signedIn: auth.isSignedIn,
            usage: usage?.forWidget,
            lastAnswer: auth.isSignedIn ? widgetAnswer : nil,
            pending: auth.isSignedIn ? widgetPending : nil
        )
        let previous = publishedWidget ?? SharedStore.load()
        publishedWidget = snapshot
        guard snapshot != previous else { return }
        SharedStore.save(snapshot)

        var kinds: Set<String> = []
        if snapshot.signedIn != previous.signedIn || snapshot.usage != previous.usage {
            kinds.formUnion([SharedStore.askWidgetKind, SharedStore.limitsWidgetKind])
        }
        if snapshot.signedIn != previous.signedIn || snapshot.lastAnswer != previous.lastAnswer || snapshot.pending != previous.pending {
            kinds.insert(SharedStore.answerWidgetKind)
        }
        for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    func makeWidgetAnswer(replyID: UUID, chatID: String) -> WidgetAnswer? {
        guard let index = messages.lastIndex(where: { $0.id == replyID }) else { return nil }
        let answer = Self.widgetText(messages[index].text, limit: 300)
        guard !answer.isEmpty else { return nil }
        let question = messages[..<index].last { $0.role == .user && $0.refine == nil }?.text ?? ""
        return WidgetAnswer(question: Self.widgetText(question, limit: 80), answer: answer, date: .now, chatID: chatID)
    }

    static func widgetText(_ text: String, limit: Int) -> String {
        let flat = Speaker.plain(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
