import Foundation
import AVFoundation
import Testing
@testable import VoiceTranscribe

@Test func sourceSlugRemovesUnsafeCharacters() {
    #expect(FileNamer.sourceSlug("Built-in Microphone") == "built-in-microphone")
    #expect(FileNamer.sourceSlug("USB Mic #2!") == "usb-mic-2")
    #expect(FileNamer.sourceSlug("!!!") == "audio-source")
}

@Test func timestampsUseRequiredShapes() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: 1_779_971_597.250)

    #expect(FileNamer.startTimestamp(date, calendar: calendar).count == 14)
    #expect(FileNamer.endTimestamp(date, calendar: calendar).count == 7)
}

@Test func recordingBasenameIncludesTimestampsAndSourceSlug() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)
    let end = Date(timeIntervalSince1970: 1_779_971_905.700)

    let basename = FileNamer.recordingBasename(
        sourceName: "Built-in Microphone",
        startDate: start,
        endDate: end,
        calendar: calendar
    )

    #expect(basename.hasSuffix("-built-in-microphone"))
    #expect(basename.split(separator: "-").count >= 3)
}

@Test func boundedBufferDropsOldestElements() {
    var buffer = BoundedBuffer<Int>(capacity: 3)
    buffer.append(1)
    buffer.append(2)
    buffer.append(3)
    buffer.append(4)

    #expect(buffer.elements == [2, 3, 4])
    #expect(buffer.droppedCount == 1)
}

@Test func appVersionFormatsVersionAndBuild() {
    #expect(AppVersion.displayText(shortVersion: "2.2.9", build: "39") == "Version 2.2.9 (39)")
    #expect(AppVersion.displayText(shortVersion: "2.2.9", build: nil) == "Version 2.2.9")
    #expect(AppVersion.displayText(shortVersion: nil, build: "39") == "Build 39")
    #expect(AppVersion.displayText(shortVersion: " ", build: " ") == "Version unavailable")
}

@MainActor
@Test func audioDisplayLevelMakesQuietInputVisible() {
    let quiet = AudioCaptureService.displayLevel(forRMS: 0.01, peak: 0.03)
    let louder = AudioCaptureService.displayLevel(forRMS: 0.10, peak: 0.30)

    #expect(quiet > 0.05)
    #expect(louder > quiet)
    #expect(louder <= 1.0)
}

@Test func transcriptionBufferFractionIsClamped() {
    let normal = TranscriptionBufferSnapshot(queuedDuration: 3, maxDuration: 10)
    let overflow = TranscriptionBufferSnapshot(queuedDuration: 12, maxDuration: 10)
    let empty = TranscriptionBufferSnapshot(queuedDuration: -1, maxDuration: 10)

    #expect(normal.fillFraction == 0.3)
    #expect(overflow.fillFraction == 1)
    #expect(empty.fillFraction == 0)
}

@MainActor
@Test func defaultTranscriptionEngineIsFluidAudio() {
    #expect(AppSettings.defaultTranscriptionEngine == .fluidAudio)
}

@MainActor
@Test func aiToggleControlsEffectiveFactChecking() {
    let settings = AppSettings()

    settings.aiEnabled = false
    settings.factCheckEnabled = true
    #expect(settings.isFactCheckActive == false)

    settings.aiEnabled = true
    settings.factCheckEnabled = false
    #expect(settings.isFactCheckActive == false)

    settings.factCheckEnabled = true
    #expect(settings.isFactCheckActive == true)
}

@Test func llmEndpointConfigurationUsesDefaultOllamaValues() {
    let configuration = LLMEndpointConfiguration.defaultConfiguration()

    #expect(configuration.name == "Local Ollama")
    #expect(configuration.endpoint == "http://localhost:11434")
    #expect(configuration.model == "igorls/gemma-4-12B-it-heretic-GGUF")
}

@Test func llmEndpointConfigurationSanitizesEmptyListsAndFields() {
    let empty = LLMEndpointConfiguration.sanitized([])
    let sanitized = LLMEndpointConfiguration.sanitized([
        LLMEndpointConfiguration(id: "", name: "", endpoint: "", model: "")
    ])

    #expect(empty.count == 1)
    #expect(sanitized.count == 1)
    #expect(sanitized[0].name == "LLM 1")
    #expect(sanitized[0].endpoint == LLMEndpointConfiguration.defaultEndpoint)
    #expect(sanitized[0].model == LLMEndpointConfiguration.defaultModel)
    #expect(!sanitized[0].id.isEmpty)
}

