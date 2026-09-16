import Foundation

enum FactCheckVerdict: String, Codable, CaseIterable {
    case supported
    case questionable
    case falseClaim = "false"
    case unverifiable
    case notFactual = "not_factual"

    var displayName: String {
        switch self {
        case .supported:
            return "Supported"
        case .questionable:
            return "Questionable"
        case .falseClaim:
            return "False"
        case .unverifiable:
            return "Unverifiable"
        case .notFactual:
            return "Not factual"
        }
    }
}

enum FactCheckConfidence: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

enum FactCheckState: Equatable {
    case queued
    case checking
    case completed(FactCheckResult)
    case failed(String)
}

struct FactCheckItem: Identifiable, Equatable {
    let id: UUID
    let sentence: String
    let llm: LLMEndpointConfiguration
    let promptTemplateID: String
    let promptTemplateName: String
    let promptTemplate: String
    let promptContext: FactCheckPromptContext
    let batchGroupID: String?
    var state: FactCheckState
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplateID: String = AIPromptTemplateConfiguration.defaultID,
        promptTemplateName: String = AIPromptTemplateConfiguration.defaultName,
        promptTemplate: String,
        promptContext: FactCheckPromptContext = .empty,
        batchGroupID: String? = nil,
        state: FactCheckState = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sentence = sentence
        self.llm = llm
        self.promptTemplateID = promptTemplateID
        self.promptTemplateName = promptTemplateName
        self.promptTemplate = promptTemplate
        self.promptContext = promptContext
        self.batchGroupID = batchGroupID
        self.state = state
        self.createdAt = createdAt
    }

    func withPromptState(_ promptState: String) -> FactCheckItem {
        FactCheckItem(
            id: id,
            sentence: sentence,
            llm: llm,
            promptTemplateID: promptTemplateID,
            promptTemplateName: promptTemplateName,
            promptTemplate: promptTemplate,
            promptContext: promptContext.withPromptState(promptState),
            batchGroupID: batchGroupID,
            state: state,
            createdAt: createdAt
        )
    }
}

struct FactCheckResult: Codable, Equatable {
    let sentence: String
    let verdict: FactCheckVerdict
    let confidence: FactCheckConfidence
    let explanation: String
    let notes: [String]
    let rawResponse: String?

    init(
        sentence: String,
        verdict: FactCheckVerdict,
        confidence: FactCheckConfidence,
        explanation: String,
        notes: [String] = [],
        rawResponse: String? = nil
    ) {
        self.sentence = sentence
        self.verdict = verdict
        self.confidence = confidence
        self.explanation = explanation
        self.notes = notes
        self.rawResponse = rawResponse
    }

    private enum CodingKeys: String, CodingKey {
        case sentence
        case verdict
        case confidence
        case explanation
        case notes
        case rawResponse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentence = try container.decode(String.self, forKey: .sentence)
        verdict = try container.decode(FactCheckVerdict.self, forKey: .verdict)
        confidence = try container.decode(FactCheckConfidence.self, forKey: .confidence)
        explanation = try container.decode(String.self, forKey: .explanation)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        rawResponse = try container.decodeIfPresent(String.self, forKey: .rawResponse)
    }

    var displayText: String {
        if let rawResponse, !rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawResponse
        }

        var parts = [
            "Verdict: \(verdict.displayName)",
            "Confidence: \(confidence.rawValue.capitalized)",
            explanation
        ]
        parts.append(contentsOf: notes.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return parts.joined(separator: "\n")
    }
}

protocol FactCheckService {
    func factCheck(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: FactCheckPromptContext
    ) async throws -> FactCheckResult

    func factCheckBatch(items: [FactCheckItem]) async throws -> [UUID: FactCheckResult]
}

extension FactCheckService {
    func factCheckBatch(items: [FactCheckItem]) async throws -> [UUID: FactCheckResult] {
        var results: [UUID: FactCheckResult] = [:]
        for item in items {
            results[item.id] = try await factCheck(
                sentence: item.sentence,
                llm: item.llm,
                promptTemplate: item.promptTemplate,
                promptContext: item.promptContext
            )
        }
        return results
    }
}

