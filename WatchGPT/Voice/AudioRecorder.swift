import AVFoundation
import Observation

/// Records the user's voice to a small AAC file and exposes live levels for the waveform.
/// Stops by itself after a pause in speech (optional).
@MainActor
@Observable
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Нет доступа к микрофону. Разрешите его в настройках часов: Конфиденциальность → Микрофон."
            case .couldNotStart: return "Не удалось включить микрофон."
            }
        }
    }

    static let barCount = 24
    static let maxDuration: TimeInterval = 180

    private(set) var levels: [Float] = Array(repeating: 0, count: AudioRecorder.barCount)
    private(set) var elapsed: TimeInterval = 0
    private(set) var isRecording = false
    private(set) var heardSpeech = false

    var autoStopOnSilence = true
    /// Called when recording stops automatically (silence or max duration).
    @ObservationIgnored var onAutoStop: (@MainActor () -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var silenceSince: Date?
    @ObservationIgnored private var startedAt = Date.now

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "dictation.m4a")
    }

    func start() async throws {
        guard await Self.requestPermission() else { throw RecorderError.permissionDenied }
        stopMetering()
        recorder?.stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder

        levels = Array(repeating: 0, count: Self.barCount)
        elapsed = 0
        heardSpeech = false
        silenceSince = nil
        startedAt = .now
        isRecording = true
        startMetering()
    }

    /// Stops and returns the recorded file (nil if nothing usable was captured).
    func stop() -> URL? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        finish()
        return duration > 0.3 ? fileURL : nil
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        finish()
    }

    private func finish() {
        isRecording = false
        stopMetering()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Metering

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0) // -160 … 0
        let level = max(0, min(1, (db + 52) / 46))
        levels.removeFirst()
        levels.append(level)
        elapsed = Date.now.timeIntervalSince(startedAt)

        let speaking = db > -36
        if speaking {
            heardSpeech = true
            silenceSince = nil
        } else if heardSpeech, silenceSince == nil {
            silenceSince = .now
        }

        let silentLongEnough = silenceSince.map { Date.now.timeIntervalSince($0) > 1.8 } ?? false
        if (autoStopOnSilence && heardSpeech && silentLongEnough) || elapsed >= Self.maxDuration {
            onAutoStop?()
        }
    }

    private static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
    }
}
