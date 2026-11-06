import Foundation
import WatchKit

extension ChatStore {
    func startVoice() {
        guard !isBusy, !voiceGivingUp, voicePhase == .idle || isFailedVoice else { return }
        speaker.stop()
        playback.stop()
        pendingRecording = nil
        voicePhase = .recording
        voiceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.recorder.start(whisper: self.whisperMode)
                guard !Task.isCancelled, self.voicePhase == .recording else {
                    self.recorder.cancel()
                    return
                }
                WKInterfaceDevice.current().play(.start)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                DiagnosticsLog.shared.record(.voice, error)
                self.failVoice(Self.describe(error))
            }
        }
    }

    func toggleVoicePause() {
        guard voicePhase == .recording else { return }
        if recorder.isPaused {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.recorder.resume()
                    WKInterfaceDevice.current().play(.start)
                } catch {
                    self.failVoice(Self.describe(error))
                }
            }
        } else if recorder.isRecording {
            recorder.pause()
            WKInterfaceDevice.current().play(.stop)
        }
    }

    func finishVoice() {
        guard voicePhase == .recording, recorder.isActive, !isFinishingVoice else { return }
        isFinishingVoice = true
        voiceTask = Task { [weak self] in
            guard let self else { return }
            let url = await self.recorder.stop()
            self.isFinishingVoice = false
            guard !Task.isCancelled, self.voicePhase == .recording else { return }
            guard let url else {
                self.failVoice("Слишком короткая запись. Нажмите и говорите.")
                return
            }
            WKInterfaceDevice.current().play(.click)
            self.pendingRecording = url
            self.transcribePending()
        }
    }

    func retryTranscription() {
        guard pendingRecording != nil else { startVoice(); return }
        transcribePending()
    }

    func cancelVoice() {
        voiceTask?.cancel()
        voiceTask = nil
        voiceCloseTask?.cancel()
        voiceCloseTask = nil
        voiceFailures = 0
        voiceGivingUp = false
        isFinishingVoice = false
        if recorder.isActive { recorder.cancel() }
        pendingRecording = nil
        voicePrompt = nil
        editingMessageID = nil
        voicePhase = .idle
    }

    func typeQuestion() {
        guard !isBusy, voicePhase == .idle else { return }
        WKHaptics.click()
        speaker.stop()
        playback.stop()
        Dictation.present { [weak self] text in self?.send(text) }
    }

    func sendFromFallback(_ text: String) {
        let message = withVoicePrompt(text)
        let editID = editingMessageID
        cancelVoice()
        deliver(message, editing: editID)
    }

    func deliver(_ text: String, editing id: UUID?) {
        if let id {
            edit(id, to: text)
        } else {
            send(text)
        }
    }

    func editByVoice(_ id: UUID) {
        guard !isBusy, voicePhase == .idle else { return }
        WKHaptics.click()
        speaker.stop()
        playback.stop()
        if usesCloudVoice {
            editingMessageID = id
            startVoice()
            if voicePhase != .recording { editingMessageID = nil }
        } else {
            Dictation.present { [weak self] text in self?.edit(id, to: text) }
        }
    }

    func runQuickPrompt(_ prompt: QuickPrompt) {
        guard !isBusy, voicePhase == .idle else { return }
        let wasNavigated = !path.isEmpty
        path = []
        guard prompt.asksVoice else {
            send(prompt.text)
            return
        }
        Task { @MainActor [weak self] in
            if wasNavigated { try? await Task.sleep(for: .milliseconds(450)) }
            guard let self, !self.isBusy, self.voicePhase == .idle else { return }
            if self.usesCloudVoice {
                self.startVoice()
                if self.voicePhase == .recording { self.voicePrompt = prompt }
            } else {
                Dictation.present { [weak self] text in self?.send(prompt.message(with: text)) }
            }
        }
    }

    func withVoicePrompt(_ text: String) -> String {
        guard let prompt = voicePrompt else { return text }
        voicePrompt = nil
        return prompt.message(with: text)
    }

    func failVoice(_ message: String) {
        voiceFailures += 1
        voicePhase = .failed(message)
        WKInterfaceDevice.current().play(.failure)
        guard voiceFailures >= Self.maxVoiceFailures else { return }
        voiceGivingUp = true
        voiceCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.voiceGivingUp else { return }
            self.cancelVoice()
        }
    }

    var isFailedVoice: Bool {
        if case .failed = voicePhase { return true }
        return false
    }

    func transcribePending() {
        guard let url = pendingRecording else { return }
        voicePhase = .transcribing
        voiceTask = Task { [weak self] in
            guard let self else { return }
            var file = url
            if AudioBoost.needsBoost(file) {
                file = await AudioBoost.prepare(file)
                guard !Task.isCancelled else { return }
                self.pendingRecording = file
            }
            self.keepLastRecording(file)
            do {
                let result = try await Transcriber.transcribe(
                    fileURL: file,
                    engine: self.voiceEngine,
                    model: self.transcribeModel,
                    language: self.voiceLanguage,
                    whisper: self.whisperMode,
                    context: self.voiceContext,
                    auth: self.auth
                )
                guard !Task.isCancelled else { return }
                self.lastVoiceLabel = result.label
                self.lastTranscript = result.text
                self.pendingRecording = nil
                self.voiceFailures = 0
                let message = self.withVoicePrompt(result.text)
                let editID = self.editingMessageID
                self.editingMessageID = nil
                self.voicePhase = .idle
                self.deliver(message, editing: editID)
            } catch {
                guard !Task.isCancelled else { return }
                DiagnosticsLog.shared.record(.voice, error)
                self.failVoice(Self.describe(error))
            }
        }
    }

    func keepLastRecording(_ file: URL) {
        playback.stop()
        let manager = FileManager.default
        let copy = manager.temporaryDirectory.appending(path: "last-dictation.\(file.pathExtension)")
        if let lastRecording { try? manager.removeItem(at: lastRecording) }
        try? manager.removeItem(at: copy)
        lastTranscript = nil
        if (try? manager.linkItem(at: file, to: copy)) != nil {
            lastRecording = copy
        } else {
            lastRecording = (try? manager.copyItem(at: file, to: copy)) != nil ? copy : nil
        }
    }

    var voiceContext: String? {
        let recent = messages.filter { !$0.isError && !$0.text.isEmpty }.suffix(4)
        guard !recent.isEmpty else { return nil }
        return recent.map { message in
            let who = message.role == .user ? "User" : "Assistant"
            let text = message.text.replacingOccurrences(of: "\n", with: " ")
            return "\(who): \(text.prefix(240))"
        }.joined(separator: "\n")
    }
}
