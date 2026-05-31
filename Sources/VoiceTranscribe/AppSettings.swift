import Foundation
import SwiftUI

enum AudioOutputFormat: String, CaseIterable, Identifiable {
    case m4a = "m4a"
    case caf = "caf"
    case wav = "wav"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a:
            return "M4A"
        case .caf:
            return "CAF"
        case .wav:
            return "WAV"
        }
    }
}

enum TranscriptionEngineKind: String, CaseIterable, Identifiable {
    case appleSpeech = "appleSpeech"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("outputFolderPath") var outputFolderPath: String = DefaultPaths.voiceTranscribeOutputFolder.path
    @AppStorage("audioOutputFormat") var audioOutputFormatRaw: String = AudioOutputFormat.m4a.rawValue
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw: String = TranscriptionEngineKind.appleSpeech.rawValue
    @AppStorage("saveTranscriptsAutomatically") var saveTranscriptsAutomatically: Bool = true
    @AppStorage("startTranscriptionWithRecording") var startTranscriptionWithRecording: Bool = true
    @AppStorage("visualizationSensitivity") var visualizationSensitivity: Double = 1.0

    static var defaultOutputFolder: URL {
        DefaultPaths.voiceTranscribeOutputFolder
    }

    var outputFolder: URL {
        URL(fileURLWithPath: outputFolderPath, isDirectory: true)
    }

    var audioOutputFormat: AudioOutputFormat {
        get { AudioOutputFormat(rawValue: audioOutputFormatRaw) ?? .m4a }
        set { audioOutputFormatRaw = newValue.rawValue }
    }

    var transcriptionEngine: TranscriptionEngineKind {
        get { TranscriptionEngineKind(rawValue: transcriptionEngineRaw) ?? .appleSpeech }
        set { transcriptionEngineRaw = newValue.rawValue }
    }
}

enum DefaultPaths {
    static var voiceTranscribeOutputFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceTranscribe", isDirectory: true)
    }
}
