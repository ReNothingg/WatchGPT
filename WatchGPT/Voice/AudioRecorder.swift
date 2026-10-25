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
    @ObservationIgnored private var isWhisper = false

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appending(path: isWhisper ? "dictation.wav" : "dictation.m4a")
    }

    var isActive: Bool { isRecording || isPaused }

    func start(whisper: Bool = false) async throws {
        guard await Self.requestPermission() else { throw RecorderError.permissionDenied }
        stopMetering()
        recorder?.stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        isWhisper = whisper
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = whisper ? [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ] : [
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
        let floor: Float = isWhisper ? -64 : -52
        let range: Float = isWhisper ? 40 : 46
        let level = max(0, min(1, (db - floor) / range))
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
        let seconds = currentDuration.rounded(.down)
        if seconds != elapsed { elapsed = seconds }
        if db > (isWhisper ? -48 : -36), !heardSpeech { heardSpeech = true }
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

enum AudioBoost {
    private static let targetLevel: Float = 0.7
    private static let maxGain: Float = 31.6
    private static let chunk: AVAudioFrameCount = 8192
    private static let cutoff: Double = 90
    private static let bitRate = 64_000

    static func prepare(_ url: URL) async -> URL {
        await Task.detached(priority: .userInitiated) {
            guard let boosted = try? process(url) else { return url }
            try? FileManager.default.removeItem(at: url)
            return boosted
        }.value
    }

    private static func process(_ input: URL) throws -> URL {
        let source = try AVAudioFile(forReading: input)
        let format = source.processingFormat
        guard format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let gain = try measureGain(source, buffer: buffer)
        let output = input.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: output)
        try encode(source, buffer: buffer, gain: gain, to: output)
        return output
    }

    private static func measureGain(_ source: AVAudioFile, buffer: AVAudioPCMBuffer) throws -> Float {
        source.framePosition = 0
        var filter = HighPass(sampleRate: source.processingFormat.sampleRate, cutoff: cutoff)
        var histogram = [Int](repeating: 0, count: 901)
        var total = 0
        while source.framePosition < source.length {
            try source.read(into: buffer, frameCount: chunk)
            let count = Int(buffer.frameLength)
            guard count > 0, let samples = buffer.floatChannelData?[0] else { break }
            for i in 0..<count {
                let db = 20 * log10(max(abs(filter.process(samples[i])), 1e-6))
                histogram[min(900, max(0, Int((db + 90) * 10)))] += 1
            }
            total += count
        }
        guard total > 0 else { throw CocoaError(.fileReadCorruptFile) }

        let skip = total / 1000
        var seen = 0
        var bin = 900
        while bin > 0 {
            seen += histogram[bin]
            if seen > skip { break }
            bin -= 1
        }
        let peak = pow(10, (Float(bin) / 10 - 90) / 20)
        return min(maxGain, max(1, targetLevel / peak))
    }

    private static func encode(_ source: AVAudioFile, buffer: AVAudioPCMBuffer, gain: Float, to url: URL) throws {
        source.framePosition = 0
        var filter = HighPass(sampleRate: source.processingFormat.sampleRate, cutoff: cutoff)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: source.processingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        let output = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: source.processingFormat.commonFormat,
            interleaved: source.processingFormat.isInterleaved
        )
        while source.framePosition < source.length {
            try source.read(into: buffer, frameCount: chunk)
            let count = Int(buffer.frameLength)
            guard count > 0, let samples = buffer.floatChannelData?[0] else { break }
            for i in 0..<count {
                samples[i] = limit(filter.process(samples[i]) * gain)
            }
            try output.write(from: buffer)
        }
    }

    private static func limit(_ x: Float) -> Float {
        let knee: Float = 0.8
        let magnitude = abs(x)
        guard magnitude > knee else { return x }
        let shaped = knee + (1 - knee) * tanh((magnitude - knee) / (1 - knee))
        return x < 0 ? -shaped : shaped
    }

    private struct HighPass {
        private let b0, b1, b2, a1, a2: Float
        private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        init(sampleRate: Double, cutoff: Double) {
            let w = 2 * Double.pi * cutoff / sampleRate
            let alpha = sin(w) / (2 * 0.7071)
            let cosw = cos(w)
            let a0 = 1 + alpha
            b0 = Float((1 + cosw) / 2 / a0)
            b1 = Float(-(1 + cosw) / a0)
            b2 = b0
            a1 = Float(-2 * cosw / a0)
            a2 = Float((1 - alpha) / a0)
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }
}