@Test func legacyRemoteLLMEndpointDefaultsToOpenAICompatibleProvider() throws {
    let data = """
    {"id":"remote","name":"Remote","endpoint":"https://example.com/api","model":"model"}
    """.data(using: .utf8)!

    let configuration = try JSONDecoder().decode(LLMEndpointConfiguration.self, from: data)

    #expect(configuration.provider == .openAICompatible)
}

@Test func legacyOpenRouterLLMEndpointDefaultsToOpenRouterProvider() throws {
    let data = """
    {"id":"openrouter","name":"OpenRouter","endpoint":"https://openrouter.ai/api","model":"openrouter/free"}
    """.data(using: .utf8)!

    let configuration = try JSONDecoder().decode(LLMEndpointConfiguration.self, from: data)

    #expect(configuration.provider == .openRouter)
}

@Test func openRouterModelRepairsMismatchedOpenCodeEndpoint() {
    let sanitized = LLMEndpointConfiguration.sanitized([
        LLMEndpointConfiguration(
            id: "openrouter",
            name: "OpenRouter",
            provider: .openAICompatible,
            endpoint: "https://opencode.ai/zen",
            model: "openrouter/free"
        )
    ])

    #expect(sanitized[0].provider == .openRouter)
    #expect(sanitized[0].endpoint == LLMProviderKind.openRouter.defaultEndpoint)
    #expect(sanitized[0].model == "openrouter/free")
}

@Test func legacyLocalLLMEndpointDefaultsToOllamaProvider() throws {
    let data = """
    {"id":"local","name":"Local","endpoint":"http://localhost:11434","model":"model"}
    """.data(using: .utf8)!

    let configuration = try JSONDecoder().decode(LLMEndpointConfiguration.self, from: data)

    #expect(configuration.provider == .ollama)
}

@Test func summaryOrganizerGroupsSentencesIntoParagraphs() {
    let paragraphs = SummaryCoordinator.organizeIntoParagraphs(
        sentences: [
            "First sentence.",
            "Second sentence.",
            "Third sentence.",
            "Fourth sentence."
        ],
        prompt: "concise summary"
    )

    #expect(paragraphs == [
        "First sentence. Second sentence. Third sentence.",
        "Fourth sentence."
    ])
}

@Test func summaryPromptDefaultIsEditableInstructionText() {
    #expect(SummaryPrompt.defaultTemplate.contains("Summarize the recording"))
    #expect(SummaryPrompt.defaultTemplate.contains("paragraphs"))
}

@Test func transcriptDocumentKeepsFinalAndInterimText() {
    var document = TranscriptDocument()
    document.apply(TranscriptSegment(text: "hello", isFinal: true))
    document.apply(TranscriptSegment(text: "world", isFinal: false))

    #expect(document.finalized.map(\.text) == ["hello"])
    #expect(document.interim?.text == "world")
    #expect(document.plainText == "hello\nworld")

    document.apply(TranscriptSegment(text: "world", isFinal: true))
    #expect(document.finalized.map(\.text) == ["hello", "world"])
    #expect(document.interim == nil)
    #expect(document.plainText == "hello\nworld")
}

