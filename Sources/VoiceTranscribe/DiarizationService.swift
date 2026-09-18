import AVFoundation
import AudioCommon
import Foundation
import SpeechVAD

@MainActor
final class DiarizationCoordinator: ObservableObject {
    @Published private(set) var segments: [SpeakerDiarizationSegment] = []
    @Published private(set) var isStarting = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var engine: SpeechSwiftSortformerDiarizationEngine?
    private let voiceIdentity = VoiceIdentityService()
    private var sessionID = UUID()
    private var lastSpeaker: SpeakerDiarizationSegment?
    private var tracedSegmentKeys = Set<String>()
    private var voiceIdentitySegmentKeys = Set<String>()
    private var voiceIdentitySkippedKeys = Set<String>()
    private var voiceIdentities: [String: VoiceIdentityMatch] = [:]
    private var sessionAudioSamples: [Float] = []
    private let identitySampleRate = 16_000
    private let identityLiveEdgeDelay: TimeInterval = 1.2
    private var hasLoggedVoiceIdentityFailure = false
    private var diarizationBufferCount = 0
    private var ignoredDiarizationBufferCount = 0
    private var speakerNames: [String: String] = [:]
    private var observedVoiceNames: [String: String] = [:]

    var currentSpeakerLabel: String? {
        lastSpeaker?.speakerLabel
    }

    var currentSpeakerID: String? {
        lastSpeaker?.speakerID
    }

    func start() async throws {
        reset()
        isStarting = true
        Trace.event("diarization.starting")
        do {
            let engine = SpeechSwiftSortformerDiarizationEngine()
            try await engine.start()
            self.engine = engine
            isStarting = false
            isRunning = true
            lastError = nil
            Trace.event("diarization.started", ["engine": "SpeechVAD Sortformer"])
        } catch {
            isStarting = false
            isRunning = false
            lastError = error.localizedDescription
            Trace.event("diarization.error", ["error": error.localizedDescription])
            throw error
        }
    }

    func reset() {
        engine = nil
        segments = []
        sessionID = UUID()
        lastSpeaker = nil
        tracedSegmentKeys = []
        voiceIdentitySegmentKeys = []
        voiceIdentitySkippedKeys = []
        voiceIdentities = [:]
        sessionAudioSamples = []
        hasLoggedVoiceIdentityFailure = false
        diarizationBufferCount = 0
        ignoredDiarizationBufferCount = 0
        speakerNames = [:]
        observedVoiceNames = [:]
        isStarting = false
        isRunning = false
        lastError = nil
        Task {
            await voiceIdentity.reset()
        }
    }

    func stop() {
        guard let engine else {
            isRunning = false
            isStarting = false
            return
        }

        let sessionID = self.sessionID
        self.engine = nil
        isRunning = false
        isStarting = false
        Task { [weak self] in
            do {
                await engine.stopAcceptingInput()
                let finalized = try await engine.finalize()
                await MainActor.run {
                    guard self?.sessionID == sessionID else {
                        return
                    }
                    self?.replaceSegments(finalized)
                    Trace.event("diarization.stopped", [
                        "segments": self?.segments.count ?? 0
                    ])
                }
            } catch {
                await MainActor.run {
                    guard self?.sessionID == sessionID else {
                        return
                    }
                    self?.lastError = error.localizedDescription
                    Trace.event("diarization.stopError", ["error": error.localizedDescription])
                }
            }
        }
    }

