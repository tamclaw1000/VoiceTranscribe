import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

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
                permissionBanner
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
    }

    private var sourceList: some View {
        List(appModel.deviceService.sources) { source in
            SourceRow(source: source)
                .environmentObject(appModel)
                .padding(.vertical, 4)
        }
        .overlay {
            if appModel.deviceService.sources.isEmpty {
                ContentUnavailableView(
                    "No Input Sources",
                    systemImage: "mic.slash",
                    description: Text("Connect or enable a microphone to begin.")
                )
            }
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            PermissionStatusView(
                title: "Microphone",
                status: microphoneStatusText(appModel.permissionService.microphoneStatus),
                isAllowed: appModel.permissionService.canCaptureAudio
            )
            PermissionStatusView(
                title: "Speech",
                status: speechStatusText(appModel.permissionService.speechStatus),
                isAllowed: appModel.permissionService.canTranscribe
            )
            Spacer()
            Button {
                appModel.requestMicrophonePermission()
            } label: {
                Label("Mic Access", systemImage: "mic")
            }
            Button {
                appModel.requestSpeechPermission()
            } label: {
                Label("Speech Access", systemImage: "text.bubble")
            }
            Button {
                appModel.permissionService.openSystemPrivacySettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .padding()
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

    private func microphoneStatusText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func speechStatusText(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
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
                actionButton(
                    title: appModel.isListening(source) ? "Stop" : "Listen",
                    systemImage: "waveform",
                    isActive: appModel.isListening(source)
                ) {
                    appModel.toggleListen(for: source)
                }

                actionButton(
                    title: appModel.isRecording(source) ? "Stop" : "Record",
                    systemImage: appModel.isRecording(source) ? "record.circle.fill" : "record.circle",
                    isActive: appModel.isRecording(source)
                ) {
                    appModel.toggleRecord(for: source)
                }

                actionButton(
                    title: appModel.isTranscribing(source) ? "Stop" : "Transcribe",
                    systemImage: appModel.isTranscribing(source) ? "text.bubble.fill" : "text.bubble",
                    isActive: appModel.isTranscribing(source)
                ) {
                    appModel.toggleTranscribe(for: source)
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

    private func actionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? Color.green : Color.secondary)
                Text(title)
                    .foregroundStyle(isActive ? Color.green : Color.primary)
            }
        }
        .tint(isActive ? .green : .accentColor)
        .accessibilityValue(isActive ? "Active" : "Inactive")
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
        if appModel.isListening(source) {
            modes.append("listen")
        }
        if appModel.isRecording(source) {
            modes.append("record")
        }
        if appModel.isTranscribing(source) {
            modes.append("transcribe")
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
        let visualization = appModel.captureService.visualization
        let buffer = appModel.transcription.bufferSnapshot

        VStack(alignment: .leading, spacing: 4) {
            Text(
                "\(captureText) modes=\(modeText) rms=\(Int(visualization.rmsLevel * 100))% peak=\(Int(visualization.peakLevel * 100))%"
            )
            Text(
                "transcription=\(appModel.transcription.isTranscribing ? "active" : "idle") buffer=\(String(format: "%.1f", buffer.queuedDuration))s receiving=\(buffer.isReceivingAudio ? "yes" : "no")"
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
                    set: { appModel.settings.transcriptionEngine = $0 }
                )) {
                    ForEach(TranscriptionEngineKind.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                Toggle("Save transcripts automatically", isOn: $appModel.settings.saveTranscriptsAutomatically)
                Toggle("Start transcription when recording", isOn: $appModel.settings.startTranscriptionWithRecording)
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
