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
            let requestedSystemPermissions = await appModel.runFirstLaunchPermissionFlowIfNeeded()
            if !requestedSystemPermissions && appModel.needsPermissionsSetup {
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

            AIToggleControl(isOn: aiEnabledBinding)

            if !permissionsOK {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Microphone & Speech access required")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
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

            TranscriptFactCheckPanel(
                finalized: appModel.transcription.segments,
                interim: appModel.transcription.interimSegment,
                factChecks: appModel.factCheck.items,
                sourceName: appModel.transcriptSourceName,
                isFactCheckEnabled: appModel.settings.isFactCheckActive,
                isFactChecking: appModel.factCheck.isRunning,
                buffer: appModel.transcription.bufferSnapshot,
                isTranscribing: appModel.transcription.isTranscribing,
                aiEnabled: aiEnabledBinding,
                hasTranscriptText: !appModel.transcription.transcriptText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty,
                onSaveToFile: appModel.saveTranscriptToFile,
                onCopyText: appModel.copyTranscriptText
            )

            Divider()

            SummaryPanel(
                paragraphs: appModel.summary.paragraphs,
                sentenceCount: appModel.summary.sentenceCount,
                onSaveToFile: appModel.saveSummaryToFile,
                onCopyText: appModel.copySummaryText
            )
            .frame(minHeight: 130, maxHeight: 190)

            if !appModel.completedRecordings.isEmpty {
                Divider()
                RecentRecordingsView(recordings: appModel.completedRecordings)
                    .frame(height: 140)
            }
        }
    }

    private var aiEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.aiEnabled },
            set: { appModel.setAIEnabled($0) }
        )
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

private struct AIToggleControl: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(isOn ? "AI On" : "AI Off", systemImage: "sparkles")
                .font(.callout.weight(.semibold))
        }
        .toggleStyle(.switch)
        .fixedSize()
        .help(isOn ? "AI fact-checking is enabled" : "AI fact-checking is disabled")
        .accessibilityLabel("AI features")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
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

            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    leftSettingsColumn
                        .padding(.trailing, 2)
                }
                .frame(width: 430)

                Divider()

                ScrollView {
                    rightSettingsColumn
                        .padding(.leading, 2)
                }
                .frame(width: 470)
            }
        }
        .padding()
        .frame(width: 960, height: 680)
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

    private var leftSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Permissions", systemImage: "lock.shield")
                        .font(.headline)

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

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Summary", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Summary Prompt")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Reset") {
                                appModel.settings.resetSummaryPrompt()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }

                        TextEditor(text: $appModel.settings.summaryPrompt)
                            .font(.caption.monospaced())
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18))
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rightSettingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI Fact Checking", systemImage: "sparkles")
                        .font(.headline)

                    Toggle("Enable AI features", isOn: aiEnabledBinding)
                    Toggle("Fact-check finalized transcript sentences", isOn: $appModel.settings.factCheckEnabled)
                        .disabled(!appModel.settings.aiEnabled)

                    HStack {
                        Button {
                            appModel.testSelectedLLMPlainPrompt()
                        } label: {
                            Label("Test Prompt", systemImage: "message")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.settings.aiEnabled)

                        Button {
                            appModel.testSelectedLLMFactCheck()
                        } label: {
                            Label("Test Fact Check", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.settings.aiEnabled)
                    }

                    LLMEndpointSettingsView(compact: true)
                        .environmentObject(appModel)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Prompt Template")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Reset") {
                                appModel.settings.resetFactCheckPrompt()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }

                        TextEditor(text: $appModel.settings.ollamaFactCheckPrompt)
                            .font(.caption.monospaced())
                            .frame(minHeight: 190)
                            .scrollContentBackground(.hidden)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18))
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var aiEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.aiEnabled },
            set: { appModel.setAIEnabled($0) }
        )
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

