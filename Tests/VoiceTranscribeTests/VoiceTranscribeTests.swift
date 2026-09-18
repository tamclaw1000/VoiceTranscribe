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
@Test func defaultTranscriptionEngineIsAppleSpeech() {
    #expect(AppSettings.defaultTranscriptionEngine == .appleSpeech)
}

@MainActor
@Test func promptTemplatesControlEffectiveAIProcessing() {
    let settings = AppSettings()

    settings.aiPromptTemplates = [
        AIPromptTemplateConfiguration.defaultConfiguration(
            llmEndpointID: settings.selectedLLMEndpointID,
            isEnabled: false
        )
    ]
    #expect(settings.isFactCheckActive == false)

    var promptTemplate = settings.aiPromptTemplates[0]
    promptTemplate.isEnabled = true
    settings.updateAIPromptTemplate(promptTemplate)
    #expect(settings.isFactCheckActive == true)
}

@Test func promptTemplateSanitizerPreservesEditableSpaces() {
    let sanitized = AIPromptTemplateConfiguration.sanitized(
        [
            AIPromptTemplateConfiguration(
                id: "prompt",
                name: "Action Items ",
                llmEndpointID: "llm",
                template: "Summarize {{sentence}} with spaces "
            )
        ],
        availableLLMEndpointIDs: ["llm"],
        fallbackLLMEndpointID: "llm"
    )

    #expect(sanitized[0].name == "Action Items ")
    #expect(sanitized[0].template == "Summarize {{sentence}} with spaces ")
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

@MainActor
@Test func globalPromptLLMOverridesPerPromptModelSelection() {
    let local = LLMEndpointConfiguration(
        id: "local",
        name: "Local",
        endpoint: "http://localhost:11434",
        model: "local-model"
    )
    let global = LLMEndpointConfiguration(
        id: "global",
        name: "Global",
        provider: .openAICompatible,
        endpoint: "https://example.com",
        model: "global-model"
    )
    let settings = AppSettings()
    settings.llmEndpoints = [local, global]
    settings.selectedLLMEndpointID = local.id
    settings.globalPromptLLMEndpointID = global.id
    settings.useGlobalPromptLLM = true
    settings.aiPromptTemplates = [
        AIPromptTemplateConfiguration(
            id: "prompt",
            name: "Prompt",
            llmEndpointID: local.id,
            template: "Process {{sentence}}",
            isEnabled: true
        )
    ]

    #expect(settings.effectiveLLMEndpoint(for: settings.aiPromptTemplates[0]).id == global.id)
    #expect(settings.effectiveEnabledAIPromptTemplates[0].llmEndpointID == global.id)

    settings.useGlobalPromptLLM = false
    #expect(settings.effectiveLLMEndpoint(for: settings.aiPromptTemplates[0]).id == local.id)
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

@Test func llmEndpointConfigurationNormalizesEscapedSlashesFromStoredDefaults() {
    let sanitized = LLMEndpointConfiguration.sanitized([
        LLMEndpointConfiguration(
            id: "openrouter",
            name: "OpenRouter",
            provider: .openRouter,
            endpoint: #"https:\/\/openrouter.ai\/api\/v1"#,
            model: #"openrouter\/free"#
        )
    ])

    #expect(sanitized[0].endpoint == "https://openrouter.ai/api/v1")
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
    document.apply(TranscriptSegment(text: "hello", isFinal: true, speakerID: "Speaker 1"))
    document.apply(TranscriptSegment(text: "world", isFinal: false))

    #expect(document.finalized.map(\.text) == ["hello"])
    #expect(document.interim?.text == "world")
    #expect(document.plainText == "[Speaker 1] hello\nworld")

    document.apply(TranscriptSegment(text: "world", isFinal: true, speakerID: "Speaker 2"))
    #expect(document.finalized.map(\.text) == ["hello", "world"])
    #expect(document.interim == nil)
    #expect(document.plainText == "[Speaker 1] hello\n[Speaker 2] world")
}

@Test func transcriptDocumentUpdatesSpeakerNames() {
    var document = TranscriptDocument()
    document.apply(TranscriptSegment(text: "hello", isFinal: true, speakerID: "Speaker 1"))
    document.apply(TranscriptSegment(text: "working", isFinal: false, speakerID: "Speaker 1"))

    document.updateSpeakerName(speakerID: "Speaker 1", speakerName: "Dana")
    #expect(document.plainText == "[Dana] hello\n[Dana] working")

    document.updateSpeakerName(speakerID: "Speaker 1", speakerName: nil)
    #expect(document.plainText == "[Speaker 1] hello\n[Speaker 1] working")
}

@Test func transcriptDocumentUpdatesIndividualSegmentSpeaker() {
    let first = TranscriptSegment(text: "hello", isFinal: true, speakerID: "Speaker 1")
    let second = TranscriptSegment(text: "world", isFinal: true, speakerID: "Speaker 1")
    var document = TranscriptDocument()
    document.apply(first)
    document.apply(second)

    document.updateSegmentSpeaker(
        segmentID: second.id,
        speakerID: "Speaker 2",
        speakerName: "Dana"
    )

    #expect(document.plainText == "[Speaker 1] hello\n[Dana] world")
}

@Test @MainActor func fluidAudioStalePartialAfterFinalSegmentIsSuppressed() async throws {
    let service = FakeTranscriptionService(engineName: "FluidAudio Test")
    let coordinator = TranscriptionCoordinator(service: service)
    var currentSpeaker = "Speaker 1"
    coordinator.speakerProvider = {
        SpeakerAnnotation(speakerID: currentSpeaker, speakerName: nil)
    }

    try await coordinator.start()
    service.emit(TranscriptSegment(text: "This sentence is complete.", isFinal: true))
    try await Task.sleep(for: .milliseconds(20))
    currentSpeaker = "Speaker 2"
    service.emit(TranscriptSegment(text: "this sentence is complete", isFinal: false))
    try await Task.sleep(for: .milliseconds(20))

    #expect(coordinator.interimSegment == nil)
    #expect(coordinator.segments.map(\.text) == ["This sentence is complete."])
    #expect(coordinator.segments.compactMap(\.speakerLabel) == ["Speaker 1"])
}

@Test @MainActor func transcriptionCoordinatorUpdatesIndividualSegmentSpeaker() async throws {
    let service = FakeTranscriptionService(engineName: "Speaker Cycle Test")
    let coordinator = TranscriptionCoordinator(service: service)
    coordinator.speakerProvider = {
        SpeakerAnnotation(speakerID: "Speaker 1", speakerName: nil)
    }

    try await coordinator.start()
    service.emit(TranscriptSegment(text: "This speaker is wrong.", isFinal: true))
    try await Task.sleep(for: .milliseconds(20))
    let segmentID = try #require(coordinator.segments.first?.id)

    coordinator.updateSegmentSpeaker(
        segmentID: segmentID,
        speakerID: "Speaker 2",
        speakerName: "Dana"
    )

    #expect(coordinator.segments.map(\.speakerLabel) == ["Dana"])
    #expect(coordinator.transcriptText == "[Dana] This speaker is wrong.")
}

@Test func transcriptDocumentUsesVoiceIdentityWhenSpeakerIsUnnamed() {
    var document = TranscriptDocument()
    document.apply(TranscriptSegment(
        text: "hello",
        isFinal: true,
        speakerID: "Speaker 1",
        voiceID: "Voice 1",
        voiceName: "Voice 1",
        voiceConfidence: 0.91
    ))

    #expect(document.plainText == "[Voice 1] hello")

    document.updateSpeakerName(speakerID: "Speaker 1", speakerName: "Dana")
    #expect(document.plainText == "[Dana] hello")
}

@Test func transcriptDocumentNamesObservedVoiceTupleOnly() {
    var document = TranscriptDocument()
    document.apply(TranscriptSegment(
        text: "picard",
        isFinal: true,
        speakerID: "Speaker 1",
        voiceID: "Voice 1",
        voiceName: "Voice 1"
    ))
    document.apply(TranscriptSegment(
        text: "okona",
        isFinal: true,
        speakerID: "Speaker 1",
        voiceID: "Voice 7",
        voiceName: "Voice 7"
    ))

    document.updateObservedVoiceName(
        speakerID: "Speaker 1",
        voiceID: "Voice 7",
        speakerName: "Okona"
    )

    #expect(document.plainText == "[Voice 1] picard\n[Okona] okona")
}

@Test func transcriptDocumentUpdatesSegmentIdentityWithVoice() {
    let segment = TranscriptSegment(text: "wrong speaker", isFinal: true, speakerID: "Speaker 1")
    var document = TranscriptDocument()
    document.apply(segment)

    document.updateSegmentIdentity(
        segmentID: segment.id,
        speakerID: "Speaker 3",
        speakerName: "Okona",
        voiceID: "Voice 5",
        voiceName: "Voice 5",
        voiceConfidence: nil
    )

    #expect(document.finalized[0].speakerID == "Speaker 3")
    #expect(document.finalized[0].voiceID == "Voice 5")
    #expect(document.plainText == "[Okona] wrong speaker")
}

@Test func voiceIdentityMatcherCreatesAndMatchesSessionVoices() {
    var matcher = VoiceIdentityMatcher(matchThreshold: 0.70, updateThreshold: 0.82)

    let first = matcher.identify(embedding: [1, 0, 0], duration: 2.5)
    let second = matcher.identify(embedding: [0.96, 0.1, 0], duration: 3.0)
    let third = matcher.identify(embedding: [0, 1, 0], duration: 2.5)

    #expect(first.voiceID == "Voice 1")
    #expect(first.confidence == nil)
    #expect(second.voiceID == "Voice 1")
    #expect((second.confidence ?? 0) > 0.9)
    #expect(third.voiceID == "Voice 2")
    #expect(matcher.profiles.count == 2)
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
            promptStates: [
                MarkdownExportPromptState(
                    promptName: "Action Items",
                    state: "- Call Dana\n- Send the deck"
                ),
                MarkdownExportPromptState(
                    promptName: "Empty State",
                    state: "   "
                )
            ],
            factCheckPrompt: "Fact-check {{sentence}}",
            summaryPrompt: "Summarize this recording.",
            audioURL: URL(fileURLWithPath: "/tmp/recording.m4a"),
            transcriptURL: URL(fileURLWithPath: "/tmp/recording.txt"),
            metadataURL: URL(fileURLWithPath: "/tmp/recording.json")
        ),
        finalizedSegments: [
            TranscriptSegment(
                text: "The Earth orbits the Sun.",
                timestamp: start,
                isFinal: true,
                speakerID: "Speaker 1"
            ),
            TranscriptSegment(text: "Pipe | characters are escaped.", timestamp: second, isFinal: true)
        ],
        speakerSegments: [
            SpeakerDiarizationSegment(
                speakerID: "Speaker 1",
                startTime: 0,
                endTime: 3,
                confidence: 0.82
            )
        ],
        factChecks: [factCheck],
        summaryParagraphs: ["The recording discusses astronomy."],
        calendar: calendar
    )

    #expect(markdown.contains("# DETAILS"))
    #expect(markdown.contains("- Location of recording: Not specified"))
    #expect(markdown.contains("# RECORDING"))
    #expect(markdown.contains("| date time | length | speaker | text | AI result |"))
    #expect(markdown.contains("| 2026-05-28 07:33:17 | 0:03 | Speaker 1 | The Earth orbits the Sun. | AI Processing: Verdict: Supported<br>Confidence: High<br>This is a basic astronomical fact. |"))
    #expect(markdown.contains("Pipe \\| characters are escaped."))
    #expect(markdown.contains("# SPEAKERS"))
    #expect(markdown.contains("| 0:00 | 0:03 | Speaker 1 | 0.82 |"))
    #expect(markdown.contains("# SUMMARY"))
    #expect(markdown.contains("The recording discusses astronomy."))
    #expect(!markdown.contains("# FACT CHECKS"))
    #expect(markdown.contains("# AI RESULTS"))
    #expect(markdown.contains("- AI processing enabled: Yes"))
    #expect(markdown.contains("- LLM provider: Ollama"))
    #expect(markdown.contains("- LLM model: igorls/gemma-4-12B-it-heretic-GGUF"))
    #expect(markdown.contains("## Summary Result"))
    #expect(!markdown.contains("## Fact-Check Results"))
    #expect(markdown.contains("## Prompt States"))
    #expect(markdown.contains("### Action Items"))
    #expect(markdown.contains("- Call Dana\n- Send the deck"))
    #expect(!markdown.contains("### Empty State"))
    #expect(markdown.contains("## AI Processing Prompts"))
    #expect(markdown.contains("AI Processing: Verdict: Supported"))
    #expect(markdown.contains("## Summary Prompt"))
    #expect(markdown.contains("Summarize this recording."))
    #expect(markdown.contains("# FILES"))
    #expect(markdown.contains("`/tmp/recording.m4a`"))
}

