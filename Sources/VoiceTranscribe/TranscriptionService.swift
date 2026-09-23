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
            // Ask for the audio time of each result. The analyzer's timeline is the audio we fed
            // it, starting at zero, so for an imported file these ranges are positions in that
            // file — what lets its transcript follow playback instead of being stuck on clock time.
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber
        try await ensureModelInstalled(for: locale, transcriber: transcriber)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.engineUnavailable
        }
        Trace.event("transcription.analyzerFormat", [
            "sampleRate": Int(analyzerFormat.sampleRate),
            "channels": Int(analyzerFormat.channelCount),
            "commonFormat": analyzerFormat.commonFormat.rawValue
        ])

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
                        confidence: nil,
                        audioOffset: Self.audioOffset(of: result)
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
                let analyzerInputBuffer = normalizeForSpeechAnalyzer(buffer)
                if sourceFormat != analyzerInputBuffer.format {
                    converter = analyzerInputBuffer.format == analyzerFormat
                        ? nil
                        : AVAudioConverter(from: analyzerInputBuffer.format, to: analyzerFormat)
                    sourceFormat = analyzerInputBuffer.format
                    Trace.event("transcription.converterConfigured", [
                        "sourceSampleRate": Int(analyzerInputBuffer.format.sampleRate),
                        "sourceChannels": Int(analyzerInputBuffer.format.channelCount),
                        "targetSampleRate": Int(analyzerFormat.sampleRate),
                        "targetChannels": Int(analyzerFormat.channelCount),
                        "hasConverter": converter != nil || analyzerInputBuffer.format == analyzerFormat
                    ])
                }

                let output: AVAudioPCMBuffer
                if analyzerInputBuffer.format == analyzerFormat {
                    output = analyzerInputBuffer
                } else if let converted = converter.flatMap({ convert(analyzerInputBuffer, using: $0, to: analyzerFormat) }) {
                    output = converted
                } else {
                    Trace.event("transcription.converterFailed", [
                        "sourceSampleRate": Int(analyzerInputBuffer.format.sampleRate),
                        "sourceChannels": Int(analyzerInputBuffer.format.channelCount),
                        "targetSampleRate": Int(analyzerFormat.sampleRate),
                        "targetChannels": Int(analyzerFormat.channelCount)
                    ])
                    continue
                }
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

    /// The earliest position in the fed audio that a result covers, or nil when the engine gave no
    /// time range for it. Measured from the start of the audio the analyzer was fed, so on an
    /// imported file it is that row's position in the file.
    ///
    /// Earliest rather than a per-run list: a row's window runs on to the next row's start, which
    /// is how the transcript's rows divide the audio between them, so the figure that matters is
    /// where the row begins.
    private static func audioOffset(of result: SpeechTranscriber.Result) -> TimeInterval? {
        var earliest: TimeInterval?
        for run in result.text.runs {
            guard let range = run.audioTimeRange, range.isValid, !range.isEmpty else {
                continue
            }
            let seconds = CMTimeGetSeconds(range.start)
            guard seconds.isFinite, seconds >= 0 else {
                continue
            }
            if let current = earliest {
                earliest = min(current, seconds)
            } else {
                earliest = seconds
            }
        }
        return earliest
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
    /// True while live capture is paused: incoming buffers are dropped instead of fed to the engine.
    @Published private(set) var isPaused = false
    /// Paused spans for this session, in pause order; the last span is open while `isPaused`.
    @Published private(set) var pauseSpans: [TranscriptionPauseSpan] = []
    var onFinalSegment: ((TranscriptSegment) -> Void)?
    var speakerProvider: ((TranscriptSegment) -> SpeakerAnnotation?)?

    private var transcript = TranscriptDocument()
    private var service: TranscriptionService
    private var bufferTimer: Timer?
    private var startTask: Task<Void, Error>?
    private var lastFinalizedNormalizedText = ""
    private var consumedBufferCount = 0
    private var sessionID = UUID()

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
            return AppleSpeechTranscriptionService()
        }
    }

    func start() async throws {
        let sessionID = UUID()
        self.sessionID = sessionID
        transcript = TranscriptDocument()
        segments = []
        interimSegment = nil
        bufferSnapshot = TranscriptionBufferSnapshot()
        consumedBufferCount = 0
        lastFinalizedNormalizedText = ""
        isPaused = false
        pauseSpans = []
        isStarting = true

        let task = Task { @MainActor in
            Trace.event("transcription.starting", ["engine": service.engineName])
            try await service.start { [weak self] segment in
                Task { @MainActor in
                    guard let self, self.sessionID == sessionID, self.isStarting || self.isTranscribing else {
                        Trace.event("transcription.segment.staleIgnored", [
                            "text": segment.text.prefix(80),
                            "final": segment.isFinal ? "true" : "false"
                        ])
                        return
                    }
                    self.apply(segment)
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
        // Paused capture withholds buffers entirely. The engine, its analyzer, and the
        // in-flight interim utterance all stay alive, so resume continues the same
        // sentence, but audio captured while paused never reaches the transcript.
        guard isTranscribing, !isPaused else {
            return
        }
        let duration = TimeInterval(buffer.frameLength) / max(buffer.format.sampleRate, 1)
        bufferSnapshot.queuedDuration = min(
            bufferSnapshot.queuedDuration + duration,
            bufferSnapshot.maxDuration
        )
        bufferSnapshot.isReceivingAudio = true
        bufferSnapshot.lastAudioAt = Date()
        consumedBufferCount += 1
        if consumedBufferCount == 1 || consumedBufferCount % 50 == 0 {
            Trace.event("transcription.bufferConsumed", [
                "buffer#": consumedBufferCount,
                "engine": service.engineName,
                "duration": String(format: "%.4f", duration),
                "sampleRate": Int(buffer.format.sampleRate),
                "channels": Int(buffer.format.channelCount)
            ])
        }
        service.append(buffer)
    }

    func stop() {
        sessionID = UUID()
        startTask?.cancel()
        startTask = nil
        isStarting = false

        closeOpenPauseSpan()
        isPaused = false
        service.stop()
        isTranscribing = false
        interimSegment = nil
        bufferTimer?.invalidate()
        bufferTimer = nil
        bufferSnapshot.isReceivingAudio = false
        Trace.event("transcription.stopped", ["finalSegments": segments.count])
    }

    /// Pauses live transcription without tearing down the engine. Buffers arriving
    /// while paused are dropped, so the paused span is absent from the transcript
    /// rather than being transcribed late when audio resumes.
    func pause() {
        guard isTranscribing, !isPaused else {
            return
        }
        isPaused = true
        pauseSpans.append(TranscriptionPauseSpan())
        bufferSnapshot.isReceivingAudio = false
        Trace.event("transcription.paused", [
            "engine": service.engineName,
            "segments": segments.count
        ])
    }

    /// Resumes buffer consumption after `pause()`. The interim utterance is kept, so
    /// speech that straddled the pause continues in the same segment.
    func resume() {
        guard isPaused else {
            return
        }
        closeOpenPauseSpan()
        isPaused = false
        Trace.event("transcription.resumed", [
            "engine": service.engineName,
            "pauseSpans": pauseSpans.count,
            "lastPausedSeconds": String(format: "%.2f", pauseSpans.last?.duration ?? 0)
        ])
    }

    private func closeOpenPauseSpan(at date: Date = Date()) {
        guard let lastIndex = pauseSpans.indices.last, pauseSpans[lastIndex].endedAt == nil else {
            return
        }
        pauseSpans[lastIndex].endedAt = date
    }

    func updateSpeakerName(speakerID: String, speakerName: String?) {
        segments = segments.map { segment in
            guard segment.speakerID == speakerID else {
                return segment
            }
            var copy = segment
            copy.speakerName = speakerName
            return copy
        }

        if var interimSegment, interimSegment.speakerID == speakerID {
            interimSegment.speakerName = speakerName
            self.interimSegment = interimSegment
        }

        transcript.updateSpeakerName(speakerID: speakerID, speakerName: speakerName)
        Trace.event("transcription.speakerName.updated", [
            "speakerID": speakerID,
            "speakerName": speakerName ?? ""
        ])
    }

    func updateObservedVoiceName(speakerID: String, voiceID: String?, speakerName: String?) {
        segments = segments.map { segment in
            guard segment.speakerID == speakerID,
                  Self.normalizedVoiceID(segment.voiceID) == Self.normalizedVoiceID(voiceID) else {
                return segment
            }
            var copy = segment
            copy.speakerName = speakerName
            return copy
        }

        if var interimSegment,
           interimSegment.speakerID == speakerID,
           Self.normalizedVoiceID(interimSegment.voiceID) == Self.normalizedVoiceID(voiceID) {
            interimSegment.speakerName = speakerName
            self.interimSegment = interimSegment
        }

        transcript.updateObservedVoiceName(
            speakerID: speakerID,
            voiceID: voiceID,
            speakerName: speakerName
        )
        Trace.event("transcription.observedVoiceName.updated", [
            "speakerID": speakerID,
            "voiceID": voiceID ?? "",
            "speakerName": speakerName ?? ""
        ])
    }

    func synchronizePeople(_ directory: SessionIdentityDirectory) {
        segments = segments.map(directory.resolved)
        if let interimSegment {
            self.interimSegment = directory.resolved(interimSegment)
        }
        transcript.synchronizePeople(directory)
    }

    func updateSegmentPerson(segmentID: UUID, personID: UUID?, name: String?) {
        segments = segments.map { segment in
            guard segment.id == segmentID else { return segment }
            var copy = segment
            copy.personID = personID
            copy.manualPersonID = personID
            copy.speakerName = name ?? "Unidentified audio"
            copy.diarizationRangeID = nil
            copy.isPersonOverride = true
            return copy
        }
        if var interimSegment, interimSegment.id == segmentID {
            interimSegment.personID = personID
            interimSegment.manualPersonID = personID
            interimSegment.speakerName = name ?? "Unidentified audio"
            interimSegment.diarizationRangeID = nil
            interimSegment.isPersonOverride = true
            self.interimSegment = interimSegment
        }
        transcript.updateSegmentPerson(segmentID: segmentID, personID: personID, name: name)
    }

    func updateVoiceIdentity(
        speakerID: String,
        voiceID: String?,
        voiceName: String?,
        voiceConfidence: Float?
    ) {
        segments = segments.map { segment in
            guard segment.speakerID == speakerID else {
                return segment
            }
            var copy = segment
            copy.voiceID = voiceID
            copy.voiceName = voiceName
            copy.voiceConfidence = voiceConfidence
            return copy
        }

        if var interimSegment, interimSegment.speakerID == speakerID {
            interimSegment.voiceID = voiceID
            interimSegment.voiceName = voiceName
            interimSegment.voiceConfidence = voiceConfidence
            self.interimSegment = interimSegment
        }

        transcript.updateVoiceIdentity(
            speakerID: speakerID,
            voiceID: voiceID,
            voiceName: voiceName,
            voiceConfidence: voiceConfidence
        )
        Trace.event("transcription.voiceIdentity.updated", [
            "speakerID": speakerID,
            "voiceID": voiceID ?? "",
            "voiceName": voiceName ?? "",
            "confidence": voiceConfidence.map { String(format: "%.3f", $0) } ?? ""
        ])
    }

    func updateSegmentSpeaker(segmentID: UUID, speakerID: String?, speakerName: String?) {
        updateSegmentIdentity(
            segmentID: segmentID,
            speakerID: speakerID,
            speakerName: speakerName,
            voiceID: nil,
            voiceName: nil,
            voiceConfidence: nil
        )
    }

    func updateSegmentIdentity(
        segmentID: UUID,
        speakerID: String?,
        speakerName: String?,
        voiceID: String?,
        voiceName: String?,
        voiceConfidence: Float?
    ) {
        segments = segments.map { segment in
            guard segment.id == segmentID else {
                return segment
            }
            var copy = segment
            copy.speakerID = speakerID
            copy.speakerName = speakerName
            copy.voiceID = voiceID
            copy.voiceName = voiceName
            copy.voiceConfidence = voiceConfidence
            copy.isPersonOverride = true
            copy.diarizationRangeID = nil
            return copy
        }

        if var interimSegment, interimSegment.id == segmentID {
            interimSegment.speakerID = speakerID
            interimSegment.speakerName = speakerName
            interimSegment.voiceID = voiceID
            interimSegment.voiceName = voiceName
            interimSegment.voiceConfidence = voiceConfidence
            interimSegment.isPersonOverride = true
            interimSegment.diarizationRangeID = nil
            self.interimSegment = interimSegment
        }

        transcript.updateSegmentIdentity(
            segmentID: segmentID,
            speakerID: speakerID,
            speakerName: speakerName,
            voiceID: voiceID,
            voiceName: voiceName,
            voiceConfidence: voiceConfidence
        )
        Trace.event("transcription.segmentIdentity.updated", [
            "segmentID": segmentID.uuidString,
            "speakerID": speakerID ?? "",
            "speakerName": speakerName ?? "",
            "voiceID": voiceID ?? "",
            "voiceName": voiceName ?? "",
            "confidence": voiceConfidence.map { String(format: "%.3f", $0) } ?? ""
        ])
    }

    private func apply(_ segment: TranscriptSegment) {
        var segment = segment
        if let speaker = speakerProvider?(segment) {
            segment.speakerID = speaker.speakerID
            segment.speakerName = speaker.speakerName
            segment.voiceID = speaker.voiceID
            segment.voiceName = speaker.voiceName
            segment.voiceConfidence = speaker.voiceConfidence
            segment.personID = speaker.personID
            segment.diarizationRangeID = speaker.rangeID
        }
        bufferSnapshot.lastResultAt = Date()
        bufferSnapshot.queuedDuration = segment.isFinal ? 0 : min(bufferSnapshot.queuedDuration, 0.75)
        if segment.isFinal {
            let normalized = Self.normalizedTranscriptText(segment.text)
            if !normalized.isEmpty, normalized == lastFinalizedNormalizedText {
                interimSegment = nil
                Trace.event("transcription.segmentFinal.duplicateSuppressed", [
                    "text": segment.text.prefix(80)
                ])
                return
            }
            transcript.apply(segment)
            lastFinalizedNormalizedText = normalized
            Trace.event("transcription.segmentFinal", [
                "text": segment.text.prefix(80),
                "confidence": segment.confidence.map { String(format: "%.2f", $0) } ?? "nil",
                "speaker": segment.speakerLabel ?? "nil"
            ])
            segments.append(segment)
            onFinalSegment?(segment)
            interimSegment = nil
        } else {
            if shouldSuppressStalePartial(segment) {
                Trace.event("transcription.segmentPartial.staleSuppressed", [
                    "text": segment.text.prefix(80),
                    "speaker": segment.speakerLabel ?? "nil"
                ])
                return
            }
            transcript.apply(segment)
            Trace.event("transcription.segmentPartial", [
                "text": segment.text.prefix(80),
                "speaker": segment.speakerLabel ?? "nil"
            ])
            interimSegment = segment
        }
    }

    private func shouldSuppressStalePartial(_ segment: TranscriptSegment) -> Bool {
        let normalized = Self.normalizedTranscriptText(segment.text)
        guard !normalized.isEmpty, !lastFinalizedNormalizedText.isEmpty else {
            return false
        }
        return lastFinalizedNormalizedText.hasPrefix(normalized)
            || normalized.hasPrefix(lastFinalizedNormalizedText)
    }

    nonisolated private static func normalizedTranscriptText(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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

    private static func normalizedVoiceID(_ voiceID: String?) -> String? {
        let trimmed = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private func normalizeForSpeechAnalyzer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
    guard buffer.format.channelCount != 1,
          let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
          ),
          let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) else {
        return buffer
    }

    monoBuffer.frameLength = buffer.frameLength
    let channelCount = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    guard let output = monoBuffer.floatChannelData?[0] else {
        return buffer
    }

    if let input = buffer.floatChannelData {
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += input[channel][frame]
            }
            output[frame] = sum / Float(channelCount)
        }
        return monoBuffer
    }

    if let input = buffer.int16ChannelData {
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += Float(input[channel][frame]) / Float(Int16.max)
            }
            output[frame] = sum / Float(channelCount)
        }
        return monoBuffer
    }

    if let input = buffer.int32ChannelData {
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += Float(input[channel][frame]) / Float(Int32.max)
            }
            output[frame] = sum / Float(channelCount)
        }
        return monoBuffer
    }

    return buffer
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
