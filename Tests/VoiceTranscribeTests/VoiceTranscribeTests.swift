import Foundation
import AVFoundation
import Combine
import Speech
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
    #expect(settings.isAIPromptActive == false)

    var promptTemplate = settings.aiPromptTemplates[0]
    promptTemplate.isEnabled = true
    settings.updateAIPromptTemplate(promptTemplate)
    #expect(settings.isAIPromptActive == true)
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
    coordinator.speakerProvider = { _ in
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
    coordinator.speakerProvider = { _ in
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

    #expect(first?.voiceID == "Voice 1")
    #expect(first?.confidence == nil)
    #expect(second?.voiceID == "Voice 1")
    #expect((second?.confidence ?? 0) > 0.9)
    #expect(third?.voiceID == "Voice 2")
    #expect(matcher.profiles.count == 2)
}

@Test func voiceMatcherLeavesAmbiguousAndShortNewSamplesUnidentified() {
    var matcher = VoiceIdentityMatcher()
    let first = matcher.identify(embedding: [1, 0, 0], duration: 3)
    let second = matcher.identify(embedding: [0, 1, 0], duration: 3)
    let ambiguous = matcher.identify(embedding: [0.72, 0.70, 0], duration: 3)
    let borderline = matcher.identify(embedding: [0.6, 0.6, 0.5], duration: 3)
    let tooShort = matcher.identify(embedding: [0, 0, 1], duration: 2.1)
    #expect(first?.voiceID == "Voice 1")
    #expect(second?.voiceID == "Voice 2")
    #expect(ambiguous == nil)
    #expect(borderline == nil)
    #expect(tooShort == nil)
    #expect(matcher.profiles.count == 2)
    let third = matcher.identify(embedding: [0, 0, 1], duration: 3)
    #expect(third?.voiceID == "Voice 3")
}

@Test func sessionIdentityAssignmentsArePerRangeAndManualWins() throws {
    var directory = SessionIdentityDirectory()
    directory.reconcile([
        SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 1),
        SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 2, endTime: 3)
    ])
    let firstID = try #require(directory.range(at: 0.5)?.id)
    let secondID = try #require(directory.range(at: 2.5)?.id)
    #expect(directory.people.isEmpty)
    #expect(directory.personLabel(for: try #require(directory.range(id: firstID))) == "Unidentified audio")

    let manual = directory.createPerson()
    directory.rename(personID: manual.id, to: "Dana")
    directory.assign([firstID], to: manual.id)
    directory.assignAutomatic(voiceID: "Voice 1", confidence: 0.91, to: firstID)
    directory.assignAutomatic(voiceID: "Voice 1", confidence: 0.89, to: secondID)
    #expect(directory.range(id: firstID)?.personID == manual.id)
    #expect(directory.range(id: firstID)?.source == .manual)
    #expect(directory.range(id: secondID)?.personID != manual.id)
    #expect(directory.range(id: secondID)?.source == .automatic)
}

@Test func sessionIdentityMergeIsExplicitAndUndoable() throws {
    var directory = SessionIdentityDirectory()
    directory.reconcile([
        SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 1),
        SpeakerDiarizationSegment(speakerID: "Speaker 2", startTime: 2, endTime: 3)
    ])
    let firstID = try #require(directory.range(at: 0.5)?.id)
    let secondID = try #require(directory.range(at: 2.5)?.id)
    let first = directory.createPerson()
    let second = directory.createPerson()
    directory.rename(personID: first.id, to: "Dana")
    directory.rename(personID: second.id, to: "Dana")
    directory.assign([firstID], to: first.id)
    directory.assign([secondID], to: second.id)
    #expect(directory.range(id: firstID)?.personID != directory.range(id: secondID)?.personID)
    directory.merge(second.id, into: first.id)
    #expect(directory.range(id: secondID)?.personID == first.id)
    #expect(directory.people.count == 1)
    let undone = directory.undo()
    #expect(undone)
    #expect(directory.range(id: secondID)?.personID == second.id)
}

@Test func revisedRangeKeepsStableIDOnlyWhenItStillCoversTheSameAudio() throws {
    var directory = SessionIdentityDirectory()
    directory.reconcile([SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 1)])
    let id = try #require(directory.range(at: 0.5)?.id)
    let person = directory.createPerson()
    directory.assign([id], to: person.id)
    directory.reconcile([SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 3)])
    #expect(directory.range(at: 2.5)?.id == id)
    directory.reconcile([
        SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 1),
        SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 1, endTime: 3)
    ])
    #expect(directory.ranges.allSatisfy { $0.id != id })
    #expect(directory.unresolvedRanges.contains { $0.id == id })
}

@Test func transcriptResolvesLateRangeWithoutOverwritingRowCorrection() throws {
    var directory = SessionIdentityDirectory()
    var document = TranscriptDocument()
    let row = TranscriptSegment(text: "hello", isFinal: true, audioOffset: 0.5)
    document.apply(row)
    directory.reconcile([SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 3)])
    let rangeID = try #require(directory.range(at: 0.5)?.id)
    directory.assignAutomatic(voiceID: "Voice 1", confidence: 0.93, to: rangeID)
    document.synchronizePeople(directory)
    #expect(document.finalized[0].diarizationRangeID == rangeID)
    #expect(document.finalized[0].voiceID == "Voice 1")

    let corrected = directory.createPerson()
    directory.rename(personID: corrected.id, to: "Lee")
    document.updateSegmentPerson(segmentID: row.id, personID: corrected.id, name: "Lee")
    directory.assignAutomatic(voiceID: "Voice 2", confidence: 0.95, to: rangeID)
    document.synchronizePeople(directory)
    #expect(document.finalized[0].speakerName == "Lee")
    #expect(document.finalized[0].personID == corrected.id)
    #expect(document.finalized[0].diarizationRangeID == nil)
}

@Test func transcriptRebindsWhenDiarizationReplacesItsRange() throws {
    var directory = SessionIdentityDirectory()
    directory.reconcile([SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 3)])
    let oldID = try #require(directory.range(at: 1.5)?.id)
    let row = TranscriptSegment(
        text: "next speaker", isFinal: true, audioOffset: 1.5,
        diarizationRangeID: oldID
    )
    directory.reconcile([
        SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 1),
        SpeakerDiarizationSegment(speakerID: "Speaker 2", startTime: 1, endTime: 3)
    ])
    let rebound = directory.resolved(row)
    #expect(rebound.diarizationRangeID != oldID)
    #expect(rebound.speakerID == "Speaker 2")
}

@Test func rowOnlyCorrectionFollowsPersonRenameMergeAndUndo() {
    var directory = SessionIdentityDirectory()
    let first = directory.createPerson()
    let second = directory.createPerson()
    var document = TranscriptDocument()
    let row = TranscriptSegment(text: "hello", isFinal: true)
    document.apply(row)
    document.updateSegmentPerson(segmentID: row.id, personID: second.id, name: second.label)

    directory.rename(personID: second.id, to: "Dana")
    document.synchronizePeople(directory)
    #expect(document.finalized[0].speakerName == "Dana")
    directory.merge(second.id, into: first.id)
    document.synchronizePeople(directory)
    #expect(document.finalized[0].personID == first.id)
    let undone = directory.undo()
    document.synchronizePeople(directory)
    #expect(undone)
    #expect(document.finalized[0].personID == second.id)
    #expect(document.finalized[0].speakerName == "Dana")
}