struct OllamaFactCheckService: FactCheckService {
    var timeout: TimeInterval = 60

    func factCheck(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: FactCheckPromptContext
    ) async throws -> FactCheckResult {
        let prompt = FactCheckPrompt.render(
            template: promptTemplate,
            sentence: sentence,
            context: promptContext
        )
        let raw = try await generate(prompt: prompt, llm: llm, wantsJSON: true, traceEvent: "factCheck.request.started")
        let result = Self.parseResult(raw, fallbackSentence: sentence)
        Trace.event("factCheck.response.received", [
            "provider": llm.provider.rawValue,
            "verdict": result.verdict.rawValue,
            "confidence": result.confidence.rawValue,
            "usedRawResponse": result.rawResponse != nil
        ])
        return result
    }

    func factCheckBatch(items: [FactCheckItem]) async throws -> [UUID: FactCheckResult] {
        guard items.count > 1, let llm = items.first?.llm else {
            var results: [UUID: FactCheckResult] = [:]
            for item in items {
                results[item.id] = try await factCheck(
                    sentence: item.sentence,
                    llm: item.llm,
                    promptTemplate: item.promptTemplate,
                    promptContext: item.promptContext
                )
            }
            return results
        }

        let prompt = BatchFactCheckPrompt.render(items: items)
        let raw = try await generate(prompt: prompt, llm: llm, wantsJSON: true, traceEvent: "factCheck.batch.request.started")
        let results = BatchFactCheckPrompt.parse(raw, items: items)
        Trace.event("factCheck.batch.response.received", [
            "provider": llm.provider.rawValue,
            "items": items.count,
            "results": results.count
        ])
        return results
    }

    func generate(
        prompt: String,
        llm: LLMEndpointConfiguration,
        wantsJSON: Bool = false,
        traceEvent: String = "llm.test.request.started"
    ) async throws -> String {
        let request: URLRequest
        switch llm.provider {
        case .ollama:
            request = try ollamaRequest(llm: llm, prompt: prompt, wantsJSON: wantsJSON)
        case .openAICompatible, .openRouter:
            request = try openAICompatibleRequest(llm: llm, prompt: prompt, wantsJSON: wantsJSON)
        case .anthropic:
            request = try anthropicRequest(llm: llm, prompt: prompt)
        case .gemini:
            request = try geminiRequest(llm: llm, prompt: prompt, wantsJSON: wantsJSON)
        }

        Trace.event(traceEvent, [
            "provider": llm.provider.rawValue,
            "model": llm.model,
            "prompt": prompt.prefix(120)
        ])
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw FactCheckError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FactCheckError.httpStatus(http.statusCode, body)
        }

