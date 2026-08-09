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
    case fluidAudio = "fluidAudio"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .fluidAudio:
            return "FluidAudio (Parakeet EOU)"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaultTranscriptionEngine: TranscriptionEngineKind = .fluidAudio

    @AppStorage("outputFolderPath") var outputFolderPath: String = DefaultPaths.voiceTranscribeOutputFolder.path
    @AppStorage("audioOutputFormat") var audioOutputFormatRaw: String = AudioOutputFormat.m4a.rawValue
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw: String = AppSettings.defaultTranscriptionEngine.rawValue
    @AppStorage("migratedDefaultTranscriptionEngineToFluidAudio") private var migratedDefaultTranscriptionEngineToFluidAudio: Bool = false
    @AppStorage("saveTranscriptsAutomatically") var saveTranscriptsAutomatically: Bool = true
    @AppStorage("visualizationSensitivity") var visualizationSensitivity: Double = 1.0
    @AppStorage("factCheckEnabled") var factCheckEnabled: Bool = true
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "igorls/gemma-4-12B-it-heretic-GGUF"
    @AppStorage("ollamaFactCheckPrompt") var ollamaFactCheckPrompt: String = FactCheckPrompt.defaultTemplate

    init() {
        migrateDefaultTranscriptionEngineIfNeeded()
    }

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
        get { TranscriptionEngineKind(rawValue: transcriptionEngineRaw) ?? Self.defaultTranscriptionEngine }
        set { transcriptionEngineRaw = newValue.rawValue }
    }

    var ollamaEndpointURL: URL {
        URL(string: ollamaEndpoint) ?? URL(string: "http://localhost:11434")!
    }

    func resetFactCheckPrompt() {
        ollamaFactCheckPrompt = FactCheckPrompt.defaultTemplate
    }

    private func migrateDefaultTranscriptionEngineIfNeeded() {
        guard !migratedDefaultTranscriptionEngineToFluidAudio else {
            return
        }

        if transcriptionEngineRaw == TranscriptionEngineKind.appleSpeech.rawValue {
            transcriptionEngineRaw = Self.defaultTranscriptionEngine.rawValue
            Trace.event("settings.transcriptionEngineMigrated", [
                "from": TranscriptionEngineKind.appleSpeech.rawValue,
                "to": Self.defaultTranscriptionEngine.rawValue
            ])
        }
        migratedDefaultTranscriptionEngineToFluidAudio = true
    }
}

enum DefaultPaths {
    static var voiceTranscribeOutputFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceTranscribe", isDirectory: true)
    }
}