@Test func undoManualAssignmentKeepsLaterAutomaticEvidence() throws {
    var directory = SessionIdentityDirectory()
    directory.reconcile([SpeakerDiarizationSegment(speakerID: "Speaker 1", startTime: 0, endTime: 3)])
    let rangeID = try #require(directory.range(at: 0.5)?.id)
    let manual = directory.createPerson()
    directory.assign([rangeID], to: manual.id)
    directory.assignAutomatic(voiceID: "Voice 1", confidence: nil, to: rangeID)
    let automaticID = try #require(directory.range(id: rangeID)?.automaticPersonID)
    let undone = directory.undo()
    #expect(undone)
    #expect(directory.range(id: rangeID)?.personID == automaticID)
    #expect(directory.person(id: automaticID) != nil)
}

// MARK: - Speaker/Voice pair in the transcript display

@Test func speakerVoicePairKeepsBothIdentitiesWhenARowIsNamed() {
    // A name used to be the whole story: `speakerLabel` returns it and the pair vanished, which is
    // the gap this accessor exists to close.
    let named = TranscriptSegment(
        text: "one",
        isFinal: true,
        speakerID: "Speaker 3",
        speakerName: "Dana",
        voiceID: "Voice 1"
    )
    #expect(named.speakerLabel == "Dana")
    #expect(named.speakerVoicePair == "Speaker 3 / Voice 1")

    // Unnamed was little better: one half showed and the other was hidden. A real session logged
    // 123 rows like this, labelled "Voice N" with no sign of the speaker they belonged to.
    let unnamed = TranscriptSegment(
        text: "two",
        isFinal: true,
        speakerID: "Speaker 3",
        voiceID: "Voice 1"
    )
    #expect(unnamed.speakerLabel == "Voice 1")
    #expect(unnamed.speakerVoicePair == "Speaker 3 / Voice 1")
}

@Test func speakerVoicePairFallsBackToWhicheverHalfIsKnown() {
    let speakerOnly = TranscriptSegment(text: "one", isFinal: true, speakerID: "Speaker 3")
    #expect(speakerOnly.speakerVoicePair == "Speaker 3")

    let voiceOnly = TranscriptSegment(text: "two", isFinal: true, voiceID: "Voice 1")
    #expect(voiceOnly.speakerVoicePair == "Voice 1")

    // Nothing detected yet — and blank strings are nothing, not identities.
    #expect(TranscriptSegment(text: "three", isFinal: true).speakerVoicePair == nil)
    #expect(TranscriptSegment(text: "four", isFinal: true, speakerID: "  ", voiceID: "").speakerVoicePair == nil)
}

@Test func markdownExportKeepsThePairOnNamedRows() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)

    let markdown = MarkdownExportService.makeDocument(
        context: MarkdownExportContext(
            sourceName: "Built-in Microphone",
            location: "",
            startDate: start,
            endDate: start.addingTimeInterval(6),
            exportedAt: start.addingTimeInterval(6),
            transcriptionEngine: "Apple SpeechTranscriber",
            aiPromptEnabled: false,
            llmName: "",
            llmProvider: "",
            llmEndpoint: "",
            llmModel: "",
            aiPromptPrompt: "",
            summaryPrompt: "",
            audioURL: nil,
            transcriptURL: nil,
            metadataURL: nil
        ),
        finalizedSegments: [
            TranscriptSegment(
                text: "Named row.",
                timestamp: start,
                isFinal: true,
                speakerID: "Speaker 3",
                speakerName: "Dana",
                voiceID: "Voice 1"
            ),
            TranscriptSegment(
                text: "Unnamed row.",
                timestamp: start.addingTimeInterval(3),
                isFinal: true,
                speakerID: "Speaker 3",
                voiceID: "Voice 1"
            )
        ],
        aiPrompts: [],
        summaryParagraphs: [],
        calendar: calendar
    )

    // A named row keeps the identity the rest of the export identifies it by.
    #expect(markdown.contains("| Dana (Speaker 3 / Voice 1) | Named row."))
    // An unnamed row is untouched: the pair was already there in the app's "voice (speaker)" form.
    #expect(markdown.contains("| Voice 1 (Speaker 3) | Unnamed row."))
}

@Test func markdownExportIncludesDetailsRecordingSummaryAndAIPrompts() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)
    let second = start.addingTimeInterval(3)
    let end = start.addingTimeInterval(7)
    let llm = LLMEndpointConfiguration.defaultConfiguration()
    let aiPrompt = AIPromptItem(
        sentence: "The Earth orbits the Sun.",
        llm: llm,
        promptTemplate: AIPromptPrompt.defaultTemplate,
        state: .completed(AIPromptResult(
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
            aiPromptEnabled: true,
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
            aiPromptPrompt: "Fact-check {{sentence}}",
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
        aiPrompts: [aiPrompt],
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

@Test func markdownExportMatchesAIResultsBySegmentOccurrenceBeforeTextFallback() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)
    let firstID = UUID()
    let secondID = UUID()
    let llm = LLMEndpointConfiguration.defaultConfiguration()
    let aiPrompt = AIPromptItem(
        segmentID: secondID,
        sentenceIndex: 0,
        sentence: "Confirmed.",
        llm: llm,
        promptTemplateName: "Verifier",
        promptTemplate: AIPromptPrompt.defaultTemplate,
        state: .completed(AIPromptResult(
            sentence: "Confirmed.",
            verdict: .supported,
            confidence: .high,
            explanation: "This result belongs to the second occurrence."
        )),
        createdAt: start
    )

    let markdown = MarkdownExportService.makeDocument(
        context: MarkdownExportContext(
            sourceName: "Test",
            location: "",
            startDate: start,
            endDate: start.addingTimeInterval(2),
            exportedAt: start,
            transcriptionEngine: "Apple Speech",
            aiPromptEnabled: true,
            llmName: "Local Ollama",
            llmProvider: "Ollama",
            llmEndpoint: "http://localhost:11434",
            llmModel: "test-model",
            aiPromptPrompt: "Verify {{sentence}}",
            summaryPrompt: "Summarize."
        ),
        finalizedSegments: [
            TranscriptSegment(id: firstID, text: "Confirmed.", timestamp: start, isFinal: true),
            TranscriptSegment(id: secondID, text: "Confirmed.", timestamp: start.addingTimeInterval(1), isFinal: true)
        ],
        aiPrompts: [aiPrompt],
        summaryParagraphs: [],
        calendar: calendar
    )

    #expect(markdown.contains("| 2026-05-28 07:33:17 | 0:01 |  | Confirmed. |  |"))
    #expect(markdown.contains("| 2026-05-28 07:33:18 | 0:01 |  | Confirmed. | Verifier: Verdict: Supported<br>Confidence: High<br>This result belongs to the second occurrence. |"))
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
            aiPromptEnabled: false,
            llmName: "Local Ollama",
            llmProvider: "Ollama",
            llmEndpoint: "http://localhost:11434",
            llmModel: "igorls/gemma-4-12B-it-heretic-GGUF",
            aiPromptPrompt: "",
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
        aiPrompts: [],
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
            aiPromptEnabled: false,
            llmName: "",
            llmProvider: "",
            llmEndpoint: "",
            llmModel: "",
            aiPromptPrompt: "",
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
        aiPrompts: [],
        summaryParagraphs: [],
        calendar: calendar
    )

    // The name leads, but the identity it would otherwise hide stays with it: this row has no
    // matched voice yet, so the speaker slot is the whole pair. (Until v2.4.47 this asserted
    // "| Dana |" — a named row silently dropping the identity the export is built on.)
    #expect(markdown.contains("| 2026-05-28 07:33:17 | 0:04 | Dana (Speaker 1) | Hello there. |  |"))
    // The SPEAKERS timeline is unchanged: it identifies the run, not the row.
    #expect(markdown.contains("| 0:00 | 0:04 | Dana |  |"))
}

