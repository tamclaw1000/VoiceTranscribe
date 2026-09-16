import AVFoundation
import FluidAudio
import Foundation

@MainActor
final class DiarizationCoordinator: ObservableObject {
    @Published private(set) var segments: [SpeakerDiarizationSegment] = []
    @Published private(set) var isStarting = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var engine: FluidAudioDiarizationEngine?
    private var sessionID = UUID()
    private var lastSpeaker: SpeakerDiarizationSegment?
    private var processedSegmentKeys = Set<String>()

    var currentSpeakerLabel: String? {
        lastSpeaker?.speakerLabel
    }

    func start() async throws {
        reset()
        isStarting = true
        Trace.event("diarization.starting")
        do {
            let engine = FluidAudioDiarizationEngine()
            try await engine.start()
            self.engine = engine
            isStarting = false
            isRunning = true
            lastError = nil
            Trace.event("diarization.started")
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
        processedSegmentKeys = []
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
                    self?.merge(finalized)
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
                    self?.merge(updates)
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

    private func merge(_ newSegments: [SpeakerDiarizationSegment]) {
        for segment in newSegments {
            let key = "\(segment.speakerID)|\(String(format: "%.2f", segment.startTime))|\(String(format: "%.2f", segment.endTime))"
            guard !processedSegmentKeys.contains(key) else {
                continue
            }
            processedSegmentKeys.insert(key)
            segments.append(segment)
            lastSpeaker = segment
            Trace.event("diarization.segment", [
                "speaker": segment.speakerLabel,
                "start": String(format: "%.2f", segment.startTime),
                "end": String(format: "%.2f", segment.endTime)
            ])
        }
        segments.sort { $0.startTime < $1.startTime }
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

private actor FluidAudioDiarizationEngine {
    private var diarizer: LSEENDDiarizer?

    func start() async throws {
        diarizer = try await LSEENDDiarizer(variant: .dihard3)
    }

    func process(samples: [Float], sampleRate: Double) throws -> [SpeakerDiarizationSegment] {
        guard let diarizer else {
            return []
        }
        let update = try diarizer.process(samples: samples, sourceSampleRate: sampleRate)
        return Self.map(update?.finalizedSegments ?? [])
    }

    func finalize() throws -> [SpeakerDiarizationSegment] {
        guard let diarizer else {
            return []
        }
        let update = try diarizer.finalizeSession()
        return Self.map(update?.finalizedSegments ?? [])
    }

    private static func map(_ segments: [DiarizerSegment]) -> [SpeakerDiarizationSegment] {
        segments.map { segment in
            let speakerNumber = segment.speakerIndex + 1
            return SpeakerDiarizationSegment(
                speakerID: "Speaker \(speakerNumber)",
                startTime: TimeInterval(segment.startTime),
                endTime: TimeInterval(segment.endTime),
                confidence: segment.activity
            )
        }
    }
}
