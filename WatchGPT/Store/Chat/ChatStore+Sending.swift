import Foundation
import WatchKit

extension ChatStore {
    func send(_ raw: String) {
        didAutoResume = false
        submit(raw)
    }

    func askFromSiri(_ raw: String) async throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SiriAskError.empty }
        guard auth.isSignedIn else { throw SiriAskError.signedOut }
        guard !isBusy, voicePhase == .idle else { throw SiriAskError.busy }

        newChat()
        siriRequest = true
        didAutoResume = true
        defer { siriRequest = false }
        submit(text)
        let task = sendTask
        await task?.value

        guard let reply = messages.last, reply.role == .assistant, !reply.text.isEmpty else {
            throw SiriAskError.failed("Ответ не получен. Попробуйте ещё раз.")
        }
        if reply.isError { throw SiriAskError.failed(reply.text) }
        return reply.text
    }

    func refine(_ kind: ChatMessage.Refinement) {
        guard lastAnswer != nil, messages.last?.isError != true else { return }
        didAutoResume = false
        submit(kind.label, refine: kind)
    }

    var canRefine: Bool {
        !isBusy && messages.last.map { $0.role == .assistant && !$0.isError && !$0.text.isEmpty } == true
    }

    func submit(_ raw: String, refine: ChatMessage.Refinement? = nil, versions: [[ChatMessage]]? = nil, versionIndex: Int? = nil) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        speaker.stop()
        interruptedInBackground = isInBackground
        resumeOnActive = false
        lastStreamActivity = .now

        var question = ChatMessage(role: .user, text: text, refine: refine)
        question.versions = versions
        question.versionIndex = versionIndex
        let reply = ChatMessage(role: .assistant, text: "", claude: provider == .claude ? true : nil)
        messages.append(question)
        messages.append(reply)
        widgetPending = WidgetPending(
            question: Self.widgetText(refine?.label ?? text, limit: 80),
            preview: nil,
            startedAt: .now,
            chatID: conversationID
        )
        publishWidget()
        scrollTarget = question.id
        status = .thinking
        WKInterfaceDevice.current().play(.start)

        sendTask = Task { [weak self] in
            await self?.generate(replyID: reply.id)
        }
    }

    func retry() {
        didAutoResume = false
        resend()
    }

    func resend() {
        guard !isBusy, let lastUser = messages.lastIndex(where: { $0.role == .user }) else { return }
        let question = messages[lastUser]
        messages.removeSubrange(lastUser...)
        submit(question.text, refine: question.refine, versions: question.versions, versionIndex: question.versionIndex)
    }

    func stop() {
        resumeOnActive = false
        sendTask?.cancel()
        sendTask = nil
    }

    func sceneEnteredBackground() {
        isInBackground = true
        if isBusy { interruptedInBackground = true }
    }

    func sceneBecameActive() {
        isInBackground = false
        updateKeepAlive()
        if isBusy {
            guard interruptedInBackground, !didAutoResume,
                  Date.now.timeIntervalSince(lastStreamActivity) > 15 else { return }
            resumeOnActive = true
            sendTask?.cancel()
        } else {
            resumePendingIfNeeded()
        }
    }

    func resumeInterrupted() {
        resumeOnActive = false
        interruptedInBackground = false
        guard !didAutoResume, !isInBackground else { return }
        didAutoResume = true
        resend()
    }

    func updateKeepAlive() {
        let working = status != .idle || voicePhase == .recording || voicePhase == .transcribing
        if working {
            keepAlive.hold()
        } else {
            let looking = WKApplication.shared().applicationState == .active
            keepAlive.release(after: looking ? .seconds(2) : .seconds(120))
        }
    }

    static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        return (error as NSError).domain == NSPOSIXErrorDomain
    }
}