    func consume(buffer: AVAudioPCMBuffer, time _: AVAudioTime) {
        guard let engine, isRunning else {
            ignoredDiarizationBufferCount += 1
            if ignoredDiarizationBufferCount == 1 || ignoredDiarizationBufferCount % 50 == 0 {
                Trace.event("diarization.bufferIgnored", [
                    "buffer#": ignoredDiarizationBufferCount,
                    "reason": engine == nil ? "noEngine" : "notRunning",
                    "isRunning": isRunning ? "true" : "false",
                    "isStarting": isStarting ? "true" : "false"
                ])
            }
            return
        }

        let sampleRate = buffer.format.sampleRate
        let samples = Self.monoFloatSamples(from: buffer)
        let sessionID = self.sessionID
        guard !samples.isEmpty else {
            return
        }
        appendSessionAudio(samples: samples, sampleRate: sampleRate)
        diarizationBufferCount += 1
        if diarizationBufferCount == 1 || diarizationBufferCount % 50 == 0 {
            let bufferedDuration = TimeInterval(sessionAudioSamples.count) / TimeInterval(identitySampleRate)
            Trace.event("diarization.bufferConsumed", [
                "buffer#": diarizationBufferCount,
                "sampleRate": Int(sampleRate),
                "channels": Int(buffer.format.channelCount),
                "frames": Int(buffer.frameLength),
                "samples": samples.count,
                "identityBufferedSeconds": String(format: "%.2f", bufferedDuration)
            ])
        }

        Task { [weak self] in
            do {
                let updates = try await engine.process(samples: samples, sampleRate: sampleRate)
                await MainActor.run {
                    guard self?.sessionID == sessionID else {
                        return
                    }
                    self?.replaceSegments(updates)
                }
            } catch {
                await MainActor.run {
                    guard self?.sessionID == sessionID else {
                        return
                    }
                    self?.lastError = error.localizedDescription
                    Trace.event("diarization.processError", ["error": error.localizedDescription])
                }
            }
        }
    }

    func annotationForCurrentSpeaker() -> SpeakerAnnotation? {
        guard let lastSpeaker else {
            return nil
        }
        return SpeakerAnnotation(
            speakerID: lastSpeaker.speakerID,
            speakerName: lastSpeaker.speakerName,
            voiceID: lastSpeaker.voiceID,
            voiceName: lastSpeaker.voiceName,
            voiceConfidence: lastSpeaker.voiceConfidence
        )
    }

    func speakerName(for speakerID: String) -> String? {
        speakerNames[speakerID]
    }

    func observedVoiceName(speakerID: String, voiceID: String?) -> String? {
        observedVoiceNames[observedVoiceKey(speakerID: speakerID, voiceID: voiceID)]
    }

    func setSpeakerName(speakerID: String, name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            speakerNames.removeValue(forKey: speakerID)
        } else {
            speakerNames[speakerID] = trimmed
        }

