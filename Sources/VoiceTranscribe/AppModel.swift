import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceService = AudioDeviceService()
    @Published var permissionService = PermissionService()
    @Published var settings = AppSettings()
    @Published var captureService = AudioCaptureService()
    @Published var recordingService = RecordingService()
    @Published var transcription = TranscriptionCoordinator()
    @Published var completedRecordings: [RecordingSession] = []
    @Published var userMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
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

    func toggleListen(for source: SoundInputSource) {
        if isListening(source) {
            Trace.button("listen.stop", source: source.name)
            captureService.removeConsumer(id: "listen")
            captureService.stopIfUnused()
            return
        }

        Trace.button("listen.start", source: source.name)
        Task {
            do {
                try await ensureCapture(for: source)
                captureService.addConsumer(id: "listen") { _, _ in }
                Trace.event("listen.started", ["source": source.name])
            } catch {
                Trace.event("listen.error", ["source": source.name, "error": error.localizedDescription])
                userMessage = error.localizedDescription
            }
        }
    }

    func toggleRecord(for source: SoundInputSource) {
        if recordingService.isRecording {
            Trace.button("record.stop", source: source.name)
            stopRecording()
            return
        }

        Trace.button("record.start", source: source.name)
        Task {
            do {
                try await ensureCapture(for: source)
                try recordingService.start(
                    source: source,
                    inputFormat: captureService.currentInputFormat,
                    outputFolder: settings.outputFolder,
                    outputFormat: settings.audioOutputFormat
                )
                captureService.addConsumer(id: "record") { [weak recordingService] buffer, time in
                    Task { @MainActor in
                        recordingService?.consume(buffer: buffer, time: time)
                    }
                }
                Trace.event("record.started", ["source": source.name, "outputFolder": settings.outputFolder.path])

                if settings.startTranscriptionWithRecording && !transcription.isTranscribing {
                    try await startTranscriptionConsumer(for: source)
                }
            } catch {
                Trace.event("record.error", ["source": source.name, "error": error.localizedDescription])
                userMessage = error.localizedDescription
            }
        }
    }

    func toggleTranscribe(for source: SoundInputSource) {
        if transcription.isTranscribing {
            Trace.button("transcribe.stop", source: source.name)
            stopTranscription()
            return
        }

        Trace.button("transcribe.start", source: source.name)
        Task {
            do {
                try await ensureCapture(for: source)
                try await startTranscriptionConsumer(for: source)
                Trace.event("transcribe.started", ["source": source.name])
            } catch {
                Trace.event("transcribe.error", ["source": source.name, "error": error.localizedDescription])
                userMessage = error.localizedDescription
            }
        }
    }

    func isListening(_ source: SoundInputSource) -> Bool {
        captureService.activeSource?.id == source.id && captureService.activeConsumerIDs.contains("listen")
    }

    func isRecording(_ source: SoundInputSource) -> Bool {
        recordingService.activeSession?.source.id == source.id
    }

    func isTranscribing(_ source: SoundInputSource) -> Bool {
        captureService.activeSource?.id == source.id && transcription.isTranscribing
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
        do {
            captureService.removeConsumer(id: "record")
            let finalized = try recordingService.stop(
                transcriptText: transcription.transcriptText,
                saveTranscript: settings.saveTranscriptsAutomatically && !transcription.transcriptText.isEmpty,
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
            }
            captureService.stopIfUnused()
        } catch {
            Trace.event("record.stopError", ["error": error.localizedDescription])
            userMessage = error.localizedDescription
        }
    }

    private func stopTranscription() {
        Trace.event("transcribe.stopped", ["segments": transcription.segments.count])
        captureService.removeConsumer(id: "transcribe")
        transcription.stop()
        captureService.stopIfUnused()
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