@Test func markdownExportIncludesJevResults() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)
    let end = start.addingTimeInterval(7)
    let jevResult = JevResultItem(
        sentence: "The export button crashes.",
        queryID: "urgency",
        queryName: "Urgency",
        batchGroupID: "batch-1",
        state: .completed(.noul(probability: 0.82)),
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
            aiEnabled: false,
            factCheckEnabled: false,
            llmName: "Local Ollama",
            llmProvider: "Ollama",
            llmEndpoint: "http://localhost:11434",
            llmModel: "igorls/gemma-4-12B-it-heretic-GGUF",
            factCheckPrompt: "",
            summaryPrompt: "Summarize this recording.",
            jevEnabled: true,
            jevBaseURL: "https://api.typesafe.ai",
            jevModel: "jev-latest",
            jevQueryDetails: "Urgency [enabled] (Noul (yes/no)):\nDoes this express urgency?"
        ),
        finalizedSegments: [
            TranscriptSegment(
                text: "The export button crashes.",
                timestamp: start,
                isFinal: true,
                speakerID: "Speaker 1"
            )
        ],
        factChecks: [],
        jevResults: [jevResult],
        summaryParagraphs: [],
        calendar: calendar
    )

    #expect(markdown.contains("| date time | length | speaker | text | AI result | Jev result |"))
    #expect(markdown.contains("Urgency: P(yes): 82% (confident)"))
    #expect(markdown.contains("# JEV RESULTS"))
    #expect(markdown.contains("- Jev enabled: Yes"))
    #expect(markdown.contains("- Jev base URL: https://api.typesafe.ai"))
    #expect(markdown.contains("- Jev model: jev-latest"))
    #expect(markdown.contains("## Jev Queries"))
    #expect(markdown.contains("Urgency [enabled] (Noul (yes/no)):\nDoes this express urgency?"))
}

