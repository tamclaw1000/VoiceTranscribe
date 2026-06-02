import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceService = AudioDeviceService()
    @Published var permissionService = PermissionService()
    @Published var settings = AppSettings()
    @Published var captureService = AudioCaptureService()
    @Published var recordingService = RecordingService()
    @Published var transcription: TranscriptionCoordinator

    private static func makeInitialService() -> TranscriptionService {
        let raw = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? TranscriptionEngineKind.appleSpeech.rawValue
        let kind = TranscriptionEngineKind(rawValue: raw) ?? .appleSpeech
        switch kind {
        case .appleSpeech:
            return AppleSpeechTranscriptionService()
        case .fluidAudio:
            return FluidAudioTranscriptionService()
        }
    }
    @Published var completedRecordings: [RecordingSession] = []
    @Published var userMessage: String?
    @Published var recordingFilename: String?  // in-progress or recently-completed basename
    @Published var recordingFileURL: URL?      // for Finder reveal

    /// Guards against double‑click races while transcription is still starting.
    @Published private(set) var isStartingTranscription = false
    /// Guards against double‑click races while recording is still starting.
    @Published private(set) var isStartingRecording = false

    private var cancellables = Set<AnyCancellable>()
    private var transcriptionTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?

    init() {
        transcription = TranscriptionCoordinator(service: AppModel.makeInitialService())

        // Propagate nested ObservableObject changes so SwiftUI re-renders
        // when captureService, recordingService, or transcription state changes.
        captureService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        recordingService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        transcription.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        permissionService.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    var activeSourceID: String? {
        captureService.activeSource?.id
    }

    func refreshDevices() {
        deviceService.refresh()
    }

    func requestMicrophonePermission() {
        Task {
            await permissionService.requestMicrophonePermission()
        }
    }

    func requestSpeechPermission() {
        Task {
            await permissionService.requestSpeechPermission()
        }
    }

    func toggleRecord(for source: SoundInputSource) {
        let isCurrentlyRecording = recordingService.isRecording
        Trace.button(
            isCurrentlyRecording ? "record.stop" : "record.start",
            source: source.name,
            extra: ["isStartingRecording": isStartingRecording]
        )

        if isCurrentlyRecording {
            stopRecording()
            return
        }

        guard !isStartingRecording else {
            Trace.event("record.guard.skip", ["reason": "alreadyStarting"])
            return
        }

        isStartingRecording = true

        recordingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isStartingRecording = false }

            do {
                try await self.ensureCapture(for: source)
                try self.recordingService.start(
                    source: source,
                    inputFormat: self.captureService.currentInputFormat,
                    outputFolder: self.settings.outputFolder,
                    outputFormat: self.settings.audioOutputFormat
                )
                self.captureService.addConsumer(id: "record") { [weak recordingService] buffer, time in
                    Task { @MainActor in
                        recordingService?.consume(buffer: buffer, time: time)
                    }
                }
                self.recordingFilename = self.recordingService.activeSession?.basename
                self.recordingFileURL = nil
                Trace.event("record.started", [
                    "source": source.name,
                    "outputFolder": self.settings.outputFolder.path
                ])
            } catch {
                Trace.event("record.error", [
                    "source": source.name,
                    "error": error.localizedDescription
                ])
                self.userMessage = error.localizedDescription
            }
        }
    }

    func toggleTranscribe(for source: SoundInputSource) {
        let isCurrentlyTranscribing = transcription.isTranscribing
        let isStarting = transcription.isStarting || isStartingTranscription
        Trace.button(
            isCurrentlyTranscribing ? "transcribe.stop" : "transcribe.start",
            source: source.name,
            extra: [
                "isTranscribing": isCurrentlyTranscribing,
                "isStarting": isStarting,
                "isStartingTranscription": isStartingTranscription,
                "engine": transcription.engineName
            ]
        )

        if isCurrentlyTranscribing {
            stopTranscription()
            return
        }

        guard !isStarting else {
            Trace.event("transcribe.guard.skip", ["reason": "alreadyStarting"])
            return
        }

        isStartingTranscription = true

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isStartingTranscription = false }

            do {
                Trace.event("transcribe.capture.ensuring", ["source": source.name])
                try await self.ensureCapture(for: source)
                Trace.event("transcribe.service.starting", [
                    "source": source.name,
                    "engine": self.transcription.engineName
                ])
                try await self.startTranscriptionConsumer(for: source)
                Trace.event("transcribe.started", [
                    "source": source.name,
                    "engine": self.transcription.engineName
                ])
            } catch {
                Trace.event("transcribe.error", [
                    "source": source.name,
                    "engine": self.transcription.engineName,
                    "error": error.localizedDescription
                ])
                self.userMessage = error.localizedDescription
            }
        }
    }

    func isRecording(_ source: SoundInputSource) -> Bool {
        guard let session = recordingService.activeSession else { return false }
        return session.source.id == source.id
    }

    func isTranscribing(_ source: SoundInputSource) -> Bool {
        // The button is "active" when transcribing OR still starting.
        guard captureService.activeSource?.id == source.id else { return false }
        return transcription.isTranscribing || transcription.isStarting || isStartingTranscription
    }

    private func ensureCapture(for source: SoundInputSource) async throws {
        if !permissionService.hasTouchedRecordingDevice {
            let authorized = await permissionService.authorizeFirstRecordingDeviceTouch()
            if !authorized {
                throw AppModelError.microphonePermissionRequired
            }
        } else {
            permissionService.refresh()
        }

        if !permissionService.canCaptureAudio {
            throw AppModelError.microphonePermissionRequired
        }

        if captureService.activeSource?.id != source.id {
            captureService.stop()
            try captureService.start(source: source)
        }
    }

    private func startTranscriptionConsumer(for source: SoundInputSource) async throws {
        if !permissionService.canTranscribe {
            throw AppModelError.speechPermissionRequired
        }

        try await transcription.start()
        captureService.addConsumer(id: "transcribe") { [weak transcription] buffer, time in
            Task { @MainActor in
                transcription?.consume(buffer: buffer, time: time)
            }
        }
    }

    private func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        isStartingRecording = false

        do {
            Trace.event("record.stopping", [
                "source": recordingService.activeSession?.source.name ?? "unknown"
            ])
            captureService.removeConsumer(id: "record")
            let saveTranscript = transcription.isTranscribing && !transcription.transcriptText.isEmpty
            let finalized = try recordingService.stop(
                transcriptText: transcription.transcriptText,
                saveTranscript: saveTranscript,
                transcriptionEngine: transcription.engineName
            )
            if let finalized {
                Trace.event("record.stopped", [
                    "basename": finalized.basename,
                    "audioFile": finalized.audioURL.path,
                    "transcriptFile": finalized.transcriptURL.path,
                    "duration": String(format: "%.2f", finalized.duration)
                ])
                completedRecordings.insert(finalized, at: 0)
                recordingFilename = finalized.basename
                recordingFileURL = finalized.audioURL
            } else {
                recordingFilename = nil
            }
            captureService.stopIfUnused()
            scheduleClearRecordingFilename()
        } catch {
            Trace.event("record.stopError", ["error": error.localizedDescription])
            userMessage = error.localizedDescription
        }
    }

    private var clearFilenameTask: Task<Void, Never>?

    private func scheduleClearRecordingFilename() {
        clearFilenameTask?.cancel()
        clearFilenameTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            recordingFilename = nil
            recordingFileURL = nil
        }
    }

    func revealRecordingInFinder() {
        guard let url = recordingFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func stopTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isStartingTranscription = false

        Trace.event("transcribe.stopping", [
            "segments": transcription.segments.count,
            "isTranscribing": transcription.isTranscribing
        ])
        captureService.removeConsumer(id: "transcribe")
        transcription.stop()
        captureService.stopIfUnused()
        Trace.event("transcribe.stopped", ["finalSegments": transcription.segments.count])
    }
}

enum AppModelError: LocalizedError {
    case microphonePermissionRequired
    case speechPermissionRequired

    var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return "Microphone permission is required before audio capture can start."
        case .speechPermissionRequired:
            return "Speech recognition permission is required before transcription can start."
        }
    }
}