private struct LLMEndpointSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Picker("Selected LLM", selection: $appModel.settings.selectedLLMEndpointID) {
                ForEach(appModel.settings.llmEndpoints) { endpoint in
                    Text(endpoint.displayName).tag(endpoint.id)
                }
            }

            ForEach(appModel.settings.llmEndpoints) { endpoint in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Name", text: stringBinding(for: endpoint, keyPath: \.name))
                            .textFieldStyle(.roundedBorder)
                        Button {
                            appModel.settings.removeLLMEndpoint(id: endpoint.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(appModel.settings.llmEndpoints.count <= 1)
                        .help("Remove this LLM")
                    }

                    Picker("API Type", selection: providerBinding(for: endpoint)) {
                        ForEach(LLMProviderKind.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    TextField("Endpoint URL", text: stringBinding(for: endpoint, keyPath: \.endpoint))
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: stringBinding(for: endpoint, keyPath: \.model))
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: stringBinding(for: endpoint, keyPath: \.apiKey))
                        .textFieldStyle(.roundedBorder)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18))
                )
            }

            Button {
                appModel.settings.addLLMEndpoint()
            } label: {
                Label("Add LLM", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }

    private func stringBinding(
        for endpoint: LLMEndpointConfiguration,
        keyPath: WritableKeyPath<LLMEndpointConfiguration, String>
    ) -> Binding<String> {
        Binding(
            get: {
                appModel.settings.llmEndpoint(id: endpoint.id)?[keyPath: keyPath] ?? ""
            },
            set: { value in
                var updated = appModel.settings.llmEndpoint(id: endpoint.id) ?? endpoint
                updated[keyPath: keyPath] = value
                appModel.settings.updateLLMEndpoint(updated)
            }
        )
    }

    private func providerBinding(for endpoint: LLMEndpointConfiguration) -> Binding<LLMProviderKind> {
        Binding(
            get: {
                appModel.settings.llmEndpoint(id: endpoint.id)?.provider ?? .ollama
            },
            set: { provider in
                var updated = appModel.settings.llmEndpoint(id: endpoint.id) ?? endpoint
                updated.provider = provider
                if updated.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || LLMProviderKind.allCases.map(\.defaultEndpoint).contains(updated.endpoint) {
                    updated.endpoint = provider.defaultEndpoint
                }
                appModel.settings.updateLLMEndpoint(updated)
            }
        )
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

private struct TranscriptFactCheckPanel: View {
    let finalized: [TranscriptSegment]
    let interim: TranscriptSegment?
    let factChecks: [FactCheckItem]
    let sourceName: String
    let isFactCheckEnabled: Bool
    let isFactChecking: Bool
    let buffer: TranscriptionBufferSnapshot
    let isTranscribing: Bool
    @Binding var aiEnabled: Bool
    let hasTranscriptText: Bool
    let onSaveToFile: () -> Void
    let onCopyText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Transcript", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                AIToggleControl(isOn: $aiEnabled)

                Button {
                    onCopyText()
                } label: {
                    Label("CopyText", systemImage: "doc.on.doc")
                }
                .disabled(!hasTranscriptText)
                .help("Copy transcript text to the clipboard")

                Button {
                    onSaveToFile()
                } label: {
                    Label("SaveToFile", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasTranscriptText)
                .help("Save transcript text to a file")

                HStack(spacing: 6) {
                    Circle()
                        .fill(factCheckStatusColor)
                        .frame(width: 7, height: 7)
                    Text(factCheckStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TranscriptionStatusView(buffer: buffer, isTranscribing: isTranscribing)
                    .frame(width: 260)
            }

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Timestamp")
                            .frame(width: 76, alignment: .leading)
                        Text("Audio Source")
                            .frame(width: 150, alignment: .leading)
                        Text("Text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Divider()
                        .gridCellColumns(3)

                    if finalized.isEmpty && interim == nil {
                        ContentUnavailableView(
                            "No Transcript",
                            systemImage: "text.bubble",
                            description: Text("Start transcription to see speech as it is processed.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .gridCellColumns(3)
                    } else {
                        ForEach(finalized) { segment in
                            transcriptRows(
                                segment: segment,
                                sourceName: sourceName,
                                factChecks: factChecks(for: segment),
                                isInterim: false
                            )
                        }
                        if let interim {
                            transcriptRows(
                                segment: interim,
                                sourceName: sourceName,
                                factChecks: [],
                                isInterim: true
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func transcriptRows(
        segment: TranscriptSegment,
        sourceName: String,
        factChecks: [FactCheckItem],
        isInterim: Bool
    ) -> some View {
        GridRow(alignment: .top) {
            Text(timestampText(for: segment.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Text(sourceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)

            Text(segment.text)
                .foregroundStyle(isInterim ? .secondary : .primary)
                .italic(isInterim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        GridRow(alignment: .top) {
            Color.clear
                .frame(width: 76, height: 1)
            Color.clear
                .frame(width: 150, height: 1)
            VStack(alignment: .leading, spacing: 6) {
                if isInterim {
                    factCheckDetail(label: "Fact Check", badge: "Pending", color: .secondary, text: "Will run when the sentence is finalized.")
                } else if !isFactCheckEnabled {
                    factCheckDetail(label: "Fact Check", badge: "Disabled", color: .secondary, text: "Fact checking is disabled.")
                } else if factChecks.isEmpty {
                    factCheckDetail(label: "Fact Check", badge: "Queued", color: .secondary, text: "Waiting for a complete sentence match.")
                } else {
                    ForEach(factChecks) { item in
                        factCheckDetail(for: item)
                    }
                }
            }
        }
    }

    private func factCheckDetail(for item: FactCheckItem) -> some View {
        switch item.state {
        case .queued:
            return factCheckDetail(label: "Fact Check", badge: "Queued", color: .secondary, text: "Waiting for the selected LLM.")
        case .checking:
            return factCheckDetail(label: "Fact Check", badge: "Checking", color: .orange, text: "Fact-check request in progress.")
        case .failed(let message):
            return factCheckDetail(label: "Fact Check", badge: "Failed", color: .red, text: message)
        case .completed(let result):
            return factCheckDetail(label: "Fact Check", badge: "Result", color: color(for: result.verdict), text: result.displayText)
        }
    }

    private func factCheckDetail(label: String, badge: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(badge)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(color)
                .background(color.opacity(0.14), in: Capsule())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 8)
    }

    private func factChecks(for segment: TranscriptSegment) -> [FactCheckItem] {
        let segmentText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSegment = FactCheckCoordinator.normalizedSentence(segmentText)
        let normalizedSentences = Set(FactCheckCoordinator.completeSentences(in: segmentText).map {
            FactCheckCoordinator.normalizedSentence($0)
        })

        return factChecks.filter { item in
            let normalizedItem = FactCheckCoordinator.normalizedSentence(item.sentence)
            return normalizedItem == normalizedSegment
                || normalizedSentences.contains(normalizedItem)
                || segmentText.localizedCaseInsensitiveContains(item.sentence)
        }
    }

    private func timestampText(for date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    private var factCheckStatusText: String {
        if !isFactCheckEnabled {
            return "Disabled"
        }
        return isFactChecking ? "Checking" : "Ready"
    }

    private var factCheckStatusColor: Color {
        if !isFactCheckEnabled {
            return .secondary
        }
        return isFactChecking ? .orange : .green
    }

    private func color(for verdict: FactCheckVerdict) -> Color {
        switch verdict {
        case .supported:
            return .green
        case .questionable:
            return .orange
        case .falseClaim:
            return .red
        case .unverifiable:
            return .blue
        case .notFactual:
            return .secondary
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct SummaryPanel: View {
    let paragraphs: [String]
    let sentenceCount: Int
    let onSaveToFile: () -> Void
    let onCopyText: () -> Void

    private var hasSummaryText: Bool {
        !paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recording Summary", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button {
                    onCopyText()
                } label: {
                    Label("CopyText", systemImage: "doc.on.doc")
                }
                .disabled(!hasSummaryText)
                .help("Copy summary text to the clipboard")

                Button {
                    onSaveToFile()
                } label: {
                    Label("SaveToFile", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasSummaryText)
                .help("Save summary text to a file")

                Text("\(sentenceCount) sentences")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if paragraphs.isEmpty {
                ContentUnavailableView(
                    "No Summary Yet",
                    systemImage: "doc.text",
                    description: Text("Finalized transcript sentences will be organized here as the recording grows.")
                )
                .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.trailing, 4)
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
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                settingsLeftColumn
                    .padding(.trailing, 2)
            }
            .frame(width: 430)

            Divider()

            ScrollView {
                settingsRightColumn
                    .padding(.leading, 2)
            }
            .frame(width: 470)
        }
        .padding()
    }

    private var settingsLeftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Output", systemImage: "folder")
                        .font(.headline)

                    HStack {
                        TextField("Folder", text: $appModel.settings.outputFolderPath)
                            .textFieldStyle(.roundedBorder)
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
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcription", systemImage: "text.bubble")
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

                    Toggle("Save transcripts automatically", isOn: $appModel.settings.saveTranscriptsAutomatically)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Summary", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    HStack {
                        Text("Summary Prompt")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Reset") {
                            appModel.settings.resetSummaryPrompt()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }

                    TextEditor(text: $appModel.settings.summaryPrompt)
                        .font(.caption.monospaced())
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18))
                        )
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Visualization", systemImage: "waveform")
                        .font(.headline)
                    Slider(
                        value: $appModel.settings.visualizationSensitivity,
                        in: 0.25...3.0,
                        step: 0.25
                    ) {
                        Text("Sensitivity")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var settingsRightColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI Fact Checking", systemImage: "sparkles")
                        .font(.headline)

                    Toggle("Enable AI features", isOn: Binding(
                        get: { appModel.settings.aiEnabled },
                        set: { appModel.setAIEnabled($0) }
                    ))
                    Toggle("Fact-check finalized sentences", isOn: $appModel.settings.factCheckEnabled)
                        .disabled(!appModel.settings.aiEnabled)

                    HStack {
                        Button {
                            appModel.testSelectedLLMPlainPrompt()
                        } label: {
                            Label("Test Prompt", systemImage: "message")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.settings.aiEnabled)

                        Button {
                            appModel.testSelectedLLMFactCheck()
                        } label: {
                            Label("Test Fact Check", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.settings.aiEnabled)
                    }

                    LLMEndpointSettingsView(compact: true)
                        .environmentObject(appModel)

                    HStack {
                        Text("Prompt Template")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Reset") {
                            appModel.settings.resetFactCheckPrompt()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }

                    TextEditor(text: $appModel.settings.ollamaFactCheckPrompt)
                        .font(.caption.monospaced())
                        .frame(minHeight: 210)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