@Test func markdownExportUsesCustomSpeakerNames() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)

    let markdown = MarkdownExportService.makeDocument(
        context: MarkdownExportContext(
            sourceName: "Test Mic",
            location: "",
            startDate: start,
            endDate: start.addingTimeInterval(4),
            exportedAt: start,
            transcriptionEngine: "Apple Speech",
            aiEnabled: false,
            factCheckEnabled: false,
            llmName: "",
            llmProvider: "",
            llmEndpoint: "",
            llmModel: "",
            factCheckPrompt: "",
            summaryPrompt: ""
        ),
        finalizedSegments: [
            TranscriptSegment(
                text: "Hello there.",
                timestamp: start,
                isFinal: true,
                speakerID: "Speaker 1",
                speakerName: "Dana"
            )
        ],
        speakerSegments: [
            SpeakerDiarizationSegment(
                speakerID: "Speaker 1",
                speakerName: "Dana",
                startTime: 0,
                endTime: 4
            )
        ],
        factChecks: [],
        summaryParagraphs: [],
        calendar: calendar
    )

    #expect(markdown.contains("| 2026-05-28 07:33:17 | 0:04 | Dana | Hello there. |  |"))
    #expect(markdown.contains("| 0:00 | 0:04 | Dana |  |"))
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

@Test func factCheckPromptTemplateReplacesConversationPlaceholderWithTimestampedTranscript() {
    let base = Calendar.current.startOfDay(for: Date())
    let context = FactCheckPromptContext(entries: [
        .init(timestamp: base, text: "First sentence."),
        .init(timestamp: base.addingTimeInterval(61), text: "Second sentence.")
    ])

    let prompt = FactCheckPrompt.render(
        template: "Conversation:\n{{conversation}}\nCurrent:\n{{sentence}}",
        sentence: "Second sentence.",
        context: context
    )

    #expect(prompt.contains("[00:00:00] First sentence."))
    #expect(prompt.contains("[00:01:01] Second sentence."))
    #expect(prompt.contains("Current:\nSecond sentence."))
    #expect(!prompt.contains("{{conversation}}"))
}