        applySpeakerNames()
        Trace.event("diarization.speakerName.updated", [
            "speakerID": speakerID,
            "speakerName": speakerNames[speakerID] ?? ""
        ])
    }

    func setObservedVoiceName(speakerID: String, voiceID: String?, name: String?) {
        let key = observedVoiceKey(speakerID: speakerID, voiceID: voiceID)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            observedVoiceNames.removeValue(forKey: key)
        } else {
            observedVoiceNames[key] = trimmed
        }

        applySpeakerNames()
        Trace.event("diarization.observedVoiceName.updated", [
            "speakerID": speakerID,
            "voiceID": voiceID ?? "",
            "speakerName": observedVoiceNames[key] ?? ""
        ])
    }

    private func replaceSegments(_ newSegments: [SpeakerDiarizationSegment]) {
        segments = newSegments
            .map { segment in
                var copy = segment
                copy.speakerName = displayName(for: copy)
                if let identity = voiceIdentities[voiceIdentityKey(segment)] {
                    copy.voiceID = identity.voiceID
                    copy.voiceName = identity.voiceName
                    copy.voiceConfidence = identity.confidence
                    copy.speakerName = displayName(for: copy)
                }
                return copy
            }
            .sorted { $0.startTime < $1.startTime }
        lastSpeaker = segments.max { $0.endTime < $1.endTime }
        queueVoiceIdentityWork(for: segments)

        for segment in segments {
            let key = segmentKey(segment)
            guard !tracedSegmentKeys.contains(key) else { continue }
            tracedSegmentKeys.insert(key)
            Trace.event("diarization.segment", [
                "speaker": segment.speakerLabel,
                "start": String(format: "%.2f", segment.startTime),
                "end": String(format: "%.2f", segment.endTime)
            ])
        }
    }

    private func segmentKey(_ segment: SpeakerDiarizationSegment) -> String {
        "\(segment.speakerID)|\(String(format: "%.2f", segment.startTime))|\(String(format: "%.2f", segment.endTime))"
    }

    private func voiceIdentityKey(_ segment: SpeakerDiarizationSegment) -> String {
        "\(segment.speakerID)|\(String(format: "%.2f", segment.startTime))"
    }

    private func applySpeakerNames() {
        segments = segments.map { segment in
            var copy = segment
            copy.speakerName = displayName(for: segment)
            return copy
        }
        if var lastSpeaker {
            lastSpeaker.speakerName = displayName(for: lastSpeaker)
            self.lastSpeaker = lastSpeaker
        }
    }

    private func displayName(for segment: SpeakerDiarizationSegment) -> String? {
        observedVoiceNames[observedVoiceKey(speakerID: segment.speakerID, voiceID: segment.voiceID)]
            ?? speakerNames[segment.speakerID]
    }

    private func observedVoiceKey(speakerID: String, voiceID: String?) -> String {
        VoiceIdentityKey.make(speakerID: speakerID, voiceID: voiceID)
    }

    private func appendSessionAudio(samples: [Float], sampleRate: Double) {
        let inputRate = Int(sampleRate.rounded())
        let prepared = inputRate == identitySampleRate
            ? samples
            : AudioFileLoader.resample(samples, from: inputRate, to: identitySampleRate)
        sessionAudioSamples.append(contentsOf: prepared)
    }

    private func queueVoiceIdentityWork(for segments: [SpeakerDiarizationSegment]) {
        let bufferedDuration = TimeInterval(sessionAudioSamples.count) / TimeInterval(identitySampleRate)
        for segment in segments {
            let key = voiceIdentityKey(segment)
            guard !voiceIdentitySegmentKeys.contains(key),
                  segment.endTime <= bufferedDuration - identityLiveEdgeDelay,
                  segment.endTime > segment.startTime else {
                continue
            }
            let duration = segment.endTime - segment.startTime
            guard duration >= 2.0 else {
                if voiceIdentitySkippedKeys.insert(key).inserted {
                    Trace.event("voiceIdentity.skipped", [
                        "reason": "tooShort",
                        "speakerID": segment.speakerID,
                        "start": String(format: "%.2f", segment.startTime),
                        "end": String(format: "%.2f", segment.endTime),
                        "duration": String(format: "%.2f", duration)
                    ])
                }
                continue
            }
            guard let audio = audioSlice(start: segment.startTime, end: segment.endTime) else {
                if voiceIdentitySkippedKeys.insert(key).inserted {
                    Trace.event("voiceIdentity.skipped", [
                        "reason": "missingAudio",
                        "speakerID": segment.speakerID,
                        "start": String(format: "%.2f", segment.startTime),
                        "end": String(format: "%.2f", segment.endTime),
                        "duration": String(format: "%.2f", duration)
                    ])
                }
                continue
            }

            voiceIdentitySegmentKeys.insert(key)
            let speakerID = segment.speakerID
            let sessionID = self.sessionID
            let sampleRate = identitySampleRate
            let identityService = voiceIdentity
            Trace.event("voiceIdentity.queued", [
                "speakerID": speakerID,
                "start": String(format: "%.2f", segment.startTime),
                "end": String(format: "%.2f", segment.endTime),
                "duration": String(format: "%.2f", duration),
                "samples": audio.count
            ])
            Task { [weak self] in
                do {
                    guard let identity = try await identityService.identify(
                        samples: audio,
                        sampleRate: sampleRate,
                        duration: duration
                    ) else {
                        return
                    }
                    await MainActor.run {
                        guard self?.sessionID == sessionID else {
                            return
                        }
                        self?.applyVoiceIdentity(identity, key: key, speakerID: speakerID)
                    }
                } catch {
                    await MainActor.run {
                        guard self?.sessionID == sessionID else {
                            return
                        }
                        if self?.hasLoggedVoiceIdentityFailure == false {
                            self?.hasLoggedVoiceIdentityFailure = true
                            Trace.event("voiceIdentity.error", ["error": error.localizedDescription])
                        }
                    }
                }
            }
        }
    }

    private func audioSlice(start: TimeInterval, end: TimeInterval) -> [Float]? {
        let startIndex = max(0, Int((start * TimeInterval(identitySampleRate)).rounded(.down)))
        let endIndex = min(sessionAudioSamples.count, Int((end * TimeInterval(identitySampleRate)).rounded(.up)))
        guard endIndex > startIndex else {
            return nil
        }
        return Array(sessionAudioSamples[startIndex..<endIndex])
    }

    private func applyVoiceIdentity(_ identity: VoiceIdentityMatch, key: String, speakerID: String) {
        voiceIdentities[key] = identity
        segments = segments.map { segment in
            guard voiceIdentityKey(segment) == key else {
                return segment
            }
            var copy = segment
            copy.voiceID = identity.voiceID
            copy.voiceName = identity.voiceName
            copy.voiceConfidence = identity.confidence
            copy.speakerName = displayName(for: copy)
            return copy
        }
        if var lastSpeaker, voiceIdentityKey(lastSpeaker) == key {
            lastSpeaker.voiceID = identity.voiceID
            lastSpeaker.voiceName = identity.voiceName
            lastSpeaker.voiceConfidence = identity.confidence
            lastSpeaker.speakerName = displayName(for: lastSpeaker)
            self.lastSpeaker = lastSpeaker
        }
        Trace.event("voiceIdentity.assigned", [
            "speakerID": speakerID,
            "voiceID": identity.voiceID,
            "voiceName": identity.voiceName,
            "matchType": identity.confidence == nil ? "new" : "matched",
            "confidence": identity.confidence.map { String(format: "%.3f", $0) } ?? ""
        ])
    }

    private static func monoFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return []
        }

        var samples = [Float](repeating: 0, count: frameLength)

        if let data = buffer.floatChannelData {
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += data[channel][frame]
                }
                samples[frame] = sum / Float(channelCount)
            }
            return samples
        }

        if let data = buffer.int16ChannelData {
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += Float(data[channel][frame]) / Float(Int16.max)
                }
                samples[frame] = sum / Float(channelCount)
            }
            return samples
        }

        if let data = buffer.int32ChannelData {
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += Float(data[channel][frame]) / Float(Int32.max)
                }
                samples[frame] = sum / Float(channelCount)
            }
            return samples
        }

        return []
    }
}

