import Foundation

enum JevAnswer: Equatable {
    case noul(probability: Double)
    case choice(selected: String, confidence: Double, probabilities: [String: Double])
    case score(value: Double, confidence: Double, legend: [String: String], probabilities: [String: Double])
}

enum JevQueryState: Equatable {
    case queued
    case checking
    case completed(JevAnswer)
    case failed(String)
}

struct JevResultItem: Identifiable, Equatable {
    let id: UUID
    let sentence: String
    let queryID: String
    let queryName: String
    let batchGroupID: String
    var state: JevQueryState
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sentence: String,
        queryID: String,
        queryName: String,
        batchGroupID: String,
        state: JevQueryState = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sentence = sentence
        self.queryID = queryID
        self.queryName = queryName
        self.batchGroupID = batchGroupID
        self.state = state
        self.createdAt = createdAt
    }
}

enum JevError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String?)
    case missingAnswer(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No Jev API key is set. Add one in Settings \u{2192} Jev Configuration."
        case .invalidResponse:
            return "Jev returned an invalid response."
        case .httpStatus(let status, let body):
            let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                return "Jev returned HTTP \(status)."
            }
            return "Jev returned HTTP \(status): \(trimmed)"
        case .missingAnswer(let queryName):
            return "Jev's response did not include an answer for \(queryName)."
        }
    }
}

protocol JevService {
    func evaluate(
        sentence: String,
        queries: [JevQueryConfiguration],
        apiKey: String,
        baseURL: String,
        model: String
    ) async throws -> [String: JevAnswer]
}

struct TypeSafeJevService: JevService {
    var timeout: TimeInterval = 30

    func evaluate(
        sentence: String,
        queries: [JevQueryConfiguration],
        apiKey: String,
        baseURL: String,
        model: String
    ) async throws -> [String: JevAnswer] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw JevError.missingAPIKey
        }

        let base = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? URL(string: "https://api.typesafe.ai")!
        let url = base.appendingPathComponent("v1").appendingPathComponent("systemone")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let questions = Dictionary(uniqueKeysWithValues: queries.map { ($0.id, JevQuestionWire(query: $0)) })
        let body = JevSystemOneRequest(state: sentence, model: model, questions: questions)
        request.httpBody = try JSONEncoder().encode(body)

        Trace.event("jev.request.started", [
            "model": model,
            "questions": queries.count,
            "sentence": sentence.prefix(120)
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw JevError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw JevError.httpStatus(http.statusCode, bodyText)
        }

        let decoded = try JSONDecoder().decode(JevSystemOneResponseWire.self, from: data)
        var answers: [String: JevAnswer] = [:]
        for query in queries {
            guard let wire = decoded.answers[query.id] else {
                continue
            }
            answers[query.id] = wire.toAnswer()
        }

        Trace.event("jev.response.received", [
            "model": decoded.model,
            "answers": answers.count
        ])
        return answers
    }
}

// MARK: - Wire format

struct JevSystemOneRequest: Encodable {
    let state: String
    let model: String
    let questions: [String: JevQuestionWire]
}

struct JevQuestionWire: Encodable {
    let query: JevQueryConfiguration

    private enum CodingKeys: String, CodingKey {
        case type
        case instructions
        case criteria
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query.primitiveType.rawValue, forKey: .type)
        let instructions = query.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            try container.encode(instructions, forKey: .instructions)
        }

        switch query.primitiveType {
        case .noul:
            let trueDescription = query.noulTrueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let falseDescription = query.noulFalseDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trueDescription.isEmpty || !falseDescription.isEmpty {
                var criteria: [String: String] = [:]
                if !trueDescription.isEmpty { criteria["true"] = trueDescription }
                if !falseDescription.isEmpty { criteria["false"] = falseDescription }
                try container.encode(criteria, forKey: .criteria)
            }
        case .choice:
            let criteria = Dictionary(uniqueKeysWithValues: query.choiceCriteria
                .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ($0.label, $0.description) })
            try container.encode(criteria, forKey: .criteria)
        case .score:
            let levels = query.scoreCriteria.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            try container.encode(levels, forKey: .criteria)
        }
    }
}

struct JevUsageWire: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct JevSystemOneResponseWire: Decodable {
    let model: String
    let usage: JevUsageWire?
    let answers: [String: JevAnswerWire]
}

struct JevAnswerWire: Decodable {
    let type: String
    let noul: Double?
    let choice: String?
    let confidence: Double?
    let score: Double?
    let legend: [String: String]?
    let probabilities: [String: Double]?

