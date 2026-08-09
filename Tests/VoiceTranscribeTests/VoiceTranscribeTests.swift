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
    let endpoint = URL(string: "http://localhost:11434")!

    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "The Earth orbits the Sun.", isFinal: true),
        enabled: true,
        endpoint: endpoint,
        model: "test-model"
    )
    coordinator.enqueueTranscriptSegment(
        TranscriptSegment(text: "  The Earth orbits the Sun.  ", isFinal: true),
        enabled: true,
        endpoint: endpoint,
        model: "test-model"
    )

    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(coordinator.items.count == 1)
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
    func factCheck(sentence: String, endpoint: URL, model: String) async throws -> FactCheckResult {
        FactCheckResult(
            sentence: sentence,
            verdict: .supported,
            confidence: .high,
            explanation: "Test result."
        )
    }
}
