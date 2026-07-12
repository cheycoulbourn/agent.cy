@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

struct SpeechTranscriptAccumulator {
    private struct Segment {
        let range: CMTimeRange
        let text: String
    }

    private let initialTranscript: String
    private var segments: [Segment] = []

    init(initialTranscript: String) {
        self.initialTranscript = initialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func merge(_ text: String, range: CMTimeRange) -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return composedTranscript }

        segments.removeAll { Self.overlaps($0.range, range) }
        segments.append(Segment(range: range, text: normalizedText))
        segments.sort { CMTimeCompare($0.range.start, $1.range.start) < 0 }
        return composedTranscript
    }

    private var composedTranscript: String {
        ([initialTranscript] + segments.map(\.text))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func overlaps(_ lhs: CMTimeRange, _ rhs: CMTimeRange) -> Bool {
        if CMTimeCompare(lhs.start, rhs.start) == 0 { return true }
        return CMTimeCompare(lhs.start, CMTimeRangeGetEnd(rhs)) < 0 &&
            CMTimeCompare(rhs.start, CMTimeRangeGetEnd(lhs)) < 0
    }
}

enum SpeechAuthorizationBridge {
    static func request(
        _ requester: @escaping @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    ) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            requester { status in
                continuation.resume(returning: status)
            }
        }
    }
}

struct SpeechCaptureAudioPlan {
    let captureFormat: AVAudioFormat
    let analyzerFormat: AVAudioFormat

    // AVAudioEngine's microphone tap must use the hardware capture format.
    // SpeechAnalyzer receives separately converted buffers.
    var tapFormat: AVAudioFormat { captureFormat }

    static func isUsableCaptureFormat(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }
}

final class SpeechAudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()

    init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard SpeechCaptureAudioPlan.isUsableCaptureFormat(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ), outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else {
            return nil
        }
        self.outputFormat = outputFormat
        if Self.formatsMatch(inputFormat, outputFormat) {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
            self.converter = converter
        }
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard let converter else { return input }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, ceil(Double(input.frameLength) * ratio) + 32))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        let source = SpeechConverterInput(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if source.wasSupplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            source.wasSupplied = true
            inputStatus.pointee = .haveData
            return source.buffer
        }
        guard conversionError == nil,
              status == .haveData || status == .inputRanDry,
              output.frameLength > 0 else {
            return nil
        }
        return output
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate &&
            lhs.channelCount == rhs.channelCount &&
            lhs.commonFormat == rhs.commonFormat &&
            lhs.isInterleaved == rhs.isInterleaved
    }
}

private final class SpeechConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var wasSupplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

typealias SpeechAudioTapHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

enum SpeechAudioTapBridge {
    static func makeHandler(
        converter: SpeechAudioBufferConverter,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> SpeechAudioTapHandler {
        { buffer, _ in
            guard let converted = converter.convert(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}

enum SpeechCaptureState: Equatable, Sendable {
    case idle
    case preparing
    case downloadingAssets
    case recording
    case unavailable(String)

    var isActive: Bool {
        switch self {
        case .preparing, .downloadingAssets, .recording:
            true
        case .idle, .unavailable:
            false
        }
    }

    var isPreparing: Bool {
        switch self {
        case .preparing, .downloadingAssets:
            true
        case .idle, .recording, .unavailable:
            false
        }
    }

    var isRecording: Bool {
        if case .recording = self { true } else { false }
    }

    var presentation: SpeechCapturePresentation {
        switch self {
        case .idle:
            SpeechCapturePresentation(
                title: "Record on this iPhone",
                detail: "Speak, keep typing, or use the keyboard’s dictation button. Raw audio is never saved.",
                systemImage: "lock.shield",
                showsProgress: false
            )
        case .preparing:
            SpeechCapturePresentation(
                title: "Getting ready",
                detail: "Setting up on-device transcription. You can keep typing.",
                systemImage: "mic",
                showsProgress: true
            )
        case .downloadingAssets:
            SpeechCapturePresentation(
                title: "Downloading speech support",
                detail: "Keep typing or use keyboard dictation while it downloads.",
                systemImage: "arrow.down.circle",
                showsProgress: true
            )
        case .recording:
            SpeechCapturePresentation(
                title: "Listening",
                detail: "Speak naturally, then tap Stop. Your text appears above.",
                systemImage: "waveform",
                showsProgress: false
            )
        case .unavailable(let message):
            SpeechCapturePresentation(
                title: "Voice capture is unavailable",
                detail: message,
                systemImage: "keyboard",
                showsProgress: false
            )
        }
    }

    var actionTitle: String {
        switch self {
        case .preparing, .downloadingAssets:
            "Cancel voice capture"
        case .recording:
            "Stop recording"
        case .idle, .unavailable:
            "Start voice capture"
        }
    }

    var actionSystemImage: String {
        switch self {
        case .preparing, .downloadingAssets:
            "xmark.circle"
        case .recording:
            "stop.circle.fill"
        case .idle, .unavailable:
            "mic"
        }
    }
}

struct SpeechCapturePresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
    let showsProgress: Bool
}

enum SpeechCaptureError: LocalizedError {
    case permissionDenied
    case unsupportedLocale
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone or speech permission is off. Keep typing or use the keyboard’s dictation button."
        case .unsupportedLocale: "On-device transcription is not available for this language yet. Keep typing or use the keyboard’s dictation button."
        case .unavailable: "On-device transcription is unavailable right now. Keep typing or use the keyboard’s dictation button."
        }
    }
}

@MainActor
protocol SpeechCapturing: AnyObject {
    var state: SpeechCaptureState { get }
    func start(
        initialTranscript: String,
        onTranscript: @escaping @MainActor @Sendable (String) -> Void
    ) async throws
    func stop() async
}

@MainActor
@Observable
final class OnDeviceSpeechCapture: SpeechCapturing {
    private enum Backend {
        case transcription(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .transcription(let module): module
            case .dictation(let module): module
            }
        }
    }

