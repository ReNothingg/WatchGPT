import AVFoundation
import NaturalLanguage
import Observation

@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private var speakToken: UUID?
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
    @ObservationIgnored private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()

    func toggle(_ text: String) {
        isSpeaking ? stop() : speak(text)
    }

    func speak(_ text: String) {
        stop()
        let token = UUID()
        speakToken = token
        isSpeaking = true
        Task {
            let prepared = try? await AudioSessionQueue.run { () -> (String, String?)? in
                let clean = Self.plain(text)
                guard !clean.isEmpty else { return nil }
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .voicePrompt, options: [])
                try? session.setActive(true)
                return (clean, NLLanguageRecognizer.dominantLanguage(for: clean)?.rawValue)
            }
            guard speakToken == token else { return }
            guard let (clean, lang) = prepared else {
                speakToken = nil
                isSpeaking = false
                return
            }
            let utterance = AVSpeechUtterance(string: clean)
            if let lang, let voice = AVSpeechSynthesisVoice(language: lang) {
                utterance.voice = voice
            }
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
            currentUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        guard speakToken != nil || isSpeaking else { return }
        speakToken = nil
        currentUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
        AudioSessionQueue.deactivate()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    private func finished(_ id: ObjectIdentifier) {
        guard id == currentUtterance else { return }
        currentUtterance = nil
        speakToken = nil
        isSpeaking = false
        AudioSessionQueue.deactivate()
    }

    nonisolated static func plain(_ text: String) -> String {
        var s = MathFormat.plain(text)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?m)^\s*[-•]\s+"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
