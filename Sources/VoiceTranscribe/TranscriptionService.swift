import AVFoundation
import CoreMedia
import Foundation
import Speech

protocol TranscriptionService {
    var engineName: String { get }
    func start(onSegment: @escaping (TranscriptSegment) -> Void) async throws
    func append(_ buffer: AVAudioPCMBuffer)
    func stop()
}

final class AppleSpeechTranscriptionService: TranscriptionService {
    let engineName = "Apple SpeechTranscriber"

    private let locale: Locale
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var rawContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var conversionTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func start(onSegment: @escaping (TranscriptSegment) -> Void) async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.engineUnavailable
        }

        stop()
        resultsTask?.cancel()
        resultsTask = nil

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber
        try await ensureModelInstalled(for: locale, transcriber: transcriber)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.engineUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (analyzerStream, analyzerContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzerContinuation = analyzerContinuation

        resultsTask = Task.detached { [transcriber] in
            do {
                for try await result in transcriber.results {
                    onSegment(TranscriptSegment(
                        text: String(result.text.characters),
                        isFinal: result.isFinal,
                        confidence: nil
                    ))
                }
            } catch {
                onSegment(TranscriptSegment(
                    text: "Transcription error: \(error.localizedDescription)",
                    isFinal: true
                ))
            }
        }

        let (rawStream, rawContinuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.rawContinuation = rawContinuation
        conversionTask = Task.detached {
            var converter: AVAudioConverter?
            var sourceFormat: AVAudioFormat?
            var sampleClock: Int64 = 0
            let timescale = CMTimeScale(analyzerFormat.sampleRate)

            for await buffer in rawStream {
                if sourceFormat != buffer.format {
                    converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
                    sourceFormat = buffer.format
                }

                let output = converter.flatMap {
                    convert(buffer, using: $0, to: analyzerFormat)
                } ?? buffer
                let startTime = CMTime(value: sampleClock, timescale: timescale)
                sampleClock += Int64(output.frameLength)
                analyzerContinuation.yield(AnalyzerInput(buffer: output, bufferStartTime: startTime))
            }

            analyzerContinuation.finish()
        }

        try await analyzer.start(inputSequence: analyzerStream)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = copyBuffer(buffer) else {
            return
        }
        rawContinuation?.yield(copy)
    }

    func stop() {
        rawContinuation?.finish()
        rawContinuation = nil
        analyzerContinuation = nil
        conversionTask = nil

        let analyzer = analyzer
        Task {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        }

        self.analyzer = nil
        transcriber = nil
    }

    private func ensureModelInstalled(for locale: Locale, transcriber: SpeechTranscriber) async throws {
        let target = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == target }) {
            return
        }

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == target }) else {
            throw TranscriptionError.localeUnsupported
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case engineUnavailable
    case localeUnsupported

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition permission is required before transcription can start."
        case .engineUnavailable:
            return "The selected transcription engine is unavailable."
        case .localeUnsupported:
            return "Speech recognition is not supported for the current language."
        }
    }
}