@Test func aiPromptSentenceExtractionRequiresCompleteSentences() {
    let sentences = AIPromptCoordinator.completeSentences(
        in: "Mars is red. Is water wet? This is incomplete"
    )

    #expect(sentences == ["Mars is red.", "Is water wet?"])
}

@Test func aiPromptPromptIncludesSchemaAndSentence() {
    let prompt = OllamaAIPromptService.prompt(for: "The Earth orbits the Sun.")

    #expect(prompt.contains("\"verdict\""))
    #expect(prompt.contains("not_factual"))
    #expect(prompt.contains("The Earth orbits the Sun."))
}

@Test func aiPromptPromptTemplateReplacesSentencePlaceholder() {
    let prompt = AIPromptPrompt.render(
        template: "Check this: {{sentence}}",
        sentence: "The Earth orbits the Sun."
    )

    #expect(prompt == "Check this: The Earth orbits the Sun.")
}

@Test func aiPromptPromptTemplateAppendsSentenceWhenPlaceholderIsMissing() {
    let prompt = AIPromptPrompt.render(
        template: "Fact-check the following transcript sentence.",
        sentence: "The Earth orbits the Sun."
    )

    #expect(prompt.contains("Fact-check the following transcript sentence."))
    #expect(prompt.contains("Sentence:\nThe Earth orbits the Sun."))
}

@Test func aiPromptPromptTemplateReplacesConversationPlaceholderWithTimestampedTranscript() {
    let base = Calendar.current.startOfDay(for: Date())
    let context = AIPromptPromptContext(entries: [
        .init(timestamp: base, text: "First sentence."),
        .init(timestamp: base.addingTimeInterval(61), text: "Second sentence.")
    ])

    let prompt = AIPromptPrompt.render(
        template: "Conversation:\n{{conversation}}\nCurrent:\n{{sentence}}",
        sentence: "Second sentence.",
        context: context
    )

    #expect(prompt.contains("[00:00:00] First sentence."))
    #expect(prompt.contains("[00:01:01] Second sentence."))
    #expect(prompt.contains("Current:\nSecond sentence."))
    #expect(!prompt.contains("{{conversation}}"))
}

@Test func aiPromptPromptTemplateReplacesLastNPlaceholdersWithRecentTimestampedTranscript() {
    let base = Calendar.current.startOfDay(for: Date())
    let context = AIPromptPromptContext(entries: (1...12).map { index in
        .init(
            timestamp: base.addingTimeInterval(TimeInterval(index)),
            text: "Sentence \(index)."
        )
    })

    let prompt = AIPromptPrompt.render(
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

@Test func aiPromptPromptTemplateAcceptsMalformedLast3Placeholder() {
    let base = Calendar.current.startOfDay(for: Date())
    let context = AIPromptPromptContext(entries: [
        .init(timestamp: base.addingTimeInterval(1), text: "One."),
        .init(timestamp: base.addingTimeInterval(2), text: "Two."),
        .init(timestamp: base.addingTimeInterval(3), text: "Three.")
    ])

    let prompt = AIPromptPrompt.render(
        template: "{{last-3}",
        sentence: "Three.",
        context: context
    )

    #expect(prompt.contains("[00:00:01] One."))
    #expect(prompt.contains("[00:00:03] Three."))
    #expect(!prompt.contains("{{last-3}"))
}

@Test func aiPromptPromptContextSplitsSegmentsIntoTimestampedSentences() {
    let timestamp = Calendar.current.startOfDay(for: Date()).addingTimeInterval(42)
    let context = AIPromptPromptContext(segments: [
        TranscriptSegment(text: "One. Two.", timestamp: timestamp, isFinal: true)
    ])

    #expect(context.formattedConversation() == "[00:00:42] One.\n[00:00:42] Two.")
}

@Test func aiPromptPromptTemplateReplacesPromptStatePlaceholder() {
    let context = AIPromptPromptContext(
        entries: [.init(timestamp: Date(), text: "New item.")],
        promptState: "- Existing item"
    )

    let prompt = AIPromptPrompt.render(
        template: "Update state:\n{{prompt-state}}\nFrom:\n{{sentence}}",
        sentence: "New item.",
        context: context
    )

    #expect(prompt.contains("Update state:\n- Existing item"))
    #expect(prompt.contains("From:\nNew item."))
    #expect(!prompt.contains("{{prompt-state}}"))
}

@Test func ollamaAIPromptParserAcceptsMissingNotes() {
    let raw = """
    {"sentence":"The Earth orbits the Sun.","verdict":"supported","confidence":"high","explanation":"This is a basic astronomical fact."}
    """

    let result = OllamaAIPromptService.parseResult(raw, fallbackSentence: "fallback")

    #expect(result.sentence == "The Earth orbits the Sun.")
    #expect(result.verdict == .supported)
    #expect(result.confidence == .high)
    #expect(result.notes == [])
}

@Test func ollamaAIPromptParserAcceptsFencedJSON() {
    let raw = """
    ```json
    {"sentence":"The Earth orbits the Sun.","verdict":"supported","confidence":"high","explanation":"This is a basic astronomical fact."}
    ```
    """

    let result = OllamaAIPromptService.parseResult(raw, fallbackSentence: "fallback")

    #expect(result.sentence == "The Earth orbits the Sun.")
    #expect(result.verdict == .supported)
    #expect(result.rawResponse == nil)
}

@Test func ollamaAIPromptParserDisplaysPlainTextResponse() {
    let raw = "This statement is broadly accurate: the Earth orbits the Sun."

    let result = OllamaAIPromptService.parseResult(raw, fallbackSentence: "The Earth orbits the Sun.")

    #expect(result.sentence == "The Earth orbits the Sun.")
    #expect(result.rawResponse == raw)
    #expect(result.displayText == raw)
}

@Test func sentenceParserKeepsEllipsesAbbreviationsAndDecimalsTogether() {
    let text = "It appears to be... humanoid. Make it so, Mr. Crusher. Starbate 424 02.7. Confirmed."

    let sentences = AIPromptCoordinator.completeSentences(in: text)

    #expect(sentences == [
        "It appears to be... humanoid.",
        "Make it so, Mr. Crusher.",
        "Starbate 424 02.7.",
        "Confirmed."
    ])
}

@MainActor
@Test func aiPromptCoordinatorSuppressesDuplicateSentenceOccurrence() async {
    let service = FakeAIPromptService()
    let coordinator = AIPromptCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )
    let promptTemplate = AIPromptTemplateConfiguration.defaultConfiguration(llmEndpointID: llm.id)
    let segmentID = UUID()

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(id: segmentID, text: "The Earth orbits the Sun.", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(id: segmentID, text: "  The Earth orbits the Sun.  ", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )

    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(coordinator.items.count == 1)
}

