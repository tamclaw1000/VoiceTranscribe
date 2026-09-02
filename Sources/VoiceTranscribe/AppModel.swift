import AppKit
import AVFoundation
import Combine
import CoreMedia
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceService = AudioDeviceService()
    @Published var permissionService = PermissionService()
    @Published var settings = AppSettings()
    @Published var captureService = AudioCaptureService()
    @Published var recordingService = RecordingService()
    @Published var transcription: TranscriptionCoordinator
    @Published var factCheck = FactCheckCoordinator()
    @Published var summary = SummaryCoordinator()

    /// Tracks whether the user has completed the initial permissions setup flow.
    /// Persisted so we don't re-prompt on every launch after setup.
    @AppStorage("hasCompletedPermissionsSetup") var hasCompletedPermissionsSetup: Bool = false
    @AppStorage("hasRunFirstLaunchPermissionRequest") private var hasRunFirstLaunchPermissionRequest: Bool = false
    @Published private(set) var isRunningFirstLaunchPermissionFlow = false

    /// Whether Settings should auto-open (permissions are missing and not yet set up).
    var needsPermissionsSetup: Bool {
        !hasCompletedPermissionsSetup
            && (!permissionService.canCaptureAudio || !permissionService.canTranscribe)
    }

    /// Call when the user dismisses Settings with both permissions granted.
    func markPermissionsSetupComplete() {
        if permissionService.canCaptureAudio && permissionService.canTranscribe {
            hasCompletedPermissionsSetup = true
        }
    }

    @discardableResult
    func runFirstLaunchPermissionFlowIfNeeded() async -> Bool {
        guard !isRunningFirstLaunchPermissionFlow else {
            return false
        }

        permissionService.refresh()
        let needsMicrophonePrompt = permissionService.microphoneStatus == .notDetermined
        let needsSpeechPrompt = permissionService.speechStatus == .notDetermined
        guard needsMicrophonePrompt || needsSpeechPrompt else {
            if !hasRunFirstLaunchPermissionRequest {
                hasRunFirstLaunchPermissionRequest = true
            }
            markPermissionsSetupComplete()
            return false
        }

        isRunningFirstLaunchPermissionFlow = true
        defer { isRunningFirstLaunchPermissionFlow = false }

        Trace.event("permission.firstLaunch.started", [
            "microphone": permissionService.microphoneStatus.rawValue,
            "speech": permissionService.speechStatus.rawValue
        ])

        if needsMicrophonePrompt {
            await permissionService.requestMicrophonePermission()
        }
        if needsSpeechPrompt {
            await permissionService.requestSpeechPermission()
        }

        permissionService.refresh()
        hasRunFirstLaunchPermissionRequest = true
        markPermissionsSetupComplete()
        UserDefaults.standard.synchronize()

        Trace.event("permission.firstLaunch.completed", [
            "microphone": permissionService.microphoneStatus.rawValue,
            "speech": permissionService.speechStatus.rawValue,
            "canCaptureAudio": permissionService.canCaptureAudio,
            "canTranscribe": permissionService.canTranscribe
        ])

        restartAfterPermissionDialog()
        return true
    }

    private func restartAfterPermissionDialog() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            userMessage = "Permissions were updated. Please restart VoiceTranscribe to continue."
            Trace.event("app.restart.skipped", ["reason": "notAppBundle", "bundle": bundleURL.path])
            return
        }

        userMessage = "Permissions were updated. VoiceTranscribe will restart now."
        Trace.event("app.restart.scheduled", ["bundle": bundleURL.path])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]

            do {
                try process.run()
                Trace.event("app.restart.launched", ["bundle": bundleURL.path])
                NSApp.terminate(nil)
            } catch {
                self.userMessage = "Permissions were updated. Please restart VoiceTranscribe manually."
                Trace.event("app.restart.failed", ["error": error.localizedDescription])
            }
        }
    }

    private static func makeInitialService() -> TranscriptionService {
        let raw = UserDefaults.standard.string(forKey: "transcriptionEngine") ?? AppSettings.defaultTranscriptionEngine.rawValue
        let kind = TranscriptionEngineKind(rawValue: raw) ?? AppSettings.defaultTranscriptionEngine
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

    // MARK: - File Input Sources

    /// Loaded audio file sources.
    @Published var fileSources: [FileInputSource] = []
    /// ID of the file source currently being transcribed, if any.
    @Published private(set) var activeFileSourceID: String?
    /// Transcription progress for the active file source (0…1).
    @Published private(set) var fileTranscriptionProgress: Double = 0
    /// Whether a file transcription is currently running.
    @Published private(set) var isTranscribingFile: Bool = false
    /// Display name for the source associated with the current transcript.
    @Published private(set) var transcriptSourceName: String = "Unknown"

    private var cancellables = Set<AnyCancellable>()
    private var transcriptionTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var fileTranscriptionTask: Task<Void, Never>?

    init() {
        transcription = TranscriptionCoordinator(service: AppModel.makeInitialService())
        transcription.onFinalSegment = { [weak self] segment in
            guard let self else { return }
            let llm = self.settings.selectedLLMEndpoint
            self.factCheck.enqueueTranscriptSegment(
                segment,
                enabled: self.settings.isFactCheckActive,
                llm: llm,
                promptTemplate: self.settings.ollamaFactCheckPrompt
            )
            self.summary.enqueueTranscriptSegment(segment, prompt: self.settings.summaryPrompt)
        }

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
        factCheck.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        summary.objectWillChange.sink { [weak self] _ in
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

    func setAIEnabled(_ enabled: Bool) {
        guard settings.aiEnabled != enabled else {
            return
        }

        settings.aiEnabled = enabled
        Trace.event("settings.aiToggled", ["enabled": enabled])
        if !enabled {
            factCheck.reset()
        }
    }

    func testSelectedLLMFactCheck() {
        guard settings.aiEnabled else {
            userMessage = "AI is disabled. Turn on AI to test fact-checking."
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let llm = self.settings.selectedLLMEndpoint
            do {
                let result = try await OllamaFactCheckService(timeout: 15).factCheck(
                    sentence: "The Earth orbits the Sun.",
                    llm: llm,
                    promptTemplate: self.settings.ollamaFactCheckPrompt
                )
                self.userMessage = "\(llm.displayName) fact-check succeeded: \(result.verdict.displayName)."
            } catch {
                self.userMessage = "\(llm.displayName) fact-check failed: \(error.localizedDescription)"
            }
        }
    }

    func testSelectedLLMPlainPrompt() {
        guard settings.aiEnabled else {
            userMessage = "AI is disabled. Turn on AI to test the selected LLM."
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let llm = self.settings.selectedLLMEndpoint
            let prompt = "Hello, what is 10 * 20?"
            do {
                let response = try await OllamaFactCheckService(timeout: 15).generate(prompt: prompt, llm: llm)
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                self.userMessage = "\(llm.displayName) replied: \(trimmed.isEmpty ? "(empty response)" : trimmed)"
            } catch {
                self.userMessage = "\(llm.displayName) prompt test failed: \(error.localizedDescription)"
            }
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
                self.transcriptSourceName = source.name
                if self.settings.isFactCheckActive {
                    self.factCheck.reset()
                }
                self.summary.reset()
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
            let saveTranscript = !transcription.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                // Auto-load the recording as a file input source (v1.7.0).
                if let source = FileInputSource.from(url: finalized.audioURL) {
                    fileSources.append(source)
                    Trace.event("fileSource.autoLoaded", [
                        "name": source.name,
                        "duration": String(format: "%.1f", source.duration)
                    ])
                }
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

    func copyTranscriptText() {
        let text = transcription.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            userMessage = "There is no transcript text to copy."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Trace.event("transcript.copied", ["chars": text.count])
        userMessage = "Transcript copied to the clipboard."
    }

    func saveTranscriptToFile() {
        let text = transcription.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            userMessage = "There is no transcript text to save."
            return
        }

        let panel = NSSavePanel()
        try? FileManager.default.createDirectory(at: settings.outputFolder, withIntermediateDirectories: true)
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputFolder
        panel.nameFieldStringValue = "\(FileNamer.startTimestamp(Date()))-\(FileNamer.sourceSlug(transcriptSourceName)).txt"
        panel.message = "Save the current transcript text."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            Trace.file("transcript.exported", path: url.path, extra: ["chars": text.count])
            userMessage = "Transcript saved to \(url.lastPathComponent)."
        } catch {
            Trace.event("transcript.exportError", [
                "path": url.path,
                "error": error.localizedDescription
            ])
            userMessage = "Could not save transcript: \(error.localizedDescription)"
        }
    }

    func saveTranscriptMarkdownToFile() {
        let text = transcription.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            userMessage = "There is no transcript text to export."
            return
        }

        let context = markdownExportContext()
        let markdown = MarkdownExportService.makeDocument(
            context: context,
            finalizedSegments: transcription.segments,
            factChecks: factCheck.items,
            summaryParagraphs: summary.paragraphs
        )

        let panel = NSSavePanel()
        try? FileManager.default.createDirectory(at: settings.outputFolder, withIntermediateDirectories: true)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputFolder
        panel.nameFieldStringValue = "\(FileNamer.startTimestamp(Date()))-\(FileNamer.sourceSlug(transcriptSourceName)).md"
        panel.message = "Export the current transcript, summary, and fact-check results as Markdown."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            Trace.file("transcript.markdownExported", path: url.path, extra: ["chars": markdown.count])
            userMessage = "Markdown exported to \(url.lastPathComponent)."
        } catch {
            Trace.event("transcript.markdownExportError", [
                "path": url.path,
                "error": error.localizedDescription
            ])
            userMessage = "Could not export Markdown: \(error.localizedDescription)"
        }
    }

    private func markdownExportContext() -> MarkdownExportContext {
        let session = recordingService.activeSession ?? completedRecordings.first
        let fallbackStart = transcription.segments.first?.timestamp
        let fallbackEnd = transcription.segments.last?.timestamp
        let selectedLLM = settings.selectedLLMEndpoint

        return MarkdownExportContext(
            sourceName: transcriptSourceName,
            location: "Not specified",
            startDate: session?.startDate ?? fallbackStart,
            endDate: session?.endDate ?? fallbackEnd,
            exportedAt: Date(),
            transcriptionEngine: transcription.engineName,
            aiEnabled: settings.aiEnabled,
            factCheckEnabled: settings.factCheckEnabled,
            llmName: selectedLLM.displayName,
            llmProvider: selectedLLM.provider.displayName,
            llmEndpoint: selectedLLM.endpoint,
            llmModel: selectedLLM.model,
            factCheckPrompt: settings.ollamaFactCheckPrompt,
            summaryPrompt: settings.summaryPrompt,
            audioURL: session?.audioURL,
            transcriptURL: session?.transcriptURL,
            metadataURL: session?.metadataURL
        )
    }

    func copySummaryText() {
        let text = summary.paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            userMessage = "There is no summary text to copy."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Trace.event("summary.copied", ["chars": text.count])
        userMessage = "Summary copied to the clipboard."
    }

    func saveSummaryToFile() {
        let text = summary.paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            userMessage = "There is no summary text to save."
            return
        }

        let panel = NSSavePanel()
        try? FileManager.default.createDirectory(at: settings.outputFolder, withIntermediateDirectories: true)
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputFolder
        panel.nameFieldStringValue = "\(FileNamer.startTimestamp(Date()))-\(FileNamer.sourceSlug(transcriptSourceName))-summary.txt"
        panel.message = "Save the current recording summary."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            Trace.file("summary.exported", path: url.path, extra: ["chars": text.count])
            userMessage = "Summary saved to \(url.lastPathComponent)."
        } catch {
            Trace.event("summary.exportError", [
                "path": url.path,
                "error": error.localizedDescription
            ])
            userMessage = "Could not save summary: \(error.localizedDescription)"
        }
    }

    // MARK: - File Input Sources

    /// Open a file picker and load audio files as virtual input sources.
    func loadAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .wav, .mp3,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "caf") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Select audio files to transcribe."

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard !fileSources.contains(where: { $0.url == url }) else {
                Trace.event("fileSource.skipDuplicate", ["url": url.path])
                continue
            }
            if let source = FileInputSource.from(url: url) {
                fileSources.append(source)
                Trace.event("fileSource.loaded", [
                    "name": source.name,
                    "format": source.audioFormat,
                    "duration": String(format: "%.1f", source.duration),
                    "sampleRate": Int(source.sampleRate),
                    "channels": source.channelCount
                ])
            } else {
                userMessage = "Could not read \(url.lastPathComponent)."
                Trace.event("fileSource.loadError", ["url": url.path])
            }
        }
    }

    /// Remove a file source. Stops transcription if this file was active.
    func removeFileSource(id: String) {
        if activeFileSourceID == id {
            cancelFileTranscription()
        }
        fileSources.removeAll { $0.id == id }
        Trace.event("fileSource.removed", ["id": id])
    }

    /// Transcribe (or stop transcribing) a file source.
    func transcribeFile(_ source: FileInputSource) {
        if isTranscribingFile && activeFileSourceID == source.id {
            Trace.button("fileTranscribe.stop", source: source.name)
            cancelFileTranscription()
            return
        }

        guard !isTranscribingFile else {
            Trace.event("fileTranscribe.guard.skip", ["reason": "alreadyTranscribing"])
            return
        }

        Trace.button("fileTranscribe.start", source: source.name, extra: [
            "duration": String(format: "%.1f", source.duration),
            "engine": transcription.engineName
        ])

        // Ensure no mic capture is active.
        captureService.stop()

        activeFileSourceID = source.id
        isTranscribingFile = true
        fileTranscriptionProgress = 0
        transcriptSourceName = source.name

        fileTranscriptionTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.transcription.start()
                if self.settings.isFactCheckActive {
                    self.factCheck.reset()
                }
                self.summary.reset()
                Trace.event("fileTranscribe.started", [
                    "file": source.name,
                    "engine": self.transcription.engineName
                ])

                try await self.feedFileToTranscription(url: source.url, duration: source.duration)

                // Brief pause to let the engine drain.
                try? await Task.sleep(nanoseconds: 500_000_000)

                await MainActor.run {
                    self.transcription.stop()
                    self.isTranscribingFile = false
                    self.activeFileSourceID = nil
                    self.fileTranscriptionProgress = 1.0
                    Trace.event("fileTranscribe.completed", ["file": source.name])
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.transcription.stop()
                    self.isTranscribingFile = false
                    self.activeFileSourceID = nil
                    Trace.event("fileTranscribe.cancelled", ["file": source.name])
                }
            } catch {
                await MainActor.run {
                    self.transcription.stop()
                    self.isTranscribingFile = false
                    self.activeFileSourceID = nil
                    self.userMessage = "File transcription failed: \(error.localizedDescription)"
                    Trace.event("fileTranscribe.error", [
                        "file": source.name,
                        "error": error.localizedDescription
                    ])
                }
            }
        }
    }

    /// Returns true if the given file source is currently being transcribed.
    func isTranscribingFileSource(_ source: FileInputSource) -> Bool {
        isTranscribingFile && activeFileSourceID == source.id
    }

    private func cancelFileTranscription() {
        fileTranscriptionTask?.cancel()
        fileTranscriptionTask = nil
        transcription.stop()
        isTranscribingFile = false
        activeFileSourceID = nil
        fileTranscriptionProgress = 0
    }

    /// Read an audio file and feed its PCM buffers to the transcription coordinator.
    private func feedFileToTranscription(url: URL, duration: TimeInterval) async throws {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            // Fallback: use AVAssetReader for formats AVAudioFile can't open
            try await feedViaAssetReader(url: url, duration: duration)
            return
        }

        let format = file.processingFormat
        let totalFrames = file.length
        let bufferSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw AppModelError.fileReadFailed
        }

        file.framePosition = 0
        var framesRead: AVAudioFramePosition = 0

        while framesRead < totalFrames {
            try Task.checkCancellation()

            buffer.frameLength = 0
            try file.read(into: buffer)
            let frames = buffer.frameLength
            if frames == 0 { break }

            // Deep-copy before handing off (buffer is reused).
            guard let copy = copyPCMBuffer(buffer) else { continue }

            let sampleTime = AVAudioFramePosition(framesRead)
            let hostTime = AVAudioTime.hostTime(
                forSeconds: Double(sampleTime) / format.sampleRate
            )
            let time = AVAudioTime(
                hostTime: hostTime,
                sampleTime: sampleTime,
                atRate: format.sampleRate
            )

            await MainActor.run {
                self.transcription.consume(buffer: copy, time: time)
            }

            framesRead += AVAudioFramePosition(frames)
            let progress = Double(framesRead) / Double(totalFrames)

            await MainActor.run {
                self.fileTranscriptionProgress = progress
            }
        }
    }

    /// Fallback: use AVAssetReader for formats AVAudioFile can't open (e.g. FLAC).
    private func feedViaAssetReader(url: URL, duration: TimeInterval) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw AppModelError.fileReadFailed
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AppModelError.fileReadFailed
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw AppModelError.fileReadFailed
        }

        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        var framesRead: AVAudioFramePosition = 0
        let totalFrames = AVAudioFramePosition(duration * 16000)

        while reader.status == .reading {
            try Task.checkCancellation()

            guard let sample = output.copyNextSampleBuffer() else { continue }
            guard let pcm = createPCMBuffer(from: sample, format: outFormat) else { continue }

            let copy = copyPCMBuffer(pcm) ?? pcm
            let sampleTime = AVAudioFramePosition(framesRead)
            let hostTime = AVAudioTime.hostTime(
                forSeconds: Double(sampleTime) / 16000
            )
            let time = AVAudioTime(
                hostTime: hostTime,
                sampleTime: sampleTime,
                atRate: 16000
            )

            await MainActor.run {
                self.transcription.consume(buffer: copy, time: time)
            }

            framesRead += AVAudioFramePosition(pcm.frameLength)
            let progress = totalFrames > 0
                ? Double(framesRead) / Double(totalFrames)
                : 0

            await MainActor.run {
                self.fileTranscriptionProgress = min(progress, 1.0)
            }
        }

        if reader.status == .failed {
            throw reader.error ?? AppModelError.fileReadFailed
        }
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
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return "Microphone permission is required before audio capture can start."
        case .speechPermissionRequired:
            return "Speech recognition permission is required before transcription can start."
        case .fileReadFailed:
            return "Could not read the audio file. It may be in an unsupported format or corrupted."
        }
    }
}

