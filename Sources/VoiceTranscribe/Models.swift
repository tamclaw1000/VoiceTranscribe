import AVFoundation
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

// MARK: - File Input Source

/// A virtual input source representing an audio file loaded from disk.
struct FileInputSource: Identifiable, Equatable {
    let id: String  // UUID string
    let name: String  // filename without extension
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channelCount: Int
    let audioFormat: String  // e.g. "WAV", "M4A", "FLAC"

    var subtitle: String {
        "\(audioFormat) — \(channelCount)ch \(Int(sampleRate)) Hz — \(Self.formatDuration(duration))"
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Attempt to create a FileInputSource from a URL by reading the audio file header.
    static func from(url: URL) -> FileInputSource? {
        let ext = url.pathExtension.uppercased()
        let formatName = ext.isEmpty ? "?" : ext

        guard let file = try? AVAudioFile(forReading: url) else {
            // Fallback: try AVAsset for compressed formats
            return fromAsset(url: url, formatName: formatName)
        }

        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate

        return FileInputSource(
            id: UUID().uuidString,
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            duration: duration,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            audioFormat: formatName
        )
    }

    private static func fromAsset(url: URL, formatName: String) -> FileInputSource? {
        let asset = AVURLAsset(url: url)
        let cmDuration = asset.duration
        let duration = CMTimeGetSeconds(cmDuration)
        guard duration > 0, duration.isFinite else { return nil }

        var sampleRate: Double = 0
        var channelCount: Int = 0

        if let track = asset.tracks(withMediaType: .audio).first,
           !track.formatDescriptions.isEmpty {
            let audioDesc = track.formatDescriptions[0] as! CMAudioFormatDescription
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc)?.pointee
            sampleRate = asbd?.mSampleRate ?? 0
            channelCount = Int(asbd?.mChannelsPerFrame ?? 0)
        }

        return FileInputSource(
            id: UUID().uuidString,
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            duration: duration,
            sampleRate: sampleRate > 0 ? sampleRate : 44100,
            channelCount: channelCount > 0 ? channelCount : 2,
            audioFormat: formatName
        )
    }
}
