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
            copy.endpoint = normalizedStoredString(copy.endpoint)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            copy.model = normalizedStoredString(copy.model)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func normalizedStoredString(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\\+/"#,
            with: "/",
            options: .regularExpression
        )
    }
}

struct AIPromptTemplateConfiguration: Identifiable, Codable, Equatable {
    static let defaultID = "default-fact-check"
    static let defaultName = "AI Processing"

    var id: String
    var name: String
    var llmEndpointID: String
    var template: String
    var isEnabled: Bool

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultName : trimmed
    }

    init(
        id: String,
        name: String,
        llmEndpointID: String,
        template: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.llmEndpointID = llmEndpointID
        self.template = template
        self.isEnabled = isEnabled
    }

    static func defaultConfiguration(
        llmEndpointID: String = LLMEndpointConfiguration.defaultID,
        template: String = FactCheckPrompt.defaultTemplate,
        isEnabled: Bool = true
    ) -> AIPromptTemplateConfiguration {
        AIPromptTemplateConfiguration(
            id: defaultID,
            name: defaultName,
            llmEndpointID: llmEndpointID,
            template: template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FactCheckPrompt.defaultTemplate : template,
            isEnabled: isEnabled
        )
    }

    static func sanitized(
        _ promptTemplates: [AIPromptTemplateConfiguration],
        availableLLMEndpointIDs: Set<String>,
        fallbackLLMEndpointID: String
    ) -> [AIPromptTemplateConfiguration] {
        var seenIDs = Set<String>()
        let sanitized = promptTemplates.enumerated().map { index, prompt -> AIPromptTemplateConfiguration in
            var copy = prompt
            copy.id = copy.id.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.llmEndpointID = copy.llmEndpointID.trimmingCharacters(in: .whitespacesAndNewlines)

            if copy.id.isEmpty || seenIDs.contains(copy.id) {
                copy.id = UUID().uuidString
            }
            seenIDs.insert(copy.id)

            if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.name = "AI Prompt \(index + 1)"
            }
            if copy.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copy.template = FactCheckPrompt.defaultTemplate
            }
            if !availableLLMEndpointIDs.isEmpty,
               !availableLLMEndpointIDs.contains(copy.llmEndpointID) {
                copy.llmEndpointID = fallbackLLMEndpointID
            }
            return copy
        }

        return sanitized.isEmpty ? [
            defaultConfiguration(llmEndpointID: fallbackLLMEndpointID)
        ] : sanitized
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaultTranscriptionEngine: TranscriptionEngineKind = .appleSpeech

    @AppStorage("outputFolderPath") var outputFolderPath: String = DefaultPaths.voiceTranscribeOutputFolder.path
    @AppStorage("audioOutputFormat") var audioOutputFormatRaw: String = AudioOutputFormat.m4a.rawValue
    @AppStorage("transcriptionEngine") var transcriptionEngineRaw: String = AppSettings.defaultTranscriptionEngine.rawValue
    @AppStorage("migratedDefaultTranscriptionEngineToFluidAudio") private var migratedDefaultTranscriptionEngineToFluidAudio: Bool = false
    @AppStorage("migratedTranscriptionPipelineToAppleSpeech") private var migratedTranscriptionPipelineToAppleSpeech: Bool = false
    @AppStorage("saveTranscriptsAutomatically") var saveTranscriptsAutomatically: Bool = true
    @AppStorage("autoScrollTranscript") var autoScrollTranscript: Bool = true
    @AppStorage("visualizationSensitivity") var visualizationSensitivity: Double = 1.0
    @AppStorage("aiEnabled") var aiEnabled: Bool = true
    @AppStorage("factCheckEnabled") var factCheckEnabled: Bool = true
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "igorls/gemma-4-12B-it-heretic-GGUF"
    @AppStorage("llmEndpointsJSON") private var llmEndpointsJSON: String = ""
    @AppStorage("selectedLLMEndpointID") var selectedLLMEndpointID: String = LLMEndpointConfiguration.defaultID
    @AppStorage("useGlobalPromptLLM") var useGlobalPromptLLM: Bool = false
    @AppStorage("globalPromptLLMEndpointID") var globalPromptLLMEndpointID: String = LLMEndpointConfiguration.defaultID
    @AppStorage("aiPromptTemplatesJSON") private var aiPromptTemplatesJSON: String = ""
    @AppStorage("ollamaFactCheckPrompt") var ollamaFactCheckPrompt: String = FactCheckPrompt.defaultTemplate
    @AppStorage("summaryPrompt") var summaryPrompt: String = SummaryPrompt.defaultTemplate

    init() {
        migrateLLMEndpointsIfNeeded()
        migratePromptTemplatesIfNeeded()
        migrateDefaultTranscriptionEngineIfNeeded()
        migrateTranscriptionPipelineToAppleSpeechIfNeeded()
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
        get { Self.defaultTranscriptionEngine }
        set { transcriptionEngineRaw = Self.defaultTranscriptionEngine.rawValue }
    }

    var ollamaEndpointURL: URL {
        URL(string: ollamaEndpoint) ?? URL(string: "http://localhost:11434")!
    }

    var isFactCheckActive: Bool {
        !enabledAIPromptTemplates.isEmpty
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
            if !sanitized.contains(where: { $0.id == globalPromptLLMEndpointID }) {
                globalPromptLLMEndpointID = selectedLLMEndpointID
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

    var globalPromptLLMEndpoint: LLMEndpointConfiguration {
        llmEndpoints.first { $0.id == globalPromptLLMEndpointID } ?? selectedLLMEndpoint
    }

    func llmEndpoint(id: String) -> LLMEndpointConfiguration? {
        llmEndpoints.first { $0.id == id }
    }

    func effectiveLLMEndpoint(for promptTemplate: AIPromptTemplateConfiguration) -> LLMEndpointConfiguration {
        if useGlobalPromptLLM {
            return globalPromptLLMEndpoint
        }
        return llmEndpoint(id: promptTemplate.llmEndpointID) ?? selectedLLMEndpoint
    }

    var aiPromptTemplates: [AIPromptTemplateConfiguration] {
        get {
            let endpoints = llmEndpoints
            let ids = Set(endpoints.map(\.id))
            guard let data = aiPromptTemplatesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([AIPromptTemplateConfiguration].self, from: data) else {
                return [
                    AIPromptTemplateConfiguration.defaultConfiguration(
                        llmEndpointID: selectedLLMEndpointID,
                        template: ollamaFactCheckPrompt,
                        isEnabled: aiEnabled && factCheckEnabled
                    )
                ]
            }
            return AIPromptTemplateConfiguration.sanitized(
                decoded,
                availableLLMEndpointIDs: ids,
                fallbackLLMEndpointID: selectedLLMEndpointID
            )
        }
        set {
            let endpoints = llmEndpoints
            let sanitized = AIPromptTemplateConfiguration.sanitized(
                newValue,
                availableLLMEndpointIDs: Set(endpoints.map(\.id)),
                fallbackLLMEndpointID: selectedLLMEndpointID
            )
            if let encoded = try? JSONEncoder().encode(sanitized),
               let json = String(data: encoded, encoding: .utf8) {
                aiPromptTemplatesJSON = json
            }
        }
    }

    var enabledAIPromptTemplates: [AIPromptTemplateConfiguration] {
        aiPromptTemplates.filter(\.isEnabled)
    }

    var effectiveAIPromptTemplates: [AIPromptTemplateConfiguration] {
        guard useGlobalPromptLLM else {
            return aiPromptTemplates
        }
        return aiPromptTemplates.map { promptTemplate in
            var copy = promptTemplate
            copy.llmEndpointID = globalPromptLLMEndpointID
            return copy
        }
    }

    var effectiveEnabledAIPromptTemplates: [AIPromptTemplateConfiguration] {
        effectiveAIPromptTemplates.filter(\.isEnabled)
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
        aiPromptTemplates = aiPromptTemplates
    }

    func resetFactCheckPrompt() {
        ollamaFactCheckPrompt = FactCheckPrompt.defaultTemplate
    }

    func updateAIPromptTemplate(_ promptTemplate: AIPromptTemplateConfiguration) {
        var promptTemplates = aiPromptTemplates
        if let index = promptTemplates.firstIndex(where: { $0.id == promptTemplate.id }) {
            promptTemplates[index] = promptTemplate
            aiPromptTemplates = promptTemplates
        }
    }

    func addAIPromptTemplate() {
        var promptTemplates = aiPromptTemplates
        let nextNumber = promptTemplates.count + 1
        let promptTemplate = AIPromptTemplateConfiguration(
            id: UUID().uuidString,
            name: "AI Prompt \(nextNumber)",
            llmEndpointID: selectedLLMEndpointID,
            template: FactCheckPrompt.defaultTemplate,
            isEnabled: true
        )
        promptTemplates.append(promptTemplate)
        aiPromptTemplates = promptTemplates
    }

    func removeAIPromptTemplate(id: String) {
        var promptTemplates = aiPromptTemplates
        guard promptTemplates.count > 1 else {
            return
        }
        promptTemplates.removeAll { $0.id == id }
        aiPromptTemplates = promptTemplates
    }

    func resetAIPromptTemplate(id: String) {
        guard var promptTemplate = aiPromptTemplates.first(where: { $0.id == id }) else {
            return
        }
        promptTemplate.template = FactCheckPrompt.defaultTemplate
        updateAIPromptTemplate(promptTemplate)
    }

    func resetSummaryPrompt() {
        summaryPrompt = SummaryPrompt.defaultTemplate
    }

    private func migrateDefaultTranscriptionEngineIfNeeded() {
        guard !migratedDefaultTranscriptionEngineToFluidAudio else {
            return
        }
        migratedDefaultTranscriptionEngineToFluidAudio = true
    }

    private func migrateTranscriptionPipelineToAppleSpeechIfNeeded() {
        guard !migratedTranscriptionPipelineToAppleSpeech else {
            return
        }

        if transcriptionEngineRaw != TranscriptionEngineKind.appleSpeech.rawValue {
            Trace.event("settings.transcriptionEngineMigrated", [
                "from": transcriptionEngineRaw,
                "to": TranscriptionEngineKind.appleSpeech.rawValue,
                "reason": "appleSpeechTranscriptFluidDiarizationPipeline"
            ])
        }
        transcriptionEngineRaw = TranscriptionEngineKind.appleSpeech.rawValue
        migratedTranscriptionPipelineToAppleSpeech = true
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

    private func migratePromptTemplatesIfNeeded() {
        guard aiPromptTemplatesJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        aiPromptTemplates = [
            AIPromptTemplateConfiguration.defaultConfiguration(
                llmEndpointID: selectedLLMEndpointID,
                template: ollamaFactCheckPrompt,
                isEnabled: aiEnabled && factCheckEnabled
            )
        ]
    }
}

enum DefaultPaths {
    static var voiceTranscribeOutputFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceTranscribe", isDirectory: true)
    }
}