@Test func factCheckPromptTemplateReplacesLastNPlaceholdersWithRecentTimestampedTranscript() {
    let base = Calendar.current.startOfDay(for: Date())
    let context = FactCheckPromptContext(entries: (1...12).map { index in
        .init(
            timestamp: base.addingTimeInterval(TimeInterval(index)),
            text: "Sentence \(index)."
        )
    })

    let prompt = FactCheckPrompt.render(
        template: "Last3:\n{{last-3}}\nLast5:\n{{last-5}}\nLast10:\n{{last-10}}",
        sentence: "Sentence 12.",
        context: context
    )

    #expect(prompt.contains("[00:00:10] Sentence 10."))
    #expect(prompt.contains("[00:00:11] Sentence 11."))
    #expect(prompt.contains("[00:00:12] Sentence 12."))
    #expect(!prompt.contains("[00:00:09] Sentence 9.\nLast3"))
    #expect(prompt.contains("[00:00:08] Sentence 8."))
    #expect(!prompt.contains("[00:00:02] Sentence 2."))
    #expect(!prompt.contains("{{last-3}}"))
    #expect(!prompt.contains("{{last-5}}"))
    #expect(!prompt.contains("{{last-10}}"))
}

@Test func factCheckPromptTemplateAcceptsMalformedLast3Placeholder() {
    let base = Calendar.current.startOfDay(for: Date())
    let context = FactCheckPromptContext(entries: [
        .init(timestamp: base.addingTimeInterval(1), text: "One."),
        .init(timestamp: base.addingTimeInterval(2), text: "Two."),
        .init(timestamp: base.addingTimeInterval(3), text: "Three.")
    ])

    let prompt = FactCheckPrompt.render(
        template: "{{last-3}",
        sentence: "Three.",
        context: context
    )

    #expect(prompt.contains("[00:00:01] One."))
    #expect(prompt.contains("[00:00:03] Three."))
    #expect(!prompt.contains("{{last-3}"))
}