        let raw = try responseText(from: data, provider: llm.provider)
        Trace.event("llm.response.received", [
            "provider": llm.provider.rawValue,
            "chars": raw.count
        ])
        return raw
    }

    private func ollamaRequest(llm: LLMEndpointConfiguration, prompt: String, wantsJSON: Bool) throws -> URLRequest {
        let url = llm.endpointURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaGenerateRequest(
            model: llm.model,
            prompt: prompt,
            stream: false,
            format: wantsJSON ? "json" : nil,
            options: OllamaGenerateOptions(temperature: 0.1)
        ))
        addAuthorization(to: &request, apiKey: llm.apiKey, style: .bearer)
        return request
    }

    private func openAICompatibleRequest(llm: LLMEndpointConfiguration, prompt: String, wantsJSON _: Bool) throws -> URLRequest {
        let url = chatCompletionsURL(from: llm.endpointURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorization(to: &request, apiKey: llm.apiKey, style: .bearer)
        if llm.provider == .openRouter {
            request.setValue("VoiceTranscribe", forHTTPHeaderField: "X-Title")
        }
        request.httpBody = try JSONEncoder().encode(OpenAIChatCompletionRequest(
            model: llm.model,
            messages: [
                OpenAIChatMessage(role: "user", content: prompt)
            ]
        ))
        return request
    }

    private func chatCompletionsURL(from endpointURL: URL) -> URL {
        let components = endpointURL.pathComponents.filter { $0 != "/" }
        if components.suffix(3) == ["v1", "chat", "completions"] {
            return endpointURL
        }
        if components.last == "v1" {
            return endpointURL
                .appendingPathComponent("chat")
                .appendingPathComponent("completions")
        }
        return endpointURL
            .appendingPathComponent("v1")
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    private func anthropicRequest(llm: LLMEndpointConfiguration, prompt: String) throws -> URLRequest {
        let url = llm.endpointURL
            .appendingPathComponent("v1")
            .appendingPathComponent("messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        addAuthorization(to: &request, apiKey: llm.apiKey, style: .anthropic)
        request.httpBody = try JSONEncoder().encode(AnthropicMessagesRequest(
            model: llm.model,
            maxTokens: 1000,
            messages: [
                AnthropicMessage(role: "user", content: prompt)
            ],
            temperature: 0.1
        ))
        return request
    }

    private func geminiRequest(llm: LLMEndpointConfiguration, prompt: String, wantsJSON: Bool) throws -> URLRequest {
        let modelPath = llm.model.hasPrefix("models/") ? llm.model : "models/\(llm.model)"
        var components = URLComponents(
            url: llm.endpointURL
                .appendingPathComponent("v1beta")
                .appendingPathComponent("\(modelPath):generateContent"),
            resolvingAgainstBaseURL: false
        )
        let key = llm.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            components?.queryItems = [URLQueryItem(name: "key", value: key)]
        }
        guard let url = components?.url else {
            throw FactCheckError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiGenerateContentRequest(
            contents: [
                GeminiContent(parts: [GeminiPart(text: prompt)])
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.1,
                responseMimeType: wantsJSON ? "application/json" : nil
            )
        ))
        return request
    }

    private func responseText(from data: Data, provider: LLMProviderKind) throws -> String {
        switch provider {
        case .ollama:
            return try JSONDecoder().decode(OllamaGenerateResponse.self, from: data).response
        case .openAICompatible, .openRouter:
            return try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
                .choices
                .first?
                .message
                .content ?? ""
        case .anthropic:
            return try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
                .content
                .filter { $0.type == "text" }
                .map(\.text)
                .joined(separator: "\n")
        case .gemini:
            return try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
                .candidates
                .first?
                .content
                .parts
                .map(\.text)
                .joined(separator: "\n") ?? ""
        }
    }

    private enum AuthorizationStyle {
        case bearer
        case anthropic
    }

    private func addAuthorization(to request: inout URLRequest, apiKey: String, style: AuthorizationStyle) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        switch style {
        case .bearer:
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(trimmed, forHTTPHeaderField: "x-api-key")
        }
    }

    static func prompt(for sentence: String) -> String {
        FactCheckPrompt.render(template: FactCheckPrompt.defaultTemplate, sentence: sentence)
    }
}

enum FactCheckPrompt {
    static let sentencePlaceholder = "{{sentence}}"
    static let conversationPlaceholder = "{{conversation}}"
    static let promptStatePlaceholder = "{{prompt-state}}"

    static let defaultTemplate = """
        You are fact-checking one sentence from a live speech transcript. The transcript may contain recognition errors.

        Evaluate only factual claims present in the sentence. Do not add unrelated claims. If the sentence is subjective, filler, a command, a question without a claim, or otherwise non-factual, use verdict "not_factual". If the claim cannot be checked from your knowledge alone, use verdict "unverifiable".

        Return only valid JSON matching this schema:
        {
          "sentence": "original sentence",
          "verdict": "supported | questionable | false | unverifiable | not_factual",
          "confidence": "low | medium | high",
          "explanation": "short explanation",
          "notes": ["optional note"]
        }

        Sentence:
        {{sentence}}
        """

