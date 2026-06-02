import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sourceList
                .navigationTitle("VoiceTranscribe")
                .toolbar {
                    Button {
                        appModel.refreshDevices()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
        } detail: {
            VStack(spacing: 0) {
                settingsBar
                Divider()
                mainDetail
            }
        }
        .alert("VoiceTranscribe", isPresented: Binding(
            get: { appModel.userMessage != nil },
            set: { if !$0 { appModel.userMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                appModel.userMessage = nil
            }
        } message: {
            Text(appModel.userMessage ?? "")
        }
        .task {
            // Auto-open Settings on first launch if permissions are missing.
            if appModel.needsPermissionsSetup {
                showSettings = true
            }
        }
    }

    private var sourceList: some View {
        List {
            // Device sources
            Section("Microphones") {
                if appModel.deviceService.sources.isEmpty {
                    Text("No microphones available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.deviceService.sources) { source in
                        SourceRow(source: source)
                            .environmentObject(appModel)
                            .padding(.vertical, 4)
                    }
                }
            }

            // File sources
            Section("File Sources") {
                if appModel.fileSources.isEmpty {
                    HStack {
                        Text("No files loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Load File…") {
                            appModel.loadAudioFiles()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                } else {
                    ForEach(appModel.fileSources) { source in
                        FileSourceRow(source: source)
                            .environmentObject(appModel)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var settingsBar: some View {
        let permissionsOK = appModel.permissionService.canCaptureAudio
            && appModel.permissionService.canTranscribe

        HStack(spacing: 12) {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .foregroundColor(permissionsOK ? .secondary : .orange)
                    Text(permissionsOK ? "Settings" : "Settings — Permissions Needed")
                        .foregroundColor(permissionsOK ? .primary : .orange)
                }
            }
            .buttonStyle(.bordered)
            .help(permissionsOK
                ? "Transcription engine, permissions, and more"
                : "Microphone or speech recognition permissions are missing — open Settings to grant them")

            if !permissionsOK {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Microphone & Speech access required")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
                .environmentObject(appModel)
        }
    }

    private var mainDetail: some View {
        VStack(spacing: 0) {
            GraphPanel(snapshot: appModel.captureService.visualization)
                .frame(height: 240)
                .padding()

            Divider()

            TranscriptPanel(
                finalized: appModel.transcription.segments,
                interim: appModel.transcription.interimSegment,
                buffer: appModel.transcription.bufferSnapshot,
                isTranscribing: appModel.transcription.isTranscribing
            )

            if !appModel.completedRecordings.isEmpty {
                Divider()
                RecentRecordingsView(recordings: appModel.completedRecordings)
                    .frame(height: 140)
            }
        }
    }
}

private struct SourceRow: View {
    @EnvironmentObject private var appModel: AppModel
    let source: SoundInputSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: source.isDefaultInput ? "mic.fill" : "mic")
                    .foregroundStyle(source.isDefaultInput ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.headline)
                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if source.isDefaultInput {
                    Text("Default")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                // Transcribe / Stop button
                let permissionsOK = appModel.permissionService.canCaptureAudio
                    && appModel.permissionService.canTranscribe

                Button {
                    appModel.toggleTranscribe(for: source)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appModel.isTranscribing(source) ? "text.bubble.fill" : "text.bubble")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(appModel.isTranscribing(source) ? Color.green : Color.secondary)
                        Text(appModel.isTranscribing(source) ? "Stop" : "Transcribe")
                            .foregroundStyle(appModel.isTranscribing(source) ? Color.green : Color.primary)
                    }
                }
                .tint(appModel.isTranscribing(source) ? .green : .accentColor)
                .disabled(!permissionsOK)
                .help(!permissionsOK ? "Microphone and speech recognition permissions are required" : "")
                .accessibilityValue(appModel.isTranscribing(source) ? "Active" : "Inactive")

                // Record checkbox
                Toggle(isOn: Binding(
                    get: { appModel.isRecording(source) },
                    set: { _ in appModel.toggleRecord(for: source) }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: appModel.isRecording(source) ? "record.circle.fill" : "record.circle")
                            .foregroundStyle(appModel.isRecording(source) ? .red : .secondary)
                        Text("Record")
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!permissionsOK)

                if let filename = appModel.recordingFilename {
                    Button {
                        appModel.revealRecordingInFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text(filename)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if appModel.activeSourceID == source.id {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!source.isAvailable)

            SourceConsoleView(source: source)
                .environmentObject(appModel)
        }
    }
}

private struct SourceConsoleView: View {
    @EnvironmentObject private var appModel: AppModel
    let source: SoundInputSource

    private var isActiveSource: Bool {
        appModel.activeSourceID == source.id
    }

    private var modeText: String {
        var modes: [String] = []
        if appModel.isTranscribing(source) {
            modes.append("transcribe")
        }
        if appModel.isRecording(source) {
            modes.append("record")
        }
        return modes.isEmpty ? "none" : modes.joined(separator: ",")
    }

    private var captureText: String {
        if isActiveSource {
            return "capture=active"
        }
        return "capture=idle"
    }

    var body: some View {
        let visualization = isActiveSource
            ? appModel.captureService.visualization
            : VisualizationSnapshot()
        let buffer = isActiveSource
            ? appModel.transcription.bufferSnapshot
            : TranscriptionBufferSnapshot()
        let isTranscribing = isActiveSource && appModel.transcription.isTranscribing

        VStack(alignment: .leading, spacing: 4) {
            Text(
                "\(captureText) modes=\(modeText) rms=\(Int(visualization.rmsLevel * 100))% peak=\(Int(visualization.peakLevel * 100))%"
            )
            Text(
                "transcription=\(isTranscribing ? "active" : "idle") buffer=\(String(format: "%.1f", buffer.queuedDuration))s receiving=\(buffer.isReceivingAudio ? "yes" : "no")"
            )
        }
        .font(.caption2.monospaced())
        .foregroundStyle(isActiveSource ? Color.green : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActiveSource ? Color.green.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct PermissionStatusView: View {
    let title: String
    let status: String
    let isAllowed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isAllowed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isAllowed ? .green : .orange)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Label("Settings", systemImage: "gearshape")
                    .font(.title2.bold())
                Spacer()
                Button {
                    appModel.markPermissionsSetupComplete()
                    isPresented = false
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 8)

            Divider()

            // Transcription engine
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcription Engine", systemImage: "text.bubble")
                        .font(.headline)
                    Picker("Engine", selection: Binding(
                        get: { appModel.settings.transcriptionEngine },
                        set: { newEngine in
                            appModel.transcription.setEngine(newEngine)
                            appModel.settings.transcriptionEngine = newEngine
                        }
                    )) {
                        ForEach(TranscriptionEngineKind.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(appModel.transcription.isTranscribing)
                    if appModel.transcription.isTranscribing {
                        Text("Stop transcription before changing the engine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Permissions
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Permissions", systemImage: "lock.shield")
                        .font(.headline)

                    // Mic
                    HStack {
                        PermissionStatusView(
                            title: "Microphone",
                            status: microphoneStatusText(appModel.permissionService.microphoneStatus),
                            isAllowed: appModel.permissionService.canCaptureAudio
                        )
                        Spacer()
                        Button {
                            appModel.requestMicrophonePermission()
                        } label: {
                            Text(appModel.permissionService.microphoneStatus == .notDetermined
                                ? "Request Access" : "Open Settings")
                        }
                        .disabled(appModel.permissionService.microphoneStatus == .authorized)
                    }

                    // Speech
                    HStack {
                        PermissionStatusView(
                            title: "Speech Recognition",
                            status: speechStatusText(appModel.permissionService.speechStatus),
                            isAllowed: appModel.permissionService.canTranscribe
                        )
                        Spacer()
                        Button {
                            appModel.requestSpeechPermission()
                        } label: {
                            Text(appModel.permissionService.speechStatus == .notDetermined
                                ? "Request Access" : "Open Settings")
                        }
                        .disabled(appModel.permissionService.speechStatus == .authorized)
                    }

                    // System Settings shortcut
                    Divider()
                    Button {
                        appModel.permissionService.openSystemPrivacySettings()
                    } label: {
                        Label("Open System Privacy Settings…", systemImage: "arrow.up.forward.app")
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 380)
    }

    private func microphoneStatusText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:  return "Allowed"
        case .denied:      return "Denied"
        case .restricted:  return "Restricted"
        case .notDetermined: return "Not Requested"
        @unknown default:  return "Unknown"
        }
    }

    private func speechStatusText(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:  return "Allowed"
        case .denied:      return "Denied"
        case .restricted:  return "Restricted"
        case .notDetermined: return "Not Requested"
        @unknown default:  return "Unknown"
        }
    }
}

private struct GraphPanel: View {
    let snapshot: VisualizationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Input Level", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text(snapshot.isClipping ? "Clipping" : "RMS \(Int(snapshot.rmsLevel * 100))%  Peak \(Int(snapshot.peakLevel * 100))%")
                    .font(.caption)
                    .foregroundStyle(snapshot.isClipping ? .red : .secondary)
            }

            Canvas { context, size in
                let midY = size.height / 2
                let values = snapshot.history.isEmpty ? [0] : snapshot.history
                let stepX = size.width / CGFloat(max(values.count, 1))
                var path = Path()

                for index in values.indices {
                    let x = CGFloat(index) * stepX + stepX / 2
                    let normalized = CGFloat(min(max(values[index], 0), 1))
                    let barHeight = max(normalized * size.height * 0.90, normalized > 0 ? 2 : 0)
                    let barRect = CGRect(
                        x: CGFloat(index) * stepX,
                        y: midY - barHeight / 2,
                        width: max(stepX - 1, 1),
                        height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: barRect, cornerRadius: 2),
                        with: .color(.green.opacity(0.32 + normalized * 0.45))
                    )

                    let y = midY - (normalized * size.height * 0.45)
                    if index == values.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                var mirror = Path()
                for index in values.indices {
                    let x = CGFloat(index) * stepX + stepX / 2
                    let normalized = CGFloat(min(max(values[index], 0), 1))
                    let y = midY + (normalized * size.height * 0.45)
                    if index == values.startIndex {
                        mirror.move(to: CGPoint(x: x, y: y))
                    } else {
                        mirror.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(path, with: .color(.green), lineWidth: 2.5)
                context.stroke(mirror, with: .color(.green.opacity(0.6)), lineWidth: 2.5)
                context.stroke(Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                }, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            }
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct TranscriptPanel: View {
    let finalized: [TranscriptSegment]
    let interim: TranscriptSegment?
    let buffer: TranscriptionBufferSnapshot
    let isTranscribing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Transcript", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                TranscriptionStatusView(buffer: buffer, isTranscribing: isTranscribing)
                    .frame(width: 260)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if finalized.isEmpty && interim == nil {
                            ContentUnavailableView(
                                "No Transcript",
                                systemImage: "text.bubble",
                                description: Text("Start transcription to see speech as it is processed.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            ForEach(finalized) { segment in
                                Text(segment.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let interim {
                                Text(interim.text)
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("interim")
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .onChange(of: finalized.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("interim", anchor: .bottom)
                    }
                }
            }
        }
        .padding()
    }
}

private struct TranscriptionStatusView: View {
    let buffer: TranscriptionBufferSnapshot
    let isTranscribing: Bool

    private var statusText: String {
        guard isTranscribing else {
            return "Idle"
        }
        if buffer.isReceivingAudio {
            return "Receiving audio"
        }
        if buffer.queuedDuration > 0 {
            return "Processing buffer"
        }
        return "Waiting for audio"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isTranscribing ? (buffer.isReceivingAudio ? Color.green : Color.orange) : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1fs", buffer.queuedDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.18))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isTranscribing ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: geometry.size.width * buffer.fillFraction)
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Transcription buffer")
            .accessibilityValue(String(format: "%.1f seconds queued", buffer.queuedDuration))
        }
    }
}

private struct RecentRecordingsView: View {
    let recordings: [RecordingSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Recordings", systemImage: "folder")
                .font(.headline)
            List(recordings) { recording in
                HStack {
                    VStack(alignment: .leading) {
                        Text(recording.basename)
                            .font(.caption.weight(.semibold))
                        Text(recording.audioURL.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(recording.duration, format: .number.precision(.fractionLength(1)))
                        .font(.caption)
                }
            }
            .listStyle(.plain)
        }
        .padding()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Output") {
                HStack {
                    TextField("Folder", text: $appModel.settings.outputFolderPath)
                    Button {
                        chooseOutputFolder()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                }

                Picker("Audio Format", selection: Binding(
                    get: { appModel.settings.audioOutputFormat },
                    set: { appModel.settings.audioOutputFormat = $0 }
                )) {
                    ForEach(AudioOutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            }

            Section("Transcription") {
                Picker("Engine", selection: Binding(
                    get: { appModel.settings.transcriptionEngine },
                    set: { newEngine in
                        appModel.transcription.setEngine(newEngine)
                        appModel.settings.transcriptionEngine = newEngine
                    }
                )) {
                    ForEach(TranscriptionEngineKind.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .disabled(appModel.transcription.isTranscribing)
                Toggle("Save transcripts automatically", isOn: $appModel.settings.saveTranscriptsAutomatically)
            }

            Section("Visualization") {
                Slider(
                    value: $appModel.settings.visualizationSensitivity,
                    in: 0.25...3.0,
                    step: 0.25
                ) {
                    Text("Sensitivity")
                }
            }
        }
        .padding()
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appModel.settings.outputFolderPath = url.path
        }
    }
}

// MARK: - File Source Row

private struct FileSourceRow: View {
    @EnvironmentObject private var appModel: AppModel
    let source: FileInputSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "doc.waveform")
                    .foregroundStyle(
                        appModel.isTranscribingFileSource(source)
                            ? Color.green : Color.secondary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.headline)
                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appModel.removeFileSource(id: source.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this file source.")
            }

            HStack(spacing: 8) {
                // Transcribe / Stop button
                Button {
                    appModel.transcribeFile(source)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appModel.isTranscribingFileSource(source)
                            ? "text.bubble.fill" : "text.bubble")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                appModel.isTranscribingFileSource(source)
                                    ? Color.green : Color.secondary
                            )
                        Text(appModel.isTranscribingFileSource(source)
                            ? "Stop" : "Transcribe")
                            .foregroundStyle(
                                appModel.isTranscribingFileSource(source)
                                    ? Color.green : Color.primary
                            )
                    }
                }
                .tint(appModel.isTranscribingFileSource(source) ? .green : .accentColor)
                .disabled(appModel.isTranscribingFile
                    && !appModel.isTranscribingFileSource(source))
                .help("Transcribe the entire audio file.")
                .accessibilityValue(appModel.isTranscribingFileSource(source)
                    ? "Active" : "Inactive")

                // Record not applicable for file sources — show NA
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.tertiary)
                    Text("N/A")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if appModel.isTranscribingFileSource(source) {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.bordered)

            // Progress bar during file transcription
            if appModel.isTranscribingFileSource(source) {
                VStack(spacing: 4) {
                    ProgressView(value: appModel.fileTranscriptionProgress)
                        .tint(.green)
                    HStack {
                        Text("Transcribing file…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", appModel.fileTranscriptionProgress * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
