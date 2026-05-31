import AVFoundation
import Foundation
import Speech

protocol TranscriptionService {
    var engineName: String { get }
    func start(onSegment: @escaping (TranscriptSegment) -> Void) throws
    func append(_ buffer: AVAudioPCMBuffer)
    func stop()
}

final class AppleSpeechTranscriptionService: TranscriptionService {
    let engineName = "Apple Speech"

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func start(onSegment: @escaping (TranscriptSegment) -> Void) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.engineUnavailable
        }

        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let best = result.bestTranscription
                let segment = TranscriptSegment(
                    text: best.formattedString,
                    isFinal: result.isFinal,
                    confidence: best.segments.last?.confidence
                )
                onSegment(segment)
            }

            if error != nil {
                request.endAudio()
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case engineUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition permission is required before transcription can start."
        case .engineUnavailable:
            return "The selected transcription engine is unavailable."
        }
    }
}

@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var interimSegment: TranscriptSegment?
    @Published private(set) var isTranscribing = false
    @Published private(set) var lastError: String?

    private var transcript = TranscriptDocument()
    private var service: TranscriptionService

    init(service: TranscriptionService = AppleSpeechTranscriptionService()) {
        self.service = service
    }

    var engineName: String {
        service.engineName
    }

    var transcriptText: String {
        transcript.plainText
    }

    func start() throws {
        transcript = TranscriptDocument()
        segments = []
        interimSegment = nil

        try service.start { [weak self] segment in
            Task { @MainActor in
                self?.apply(segment)
            }
        }
        isTranscribing = true
        lastError = nil
    }

    func consume(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        service.append(buffer)
    }

    func stop() {
        service.stop()
        isTranscribing = false
        interimSegment = nil
    }

    private func apply(_ segment: TranscriptSegment) {
        transcript.apply(segment)
        if segment.isFinal {
            segments.append(segment)
            interimSegment = nil
        } else {
            interimSegment = segment
        }
    }
}