    static func render(
        template: String,
        sentence: String,
        context: FactCheckPromptContext = .empty
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? defaultTemplate : template
        let promptContext = context.isEmpty
            ? FactCheckPromptContext(entries: [.init(timestamp: Date(), text: sentence)])
            : context
        var rendered = base

        let usesSupportedPlaceholder = rendered.contains(sentencePlaceholder)
            || rendered.contains(conversationPlaceholder)
            || rendered.contains(promptStatePlaceholder)
            || rendered.contains("{{last-3}}")
            || rendered.contains("{{last-3}")
            || rendered.contains("{{last-5}}")
            || rendered.contains("{{last-5}")
            || rendered.contains("{{last-10}}")
            || rendered.contains("{{last-10}")

        rendered = rendered.replacingOccurrences(of: sentencePlaceholder, with: sentence)
        rendered = rendered.replacingOccurrences(
            of: conversationPlaceholder,
            with: promptContext.formattedConversation()
        )
        rendered = rendered.replacingOccurrences(
            of: promptStatePlaceholder,
            with: promptContext.promptState
        )
        for count in [3, 5, 10] {
            rendered = rendered.replacingOccurrences(
                of: "{{last-\(count)}}",
                with: promptContext.formattedConversation(limit: count)
            )
            rendered = rendered.replacingOccurrences(
                of: "{{last-\(count)}",
                with: promptContext.formattedConversation(limit: count)
            )
        }

        if usesSupportedPlaceholder {
            return rendered
        }

        return """
        \(base)

        Sentence:
        \(sentence)
        """
    }

    static func containsPromptStatePlaceholder(in template: String) -> Bool {
        template.contains(promptStatePlaceholder)
    }
}

struct FactCheckPromptContext: Equatable {
    struct Entry: Equatable {
        var timestamp: Date
        var text: String
    }

    static let empty = FactCheckPromptContext(entries: [])

    var entries: [Entry]
    var promptState: String

    var isEmpty: Bool {
        entries.isEmpty && promptState.isEmpty
    }