@Test func factCheckPromptContextSplitsSegmentsIntoTimestampedSentences() {
    let timestamp = Calendar.current.startOfDay(for: Date()).addingTimeInterval(42)
    let context = FactCheckPromptContext(segments: [
        TranscriptSegment(text: "One. Two.", timestamp: timestamp, isFinal: true)
    ])

    #expect(context.formattedConversation() == "[00:00:42] One.\n[00:00:42] Two.")
}

@Test func factCheckPromptTemplateReplacesPromptStatePlaceholder() {
    let context = FactCheckPromptContext(
        entries: [.init(timestamp: Date(), text: "New item.")],
        promptState: "- Existing item"
    )

    let prompt = FactCheckPrompt.render(
        template: "Update state:\n{{prompt-state}}\nFrom:\n{{sentence}}",
        sentence: "New item.",
        context: context
    )

    #expect(prompt.contains("Update state:\n- Existing item"))
    #expect(prompt.contains("From:\nNew item."))
    #expect(!prompt.contains("{{prompt-state}}"))
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
    let promptTemplate = AIPromptTemplateConfiguration.defaultConfiguration(llmEndpointID: llm.id)

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "  The Earth orbits the Sun.  ", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
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
    let promptTemplate = AIPromptTemplateConfiguration.defaultConfiguration(llmEndpointID: llm.id)

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: false,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )

    #expect(coordinator.items.isEmpty)
}

@MainActor
@Test func factCheckCoordinatorQueuesOneItemPerEnabledPrompt() async {
    let service = FakeFactCheckService()
    let coordinator = FactCheckCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )
    let firstPrompt = AIPromptTemplateConfiguration(
        id: "first",
        name: "Verifier",
        llmEndpointID: llm.id,
        template: "Verify {{sentence}}",
        isEnabled: true
    )
    let secondPrompt = AIPromptTemplateConfiguration(
        id: "second",
        name: "Risk Scan",
        llmEndpointID: llm.id,
        template: "Find risk in {{sentence}}",
        isEnabled: true
    )

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: true,
        promptTemplates: [firstPrompt, secondPrompt],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(coordinator.items.count == 2)
    #expect(Set(coordinator.items.map(\.promptTemplateName)) == ["Verifier", "Risk Scan"])
}