    private(set) var state: SpeechCaptureState = .idle
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?
    private var tapInstalled = false
    private var activeCaptureID: UUID?

    func start(
        initialTranscript: String,
        onTranscript: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        guard !state.isActive else { return }
        let captureID = UUID()
        activeCaptureID = captureID
        state = .preparing
        do {
            guard await permissionsGranted() else { throw SpeechCaptureError.permissionDenied }
            try ensureCaptureIsActive(captureID)

            let locale = Locale.current
            let backend: Backend
            if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                backend = .transcription(SpeechTranscriber(locale: supported, preset: .progressiveTranscription))
            } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
                backend = .dictation(DictationTranscriber(locale: supported, preset: .progressiveShortDictation))
            } else {
                throw SpeechCaptureError.unsupportedLocale
            }

            try await installAssetsIfNeeded(for: backend.module)
            try ensureCaptureIsActive(captureID)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: [])
            let input = audioEngine.inputNode
            let captureFormat = input.outputFormat(forBus: 0)
            guard SpeechCaptureAudioPlan.isUsableCaptureFormat(
                sampleRate: captureFormat.sampleRate,
                channelCount: captureFormat.channelCount
            ) else {
                throw SpeechCaptureError.unavailable
            }

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [backend.module],
                considering: captureFormat
            ) else {
                throw SpeechCaptureError.unavailable
            }
            let audioPlan = SpeechCaptureAudioPlan(captureFormat: captureFormat, analyzerFormat: analyzerFormat)
            guard let converter = SpeechAudioBufferConverter(from: captureFormat, to: analyzerFormat) else {
                throw SpeechCaptureError.unavailable
            }

            state = .preparing
            let analyzer = SpeechAnalyzer(modules: [backend.module])
            self.analyzer = analyzer
            try ensureCaptureIsActive(captureID)
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            try ensureCaptureIsActive(captureID)

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.continuation = continuation
            resultTask = Task { @MainActor in
                var transcript = SpeechTranscriptAccumulator(initialTranscript: initialTranscript)
                do {
                    switch backend {
                    case .transcription(let module):
                        for try await result in module.results {
                            onTranscript(transcript.merge(String(result.text.characters), range: result.range))
                        }
                    case .dictation(let module):
                        for try await result in module.results {
                            onTranscript(transcript.merge(String(result.text.characters), range: result.range))
                        }
                    }
                } catch is CancellationError {
                    // Normal when the creator stops capture.
                } catch {
                    guard self.activeCaptureID == captureID else { return }
                    self.activeCaptureID = nil
                    await self.cleanupAudio()
                    self.state = .unavailable(SpeechCaptureError.unavailable.localizedDescription)
                }
            }

            let tapHandler = SpeechAudioTapBridge.makeHandler(converter: converter, continuation: continuation)
            input.installTap(onBus: 0, bufferSize: 1_024, format: audioPlan.tapFormat, block: tapHandler)
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            try ensureCaptureIsActive(captureID)
            state = .recording
            try await analyzer.start(inputSequence: stream)
        } catch is CancellationError {
            if activeCaptureID == captureID {
                activeCaptureID = nil
                await cleanupAudio()
                state = .idle
            }
            throw CancellationError()
        } catch {
            guard activeCaptureID == captureID else { throw CancellationError() }
            activeCaptureID = nil
            await cleanupAudio()
            let captureError = error as? SpeechCaptureError ?? .unavailable
            state = .unavailable(captureError.localizedDescription)
            throw captureError
        }
    }

    func stop() async {
        activeCaptureID = nil
        await cleanupAudio()
        state = .idle
    }

    private func cleanupAudio() async {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.reset()
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultTask?.cancel()
        resultTask = nil
        continuation = nil
        analyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func permissionsGranted() async -> Bool {
        let speechStatus = await SpeechAuthorizationBridge.request { completion in
            SFSpeechRecognizer.requestAuthorization(completion)
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func ensureCaptureIsActive(_ captureID: UUID) throws {
        try Task.checkCancellation()
        guard activeCaptureID == captureID else { throw CancellationError() }
    }

    private func installAssetsIfNeeded(for module: any SpeechModule) async throws {
        let status = await AssetInventory.status(forModules: [module])
        switch status {
        case .installed:
            return
        case .supported, .downloading:
            state = .downloadingAssets
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        case .unsupported:
            throw SpeechCaptureError.unavailable
        @unknown default:
            throw SpeechCaptureError.unavailable
        }
    }
}

@MainActor
@Observable
final class PreviewSpeechCapture: SpeechCapturing {
    private(set) var state: SpeechCaptureState = .idle

    func start(
        initialTranscript: String,
        onTranscript: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        state = .recording
        let preview = "A rough idea about making the first step smaller and easier to act on."
        onTranscript([initialTranscript, preview].filter { !$0.isEmpty }.joined(separator: " "))
    }

    func stop() async {
        state = .idle
    }
}