private actor SpeechSwiftSortformerDiarizationEngine {
    private let targetSampleRate = 16_000
    private var session: SortformerStreamingSession?
    private var isAcceptingInput = false

    func start() async throws {
        session = try await SortformerStreamingSession.fromPretrained(
            config: .streaming,
            progressHandler: { progress, stage in
                Trace.event("diarization.modelProgress", [
                    "engine": "SpeechVAD Sortformer",
                    "progress": String(format: "%.2f", progress),
                    "stage": stage
                ])
            }
        )
        isAcceptingInput = true
    }

    func stopAcceptingInput() {
        isAcceptingInput = false
    }

    func process(samples: [Float], sampleRate: Double) throws -> [SpeakerDiarizationSegment] {
        guard isAcceptingInput, let session else {
            return []
        }
        let prepared = prepare(samples: samples, sampleRate: sampleRate)
        guard !prepared.isEmpty else {
            return []
        }
        let result = try session.push(audio: prepared)
        return Self.map(result.segments)
    }

    func finalize() throws -> [SpeakerDiarizationSegment] {
        isAcceptingInput = false
        guard let session else {
            return []
        }
        let result = try session.finish()
        self.session = nil
        return Self.map(result.segments)
    }

    private func prepare(samples: [Float], sampleRate: Double) -> [Float] {
        let inputRate = Int(sampleRate.rounded())
        guard inputRate > 0 else {
            return samples
        }
        return AudioFileLoader.resample(samples, from: inputRate, to: targetSampleRate)
    }

    private static func map(_ segments: [DiarizedSegment]) -> [SpeakerDiarizationSegment] {
        segments.map { segment in
            let speakerNumber = segment.speakerId + 1
            return SpeakerDiarizationSegment(
                speakerID: "Speaker \(speakerNumber)",
                startTime: TimeInterval(segment.startTime),
                endTime: TimeInterval(segment.endTime),
                confidence: nil
            )
        }
    }
}