@MainActor
@Test func factCheckCoordinatorBatchesPromptQuestionsWhenEnabled() async {
    let probe = BatchFactCheckProbe()
    let service = BatchProbeFactCheckService(probe: probe)
    let coordinator = FactCheckCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )
    let prompts = (1...3).map { index in
        AIPromptTemplateConfiguration(
            id: "prompt-\(index)",
            name: "Question \(index)",
            llmEndpointID: llm.id,
            template: "Answer question \(index): {{sentence}}",
            isEnabled: true
        )
    }

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: true,
        promptTemplates: prompts,
        llmEndpoints: [llm],
        fallbackLLM: llm,
        batchPrompts: true
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    let snapshot = await probe.snapshot()
    #expect(snapshot.singleCalls == 0)
    #expect(snapshot.batchCalls == 1)
    #expect(snapshot.batchSizes == [3])
    #expect(coordinator.items.count == 3)
    #expect(coordinator.items.allSatisfy {
        if case .completed = $0.state {
            return true
        }
        return false
    })
}

@MainActor
@Test func factCheckCoordinatorAccruesPromptStateBetweenPromptCalls() async {
    let probe = PromptStateProbe()
    let service = PromptStateFactCheckService(probe: probe)
    let coordinator = FactCheckCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )
    let promptTemplate = AIPromptTemplateConfiguration(
        id: "action-items",
        name: "Action Items",
        llmEndpointID: llm.id,
        template: "Update prompt-state=\"{{prompt-state}}\" from \"{{sentence}}\".",
        isEnabled: true
    )

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "First action. Second action.", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )

    try? await Task.sleep(nanoseconds: 140_000_000)

    let states = await probe.states()
    #expect(states.count == 2)
    #expect(states[0] == "")
    #expect(states[1] == "state-1")
}

@MainActor
@Test func factCheckCoordinatorLimitsConcurrentRequestsToThree() async {
    let probe = ConcurrentFactCheckProbe()
    let service = SlowFactCheckService(probe: probe)
    let coordinator = FactCheckCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )
    let promptTemplate = AIPromptTemplateConfiguration.defaultConfiguration(llmEndpointID: llm.id)

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "One. Two. Three. Four. Five.", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )

    try? await Task.sleep(nanoseconds: 260_000_000)

    let maxObserved = await probe.maxObserved()
    #expect(maxObserved > 1)
    #expect(maxObserved <= 3)
    #expect(coordinator.items.count == 5)
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

private final class FakeTranscriptionService: TranscriptionService {
    let engineName: String
    private var onSegment: ((TranscriptSegment) -> Void)?

    init(engineName: String) {
        self.engineName = engineName
    }

    func start(onSegment: @escaping (TranscriptSegment) -> Void) async throws {
        self.onSegment = onSegment
    }

    func append(_ buffer: AVAudioPCMBuffer) {}

    func stop() {}

    func emit(_ segment: TranscriptSegment) {
        onSegment?(segment)
    }
}

private struct FakeFactCheckService: FactCheckService {
    func factCheck(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: FactCheckPromptContext
    ) async throws -> FactCheckResult {
        FactCheckResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Test result."
        )
    }
}

private actor ConcurrentFactCheckProbe {
    private var current = 0
    private var maximum = 0

    func started() {
        current += 1
        maximum = max(maximum, current)
    }

    func finished() {
        current = max(0, current - 1)
    }

    func maxObserved() -> Int {
        maximum
    }
}

private actor BatchFactCheckProbe {
    private var singleCalls = 0
    private var batchCalls = 0
    private var batchSizes: [Int] = []

    func recordSingleCall() {
        singleCalls += 1
    }

    func recordBatchCall(size: Int) {
        batchCalls += 1
        batchSizes.append(size)
    }

    func snapshot() -> (singleCalls: Int, batchCalls: Int, batchSizes: [Int]) {
        (singleCalls, batchCalls, batchSizes)
    }
}

private struct BatchProbeFactCheckService: FactCheckService {
    let probe: BatchFactCheckProbe