    init(entries: [Entry], promptState: String = "") {
        self.entries = entries
            .map { entry in
                Entry(
                    timestamp: entry.timestamp,
                    text: entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }
        self.promptState = promptState.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(segments: [TranscriptSegment], promptState: String = "") {
        self.init(entries: segments.flatMap { segment in
            let sentences = FactCheckCoordinator.completeSentences(in: segment.text)
            let texts = sentences.isEmpty ? [segment.text] : sentences
            return texts.map { Entry(timestamp: segment.timestamp, text: $0) }
        }, promptState: promptState)
    }

    func withPromptState(_ promptState: String) -> FactCheckPromptContext {
        FactCheckPromptContext(entries: entries, promptState: promptState)
    }

    func formattedConversation(limit: Int? = nil) -> String {
        let selectedEntries: [Entry]
        if let limit {
            selectedEntries = Array(entries.suffix(max(0, limit)))
        } else {
            selectedEntries = entries
        }

        return selectedEntries
            .map { "[\(Self.timestampFormatter.string(from: $0.timestamp))] \($0.text)" }
            .joined(separator: "\n")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

enum BatchFactCheckPrompt {
    private struct Question: Codable {
        var id: String
        var name: String
        var prompt: String
    }

    private struct RequestPayload: Codable {
        var questions: [Question]
    }

    private struct ResponsePayload: Codable {
        var answers: [Answer]
    }

    private struct Answer: Codable {
        var id: String
        var response: String
    }

    static func render(items: [FactCheckItem]) -> String {
        let questions = items.map { item in
            Question(
                id: item.id.uuidString,
                name: item.promptTemplateName,
                prompt: FactCheckPrompt.render(
                    template: item.promptTemplate,
                    sentence: item.sentence,
                    context: item.promptContext
                )
            )
        }
        let payload = RequestPayload(questions: questions)
        let encoded = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"questions":[]}"#

        return """
        You will answer multiple independent AI processing prompts for the same transcript point.

        For each question, follow that question's prompt exactly. Do not merge questions together. Return only valid JSON matching this schema:
        {
          "answers": [
            {
              "id": "question id",
              "response": "complete answer for that question"
            }
          ]
        }

        The response string may contain JSON or plain text if the individual question asks for it.

        Questions:
        \(encoded)
        """
    }

    static func parse(_ raw: String, items: [FactCheckItem]) -> [UUID: FactCheckResult] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for candidate in jsonCandidates(from: trimmed) {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ResponsePayload.self, from: data) else {
                continue
            }

            let responseByID = Dictionary(uniqueKeysWithValues: decoded.answers.map { ($0.id, $0.response) })
            return Dictionary(uniqueKeysWithValues: items.map { item in
                let response = responseByID[item.id.uuidString]
                    ?? "Batch response did not include an answer for \(item.promptTemplateName)."
                return (item.id, OllamaFactCheckService.parseResult(response, fallbackSentence: item.sentence))
            })
        }

        return Dictionary(uniqueKeysWithValues: items.map { item in
            let result = FactCheckResult(
                sentence: item.sentence,
                verdict: .unverifiable,
                confidence: .low,
                explanation: trimmed.isEmpty ? "The batch AI response was empty." : trimmed,
                rawResponse: trimmed.isEmpty ? "The batch AI response was empty." : trimmed
            )
            return (item.id, result)
        })
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        var candidates = [raw]

        if raw.hasPrefix("```") {
            let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            let withoutFence = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !withoutFence.isEmpty {
                candidates.append(withoutFence)
            }
        }

        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           start <= end {
            candidates.append(String(raw[start...end]))
        }

        return candidates
    }
}

extension OllamaFactCheckService {
    static func parseResult(_ raw: String, fallbackSentence: String) -> FactCheckResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in jsonCandidates(from: trimmed) {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(FactCheckResult.self, from: data) else {
                continue
            }

            if decoded.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return FactCheckResult(
                    sentence: fallbackSentence,
                    verdict: decoded.verdict,
                    confidence: decoded.confidence,
                    explanation: decoded.explanation,
                    notes: decoded.notes
                )
            }
            return decoded
        }

        Trace.event("factCheck.response.usedRawText", ["raw": trimmed.prefix(200)])
        return FactCheckResult(
            sentence: fallbackSentence,
            verdict: .unverifiable,
            confidence: .low,
            explanation: trimmed.isEmpty ? "Ollama returned an empty response." : trimmed,
            notes: [],
            rawResponse: trimmed.isEmpty ? "Ollama returned an empty response." : trimmed
        )
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        var candidates = [raw]

        if raw.hasPrefix("```") {
            let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            let withoutFence = lines
                .dropFirst()
                .dropLast(lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !withoutFence.isEmpty {
                candidates.append(withoutFence)
            }
        }

        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}"),
           start <= end {
            candidates.append(String(raw[start...end]))
        }

        return candidates
    }
}

@MainActor
final class FactCheckCoordinator: ObservableObject {
    @Published private(set) var items: [FactCheckItem] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let service: FactCheckService
    private var seenSentences = Set<String>()
    private var workerTasks: [Task<Void, Never>] = []
    private var activeWorkerCount = 0
    private var promptStates: [String: String] = [:]
    private var activePromptStateTemplateIDs = Set<String>()
    private let maxConcurrentRequests = 3

    init(service: FactCheckService = OllamaFactCheckService()) {
        self.service = service
    }

    func reset() {
        workerTasks.forEach { $0.cancel() }
        workerTasks = []
        activeWorkerCount = 0
        items = []
        seenSentences = []
        promptStates = [:]
        activePromptStateTemplateIDs = []
        isRunning = false
        lastError = nil
    }