@Test func markdownExportIncludesDetailsRecordingSummaryAndFactChecks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)
    let second = start.addingTimeInterval(3)
    let end = start.addingTimeInterval(7)
    let llm = LLMEndpointConfiguration.defaultConfiguration()
    let factCheck = FactCheckItem(
        sentence: "The Earth orbits the Sun.",
        llm: llm,
        promptTemplate: FactCheckPrompt.defaultTemplate,
        state: .completed(FactCheckResult(
            sentence: "The Earth orbits the Sun.",
            verdict: .supported,
            confidence: .high,
            explanation: "This is a basic astronomical fact."
        )),
        createdAt: start
    )

    let markdown = MarkdownExportService.makeDocument(
        context: MarkdownExportContext(
            sourceName: "BlackHole 2ch",
            location: "",
            startDate: start,
            endDate: end,
            exportedAt: end,
            transcriptionEngine: "FluidAudio",
            aiEnabled: true,
            factCheckEnabled: true,
            llmName: "Local Ollama",
            llmProvider: "Ollama",
            llmEndpoint: "http://localhost:11434",
            llmModel: "igorls/gemma-4-12B-it-heretic-GGUF",
            factCheckPrompt: "Fact-check {{sentence}}",
            summaryPrompt: "Summarize this recording.",
            audioURL: URL(fileURLWithPath: "/tmp/recording.m4a"),
            transcriptURL: URL(fileURLWithPath: "/tmp/recording.txt"),
            metadataURL: URL(fileURLWithPath: "/tmp/recording.json")
        ),
        finalizedSegments: [
            TranscriptSegment(text: "The Earth orbits the Sun.", timestamp: start, isFinal: true),
            TranscriptSegment(text: "Pipe | characters are escaped.", timestamp: second, isFinal: true)
        ],
        factChecks: [factCheck],
        summaryParagraphs: ["The recording discusses astronomy."],
        calendar: calendar
    )

    #expect(markdown.contains("# DETAILS"))
    #expect(markdown.contains("- Location of recording: Not specified"))
    #expect(markdown.contains("# RECORDING"))
    #expect(markdown.contains("| date time | length | text | AI result |"))
    #expect(markdown.contains("| 2026-05-28 07:33:17 | 0:03 | The Earth orbits the Sun. | Verdict: Supported<br>Confidence: High<br>This is a basic astronomical fact. |"))
    #expect(markdown.contains("Pipe \\| characters are escaped."))
    #expect(markdown.contains("# SUMMARY"))
    #expect(markdown.contains("The recording discusses astronomy."))
    #expect(!markdown.contains("# FACT CHECKS"))
    #expect(markdown.contains("# AI RESULTS"))
    #expect(markdown.contains("- AI enabled: Yes"))
    #expect(markdown.contains("- LLM provider: Ollama"))
    #expect(markdown.contains("- LLM model: igorls/gemma-4-12B-it-heretic-GGUF"))
    #expect(markdown.contains("## Summary Result"))
    #expect(!markdown.contains("## Fact-Check Results"))
    #expect(markdown.contains("## Fact-Check Prompt"))
    #expect(markdown.contains("Fact-check {{sentence}}"))
    #expect(markdown.contains("## Summary Prompt"))
    #expect(markdown.contains("Summarize this recording."))
    #expect(markdown.contains("# FILES"))
    #expect(markdown.contains("`/tmp/recording.m4a`"))
}

@Test func factCheckSentenceExtractionRequiresCompleteSentences() {
    let sentences = FactCheckCoordinator.completeSentences(
        in: "Mars is red. Is water wet? This is incomplete"
    )

    #expect(sentences == ["Mars is red.", "Is water wet?"])
}

@Test func factCheckPromptIncludesSchemaAndSentence() {
    let prompt = OllamaFactCheckService.prompt(for: "The Earth orbits the Sun.")

    #expect(prompt.contains("\"verdict\""))
    #expect(prompt.contains("not_factual"))
    #expect(prompt.contains("The Earth orbits the Sun."))
}

@Test func factCheckPromptTemplateReplacesSentencePlaceholder() {
    let prompt = FactCheckPrompt.render(
        template: "Check this: {{sentence}}",
        sentence: "The Earth orbits the Sun."
    )

    #expect(prompt == "Check this: The Earth orbits the Sun.")
}

@Test func factCheckPromptTemplateAppendsSentenceWhenPlaceholderIsMissing() {
    let prompt = FactCheckPrompt.render(
        template: "Fact-check the following transcript sentence.",
        sentence: "The Earth orbits the Sun."
    )

    #expect(prompt.contains("Fact-check the following transcript sentence."))
    #expect(prompt.contains("Sentence:\nThe Earth orbits the Sun."))
}

@Test func ollamaFactCheckParserAcceptsMissingNotes() {
    let raw = """
    {"sentence":"The Earth orbits the Sun.","verdict":"supported","confidence":"high","explanation":"This is a basic astronomical fact."}
    """

    let result = OllamaFactCheckService.parseResult(raw, fallbackSentence: "fallback")

    #expect(result.sentence == "The Earth orbits the Sun.")
    #expect(result.verdict == .supported)
    #expect(result.confidence == .high)
    #expect(result.notes == [])
}