@MainActor
@Test func aiPromptCoordinatorKeepsRepeatedSentenceOccurrencesSeparate() async {
    let service = FakeAIPromptService()
    let coordinator = AIPromptCoordinator(service: service)
    let llm = LLMEndpointConfiguration.defaultConfiguration(
        endpoint: "http://localhost:11434",
        model: "test-model"
    )
    let promptTemplate = AIPromptTemplateConfiguration.defaultConfiguration(llmEndpointID: llm.id)

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "Confirmed.", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "Confirmed.", isFinal: true),
        enabled: true,
        promptTemplates: [promptTemplate],
        llmEndpoints: [llm],
        fallbackLLM: llm
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(coordinator.items.count == 2)
    #expect(Set(coordinator.items.compactMap(\.segmentID)).count == 2)
}

@MainActor
@Test func aiPromptCoordinatorDoesNotQueueWhenDisabled() async {
    let service = FakeAIPromptService()
    let coordinator = AIPromptCoordinator(service: service)
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
@Test func aiPromptCoordinatorQueuesOneItemPerEnabledPrompt() async {
    let service = FakeAIPromptService()
    let coordinator = AIPromptCoordinator(service: service)
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
@Test func aiPromptCoordinatorBatchesPromptQuestionsWhenEnabled() async {
    let probe = BatchAIPromptProbe()
    let service = BatchProbeAIPromptService(probe: probe)
    let coordinator = AIPromptCoordinator(service: service)
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

    // Wait for the work rather than for the clock: the coordinator finishes the batch on its
    // own task, and the suite runs tests in parallel, so a fixed sleep here only measures how
    // much spare capacity the machine had. A fixed 80ms budget made this the one test in the
    // suite that failed intermittently under load.
    await waitUntil { coordinator.items.allSatisfy { item in
        if case .completed = item.state {
            return true
        }
        return false
    } }

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

/// Polls `condition` until it holds or `timeout` elapses.
///
/// Tests in this file that assert on work a background task performs use fixed `Task.sleep`
/// budgets, which pass or fail according to how much spare capacity the machine had while the
/// suite ran its tests in parallel. Waiting for the condition is what those assertions actually
/// mean; this is the reliable form of the same wait.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Test func aiPromptCoordinatorAccruesPromptStateBetweenPromptCalls() async {
    let probe = PromptStateProbe()
    let service = PromptStateAIPromptService(probe: probe)
    let coordinator = AIPromptCoordinator(service: service)
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
@Test func aiPromptCoordinatorLimitsConcurrentRequestsToThree() async {
    let probe = ConcurrentAIPromptProbe()
    let service = SlowAIPromptService(probe: probe)
    let coordinator = AIPromptCoordinator(service: service)
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

@Test @MainActor func transcriptionCoordinatorPausesBufferConsumptionAndResumes() async throws {
    let service = FakeTranscriptionService(engineName: "Pause Test")
    let coordinator = TranscriptionCoordinator(service: service)
    try await coordinator.start()

    coordinator.consume(buffer: makeTestAudioBuffer(), time: AVAudioTime(sampleTime: 0, atRate: 16_000))
    #expect(service.appendedBufferCount == 1)

    coordinator.pause()

    #expect(coordinator.isPaused)
    #expect(coordinator.pauseSpans.count == 1)
    #expect(coordinator.pauseSpans.first?.endedAt == nil)

    // Buffers captured while paused must not reach the engine at all.
    coordinator.consume(buffer: makeTestAudioBuffer(), time: AVAudioTime(sampleTime: 1_024, atRate: 16_000))
    #expect(service.appendedBufferCount == 1)

    coordinator.resume()

    #expect(!coordinator.isPaused)
    #expect(coordinator.pauseSpans.first?.endedAt != nil)

    coordinator.consume(buffer: makeTestAudioBuffer(), time: AVAudioTime(sampleTime: 2_048, atRate: 16_000))
    #expect(service.appendedBufferCount == 2)

    coordinator.stop()
}

@Test @MainActor func transcriptionCoordinatorStopClosesPauseSpanAndRestartClearsIt() async throws {
    let service = FakeTranscriptionService(engineName: "Pause Reset Test")
    let coordinator = TranscriptionCoordinator(service: service)
    try await coordinator.start()

    coordinator.pause()
    coordinator.stop()

    #expect(!coordinator.isPaused)
    #expect(coordinator.pauseSpans.count == 1)
    #expect(coordinator.pauseSpans.first?.endedAt != nil)

    try await coordinator.start()

    #expect(coordinator.pauseSpans.isEmpty)
    #expect(!coordinator.isPaused)

    coordinator.stop()
}

@Test func markdownExportRecordsPausedSpans() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)
    let pauseStart = start.addingTimeInterval(30)
    let pauseEnd = pauseStart.addingTimeInterval(42)

    let markdown = MarkdownExportService.makeDocument(
        context: MarkdownExportContext(
            sourceName: "BlackHole 2ch",
            location: "",
            startDate: start,
            endDate: start.addingTimeInterval(90),
            exportedAt: start.addingTimeInterval(90),
            transcriptionEngine: "Apple Speech",
            aiPromptEnabled: false,
            llmName: "Local Ollama",
            llmProvider: "Ollama",
            llmEndpoint: "http://localhost:11434",
            llmModel: "test-model",
            aiPromptPrompt: "",
            summaryPrompt: ""
        ),
        finalizedSegments: [
            TranscriptSegment(text: "Before the pause.", timestamp: start, isFinal: true),
            TranscriptSegment(text: "After the pause.", timestamp: pauseEnd, isFinal: true)
        ],
        pauseSpans: [
            TranscriptionPauseSpan(startedAt: pauseStart, endedAt: pauseEnd)
        ],
        aiPrompts: [],
        summaryParagraphs: [],
        calendar: calendar
    )

    #expect(markdown.contains("- Paused: 1 span totaling 0:42"))
    #expect(markdown.contains("# PAUSES"))
    #expect(markdown.contains("| started | duration |"))
    #expect(markdown.contains("| 0:42 |"))
}

@Test func markdownExportOmitsPauseSectionWhenNeverPaused() {
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)

    let markdown = MarkdownExportService.makeDocument(
        context: MarkdownExportContext(
            sourceName: "BlackHole 2ch",
            location: "",
            startDate: start,
            endDate: start.addingTimeInterval(30),
            exportedAt: start.addingTimeInterval(30),
            transcriptionEngine: "Apple Speech",
            aiPromptEnabled: false,
            llmName: "Local Ollama",
            llmProvider: "Ollama",
            llmEndpoint: "http://localhost:11434",
            llmModel: "test-model",
            aiPromptPrompt: "",
            summaryPrompt: ""
        ),
        finalizedSegments: [
            TranscriptSegment(text: "Never paused.", timestamp: start, isFinal: true)
        ],
        aiPrompts: [],
        summaryParagraphs: []
    )

    #expect(!markdown.contains("# PAUSES"))
    #expect(!markdown.contains("- Paused:"))
}

private func makeTestAudioBuffer(frames: AVAudioFrameCount = 1_024) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    return buffer
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

    private(set) var appendedBufferCount = 0

    func append(_ buffer: AVAudioPCMBuffer) {
        appendedBufferCount += 1
    }

    func stop() {}

    func emit(_ segment: TranscriptSegment) {
        onSegment?(segment)
    }
}

