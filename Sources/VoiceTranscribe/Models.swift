import AudioToolbox
import Foundation

struct SoundInputSource: Identifiable, Equatable {
    let id: String
    let audioDeviceID: AudioDeviceID
    let name: String
    let manufacturer: String?
    let channelCount: Int
    let sampleRate: Double?
    let transportType: String?
    let isDefaultInput: Bool
    let isAvailable: Bool

    var subtitle: String {
        var parts: [String] = []
        if let manufacturer, !manufacturer.isEmpty {
            parts.append(manufacturer)
        }
        if let transportType, !transportType.isEmpty {
            parts.append(transportType)
        }
        parts.append("\(channelCount) ch")
        if let sampleRate {
            parts.append("\(Int(sampleRate)) Hz")
        }
        return parts.joined(separator: " - ")
    }
}



enum CaptureStatus: Equatable {
    case idle
    case starting
    case active(sourceID: String)
    case failed(String)

    var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }
}

struct TranscriptSegment: Identifiable, Equatable {
    let id: UUID
    var text: String
    var timestamp: Date
    var isFinal: Bool
    var confidence: Float?

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        isFinal: Bool,
        confidence: Float? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

struct RecordingSession: Identifiable, Equatable {
    let id: UUID
    let source: SoundInputSource
    let startDate: Date
    var endDate: Date?
    let basename: String
    let audioURL: URL
    let transcriptURL: URL
    let metadataURL: URL

    var duration: TimeInterval {
        (endDate ?? Date()).timeIntervalSince(startDate)
    }
}

struct RecordingMetadata: Codable, Equatable {
    let sourceID: String
    let sourceName: String
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let audioFormat: String
    let transcriptionEngine: String
}

struct VisualizationSnapshot: Equatable {
    var rmsLevel: Float = 0
    var peakLevel: Float = 0
    var isClipping: Bool = false
    var history: [Float] = []
}

struct TranscriptionBufferSnapshot: Equatable {
    var queuedDuration: TimeInterval = 0
    var maxDuration: TimeInterval = 10
    var isReceivingAudio: Bool = false
    var lastAudioAt: Date?
    var lastResultAt: Date?

    var fillFraction: Double {
        guard maxDuration > 0 else {
            return 0
        }
        return min(max(queuedDuration / maxDuration, 0), 1)
    }
}
