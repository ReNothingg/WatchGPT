import AVFoundation
import Observation

/// Records the user's voice to a small AAC file and exposes live levels for the waveform.
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

    private(set) var levels: [Float] = Array(repeating: 0, count: AudioRecorder.barCount)
    private(set) var elapsed: TimeInterval = 0
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var heardSpeech = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var recordedBeforeResume: TimeInterval = 0
    @ObservationIgnored private var resumedAt = Date.now
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "dictation.m4a")
    }

    var isActive: Bool { isRecording || isPaused }

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
        recordedBeforeResume = 0
        resumedAt = .now
        heardSpeech = false
        isPaused = false
        isRecording = true
        observeInterruptions()
        startMetering()
    }

    func pause() {
        guard let recorder, isRecording else { return }
        recorder.pause()
        markPaused()
    }

    func resume() throws {
        guard let recorder, isPaused else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        guard recorder.record() else { throw RecorderError.couldNotStart }
        resumedAt = .now
        isPaused = false
        isRecording = true
        startMetering()
    }

    /// Stops and returns the recorded file (nil if nothing usable was captured).
    func stop() -> URL? {
        guard let recorder else { return nil }
        let duration = currentDuration
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

    private var currentDuration: TimeInterval {
        isRecording ? recordedBeforeResume + Date.now.timeIntervalSince(resumedAt) : recordedBeforeResume
    }

    private func markPaused() {
        guard isRecording else { return }
        recordedBeforeResume += Date.now.timeIntervalSince(resumedAt)
        elapsed = recordedBeforeResume
        isRecording = false
        isPaused = true
        stopMetering()
        levels = Array(repeating: 0, count: Self.barCount)
    }

    private func finish() {
        isRecording = false
        isPaused = false
        stopMetering()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
            MainActor.assumeIsolated { self?.markPaused() }
        }
    }

    // MARK: Metering

    private func startMetering() {
        stopMetering()
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
        guard let recorder, isRecording else { return }
        guard recorder.isRecording else {
            markPaused()
            return
        }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let level = max(0, min(1, (db + 52) / 46))
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
        let seconds = currentDuration.rounded(.down)
        if seconds != elapsed { elapsed = seconds }
        if db > -36, !heardSpeech { heardSpeech = true }
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