private struct FakeAIPromptService: AIPromptService {
    func evaluate(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: AIPromptPromptContext
    ) async throws -> AIPromptResult {
        AIPromptResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Test result."
        )
    }
}

private actor ConcurrentAIPromptProbe {
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

private actor BatchAIPromptProbe {
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

private struct BatchProbeAIPromptService: AIPromptService {
    let probe: BatchAIPromptProbe

    func evaluate(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: AIPromptPromptContext
    ) async throws -> AIPromptResult {
        await probe.recordSingleCall()
        return AIPromptResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Single result."
        )
    }

    func evaluateBatch(items: [AIPromptItem]) async throws -> [UUID: AIPromptResult] {
        await probe.recordBatchCall(size: items.count)
        return Dictionary(uniqueKeysWithValues: items.map { item in
            (
                item.id,
                AIPromptResult(
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

private struct PromptStateAIPromptService: AIPromptService {
    let probe: PromptStateProbe

    func evaluate(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: AIPromptPromptContext
    ) async throws -> AIPromptResult {
        let index = await probe.record(promptContext.promptState)
        try? await Task.sleep(nanoseconds: 20_000_000)
        return AIPromptResult(
            sentence: sentence,
            verdict: .unverifiable,
            confidence: .low,
            explanation: "state-\(index)",
            rawResponse: "state-\(index)"
        )
    }
}

private struct SlowAIPromptService: AIPromptService {
    let probe: ConcurrentAIPromptProbe

    func evaluate(
        sentence: String,
        llm: LLMEndpointConfiguration,
        promptTemplate: String,
        promptContext: AIPromptPromptContext
    ) async throws -> AIPromptResult {
        await probe.started()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await probe.finished()
        return AIPromptResult(
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
@Test func jevCoordinatorDedupesResubmittedSentenceOccurrencePerQuery() async {
    let probe = JevBatchProbe()
    let coordinator = JevCoordinator(service: BatchProbeJevService(probe: probe))
    let query = JevQueryConfiguration(name: "Urgency", primitiveType: .noul)
    let segmentID = UUID()

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(id: segmentID, text: "The export button crashes.", isFinal: true),
        enabled: true,
        queries: [query],
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(id: segmentID, text: "  The export button crashes.  ", isFinal: true),
        enabled: true,
        queries: [query],
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(coordinator.items.count == 1)
}

@MainActor
@Test func jevCoordinatorKeepsRepeatedSentenceOccurrencesSeparate() async {
    let probe = JevBatchProbe()
    let coordinator = JevCoordinator(service: BatchProbeJevService(probe: probe))
    let query = JevQueryConfiguration(name: "Urgency", primitiveType: .noul)

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "Confirmed.", isFinal: true),
        enabled: true,
        queries: [query],
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "Confirmed.", isFinal: true),
        enabled: true,
        queries: [query],
        apiKey: "test-key",
        baseURL: "https://api.typesafe.ai",
        model: "jev-latest"
    )

    try? await Task.sleep(nanoseconds: 80_000_000)

    #expect(coordinator.items.count == 2)
    #expect(Set(coordinator.items.compactMap(\.segmentID)).count == 2)
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

// MARK: - Canonical speakers: existing-name selection and same-name merging

private func voiceEntry(
    _ speakerID: String,
    _ voiceID: String?,
    name: String = "",
    origin: SpeakerNameOrigin? = nil,
    segmentCount: Int = 0,
    totalDuration: TimeInterval = 0
) -> SpeakerComboEntry {
    SpeakerComboEntry(
        combo: SpeakerCombo(speakerID: speakerID, voiceID: voiceID),
        segmentCount: segmentCount,
        totalDuration: totalDuration,
        name: name,
        origin: origin
    )
}

@Test func canonicalResolverKeepsNamedCombosSeparateWhileMergingIsOff() {
    let resolver = CanonicalSpeakerResolver(
        mergeSameNamedSpeakers: false,
        entries: [
            voiceEntry("Speaker 1", "Voice 1", name: "Dana"),
            voiceEntry("Speaker 2", "Voice 2", name: "Dana")
        ]
    )

    let resolutions = resolver.resolutions()

    #expect(resolutions.count == 2)
    #expect(resolutions.allSatisfy { !$0.isMerged })
    // Same name, two rows: without merging the pane still exposes both combos.
    #expect(Set(resolutions.map(\.canonicalID)).count == 2)
    #expect(resolutions.map(\.displayName) == ["Dana", "Dana"])
}

@Test func canonicalResolverMergesCombosSharingAName() throws {
    let resolver = CanonicalSpeakerResolver(
        mergeSameNamedSpeakers: true,
        entries: [
            voiceEntry("Speaker 1", "Voice 1", name: "Dana", origin: .picked, segmentCount: 2, totalDuration: 4),
            voiceEntry("Speaker 2", "Voice 2", name: "  dana  ", origin: .typed, segmentCount: 3, totalDuration: 9)
        ]
    )

    let resolutions = resolver.resolutions()

    #expect(resolutions.count == 1)
    let merged = try #require(resolutions.first)
    #expect(merged.isMerged)
    #expect(merged.combos.count == 2)
    // The first spelling wins, so merging never silently rewrites the visible name.
    #expect(merged.displayName == "Dana")
    #expect(merged.observedLabel == "Speaker 1 / Voice 1 + Speaker 2 / Voice 2")
}

@Test func canonicalResolverLeavesUnnamedCombosAloneWhileMerging() {
    let resolver = CanonicalSpeakerResolver(
        mergeSameNamedSpeakers: true,
        entries: [
            voiceEntry("Speaker 1", "Voice 1", name: "Dana"),
            voiceEntry("Speaker 2", "Voice 2")
        ]
    )

    #expect(resolver.resolutions().map(\.displayName) == ["Dana", "Speaker 2 / Voice 2"])
    #expect(resolver.resolutions().map(\.isMerged) == [false, false])
}

@Test func canonicalResolverListsDistinctAssignedNamesForQuickPicks() {
    let resolver = CanonicalSpeakerResolver(
        mergeSameNamedSpeakers: false,
        entries: [
            voiceEntry("Speaker 1", "Voice 1", name: "Dana"),
            voiceEntry("Speaker 2", "Voice 2", name: "dana"),
            voiceEntry("Speaker 3", nil, name: "   ")
        ]
    )

    #expect(resolver.assignedNames == ["Dana"])
}

@Test func canonicalResolverNameKeyIgnoresCaseAndSpacing() {
    #expect(CanonicalSpeakerResolver.nameKey("  Dana   Scully ") == "dana scully")
    #expect(CanonicalSpeakerResolver.nameKey("DANA SCULLY") == CanonicalSpeakerResolver.nameKey("dana  scully"))
}

@Test func canonicalResolverSumsMergedStatsAndLocksOnlyPickedNames() throws {
    var resolver = CanonicalSpeakerResolver(
        mergeSameNamedSpeakers: true,
        entries: [
            voiceEntry("Speaker 1", "Voice 1", name: "Dana", origin: .picked, segmentCount: 2, totalDuration: 4),
            voiceEntry("Speaker 2", "Voice 2", name: "Dana", origin: .picked, segmentCount: 3, totalDuration: 9),
            voiceEntry("Speaker 3", "Voice 3", name: "", segmentCount: 5, totalDuration: 1)
        ]
    )

    let items = resolver.editorItems()
    #expect(items.count == 2)
    // The pane and the transcript speaker menu both render these rows, so with merging on a
    // speaker must appear exactly once — the names the user sees are unique.
    #expect(Set(items.map(\.displayName)).count == items.count)

    let merged = try #require(items.first)
    #expect(merged.displayName == "Dana")
    #expect(merged.segmentCount == 5)
    #expect(merged.totalDuration == 13)
    #expect(merged.combos.count == 2)
    // Every member was picked, so the merged row's type-in field is locked.
    #expect(merged.isNameLocked)

    // One typed member is enough to leave the row editable.
    resolver.entries[1].origin = .typed
    let reopened = try #require(resolver.editorItems().first)
    #expect(!reopened.isNameLocked)
    #expect(reopened.customName == "Dana")
}

@Test @MainActor func mergeTogglePublishesSoThePaneRegroups() {
    let key = AppSettings.mergeSameNamedSpeakersStorageKey
    let original = UserDefaults.standard.object(forKey: key)
    defer {
        if let original {
            UserDefaults.standard.set(original, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    let settings = AppSettings()
    var notifications = 0
    let subscription = settings.objectWillChange.sink { _ in notifications += 1 }

    settings.mergeSameNamedSpeakers = true

    #expect(settings.mergeSameNamedSpeakers)
    #expect(UserDefaults.standard.bool(forKey: key))
    // The pane only regroups if this fires: `@AppStorage` here would persist the click but
    // publish nothing, which is exactly how the checkbox appeared to do nothing.
    #expect(notifications > 0)
    withExtendedLifetime(subscription) {}
}

@Test func canonicalEditorRowIDsStayStableWhileANameIsTyped() {
    let first = SpeakerCombo(speakerID: "Speaker 1", voiceID: "Voice 1")
    let second = SpeakerCombo(speakerID: "Speaker 2", voiceID: "Voice 2")

    func rowIDs(firstName: String, secondName: String = "", merging: Bool = true) -> [String] {
        CanonicalSpeakerResolver(
            mergeSameNamedSpeakers: merging,
            entries: [
                voiceEntry("Speaker 1", "Voice 1", name: firstName),
                voiceEntry("Speaker 2", "Voice 2", name: secondName)
            ]
        ).editorItems().map(\.id)
    }

    // Typing into a row must not change that row's identity, or SwiftUI rebuilds the row and
    // the type-in field loses focus after every letter.
    #expect(rowIDs(firstName: "") == [first.id, second.id])
    #expect(rowIDs(firstName: "D") == [first.id, second.id])
    #expect(rowIDs(firstName: "Da") == [first.id, second.id])
    #expect(rowIDs(firstName: "Dana") == [first.id, second.id])

    // Merging changes which rows exist, but never invents an id or duplicates one.
    #expect(rowIDs(firstName: "Dana", secondName: "dana") == [first.id])
    #expect(rowIDs(firstName: "Dana", secondName: "Bob") == [first.id, second.id])

    let unmerged = CanonicalSpeakerResolver(
        mergeSameNamedSpeakers: false,
        entries: [
            voiceEntry("Speaker 1", "Voice 1", name: "Dana"),
            voiceEntry("Speaker 2", "Voice 2", name: "Dana")
        ]
    ).editorItems()
    #expect(Set(unmerged.map(\.id)).count == unmerged.count)
}

@Test func speakerNameEditorItemFallsBackToItsOwnCombo() {
    let item = SpeakerNameEditorItem(
        id: "combo:Speaker 1|Voice 1",
        speakerID: "Speaker 1",
        voiceID: "Voice 1",
        observedLabel: "Speaker 1 / Voice 1",
        displayName: "Speaker 1 / Voice 1",
        customName: ""
    )

    #expect(item.memberCombos == [SpeakerCombo(speakerID: "Speaker 1", voiceID: "Voice 1")])
    #expect(!item.isNameLocked)
}

@Test @MainActor func pickedVoiceNameLocksItsFieldUntilUnlockedOrCleared() {
    let coordinator = DiarizationCoordinator()

    coordinator.setObservedVoiceName(speakerID: "Speaker 1", voiceID: "Voice 1", name: "Dana", origin: .picked)
    #expect(coordinator.observedVoiceName(speakerID: "Speaker 1", voiceID: "Voice 1") == "Dana")
    #expect(coordinator.observedVoiceNameOrigin(speakerID: "Speaker 1", voiceID: "Voice 1") == .picked)

    // Unlocking keeps the name and re-enables typing, so a picked name stays correctable.
    coordinator.unlockObservedVoiceName(speakerID: "Speaker 1", voiceID: "Voice 1")
    #expect(coordinator.observedVoiceNameOrigin(speakerID: "Speaker 1", voiceID: "Voice 1") == .typed)
    #expect(coordinator.observedVoiceName(speakerID: "Speaker 1", voiceID: "Voice 1") == "Dana")

    // Clearing the name clears the lock with it, so a later rename starts editable.
    coordinator.setObservedVoiceName(speakerID: "Speaker 1", voiceID: "Voice 1", name: "")
    #expect(coordinator.observedVoiceName(speakerID: "Speaker 1", voiceID: "Voice 1") == nil)
    #expect(coordinator.observedVoiceNameOrigin(speakerID: "Speaker 1", voiceID: "Voice 1") == nil)
}

@Test func markdownExportCoalescesAdjacentSameNamedSpeakerRunsOnlyWhenAsked() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_779_971_597.0)

    var segments = [
        SpeakerDiarizationSegment(speakerID: "Speaker 1", speakerName: "Dana", startTime: 0, endTime: 3, confidence: 0.8),
        SpeakerDiarizationSegment(speakerID: "Speaker 2", speakerName: "Dana", startTime: 3, endTime: 6, confidence: 0.6),
        SpeakerDiarizationSegment(speakerID: "Speaker 3", speakerName: "Bob", startTime: 6, endTime: 8, confidence: 0.9),
        // A repeated, non-adjacent run stays its own row: the timeline is time-ordered.
        SpeakerDiarizationSegment(speakerID: "Speaker 1", speakerName: "Dana", startTime: 8, endTime: 10, confidence: 1.0)
    ]

    func export(merging: Bool) -> String {
        MarkdownExportService.makeDocument(
            context: MarkdownExportContext(
                sourceName: "Test Mic",
                location: "",
                startDate: start,
                endDate: start.addingTimeInterval(10),
                exportedAt: start,
                transcriptionEngine: "Apple Speech",
                aiPromptEnabled: false,
                llmName: "",
                llmProvider: "",
                llmEndpoint: "",
                llmModel: "",
                aiPromptPrompt: "",
                summaryPrompt: ""
            ),
            finalizedSegments: [],
            speakerSegments: segments,
            mergeSameNamedSpeakers: merging,
            aiPrompts: [],
            summaryParagraphs: [],
            calendar: calendar
        )
    }

    let merged = export(merging: true)
    // Two Dana combos speaking back to back read as one person, with a true mean confidence.
    #expect(merged.contains("| 0:00 | 0:06 | Dana | 0.70 |"))
    #expect(merged.contains("| 0:06 | 0:08 | Bob | 0.90 |"))
    #expect(merged.contains("| 0:08 | 0:10 | Dana | 1.00 |"))
    #expect(!merged.contains("| 0:00 | 0:03 |"))

    let unmerged = export(merging: false)
    #expect(unmerged.contains("| 0:00 | 0:03 | Dana | 0.80 |"))
    #expect(unmerged.contains("| 0:03 | 0:06 | Dana | 0.60 |"))

    let samePerson = UUID()
    segments[0].personID = samePerson
    segments[1].personID = samePerson
    let explicitlyMerged = export(merging: false)
    #expect(explicitlyMerged.contains("| 0:00 | 0:06 | Dana | 0.70 |"))
    segments[1].personID = UUID()
    let distinctPeople = export(merging: false)
    #expect(distinctPeople.contains("| 0:00 | 0:03 | Dana | 0.80 |"))
    #expect(distinctPeople.contains("| 0:03 | 0:06 | Dana | 0.60 |"))
}

// MARK: - Playback follow

@Test func playbackTimelineMapsAudioPositionToTheRowSpokenThen() {
    let anchor = Date(timeIntervalSince1970: 1_779_971_597.0)
    let first = TranscriptSegment(
        text: "one",
        timestamp: anchor.addingTimeInterval(0.5),
        isFinal: true
    )
    let second = TranscriptSegment(
        text: "two",
        timestamp: anchor.addingTimeInterval(4.0),
        isFinal: true
    )

    let timeline = TranscriptPlaybackTimeline(
        segments: [first, second],
        pauseSpans: [],
        anchorDate: anchor
    )

    let unwrapped = try! #require(timeline)
    #expect(unwrapped.rows.map(\.offset) == [0.5, 4.0])
    // Before the first row there is nothing to show.
    #expect(unwrapped.rowID(atOffset: 0) == nil)
    #expect(unwrapped.rowID(atOffset: 0.5) == TranscriptPlaybackTimeline.rowID(forSegmentID: first.id))
    #expect(unwrapped.rowID(atOffset: 3.9) == TranscriptPlaybackTimeline.rowID(forSegmentID: first.id))
    #expect(unwrapped.rowID(atOffset: 4.0) == TranscriptPlaybackTimeline.rowID(forSegmentID: second.id))
    // Past the last row the last row stays active, so the highlight never disappears.
    #expect(unwrapped.rowID(atOffset: 900) == TranscriptPlaybackTimeline.rowID(forSegmentID: second.id))
    // Round-trips, which is what click-to-seek relies on.
    #expect(unwrapped.offset(forRowID: TranscriptPlaybackTimeline.rowID(forSegmentID: second.id)) == 4.0)
}

@Test func playbackTimelineOrdersPauseMarkersAmongSegments() {
    let anchor = Date(timeIntervalSince1970: 1_779_971_597.0)
    let before = TranscriptSegment(text: "before", timestamp: anchor, isFinal: true)
    let after = TranscriptSegment(text: "after", timestamp: anchor.addingTimeInterval(30), isFinal: true)
    let span = TranscriptionPauseSpan(
        startedAt: anchor.addingTimeInterval(10),
        endedAt: anchor.addingTimeInterval(25)
    )

    let timeline = try! #require(TranscriptPlaybackTimeline(
        segments: [before, after],
        pauseSpans: [span],
        anchorDate: anchor
    ))

    #expect(timeline.rows.map(\.offset) == [0, 10, 30])
    #expect(timeline.rowID(atOffset: 12) == TranscriptPlaybackTimeline.rowID(forPauseSpanID: span.id))
    #expect(timeline.rowID(atOffset: 29) == TranscriptPlaybackTimeline.rowID(forPauseSpanID: span.id))
    #expect(timeline.rows[0].endOffset == 10)
    #expect(timeline.rows[2].endOffset == nil)
}

@Test func playbackTimelineDropsRowsThisAudioCannotContain() {
    let anchor = Date(timeIntervalSince1970: 1_779_971_597.0)
    // A transcript that began before the recording did has rows with no position in the file.
    let early = TranscriptSegment(text: "early", timestamp: anchor.addingTimeInterval(-5), isFinal: true)
    let kept = TranscriptSegment(text: "kept", timestamp: anchor.addingTimeInterval(2), isFinal: true)

    let timeline = try! #require(TranscriptPlaybackTimeline(
        segments: [early, kept],
        pauseSpans: [],
        anchorDate: anchor
    ))

    #expect(timeline.rows.count == 1)
    #expect(timeline.rows[0].id == TranscriptPlaybackTimeline.rowID(forSegmentID: kept.id))
}

@Test func playbackTimelineIsNilWhenNoRowFitsTheAudio() {
    let anchor = Date(timeIntervalSince1970: 1_779_971_597.0)
    let early = TranscriptSegment(text: "early", timestamp: anchor.addingTimeInterval(-1), isFinal: true)

    #expect(TranscriptPlaybackTimeline(segments: [early], pauseSpans: [], anchorDate: anchor) == nil)
    #expect(TranscriptPlaybackTimeline(segments: [], pauseSpans: [], anchorDate: anchor) == nil)
}

@Test func playbackTimelinePlacesImportedRowsByTheirAudioOffsets() {
    // An imported file has no anchor, and its rows' timestamps are the moments the recognizer
    // returned them, which say nothing about the audio. The engine's audio offsets do, so the
    // transcript maps onto the file and can follow playback.
    let first = TranscriptSegment(text: "one", isFinal: true, audioOffset: 3.0)
    let second = TranscriptSegment(text: "two", isFinal: true, audioOffset: 7.5)

    let timeline = try! #require(TranscriptPlaybackTimeline(
        segments: [first, second],
        pauseSpans: [],
        anchorDate: nil
    ))

    #expect(timeline.rows.map(\.offset) == [3.0, 7.5])
    #expect(timeline.rowID(atOffset: 3) == TranscriptPlaybackTimeline.rowID(forSegmentID: first.id))
    #expect(timeline.rowID(atOffset: 4) == TranscriptPlaybackTimeline.rowID(forSegmentID: first.id))
    #expect(timeline.rowID(atOffset: 9) == TranscriptPlaybackTimeline.rowID(forSegmentID: second.id))
    // Round-trips, which is what click-to-seek on an imported file relies on.
    #expect(timeline.offset(forRowID: TranscriptPlaybackTimeline.rowID(forSegmentID: second.id)) == 7.5)
}

@Test func playbackTimelinePrefersTheAnchorOverAudioOffsets() {
    // In a live session the analyzer's clock can start before the recording file does, so an
    // offset measured from it disagrees with the file. The anchor comes from the file itself.
    let anchor = Date(timeIntervalSince1970: 1_779_971_597.0)
    let segment = TranscriptSegment(
        text: "one",
        timestamp: anchor.addingTimeInterval(12),
        isFinal: true,
        audioOffset: 4.0
    )

    let timeline = try! #require(TranscriptPlaybackTimeline(
        segments: [segment],
        pauseSpans: [],
        anchorDate: anchor
    ))

    #expect(timeline.rows.map(\.offset) == [12.0])
}

@Test func playbackTimelineLeavesOutRowsNothingCanPlace() {
    // A row the engine gave no time range for — an error line, say — is dropped rather than
    // guessed at, and the rows that can be placed still map.
    let placed = TranscriptSegment(text: "placed", isFinal: true, audioOffset: 2.0)
    let unplaced = TranscriptSegment(text: "unplaced", isFinal: true)

    let timeline = try! #require(TranscriptPlaybackTimeline(
        segments: [placed, unplaced],
        pauseSpans: [],
        anchorDate: nil
    ))

    #expect(timeline.rows.count == 1)
    #expect(timeline.rows[0].offset == 2.0)
    // With nothing placeable at all there is no timeline, so the pane says so instead of
    // offering a follow that would point nowhere.
    #expect(TranscriptPlaybackTimeline(segments: [unplaced], pauseSpans: [], anchorDate: nil) == nil)
}

