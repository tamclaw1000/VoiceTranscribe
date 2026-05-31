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
            captureService.removeConsumer(id: "listen")
            captureService.stopIfUnused()
            return
        }

        Task {
            do {
                try await ensureCapture(for: source)
                captureService.addConsumer(id: "listen") { _, _ in }
            } catch {
                userMessage = error.localizedDescription
            }
        }
    }

    func toggleRecord(for source: SoundInputSource) {
        if recordingService.isRecording {
            stopRecording()
            return
        }

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

                if settings.startTranscriptionWithRecording && !transcription.isTranscribing {
                    try startTranscriptionConsumer(for: source)
                }
            } catch {
                userMessage = error.localizedDescription
            }
        }
    }

    func toggleTranscribe(for source: SoundInputSource) {
        if transcription.isTranscribing {
            stopTranscription()
            return
        }

        Task {
            do {
                try await ensureCapture(for: source)
                try startTranscriptionConsumer(for: source)
            } catch {
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

    private func startTranscriptionConsumer(for source: SoundInputSource) throws {
        if !permissionService.canTranscribe {
            throw AppModelError.speechPermissionRequired
        }

        try transcription.start()
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
                completedRecordings.insert(finalized, at: 0)
            }
            captureService.stopIfUnused()
        } catch {
            userMessage = error.localizedDescription
        }
    }

    private func stopTranscription() {
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
