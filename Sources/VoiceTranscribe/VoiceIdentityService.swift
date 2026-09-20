import Foundation
import AudioCommon
import SpeechVAD

struct VoiceIdentityMatch: Equatable, Sendable {
    var voiceID: String
    var voiceName: String
    var confidence: Float?
}

struct VoiceIdentityProfile: Equatable, Sendable {
    var id: String
    var name: String
    var centroid: [Float]
    var sampleCount: Int
    var totalDuration: TimeInterval
}

struct VoiceIdentityMatcher: Sendable {
    var matchThreshold: Float = 0.70
    var updateThreshold: Float = 0.82

    private(set) var profiles: [VoiceIdentityProfile] = []
    private var nextVoiceNumber = 1

    init(matchThreshold: Float = 0.70, updateThreshold: Float = 0.82) {
        self.matchThreshold = matchThreshold
        self.updateThreshold = updateThreshold
    }

    mutating func reset() {
        profiles = []
        nextVoiceNumber = 1
    }

    mutating func identify(embedding: [Float], duration: TimeInterval) -> VoiceIdentityMatch {
        let normalized = Self.normalized(embedding)
        let best = bestProfile(for: normalized)

        if let best, best.similarity >= matchThreshold {
            updateProfile(at: best.index, with: normalized, similarity: best.similarity, duration: duration)
            let profile = profiles[best.index]
            return VoiceIdentityMatch(
                voiceID: profile.id,
                voiceName: profile.name,
                confidence: best.similarity
            )
        }

        let id = "Voice \(nextVoiceNumber)"
        nextVoiceNumber += 1
        let profile = VoiceIdentityProfile(
            id: id,
            name: id,
            centroid: normalized,
            sampleCount: 1,
            totalDuration: duration
        )
        profiles.append(profile)
        return VoiceIdentityMatch(voiceID: id, voiceName: id, confidence: nil)
    }

    private func bestProfile(for embedding: [Float]) -> (index: Int, similarity: Float)? {
        var best: (index: Int, similarity: Float)?
        for index in profiles.indices {
            let similarity = Self.cosineSimilarity(embedding, profiles[index].centroid)
            if best == nil || similarity > best!.similarity {
                best = (index, similarity)
            }
        }
        return best
    }

    private mutating func updateProfile(
        at index: Int,
        with embedding: [Float],
        similarity: Float,
        duration: TimeInterval
    ) {
        guard similarity >= updateThreshold else {
            return
        }

        var profile = profiles[index]
        let oldWeight = Float(max(profile.sampleCount, 1))
        let newWeight: Float = 1
        let totalWeight = oldWeight + newWeight
        let merged = zip(profile.centroid, embedding).map { old, new in
            (old * oldWeight + new * newWeight) / totalWeight
        }
        profile.centroid = Self.normalized(merged)
        profile.sampleCount += 1
        profile.totalDuration += duration
        profiles[index] = profile
    }

    static func normalized(_ values: [Float]) -> [Float] {
        let norm = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0, norm.isFinite else {
            return values
        }
        return values.map { $0 / norm }
    }

    static func cosineSimilarity(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count, !left.isEmpty else {
            return 0
        }
        var dot: Float = 0
        var normLeft: Float = 0
        var normRight: Float = 0
        for index in left.indices {
            dot += left[index] * right[index]
            normLeft += left[index] * left[index]
            normRight += right[index] * right[index]
        }
        let denominator = sqrt(normLeft) * sqrt(normRight)
        return denominator > 0 ? dot / denominator : 0
    }
}

actor VoiceIdentityService {
    private let targetSampleRate = 16_000
    private let minimumDuration: TimeInterval = 2.0
    private var model: WeSpeakerModel?
    private var matcher = VoiceIdentityMatcher()

    func reset() {
        matcher.reset()
    }

    func identify(samples: [Float], sampleRate: Int, duration: TimeInterval) async throws -> VoiceIdentityMatch? {
        guard duration >= minimumDuration else {
            Trace.event("voiceIdentity.identify.skipped", [
                "reason": "tooShort",
                "duration": String(format: "%.2f", duration),
                "samples": samples.count,
                "sampleRate": sampleRate
            ])
            return nil
        }
        let prepared = sampleRate == targetSampleRate
            ? samples
            : AudioFileLoader.resample(samples, from: sampleRate, to: targetSampleRate)
        guard !prepared.isEmpty else {
            Trace.event("voiceIdentity.identify.skipped", [
                "reason": "emptyAudio",
                "duration": String(format: "%.2f", duration),
                "samples": samples.count,
                "sampleRate": sampleRate
            ])
            return nil
        }

        let model = try await loadModel()
        let embedding = model.embed(audio: prepared, sampleRate: targetSampleRate)
        guard embedding.contains(where: { $0 != 0 && $0.isFinite }) else {
            Trace.event("voiceIdentity.identify.skipped", [
                "reason": "emptyEmbedding",
                "duration": String(format: "%.2f", duration),
                "samples": prepared.count,
                "sampleRate": targetSampleRate,
                "embeddingDimensions": embedding.count
            ])
            return nil
        }
        Trace.event("voiceIdentity.embedding.created", [
            "duration": String(format: "%.2f", duration),
            "samples": prepared.count,
            "sampleRate": targetSampleRate,
            "embeddingDimensions": embedding.count
        ])
        return matcher.identify(embedding: embedding, duration: duration)
    }

    private func loadModel() async throws -> WeSpeakerModel {
        if let model {
            return model
        }
        Trace.event("voiceIdentity.model.loading", ["engine": "WeSpeaker CoreML"])
        let loaded = try await WeSpeakerModel.fromPretrained(
            engine: .coreml,
            progressHandler: { progress, stage in
                Trace.event("voiceIdentity.model.progress", [
                    "progress": String(format: "%.2f", progress),
                    "stage": stage
                ])
            }
        )
        model = loaded
        Trace.event("voiceIdentity.model.ready", ["engine": "WeSpeaker CoreML"])
        return loaded
    }
}