    func factCheck(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: FactCheckPromptContext
    ) async throws -> FactCheckResult {
        await probe.recordSingleCall()
        return FactCheckResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Single result."
        )
    }

    func factCheckBatch(items: [FactCheckItem]) async throws -> [UUID: FactCheckResult] {
        await probe.recordBatchCall(size: items.count)
        return Dictionary(uniqueKeysWithValues: items.map { item in
            (
                item.id,
                FactCheckResult(
                    sentence: item.sentence,
                    verdict: .supported,
                    confidence: .high,
                    explanation: "Batch result for \(item.promptTemplateName)."
                )
            )
        })
    }
}

private actor PromptStateProbe {
    private var receivedStates: [String] = []

    func record(_ state: String) -> Int {
        receivedStates.append(state)
        return receivedStates.count
    }

    func states() -> [String] {
        receivedStates
    }
}

private struct PromptStateFactCheckService: FactCheckService {
    let probe: PromptStateProbe

    func factCheck(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: FactCheckPromptContext
    ) async throws -> FactCheckResult {
        let index = await probe.record(promptContext.promptState)
        try? await Task.sleep(nanoseconds: 20_000_000)
        return FactCheckResult(
            sentence: sentence,
            verdict: .unverifiable,
            confidence: .low,
            explanation: "state-\(index)",
            rawResponse: "state-\(index)"
        )
    }
}

private struct SlowFactCheckService: FactCheckService {
    let probe: ConcurrentFactCheckProbe

    func factCheck(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: FactCheckPromptContext
    ) async throws -> FactCheckResult {
        await probe.started()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await probe.finished()
        return FactCheckResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Test result."
        )
    }
}

// MARK: - Jev

@Test func jevQuerySanitizerFillsBlankNamesAndDedupesIDs() {
    let queries = [
        JevQueryConfiguration(id: "", name: "  ", primitiveType: .noul),
        JevQueryConfiguration(id: "dup", name: "Second", primitiveType: .choice),
        JevQueryConfiguration(id: "dup", name: "Third", primitiveType: .score)
    ]

    let sanitized = JevQueryConfiguration.sanitized(queries)

    #expect(sanitized.count == 3)
    #expect(sanitized[0].name == "Jev Query 1")
    #expect(Set(sanitized.map(\.id)).count == 3)
}

@Test func jevQueryIsRunnableRequiresEnoughCriteria() {
    let noul = JevQueryConfiguration(name: "Urgency", primitiveType: .noul)
    #expect(noul.isRunnable)

    var choice = JevQueryConfiguration(name: "Team", primitiveType: .choice)
    #expect(!choice.isRunnable)
    choice.choiceCriteria = [JevChoiceCriterion(label: "billing"), JevChoiceCriterion(label: "shipping")]
    #expect(choice.isRunnable)

    var score = JevQueryConfiguration(name: "Severity", primitiveType: .score)
    #expect(!score.isRunnable)
    score.scoreCriteria = ["Cosmetic", "Blocking"]
    #expect(score.isRunnable)
}

@Test func jevQuestionWireEncodesCriteriaShapePerPrimitiveType() throws {
    let noul = JevQueryConfiguration(
        name: "Urgency",
        primitiveType: .noul,
        instructions: "Does this express urgency?",
        noulTrueDescription: "Mentions a deadline",
        noulFalseDescription: "No time pressure"
    )
    let choice = JevQueryConfiguration(
        name: "Team",
        primitiveType: .choice,
        instructions: "Which team should handle this?",
        choiceCriteria: [
            JevChoiceCriterion(label: "billing", description: "Charges and invoices"),
            JevChoiceCriterion(label: "shipping", description: "Delivery status")
        ]
    )
    let score = JevQueryConfiguration(
        name: "Severity",
        primitiveType: .score,
        instructions: "How severe is this?",
        scoreCriteria: ["Cosmetic", "Degraded", "Blocking"]
    )

    let request = JevSystemOneRequest(
        state: "The export button crashes.",
        model: "jev-latest",
        questions: [
            "noul": JevQuestionWire(query: noul),
            "choice": JevQuestionWire(query: choice),
            "score": JevQuestionWire(query: score)
        ]
    )
    let data = try JSONEncoder().encode(request)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let questions = try #require(json["questions"] as? [String: Any])

    let noulPayload = try #require(questions["noul"] as? [String: Any])
    #expect(noulPayload["type"] as? String == "noul")
    let noulCriteria = try #require(noulPayload["criteria"] as? [String: String])
    #expect(noulCriteria["true"] == "Mentions a deadline")
    #expect(noulCriteria["false"] == "No time pressure")

    let choicePayload = try #require(questions["choice"] as? [String: Any])
    let choiceCriteria = try #require(choicePayload["criteria"] as? [String: String])
    #expect(choiceCriteria["billing"] == "Charges and invoices")
    #expect(choiceCriteria["shipping"] == "Delivery status")

    let scorePayload = try #require(questions["score"] as? [String: Any])
    let scoreCriteria = try #require(scorePayload["criteria"] as? [String])
    #expect(scoreCriteria == ["Cosmetic", "Degraded", "Blocking"])
}

