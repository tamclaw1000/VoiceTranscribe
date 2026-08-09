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
    var state: FactCheckState
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sentence: String,
        state: FactCheckState = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sentence = sentence
        self.state = state
        self.createdAt = createdAt
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
    func factCheck(sentence: String, endpoint: URL, model: String) async throws -> FactCheckResult
}

struct OllamaFactCheckService: FactCheckService {
    var timeout: TimeInterval = 60

    func factCheck(sentence: String, endpoint: URL, model: String) async throws -> FactCheckResult {
        let url = endpoint.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaGenerateRequest(
            model: model,
            prompt: Self.prompt(for: sentence),
            stream: false,
            format: "json",
            options: OllamaGenerateOptions(temperature: 0.1)
        ))

        Trace.event("factCheck.request.started", ["model": model, "sentence": sentence.prefix(120)])
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw FactCheckError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FactCheckError.httpStatus(http.statusCode)
        }

        let generated = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let result = Self.parseResult(generated.response, fallbackSentence: sentence)
        Trace.event("factCheck.response.received", [
            "verdict": result.verdict.rawValue,
            "confidence": result.confidence.rawValue,
            "usedRawResponse": result.rawResponse != nil
        ])
        return result
    }

    static func prompt(for sentence: String) -> String {
        """
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
        \(sentence)
        """
    }

    static func parseResult(_ raw: String, fallbackSentence: String) -> FactCheckResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in Self.jsonCandidates(from: trimmed) {
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
    private var processingTask: Task<Void, Never>?

    init(service: FactCheckService = OllamaFactCheckService()) {
        self.service = service
    }

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        items = []
        seenSentences = []
        isRunning = false
        lastError = nil
    }

    func enqueueTranscriptSegment(
        _ segment: TranscriptSegment,
        enabled: Bool,
        endpoint: URL,
        model: String
    ) {
        guard enabled, segment.isFinal else {
            return
        }

        for sentence in Self.completeSentences(in: segment.text) {
            enqueue(sentence: sentence, endpoint: endpoint, model: model)
        }
    }

    private func enqueue(sentence: String, endpoint: URL, model: String) {
        let normalized = Self.normalizedSentence(sentence)
        guard !normalized.isEmpty, !seenSentences.contains(normalized) else {
            return
        }

        seenSentences.insert(normalized)
        let item = FactCheckItem(sentence: sentence)
        items.append(item)
        Trace.event("factCheck.queued", ["id": item.id.uuidString, "sentence": sentence.prefix(120)])
        startProcessing(endpoint: endpoint, model: model)
    }

    private func startProcessing(endpoint: URL, model: String) {
        guard processingTask == nil else {
            return
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue(endpoint: endpoint, model: model)
        }
    }

    private func processQueue(endpoint: URL, model: String) async {
        isRunning = true

        while !Task.isCancelled, let next = nextQueuedItem() {
            update(id: next.id, state: .checking)

            do {
                let result = try await service.factCheck(sentence: next.sentence, endpoint: endpoint, model: model)
                guard !Task.isCancelled else { return }
                update(id: next.id, state: .completed(result))
                Trace.event("factCheck.completed", [
                    "id": next.id.uuidString,
                    "verdict": result.verdict.rawValue,
                    "confidence": result.confidence.rawValue
                ])
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                lastError = message
                update(id: next.id, state: .failed(message))
                Trace.event("factCheck.failed", ["id": next.id.uuidString, "error": message])
            }
        }

        isRunning = false
        processingTask = nil
    }

    private func nextQueuedItem() -> FactCheckItem? {
        items.first {
            if case .queued = $0.state {
                return true
            }
            return false
        }
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
    case httpStatus(Int)
    case malformedJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ollama returned an invalid response."
        case .httpStatus(let status):
            return "Ollama returned HTTP \(status)."
        case .malformedJSON:
            return "Ollama returned malformed JSON."
        }
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String
    let options: OllamaGenerateOptions
}

private struct OllamaGenerateOptions: Encodable {
    let temperature: Double
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}
