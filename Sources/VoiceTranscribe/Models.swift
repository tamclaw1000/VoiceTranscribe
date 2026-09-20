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

/// A span of live capture during which transcription was paused. The last span in
/// `TranscriptionCoordinator.pauseSpans` stays open (`endedAt == nil`) while paused.
struct TranscriptionPauseSpan: Identifiable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?

    var duration: TimeInterval? {
        guard let endedAt else {
            return nil
        }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    init(id: UUID = UUID(), startedAt: Date = Date(), endedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

struct TranscriptSegment: Identifiable, Equatable {
    let id: UUID
    var text: String
    var timestamp: Date
    var isFinal: Bool
    var confidence: Float?
    var speakerID: String?
    var speakerName: String?
    var voiceID: String?
    var voiceName: String?
    var voiceConfidence: Float?

    var speakerLabel: String? {
        let name = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        let voiceName = voiceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let voiceName, !voiceName.isEmpty {
            return voiceName
        }
        let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let voiceID, !voiceID.isEmpty {
            return voiceID
        }
        let id = speakerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return id?.isEmpty == false ? id : nil
    }

    var textWithSpeaker: String {
        guard let speakerLabel else {
            return text
        }
        return "[\(speakerLabel)] \(text)"
    }

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        isFinal: Bool,
        confidence: Float? = nil,
        speakerID: String? = nil,
        speakerName: String? = nil,
        voiceID: String? = nil,
        voiceName: String? = nil,
        voiceConfidence: Float? = nil
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isFinal = isFinal
        self.confidence = confidence
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.voiceID = voiceID
        self.voiceName = voiceName
        self.voiceConfidence = voiceConfidence
    }
}

struct SpeakerDiarizationSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    var speakerID: String
    var speakerName: String?
    var voiceID: String?
    var voiceName: String?
    var voiceConfidence: Float?
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float?

    var speakerLabel: String {
        let name = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        let voiceName = voiceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let voiceName, !voiceName.isEmpty {
            return voiceName
        }
        let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let voiceID, !voiceID.isEmpty {
            return voiceID
        }
        return speakerID
    }

    init(
        id: UUID = UUID(),
        speakerID: String,
        speakerName: String? = nil,
        voiceID: String? = nil,
        voiceName: String? = nil,
        voiceConfidence: Float? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float? = nil
    ) {
        self.id = id
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.voiceID = voiceID
        self.voiceName = voiceName
        self.voiceConfidence = voiceConfidence
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

struct SpeakerAnnotation: Equatable {
    var speakerID: String
    var speakerName: String?
    var voiceID: String?
    var voiceName: String?
    var voiceConfidence: Float?
}

/// One observed `Speaker N / Voice M` combination. Session-only, like the rest of
/// voice identity — it exists because diarization slots and voice labels are both
/// per-session and the user edits the pair, not either half on its own.
struct SpeakerCombo: Hashable, Identifiable {
    var speakerID: String
    var voiceID: String?

    var id: String { VoiceIdentityKey.make(speakerID: speakerID, voiceID: voiceID) }

    var observedLabel: String {
        VoiceIdentityKey.observedLabel(speakerID: speakerID, voiceID: voiceID)
    }
}

/// How a combo got its name. A name the user typed stays editable; a name chosen
/// from the list of names already assigned this session locks the type-in field,
/// so a quick pick cannot be silently rewritten by a stray keystroke.
enum SpeakerNameOrigin: String, Equatable {
    case typed
    case picked
}

/// The speaker a combo is shown as, after canonical-name merging. `canonicalID` is
/// shared by every combo folded into the same speaker, which is what lets the pane,
/// the transcript colors, and the export timeline agree on one identity.
struct SpeakerIdentityResolution: Equatable {
    var canonicalID: String
    var displayName: String
    /// Every combo folded into this speaker, in display order. One entry when merging
    /// is off, or when the combo carries no assigned name.
    var combos: [SpeakerCombo]
    /// True only when more than one combo was folded together by name.
    var isMerged: Bool

    /// `Speaker 1 / Voice 2` for a single combo, or every folded label joined.
    var observedLabel: String {
        combos.map(\.observedLabel).joined(separator: " + ")
    }

    /// A combo the user can be asked about — the first folded combo.
    var representative: SpeakerCombo? { combos.first }
}

/// One observed combo as the Voice Identification pane sees it: the combo, the live stats
/// behind it, and the name the user gave it (plus how that name was set).
struct SpeakerComboEntry: Equatable {
    var combo: SpeakerCombo
    var segmentCount: Int = 0
    var totalDuration: TimeInterval = 0
    var name: String = ""
    var origin: SpeakerNameOrigin?

    var assignedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Folds `Speaker N / Voice M` combos into canonical speakers using the display names
/// assigned this session. With merging on, combos sharing a name (compared
/// case- and whitespace-insensitively, so "alice" and " Alice " are one person)
/// become a single speaker; with it off, every combo stays its own speaker. Pure and
/// value-typed so the grouping rules are testable without a running app.
struct CanonicalSpeakerResolver: Equatable {
    var mergeSameNamedSpeakers: Bool = false
    /// Combos to resolve, with stats and names, in the order they should be displayed.
    var entries: [SpeakerComboEntry] = []

    /// Distinct assigned names in combo order — the list offered as quick picks.
    var assignedNames: [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for entry in entries {
            guard let name = entry.assignedName else { continue }
            guard seen.insert(Self.nameKey(name)).inserted else { continue }
            names.append(name)
        }
        return names
    }

    /// Resolutions grouped by canonical speaker, ordered by each speaker's first combo.
    func resolutions() -> [SpeakerIdentityResolution] {
        var order: [String] = []
        var grouped: [String: [SpeakerCombo]] = [:]
        var displayNames: [String: String] = [:]

        for entry in entries {
            let combo = entry.combo
            let name = entry.assignedName
            let canonicalID = makeCanonicalID(for: combo, name: name)
            if grouped[canonicalID] == nil {
                order.append(canonicalID)
            }
            grouped[canonicalID, default: []].append(combo)
            if displayNames[canonicalID] == nil {
                displayNames[canonicalID] = name ?? combo.observedLabel
            }
        }

        return order.map { canonicalID in
            let members = grouped[canonicalID] ?? []
            return SpeakerIdentityResolution(
                canonicalID: canonicalID,
                displayName: displayNames[canonicalID] ?? "",
                combos: members,
                isMerged: members.count > 1
            )
        }
    }

    /// The rows the pane edits: one per canonical speaker, with member stats summed and the
    /// type-in lock derived from how each member's name was set. Naming one row names every
    /// combo behind it, which is what makes a merge editable as a single person.
    func editorItems() -> [SpeakerNameEditorItem] {
        var entriesByComboID: [String: SpeakerComboEntry] = [:]
        for entry in entries {
            entriesByComboID[entry.combo.id] = entry
        }

        return resolutions().map { resolution in
            let members = resolution.combos
            let memberEntries = members.compactMap { entriesByComboID[$0.id] }
            let customName = memberEntries.compactMap(\.assignedName).first ?? ""
            let observedLabel = resolution.observedLabel
            let representative = members.first ?? SpeakerCombo(speakerID: "", voiceID: nil)
            // Identity is the row's first combo, NOT the canonical id: the canonical id is
            // derived from the assigned name, so it changed on every keystroke, which made
            // SwiftUI tear the row down and steal focus from the type-in field mid-word.
            // Locked only when every member was set from the quick-pick list, so a merged row
            // can never lock a combo the user had left open for typing.
            let isNameLocked = !memberEntries.isEmpty
                && memberEntries.allSatisfy { $0.origin == .picked && $0.assignedName != nil }
            return SpeakerNameEditorItem(
                id: representative.id,
                speakerID: representative.speakerID,
                voiceID: representative.voiceID,
                observedLabel: observedLabel,
                displayName: customName.isEmpty ? observedLabel : customName,
                customName: customName,
                segmentCount: memberEntries.reduce(0) { $0 + $1.segmentCount },
                totalDuration: memberEntries.reduce(0) { $0 + $1.totalDuration },
                combos: members,
                isNameLocked: isNameLocked
            )
        }
    }

    /// Merging is what makes two combos with the same name share an identity; without
    /// it each combo keys on its own observed label, exactly as before this feature.
    private func makeCanonicalID(for combo: SpeakerCombo, name: String?) -> String {
        if mergeSameNamedSpeakers, let name {
            return "name:\(Self.nameKey(name))"
        }
        return "combo:\(combo.id)"
    }

    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}

struct SpeakerNameEditorItem: Identifiable, Equatable {
    /// Row identity, used by `ForEach`. This is the row's first combo id, which stays put as
    /// the name is edited — keying it on the name instead would rebuild the row and drop focus
    /// from the type-in field on every keystroke.
    var id: String
    var speakerID: String
    var voiceID: String?
    var observedLabel: String
    var displayName: String
    var customName: String
    var segmentCount: Int = 0
    var totalDuration: TimeInterval = 0
    /// Every combo this row edits — one for a normal row, several when the row is a
    /// merged canonical speaker, so naming the row names all of them at once.
    var combos: [SpeakerCombo] = []
    /// True when the name came from the quick-pick list, which disables the type-in field.
    var isNameLocked: Bool = false

    var hasCustomName: Bool {
        !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Combo ids to edit; falls back to this row's own combo when unset.
    var memberCombos: [SpeakerCombo] {
        combos.isEmpty ? [SpeakerCombo(speakerID: speakerID, voiceID: voiceID)] : combos
    }
}

enum VoiceIdentityKey {
    static func make(speakerID: String, voiceID: String?) -> String {
        if let voice = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !voice.isEmpty {
            return "\(speakerID)|\(voice)"
        }
        return "\(speakerID)|_"
    }

    static func observedLabel(speakerID: String, voiceID: String?) -> String {
        let voice = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let voice, !voice.isEmpty {
            return "\(speakerID) / \(voice)"
        }
        return "\(speakerID) / no voice"
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