@Test func jevAnswerWireDecodesEachPrimitiveType() throws {
    let raw = """
    {
      "model": "jev-latest",
      "usage": {"input_tokens": 10, "output_tokens": 5},
      "answers": {
        "noul": {"type": "noul", "noul": 0.82},
        "choice": {"type": "choice", "choice": "billing", "confidence": 0.74, "probabilities": {"billing": 0.74, "shipping": 0.26}},
        "score": {"type": "score", "score": 1.6, "confidence": 0.68, "legend": {"0": "Cosmetic", "1": "Degraded", "2": "Blocking"}, "probabilities": {"0": 0.1, "1": 0.3, "2": 0.6}}
      }
    }
    """
    let decoded = try JSONDecoder().decode(JevSystemOneResponseWire.self, from: Data(raw.utf8))

    let noulAnswer = try #require(decoded.answers["noul"]?.toAnswer())
    #expect(noulAnswer == .noul(probability: 0.82))

    let choiceAnswer = try #require(decoded.answers["choice"]?.toAnswer())
    #expect(choiceAnswer == .choice(selected: "billing", confidence: 0.74, probabilities: ["billing": 0.74, "shipping": 0.26]))

    let scoreAnswer = try #require(decoded.answers["score"]?.toAnswer())
    #expect(scoreAnswer == .score(
        value: 1.6,
        confidence: 0.68,
        legend: ["0": "Cosmetic", "1": "Degraded", "2": "Blocking"],
        probabilities: ["0": 0.1, "1": 0.3, "2": 0.6]
    ))
}

@MainActor
@Test func jevCoordinatorBatchesAllEnabledQueriesForOneSentenceIntoOneCall() async {
    let probe = JevBatchProbe()
    let coordinator = JevCoordinator(service: BatchProbeJevService(probe: probe))
    let queries = [
        JevQueryConfiguration(name: "Urgency", primitiveType: .noul),
        JevQueryConfiguration(
            name: "Team",
            primitiveType: .choice,
            choiceCriteria: [JevChoiceCriterion(label: "billing"), JevChoiceCriterion(label: "shipping")]
        )
    ]

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The export button crashes.", isFinal: true),
        enabled: true,
        queries: queries,
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(coordinator.items.count == 2)
    #expect(await probe.callCount() == 1)
    #expect(await probe.queryCountOfLastCall() == 2)
}

@MainActor
@Test func jevCoordinatorDedupesResubmittedSentencePerQuery() async {
    let probe = JevBatchProbe()
    let coordinator = JevCoordinator(service: BatchProbeJevService(probe: probe))
    let query = JevQueryConfiguration(name: "Urgency", primitiveType: .noul)

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The export button crashes.", isFinal: true),
        enabled: true,
        queries: [query],
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "  The export button crashes.  ", isFinal: true),
        enabled: true,
        queries: [query],
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(coordinator.items.count == 1)
}

private actor JevBatchProbe {
    private var calls = 0
    private var lastQueryCount = 0

    func record(queryCount: Int) {
        calls += 1
        lastQueryCount = queryCount
    }

    func callCount() -> Int { calls }
    func queryCountOfLastCall() -> Int { lastQueryCount }
}

private struct BatchProbeJevService: JevService {
    let probe: JevBatchProbe

    func evaluate(
        sentence: String,
        queries: [JevQueryConfiguration],
        apiKey: String,
        baseURL: String,
        model: String
    ) async throws -> [String: JevAnswer] {
        await probe.record(queryCount: queries.count)
        return Dictionary(uniqueKeysWithValues: queries.map { query in
            (query.id, JevAnswer.noul(probability: 0.5))
        })
    }
}
