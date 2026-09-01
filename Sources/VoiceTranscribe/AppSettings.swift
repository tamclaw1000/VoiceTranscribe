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

enum LLMProviderKind: String, CaseIterable, Identifiable, Codable {
    case ollama
    case openAICompatible
    case openRouter
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .openAICompatible:
            return "OpenAI Compatible"
        case .openRouter:
            return "OpenRouter"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama:
            return "http://localhost:11434"
        case .openAICompatible:
            return "https://api.openai.com"
        case .openRouter:
            return "https://openrouter.ai/api"
        case .anthropic:
            return "https://api.anthropic.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        }
    }
}

struct LLMEndpointConfiguration: Identifiable, Codable, Equatable {
    static let defaultID = "local-ollama"
    static let defaultName = "Local Ollama"
    static let defaultEndpoint = "http://localhost:11434"
    static let defaultModel = "igorls/gemma-4-12B-it-heretic-GGUF"

    var id: String
    var name: String
    var provider: LLMProviderKind
    var endpoint: String
    var model: String
    var apiKey: String

    var endpointURL: URL {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? URL(string: Self.defaultEndpoint)!
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? model : trimmed
    }

    init(
        id: String,
        name: String,
        provider: LLMProviderKind = .ollama,
        endpoint: String,
        model: String,
        apiKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case endpoint
        case model
        case apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        if let rawProvider = try container.decodeIfPresent(String.self, forKey: .provider),
           let decodedProvider = LLMProviderKind(rawValue: rawProvider) {
            provider = decodedProvider
        } else {
            provider = Self.inferredProvider(for: endpoint)
        }
        model = try container.decode(String.self, forKey: .model)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }

    private static func inferredProvider(for endpoint: String) -> LLMProviderKind {
        guard let host = URLComponents(string: endpoint)?.host?.lowercased() else {
            return .ollama
        }
        if host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") {
            return .openRouter
        }
        return host == "localhost" || host == "127.0.0.1" ? .ollama : .openAICompatible
    }

    static func defaultConfiguration(
        endpoint: String = defaultEndpoint,
        model: String = defaultModel
    ) -> LLMEndpointConfiguration {
        LLMEndpointConfiguration(
            id: defaultID,
            name: defaultName,
            provider: .ollama,
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultEndpoint : endpoint,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultModel : model,
            apiKey: ""
        )
    }

    static func sanitized(_ endpoints: [LLMEndpointConfiguration]) -> [LLMEndpointConfiguration] {
        var seenIDs = Set<String>()
        let sanitized = endpoints.enumerated().compactMap { index, endpoint -> LLMEndpointConfiguration? in
            var copy = endpoint
            copy.id = copy.id.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.endpoint = copy.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.model = copy.model.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.apiKey = copy.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            if copy.id.isEmpty || seenIDs.contains(copy.id) {
                copy.id = UUID().uuidString
            }
            seenIDs.insert(copy.id)

            if copy.name.isEmpty {
                copy.name = "LLM \(index + 1)"
            }
            if copy.endpoint.isEmpty {
                copy.endpoint = copy.provider.defaultEndpoint
            }
            if copy.model.isEmpty {
                copy.model = defaultModel
            }
            copy.repairKnownProviderMismatch()
            return copy
        }

        return sanitized.isEmpty ? [defaultConfiguration()] : sanitized
    }

    private mutating func repairKnownProviderMismatch() {
        let lowerName = name.lowercased()
        let lowerModel = model.lowercased()
        let host = URLComponents(string: endpoint)?.host?.lowercased() ?? ""
        let isOpenRouterProfile = provider == .openRouter
            || host == "openrouter.ai"
            || host.hasSuffix(".openrouter.ai")
            || lowerName.contains("openrouter")
            || lowerModel.hasPrefix("openrouter/")
            || lowerModel.contains(":free")

        guard isOpenRouterProfile else {
            return
        }

        provider = .openRouter
        if host.isEmpty || host == "opencode.ai" || host == "api.openai.com" || host == "localhost" || host == "127.0.0.1" {
            endpoint = LLMProviderKind.openRouter.defaultEndpoint
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
    @AppStorage("aiEnabled") var aiEnabled: Bool = true
    @AppStorage("factCheckEnabled") var factCheckEnabled: Bool = true
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "igorls/gemma-4-12B-it-heretic-GGUF"
    @AppStorage("llmEndpointsJSON") private var llmEndpointsJSON: String = ""
    @AppStorage("selectedLLMEndpointID") var selectedLLMEndpointID: String = LLMEndpointConfiguration.defaultID
    @AppStorage("ollamaFactCheckPrompt") var ollamaFactCheckPrompt: String = FactCheckPrompt.defaultTemplate
    @AppStorage("summaryPrompt") var summaryPrompt: String = SummaryPrompt.defaultTemplate

    init() {
        migrateLLMEndpointsIfNeeded()
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

    var isFactCheckActive: Bool {
        aiEnabled && factCheckEnabled
    }

    var llmEndpoints: [LLMEndpointConfiguration] {
        get {
            guard let data = llmEndpointsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([LLMEndpointConfiguration].self, from: data) else {
                return [LLMEndpointConfiguration.defaultConfiguration(endpoint: ollamaEndpoint, model: ollamaModel)]
            }
            return LLMEndpointConfiguration.sanitized(decoded)
        }
        set {
            let sanitized = LLMEndpointConfiguration.sanitized(newValue)
            if !sanitized.contains(where: { $0.id == selectedLLMEndpointID }) {
                selectedLLMEndpointID = sanitized[0].id
            }
            if let encoded = try? JSONEncoder().encode(sanitized),
               let json = String(data: encoded, encoding: .utf8) {
                llmEndpointsJSON = json
            }
        }
    }

    var selectedLLMEndpoint: LLMEndpointConfiguration {
        llmEndpoints.first { $0.id == selectedLLMEndpointID } ?? llmEndpoints[0]
    }

    func llmEndpoint(id: String) -> LLMEndpointConfiguration? {
        llmEndpoints.first { $0.id == id }
    }

    func updateLLMEndpoint(_ endpoint: LLMEndpointConfiguration) {
        var endpoints = llmEndpoints
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = endpoint
            llmEndpoints = endpoints
        }
    }

    func addLLMEndpoint() {
        var endpoints = llmEndpoints
        let nextNumber = endpoints.count + 1
        let endpoint = LLMEndpointConfiguration(
            id: UUID().uuidString,
            name: "LLM \(nextNumber)",
            provider: .ollama,
            endpoint: LLMEndpointConfiguration.defaultEndpoint,
            model: LLMEndpointConfiguration.defaultModel,
            apiKey: ""
        )
        endpoints.append(endpoint)
        llmEndpoints = endpoints
        selectedLLMEndpointID = endpoint.id
    }

    func removeLLMEndpoint(id: String) {
        var endpoints = llmEndpoints
        guard endpoints.count > 1 else {
            return
        }
        endpoints.removeAll { $0.id == id }
        llmEndpoints = endpoints
    }

    func resetFactCheckPrompt() {
        ollamaFactCheckPrompt = FactCheckPrompt.defaultTemplate
    }

    func resetSummaryPrompt() {
        summaryPrompt = SummaryPrompt.defaultTemplate
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

    private func migrateLLMEndpointsIfNeeded() {
        guard llmEndpointsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        llmEndpoints = [
            LLMEndpointConfiguration.defaultConfiguration(endpoint: ollamaEndpoint, model: ollamaModel)
        ]
        selectedLLMEndpointID = LLMEndpointConfiguration.defaultID
    }
}

enum DefaultPaths {
    static var voiceTranscribeOutputFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceTranscribe", isDirectory: true)
    }
}