@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var interimSegment: TranscriptSegment?
    @Published private(set) var isTranscribing = false
    @Published private(set) var isStarting = false
    @Published private(set) var lastError: String?
    @Published private(set) var bufferSnapshot = TranscriptionBufferSnapshot()

    private var transcript = TranscriptDocument()
    private var service: TranscriptionService
    private var bufferTimer: Timer?
    private var startTask: Task<Void, Error>?

    init(service: TranscriptionService = AppleSpeechTranscriptionService()) {
        self.service = service
    }

    var engineName: String {
        service.engineName
    }

    var transcriptText: String {
        transcript.plainText
    }

    /// Replace the transcription engine.  Cancels any in-progress start and
    /// stops active transcription before swapping.
    func setEngine(_ kind: TranscriptionEngineKind) {
        let oldEngine = service.engineName
        let wasRunning = isTranscribing || isStarting

        // Cancel any pending start (e.g. FluidAudio model download in flight).
        startTask?.cancel()
        startTask = nil
        isStarting = false

        if isTranscribing {
            stop()
        }

        service = Self.makeService(for: kind)

        Trace.event("transcription.engineChanged", [
            "from": oldEngine,
            "to": service.engineName,
            "wasRunning": wasRunning
        ])
    }

    private static func makeService(for kind: TranscriptionEngineKind) -> TranscriptionService {
        switch kind {
        case .appleSpeech:
            return AppleSpeechTranscriptionService()
        case .fluidAudio:
            return FluidAudioTranscriptionService()
        }
    }

    func start() async throws {
        transcript = TranscriptDocument()
        segments = []
        interimSegment = nil
        bufferSnapshot = TranscriptionBufferSnapshot()
        isStarting = true

        let task = Task { @MainActor in
            Trace.event("transcription.starting", ["engine": service.engineName])
            try await service.start { [weak self] segment in
                Task { @MainActor in
                    self?.apply(segment)
                }
            }

            // Check cancellation before committing — setEngine or stop may
            // have been called during a long model download.
            try Task.checkCancellation()

            isTranscribing = true
            isStarting = false
            startBufferTimer()
            lastError = nil
            Trace.event("transcription.started", ["engine": service.engineName])
        }

        startTask = task

        do {
            try await task.value
        } catch is CancellationError {
            isStarting = false
            Trace.event("transcription.cancelled", ["engine": service.engineName])
            throw CancellationError()
        } catch {
            isStarting = false
            throw error
        }
    }

    func consume(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let duration = TimeInterval(buffer.frameLength) / max(buffer.format.sampleRate, 1)
        bufferSnapshot.queuedDuration = min(
            bufferSnapshot.queuedDuration + duration,
            bufferSnapshot.maxDuration
        )
        bufferSnapshot.isReceivingAudio = true
        bufferSnapshot.lastAudioAt = Date()
        service.append(buffer)
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        isStarting = false

        service.stop()
        isTranscribing = false
        interimSegment = nil
        bufferTimer?.invalidate()
        bufferTimer = nil
        bufferSnapshot.isReceivingAudio = false
        Trace.event("transcription.stopped", ["finalSegments": segments.count])
    }

    private func apply(_ segment: TranscriptSegment) {
        bufferSnapshot.lastResultAt = Date()
        bufferSnapshot.queuedDuration = segment.isFinal ? 0 : min(bufferSnapshot.queuedDuration, 0.75)
        transcript.apply(segment)
        if segment.isFinal {
            Trace.event("transcription.segmentFinal", ["text": segment.text.prefix(80), "confidence": segment.confidence.map { String(format: "%.2f", $0) } ?? "nil"])
            segments.append(segment)
            interimSegment = nil
        } else {
            Trace.event("transcription.segmentPartial", ["text": segment.text.prefix(80)])
            interimSegment = segment
        }
    }

    private func startBufferTimer() {
        bufferTimer?.invalidate()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickBuffer()
            }
        }
    }

    private func tickBuffer() {
        guard isTranscribing else {
            return
        }

        bufferSnapshot.queuedDuration = max(bufferSnapshot.queuedDuration - 0.25, 0)
        if let lastAudioAt = bufferSnapshot.lastAudioAt {
            bufferSnapshot.isReceivingAudio = Date().timeIntervalSince(lastAudioAt) < 0.75
        } else {
            bufferSnapshot.isReceivingAudio = false
        }
    }
}

private func convert(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat
) -> AVAudioPCMBuffer? {
    if buffer.format == format {
        return buffer
    }

    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        return nil
    }

    var fed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        if fed {
            status.pointee = .noDataNow
            return nil
        }

        fed = true
        status.pointee = .haveData
        return buffer
    }

    return output.frameLength > 0 ? output : nil
}

private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
        return nil
    }

    copy.frameLength = buffer.frameLength
    let channels = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)

    if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
        for channel in 0..<channels {
            memcpy(destination[channel], source[channel], frames * MemoryLayout<Float>.size)
        }
        return copy
    }

    if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
        for channel in 0..<channels {
            memcpy(destination[channel], source[channel], frames * MemoryLayout<Int16>.size)
        }
        return copy
    }

    if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
        for channel in 0..<channels {
            memcpy(destination[channel], source[channel], frames * MemoryLayout<Int32>.size)
        }
        return copy
    }

    return nil
}