@Test func ollamaFactCheckParserAcceptsFencedJSON() {
    let raw = """
    ```json
    {"sentence":"The Earth orbits the Sun.","verdict":"supported","confidence":"high","explanation":"This is a basic astronomical fact."}
    ```
    """

    let result = OllamaFactCheckService.parseResult(raw, fallbackSentence: "fallback")

    #expect(result.sentence == "The Earth orbits the Sun.")
    #expect(result.verdict == .supported)
    #expect(result.rawResponse == nil)
}

@Test func ollamaFactCheckParserDisplaysPlainTextResponse() {
    let raw = "This statement is broadly accurate: the Earth orbits the Sun."

    let result = OllamaFactCheckService.parseResult(raw, fallbackSentence: "The Earth orbits the Sun.")

    #expect(result.sentence == "The Earth orbits the Sun.")
    #expect(result.rawResponse == raw)
    #expect(result.displayText == raw)
}

@MainActor
@Test func factCheckCoordinatorSuppressesDuplicateSentences() async {
    let service = FakeFactCheckService()
    let coordinator = FactCheckCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: true,
        llm: llm,
        promptTemplate: FactCheckPrompt.defaultTemplate
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "  The Earth orbits the Sun.  ", isFinal: true),
        enabled: true,
        llm: llm,
        promptTemplate: FactCheckPrompt.defaultTemplate
    )

    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(coordinator.items.count == 1)
}

@MainActor
@Test func factCheckCoordinatorDoesNotQueueWhenDisabled() async {
    let service = FakeFactCheckService()
    let coordinator = FactCheckCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: false,
        llm: llm,
        promptTemplate: FactCheckPrompt.defaultTemplate
    )

    #expect(coordinator.items.isEmpty)
}

@MainActor
@Test func permissionServiceDoesNotPromptDuringInitialization() {
    let provider = FakeMicrophonePermissionProvider(initialStatus: .notDetermined, requestedStatus: .authorized)
    let service = PermissionService(microphoneProvider: provider)

    #expect(service.microphoneStatus == .notDetermined)
    #expect(service.hasTouchedRecordingDevice == false)
    #expect(provider.requestCount == 0)
}

@MainActor
@Test func firstRecordingDeviceTouchRequestsPermissionOnceAndCachesState() async {
    let provider = FakeMicrophonePermissionProvider(initialStatus: .notDetermined, requestedStatus: .authorized)
    let service = PermissionService(microphoneProvider: provider)

    let firstResult = await service.authorizeFirstRecordingDeviceTouch()
    let secondResult = await service.authorizeFirstRecordingDeviceTouch()

    #expect(firstResult == true)
    #expect(secondResult == true)
    #expect(service.hasTouchedRecordingDevice == true)
    #expect(service.microphoneStatus == .authorized)
    #expect(provider.requestCount == 1)
}

@MainActor
@Test func deniedRecordingDevicePermissionIsCachedWithoutReprompting() async {
    let provider = FakeMicrophonePermissionProvider(initialStatus: .notDetermined, requestedStatus: .denied)
    let service = PermissionService(microphoneProvider: provider)

    let firstResult = await service.authorizeFirstRecordingDeviceTouch()
    let secondResult = await service.authorizeFirstRecordingDeviceTouch()

    #expect(firstResult == false)
    #expect(secondResult == false)
    #expect(service.hasTouchedRecordingDevice == true)
    #expect(service.microphoneStatus == .denied)
    #expect(provider.requestCount == 1)
}

private final class FakeMicrophonePermissionProvider: MicrophonePermissionProvider {
    private var status: AVAuthorizationStatus
    private let requestedStatus: AVAuthorizationStatus
    private(set) var requestCount = 0

    init(initialStatus: AVAuthorizationStatus, requestedStatus: AVAuthorizationStatus) {
        status = initialStatus
        self.requestedStatus = requestedStatus
    }

    func currentStatus() -> AVAuthorizationStatus {
        status
    }

    func requestAccess() async -> AVAuthorizationStatus {
        requestCount += 1
        status = requestedStatus
        return status
    }
}

private struct FakeFactCheckService: FactCheckService {
    func factCheck(sentence: String, llm: LLMEndpointConfiguration, promptTemplate: String) async throws -> FactCheckResult {
        FactCheckResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Test result."
        )
    }
}