    func toAnswer() -> JevAnswer? {
        switch type {
        case "noul":
            guard let noul else { return nil }
            return .noul(probability: noul)
        case "choice":
            guard let choice, let confidence else { return nil }
            return .choice(selected: choice, confidence: confidence, probabilities: probabilities ?? [:])
        case "score":
            guard let score, let confidence else { return nil }
            return .score(value: score, confidence: confidence, legend: legend ?? [:], probabilities: probabilities ?? [:])
        default:
            return nil
        }
    }
}

// MARK: - Coordinator

@MainActor
final class JevCoordinator: ObservableObject {
    @Published private(set) var items: [JevResultItem] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private let service: JevService
    private var seenSentences = Set<String>()
    private var workerTasks: [Task<Void, Never>] = []
    private var activeWorkerCount = 0
    private let maxConcurrentRequests = 3

    init(service: JevService = TypeSafeJevService()) {
        self.service = service
    }

    func reset() {
        workerTasks.forEach { $0.cancel() }
        workerTasks = []
        activeWorkerCount = 0
        items = []
        seenSentences = []
        isRunning = false
        lastError = nil
    }

    func enqueueTranscriptSegment(
        _ segment: TranscriptSegment,
        enabled: Bool,
        queries: [JevQueryConfiguration],
        apiKey: String,
        baseURL: String,
        model: String
    ) {
        guard enabled, !queries.isEmpty, segment.isFinal else {
            return
        }

        for sentence in FactCheckCoordinator.completeSentences(in: segment.text) {
            enqueue(sentence: sentence, queries: queries, apiKey: apiKey, baseURL: baseURL, model: model)
        }
    }

    private func enqueue(
        sentence: String,
        queries: [JevQueryConfiguration],
        apiKey: String,
        baseURL: String,
        model: String
    ) {
        let normalized = FactCheckCoordinator.normalizedSentence(sentence)
        guard !normalized.isEmpty else {
            return
        }

        let unseenQueries = queries.filter { !seenSentences.contains("\($0.id)|\(normalized)") }
        guard !unseenQueries.isEmpty else {
            return
        }
        for query in unseenQueries {
            seenSentences.insert("\(query.id)|\(normalized)")
        }

        let batchGroupID = UUID().uuidString
        let newItems = unseenQueries.map { query in
            JevResultItem(
                sentence: sentence,
                queryID: query.id,
                queryName: query.displayName,
                batchGroupID: batchGroupID
            )
        }
        items.append(contentsOf: newItems)
        Trace.event("jev.queued", [
            "batchGroupID": batchGroupID,
            "queries": newItems.count,
            "sentence": sentence.prefix(120)
        ])
        startProcessing(queries: queries, apiKey: apiKey, baseURL: baseURL, model: model)
    }

    private func startProcessing(queries: [JevQueryConfiguration], apiKey: String, baseURL: String, model: String) {
        while activeWorkerCount < maxConcurrentRequests, hasQueuedItem {
            activeWorkerCount += 1
            isRunning = true
            let task = Task { [weak self] in
                guard let self else { return }
                await self.processQueueWorker(queries: queries, apiKey: apiKey, baseURL: baseURL, model: model)
            }
            workerTasks.append(task)
        }
    }

    private var hasQueuedItem: Bool {
        !nextQueuedBatch().isEmpty
    }

    private func processQueueWorker(queries: [JevQueryConfiguration], apiKey: String, baseURL: String, model: String) async {
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

            for item in batch {
                update(id: item.id, state: .checking)
            }

            let queryByID = Dictionary(uniqueKeysWithValues: queries.map { ($0.id, $0) })
            let batchQueries = batch.compactMap { queryByID[$0.queryID] }
            guard let sentence = batch.first?.sentence else {
                continue
            }

            do {
                let answers = try await service.evaluate(
                    sentence: sentence,
                    queries: batchQueries,
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model
                )
                if Task.isCancelled { return }
                for item in batch {
                    guard let answer = answers[item.queryID] else {
                        update(id: item.id, state: .failed("Jev's response did not include an answer for \(item.queryName)."))
                        continue
                    }
                    update(id: item.id, state: .completed(answer))
                    Trace.event("jev.completed", [
                        "id": item.id.uuidString,
                        "query": item.queryName
                    ])
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                lastError = message
                for item in batch {
                    update(id: item.id, state: .failed(message))
                    Trace.event("jev.failed", [
                        "id": item.id.uuidString,
                        "query": item.queryName,
                        "error": message
                    ])
                }
            }
        }
    }

    private func nextQueuedBatch() -> [JevResultItem] {
        guard let first = items.first(where: {
            if case .queued = $0.state { return true }
            return false
        }) else {
            return []
        }

        return items.filter { item in
            guard item.batchGroupID == first.batchGroupID else {
                return false
            }
            if case .queued = item.state { return true }
            return false
        }
    }

    private func update(id: UUID, state: JevQueryState) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].state = state
    }
}