// MARK: - PCM Buffer Helpers

/// Deep-copy an AVAudioPCMBuffer.
private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
        return nil
    }
    copy.frameLength = buffer.frameLength
    let channels = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)

    if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
        for ch in 0..<channels {
            memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size)
        }
        return copy
    }
    if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
        for ch in 0..<channels {
            memcpy(dst[ch], src[ch], frames * MemoryLayout<Int16>.size)
        }
        return copy
    }
    if let src = buffer.int32ChannelData, let dst = copy.int32ChannelData {
        for ch in 0..<channels {
            memcpy(dst[ch], src[ch], frames * MemoryLayout<Int32>.size)
        }
        return copy
    }
    return nil
}

/// Create an AVAudioPCMBuffer from a CMSampleBuffer.
private func createPCMBuffer(from sample: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    var bufferList = AudioBufferList()
    var blockBuffer: CMBlockBuffer?
    let frameCount = CMSampleBufferGetNumSamples(sample)

    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sample,
        bufferListSizeNeededOut: nil,
        bufferListOut: &bufferList,
        bufferListSize: MemoryLayout<AudioBufferList>.size,
        blockBufferAllocator: nil,
        blockBufferMemoryAllocator: nil,
        flags: 0,
        blockBufferOut: &blockBuffer
    )

    guard status == noErr, frameCount > 0 else { return nil }

    guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
        return nil
    }
    pcm.frameLength = AVAudioFrameCount(frameCount)

    // Copy from the AudioBufferList into our PCM buffer
    let channels = Int(format.channelCount)
    for ch in 0..<min(channels, 1) {
        if let src = bufferList.mBuffers.mData?.assumingMemoryBound(to: Int16.self),
           let dst = pcm.int16ChannelData?[ch] {
            memcpy(dst, src, Int(frameCount) * MemoryLayout<Int16>.size)
        }
    }

    return pcm
}
