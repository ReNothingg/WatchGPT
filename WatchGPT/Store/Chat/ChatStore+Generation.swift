import Foundation
import WatchKit

extension ChatStore {
    func generate(replyID: UUID) async {
        var didRetryAuth = false
        var didFixEffort = false
        var didUpgradeClient = false
        let chatID = conversationID
        let useClaude = provider == .claude
        defer {
            status = .idle
            sendTask = nil
            if conversationID == chatID { saveConversation() }
            widgetPending = nil
            publishWidget()
            if resumeOnActive {
                if !isInBackground {
                    Task { @MainActor [weak self] in self?.resumeInterrupted() }
                }
            } else {
                interruptedInBackground = false
            }
        }

        while true {
            do {
                let history = messages.filter { $0.id != replyID }
                let stream: AsyncThrowingStream<ChatGPTClient.StreamEvent, Error>
                if useClaude {
                    guard let key = auth.claudeKey?.key else { throw AnthropicClient.APIError.noKey }
                    stream = AnthropicClient(apiKey: key).stream(messages: history, options: claudeOptions())
                } else {
                    let tokens = try await auth.validTokens()
                    stream = ChatGPTClient(tokens: tokens).stream(messages: history, options: requestOptions())
                }

                var pending = ""
                var shownLength = 0
                var lastFlush = ContinuousClock.now - .seconds(1)
                var interval = Self.flushInterval(length: 0)
                var lastIntervalCheck = ContinuousClock.now
                func flush() {
                    guard !pending.isEmpty else { return }
                    let chunk = pending
                    pending = ""
                    lastFlush = .now
                    shownLength += chunk.utf8.count
                    update(replyID) { $0.text += chunk }
                    if widgetPending != nil, widgetPending?.preview == nil, shownLength > 80 {
                        widgetPending?.preview = Self.widgetText(text(of: replyID), limit: 120)
                        publishWidget()
                    }
                    if lastFlush - lastIntervalCheck >= .seconds(1) {
                        lastIntervalCheck = lastFlush
                        interval = Self.flushInterval(length: shownLength)
                    }
                }

                do {
                    for try await event in stream {
                        lastStreamActivity = .now
                        switch event {
                        case .waitingForNetwork:
                            if siriRequest { throw URLError(.notConnectedToInternet) }
                            if status == .thinking { status = .waitingForNetwork }
                        case .responseStarted:
                            if status == .waitingForNetwork { status = .thinking }
                        case let .textDelta(delta):
                            if status != .streaming { status = .streaming }
                            pending += delta
                            if ContinuousClock.now - lastFlush >= interval { flush() }
                        case .searching:
                            if status != .streaming && status != .searching { status = .searching }
                        case let .usage(snapshot):
                            applyUsage(snapshot)
                        case .completed:
                            break
                        }
                    }
                    flush()
                } catch {
                    flush()
                    throw error
                }

                if text(of: replyID).isEmpty {
                    update(replyID) { $0.text = "Пустой ответ. Попробуйте ещё раз."; $0.isError = true }
                    WKInterfaceDevice.current().play(.failure)
                } else {
                    DiagnosticsLog.shared.markSuccess()
                    widgetAnswer = makeWidgetAnswer(replyID: replyID, chatID: chatID) ?? widgetAnswer
                    WKInterfaceDevice.current().play(.success)
                    if autoSpeak && !siriRequest { speaker.speak(text(of: replyID)) }
                }
                return
            } catch where !useClaude && !didFixEffort && text(of: replyID).isEmpty && fixUnsupportedEffort(error) {
                didFixEffort = true
                continue
            } catch ChatGPTClient.APIError.unauthorized where !didRetryAuth {
                didRetryAuth = true
                do { try await auth.refresh() } catch { fail(replyID, error); return }
                continue
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    if text(of: replyID).isEmpty { messages.removeAll { $0.id == replyID } }
                    return
                }
                if (isInBackground || interruptedInBackground) && !didAutoResume && Self.isTransient(error) {
                    resumeOnActive = true
                    return
                }
                if !useClaude, !didUpgradeClient, text(of: replyID).isEmpty, await ClientVersion.refreshAfterError(error) {
                    didUpgradeClient = true
                    continue
                }
                fail(replyID, error)
                if case let ChatGPTClient.APIError.usageLimit(resetAt) = error {
                    if let resetAt { LimitReminder.schedule(at: resetAt) }
                    Task { await refreshUsage() }
                }
                return
            }
        }
    }

    static func flushInterval(length: Int) -> Duration {
        if WKApplication.shared().applicationState != .active { return .seconds(1) }
        let base: Int
        switch length {
        case ..<600: base = 150
        case ..<1500: base = 220
        case ..<3000: base = 320
        default: base = 450
        }
        return .milliseconds(PowerMonitor.shared.isLowPower ? base * 2 : base)
    }

    func fail(_ replyID: UUID, _ error: Error) {
        DiagnosticsLog.shared.record(.answer, error)
        let message = Self.describe(error)
        if text(of: replyID).isEmpty {
            update(replyID) { $0.text = message; $0.isError = true }
        } else {
            messages.append(ChatMessage(role: .assistant, text: message, isError: true))
        }
        WKInterfaceDevice.current().play(.failure)
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Нет интернета. Проверьте связь с iPhone или Wi‑Fi."
            case .timedOut:
                return "Сервер долго не отвечает. Попробуйте ещё раз."
            default:
                return "Ошибка сети: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    func update(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    func text(of id: UUID) -> String {
        messages.last { $0.id == id }?.text ?? ""
    }
}
