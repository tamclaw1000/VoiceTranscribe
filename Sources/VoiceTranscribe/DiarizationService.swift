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
    private var sessionID = UUID()
    private var lastSpeaker: SpeakerDiarizationSegment?
    private var tracedSegmentKeys = Set<String>()

    var currentSpeakerLabel: String? {
        lastSpeaker?.speakerLabel
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
        isStarting = false
        isRunning = false
        lastError = nil
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
            return
        }

        let sampleRate = buffer.format.sampleRate
        let samples = Self.monoFloatSamples(from: buffer)
        let sessionID = self.sessionID
        guard !samples.isEmpty else {
            return
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

    func annotationForCurrentSpeaker() -> (id: String, name: String?)? {
        guard let lastSpeaker else {
            return nil
        }
        return (lastSpeaker.speakerID, lastSpeaker.speakerName)
    }

    private func replaceSegments(_ newSegments: [SpeakerDiarizationSegment]) {
        segments = newSegments.sorted { $0.startTime < $1.startTime }
        lastSpeaker = segments.max { $0.endTime < $1.endTime }

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
    }

    func process(samples: [Float], sampleRate: Double) throws -> [SpeakerDiarizationSegment] {
        guard let session else {
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
        guard let session else {
            return []
        }
        let result = try session.finish()
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