    func promptState(for promptTemplateID: String) -> String {
        promptStates[promptTemplateID] ?? ""
    }

    func enqueueTranscriptSegment(
        _ segment: TranscriptSegment,
        enabled: Bool,
        promptTemplates: [AIPromptTemplateConfiguration],
        llmEndpoints: [LLMEndpointConfiguration],
        fallbackLLM: LLMEndpointConfiguration,
        conversation: [TranscriptSegment] = [],
        batchPrompts: Bool = false
    ) {
        guard enabled, segment.isFinal else {
            return
        }

        let conversationSegments = conversation.isEmpty ? [segment] : conversation
        let promptContext = FactCheckPromptContext(segments: conversationSegments)
        let endpointByID = Dictionary(uniqueKeysWithValues: llmEndpoints.map { ($0.id, $0) })
        let enabledPromptTemplates = promptTemplates.filter(\.isEnabled)
        let promptRoutes = enabledPromptTemplates.map { promptTemplate in
            (promptTemplate: promptTemplate, llm: endpointByID[promptTemplate.llmEndpointID] ?? fallbackLLM)
        }
        let canBatchPrompts = batchPrompts
            && promptRoutes.count > 1
            && Set(promptRoutes.map { $0.llm.id }).count == 1
        for sentence in Self.completeSentences(in: segment.text) {
            let batchGroupID = canBatchPrompts ? UUID().uuidString : nil
            for route in promptRoutes {
                enqueue(
                    sentence: sentence,
                    llm: route.llm,
                    promptTemplate: route.promptTemplate,
                    promptContext: promptContext,
                    batchGroupID: batchGroupID
                )
            }
        }
    }

    private func enqueue(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: AIPromptTemplateConfiguration,
        promptContext: FactCheckPromptContext,
        batchGroupID: String?
    ) {
        let normalized = Self.normalizedSentence(sentence)
        let dedupeKey = "\(promptTemplate.id)|\(normalized)"
        guard !normalized.isEmpty, !seenSentences.contains(dedupeKey) else {
            return
        }

        seenSentences.insert(dedupeKey)
        let item = FactCheckItem(
            sentence: sentence,
            llm: llm,
            promptTemplateID: promptTemplate.id,
            promptTemplateName: promptTemplate.displayName,
            promptTemplate: promptTemplate.template,
            promptContext: promptContext,
            batchGroupID: batchGroupID
        )
        items.append(item)
        Trace.event("factCheck.queued", [
            "id": item.id.uuidString,
            "promptTemplate": promptTemplate.displayName,
            "provider": llm.provider.rawValue,
            "model": llm.model,
            "sentence": sentence.prefix(120)
        ])
        startProcessing()
    }

    private func startProcessing() {
        while activeWorkerCount < maxConcurrentRequests, hasQueuedItem {
            activeWorkerCount += 1
            isRunning = true
            let task = Task { [weak self] in
                guard let self else { return }
                await self.processQueueWorker()
            }
            workerTasks.append(task)
        }
    }

    private var hasQueuedItem: Bool {
        !nextQueuedBatch().isEmpty
    }