/// Requires a real file *and* a speech-authorized process:
/// `VOICETRANSCRIBE_SAMPLE=/path/to/audio.wav swift test --filter engineReportsAudioOffsets`.
///
/// Following an imported file rests entirely on the engine reporting audio time ranges, and that
/// is an assumption about the Speech framework rather than about this code, so it is pinned
/// against a real file instead of a reading of the API.
///
/// Skipped both when the variable is unset and when the process is not authorized for speech
/// recognition — as `swift test` is not, having no bundle to carry the usage description. The
/// offset behavior was confirmed on `samples/star-trek-first-120s.wav` from an authorized host:
/// every result carried a time range, the first line at 3.00s and the last at 117.84s.
@Test func engineReportsAudioOffsetsForImportedAudio() async throws {
    guard let path = ProcessInfo.processInfo.environment["VOICETRANSCRIBE_SAMPLE"],
          SFSpeechRecognizer.authorizationStatus() == .authorized else {
        return
    }
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let sink = SegmentSink()

    let service = AppleSpeechTranscriptionService(locale: Locale(identifier: "en-US"))
    try await service.start { segment in sink.append(segment) }

    let chunk: AVAudioFrameCount = 4096
    while true {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
            break
        }
        try file.read(into: buffer)
        if buffer.frameLength == 0 {
            break
        }
        service.append(buffer)
    }

    // Let the recognizer drain the audio it was handed.
    try await Task.sleep(nanoseconds: 6_000_000_000)
    service.stop()

    let offsets = sink.snapshot().filter(\.isFinal).compactMap(\.audioOffset)
    #expect(!offsets.isEmpty, "the engine reported no audio offsets, so an imported file could not be followed")
    #expect(offsets.allSatisfy { $0 >= 0 && $0 <= duration + 1 })
    // Rows are ordered in the audio, so the offsets rise as the file plays.
    #expect(offsets == offsets.sorted())
}

/// Collects segments from the transcriber's callback, which arrives off the main thread.
private final class SegmentSink: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [TranscriptSegment] = []

    func append(_ segment: TranscriptSegment) {
        lock.lock()
        segments.append(segment)
        lock.unlock()
    }

    func snapshot() -> [TranscriptSegment] {
        lock.lock()
        defer { lock.unlock() }
        return segments
    }
}

@Test func playbackTimelineRowIDsMatchTheTranscriptPane() {
    let segmentID = UUID()
    let pauseID = UUID()

    // The pane builds its `ForEach` ids through these helpers, so a row the timeline names is
    // a row the pane can actually scroll to.
    #expect(TranscriptPlaybackTimeline.rowID(forSegmentID: segmentID) == "segment-\(segmentID.uuidString)")
    #expect(TranscriptPlaybackTimeline.rowID(forPauseSpanID: pauseID) == "pause-\(pauseID.uuidString)")
    #expect(TranscriptPlaybackState.unavailable.isAvailable == false)
}

@MainActor
@Test func audioPlaybackLoadsFinalizedAudioAndSeeks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vt-playback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = try makeSilentAudioFile(
        named: "playback.wav",
        seconds: 0.5,
        in: directory
    )

    let service = AudioPlaybackService()
    #expect(service.load(url: url))
    #expect(service.hasAudio)
    #expect(abs(service.duration - 0.5) < 0.05)
    #expect(service.lastError == nil)

    service.seek(to: 0.25)
    #expect(abs(service.currentTime - 0.25) < 0.01)

    // Seeking past the end clamps rather than throwing the playhead out of the file.
    service.seek(to: 99)
    #expect(service.currentTime <= service.duration + 0.01)

    service.unload()
    #expect(service.hasAudio == false)
    #expect(service.url == nil)
}