    private func processQueueWorker() async {
        defer {
            activeWorkerCount = max(0, activeWorkerCount - 1)
            workerTasks.removeAll { $0.isCancelled }
            if activeWorkerCount == 0 {
                workerTasks = []
                isRunning = false
            }
        }

        while !Task.isCancelled {
            let batch = nextQueuedBatch()
            guard !batch.isEmpty else {
                return
            }
            let statefulPromptIDs = promptStateTemplateIDs(in: batch)
            activePromptStateTemplateIDs.formUnion(statefulPromptIDs)
            let batchWithState = batch.map { item in
                item.withPromptState(promptStates[item.promptTemplateID] ?? "")
            }

            for item in batchWithState {
                update(id: item.id, state: .checking)
            }
            do {
                let results = try await service.factCheckBatch(items: batchWithState)
                if Task.isCancelled {
                    releasePromptStateTemplates(statefulPromptIDs)
                    return
                }
                for item in batchWithState {
                    guard let result = results[item.id] else {
                        let message = "The AI batch response did not include \(item.promptTemplateName)."
                        update(id: item.id, state: .failed(message))
                        continue
                    }
                    update(id: item.id, state: .completed(result))
                    updatePromptStateIfNeeded(for: item, result: result)
                    Trace.event("factCheck.completed", [
                        "id": item.id.uuidString,
                        "promptTemplate": item.promptTemplateName,
                        "batchSize": batchWithState.count,
                        "verdict": result.verdict.rawValue,
                        "confidence": result.confidence.rawValue
                    ])
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                lastError = message
                for item in batchWithState {
                    update(id: item.id, state: .failed(message))
                    Trace.event("factCheck.failed", [
                        "id": item.id.uuidString,
                        "promptTemplate": item.promptTemplateName,
                        "batchSize": batchWithState.count,
                        "error": message
                    ])
                }
            }
            releasePromptStateTemplates(statefulPromptIDs)
        }
    }

    private func nextQueuedBatch() -> [FactCheckItem] {
        guard let first = items.first(where: {
            if case .queued = $0.state, canStart($0) {
                return true
            }
            return false
        }) else {
            return []
        }

        guard let batchGroupID = first.batchGroupID else {
            return [first]
        }

        return items.filter { item in
            guard item.batchGroupID == batchGroupID else {
                return false
            }
            if case .queued = item.state, canStart(item) {
                return true
            }
            return false
        }
    }

    private func canStart(_ item: FactCheckItem) -> Bool {
        guard FactCheckPrompt.containsPromptStatePlaceholder(in: item.promptTemplate) else {
            return true
        }
        return !activePromptStateTemplateIDs.contains(item.promptTemplateID)
    }

    private func promptStateTemplateIDs(in items: [FactCheckItem]) -> Set<String> {
        Set(items.compactMap { item in
            FactCheckPrompt.containsPromptStatePlaceholder(in: item.promptTemplate)
                ? item.promptTemplateID
                : nil
        })
    }

    private func releasePromptStateTemplates(_ ids: Set<String>) {
        activePromptStateTemplateIDs.subtract(ids)
    }

    private func updatePromptStateIfNeeded(for item: FactCheckItem, result: FactCheckResult) {
        guard FactCheckPrompt.containsPromptStatePlaceholder(in: item.promptTemplate) else {
            return
        }

        let nextState = result.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        promptStates[item.promptTemplateID] = nextState
        Trace.event("factCheck.promptState.updated", [
            "promptTemplate": item.promptTemplateName,
            "chars": nextState.count
        ])
    }

    private func update(id: UUID, state: FactCheckState) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].state = state
    }

    nonisolated static func completeSentences(in text: String) -> [String] {
        var sentences: [String] = []
        var start = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "." || character == "?" || character == "!" {
                let end = text.index(after: index)
                let sentence = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                start = end
            }
            index = text.index(after: index)
        }

        return sentences
    }

    nonisolated static func normalizedSentence(_ sentence: String) -> String {
        sentence
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

enum FactCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)
    case malformedJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The LLM endpoint returned an invalid response."
        case .httpStatus(let status, let body):
            let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                return "The LLM endpoint returned HTTP \(status)."
            }
            return "The LLM endpoint returned HTTP \(status): \(trimmed)"
        case .malformedJSON:
            return "The LLM endpoint returned malformed JSON."
        }
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String?
    let options: OllamaGenerateOptions
}

private struct OllamaGenerateOptions: Encodable {
    let temperature: Double
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIChatMessage
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]
    let temperature: Double

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case temperature
    }
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [AnthropicContentBlock]
}

private struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String
}

private struct GeminiGenerateContentRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let responseMimeType: String?

    private enum CodingKeys: String, CodingKey {
        case temperature
        case responseMimeType = "response_mime_type"
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}