@MainActor
@Test func audioPlaybackRejectsAnUnfinalizedM4AHeader() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vt-playback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // The shape of an `.m4a` that was opened for writing but never finalized: an `ftyp` box
    // and nothing else. No `moov` means no decoder can read it, which is why a recording that
    // is still in progress cannot be played back (and why the pane only offers finished ones).
    var header: [UInt8] = [0x00, 0x00, 0x00, 0x1C]
    header.append(contentsOf: Array("ftypM4A ".utf8))
    header.append(contentsOf: [UInt8](repeating: 0, count: 28 - header.count))
    #expect(header.count == 28)

    let url = directory.appendingPathComponent("unfinalized.m4a")
    try Data(header).write(to: url)

    let service = AudioPlaybackService()
    #expect(service.load(url: url) == false)
    #expect(service.hasAudio == false)
    #expect(service.lastError != nil)
}

@Test func playbackStateShowsAudioTimeOnlyWhilePlaybackIsEngaged() {
    func state(
        label: String? = "recording.m4a",
        currentTime: TimeInterval = 0,
        isPlaying: Bool = false,
        canFollow: Bool = true
    ) -> TranscriptPlaybackState {
        TranscriptPlaybackState(
            label: label,
            duration: 60,
            currentTime: currentTime,
            isPlaying: isPlaying,
            canFollow: canFollow,
            activeRowID: nil,
            error: nil
        )
    }

    // Nothing playable at all: the timestamp column stays clock time.
    #expect(state(label: nil).isShowingAudioTime == false)
    // Imported audio has no mapping onto the transcript, so it also keeps clock time.
    #expect(state(canFollow: false).isShowingAudioTime == false)
    #expect(state(isPlaying: true, canFollow: false).isShowingAudioTime == false)
    // Playback loaded but untouched: still clock time, so a recording that is merely finished does
    // not silently relabel every row in the transcript.
    #expect(state().isShowingAudioTime == false)
    // Playing, or parked somewhere after a scrub, the column reads as positions in the audio.
    #expect(state(isPlaying: true).isShowingAudioTime)
    #expect(state(currentTime: 5).isShowingAudioTime)
}

@MainActor
@Test func audioPlaybackKeepsASeekMadeBeforeTheFileWasOpened() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vt-playback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = try makeSilentAudioFile(named: "pending.wav", seconds: 0.5, in: directory)

    let service = AudioPlaybackService()
    // The file is opened lazily, so a scrubber drag can arrive before it is open. Dropping that
    // position is what made scrubbing look inert until playback had been started once, and it
    // also left the transcript following a playhead that had not actually moved.
    service.seek(to: 0.3)
    #expect(service.hasAudio == false)

    #expect(service.load(url: url))
    #expect(abs(service.currentTime - 0.3) < 0.01)

    // Once the position has been applied to a real player, seeking is ordinary, and stopping
    // rewinds to the start rather than holding the old playhead.
    service.seek(to: 0.4)
    #expect(abs(service.currentTime - 0.4) < 0.01)
    service.stop()
    #expect(service.currentTime == 0)
}

/// Writes a short silent WAV so playback can be exercised without any audio hardware input.
private func makeSilentAudioFile(named name: String, seconds: Double, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(16_000 * seconds)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    try file.write(from: buffer)
    return url
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
