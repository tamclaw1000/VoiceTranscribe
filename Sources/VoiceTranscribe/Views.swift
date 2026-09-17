import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedDetailTab: DetailTab = .transcript

    private enum DetailTab: Hashable {
        case transcript
        case summary
        case recordings
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sourceList
                Divider()
                AppVersionFooter()
            }
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
                openSettings()
            }
            appModel.testAIReachabilityOnLaunch()
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

            Section("AI Prompts") {
                ForEach(appModel.settings.aiPromptTemplates) { promptTemplate in
                    AIPromptSourceRow(promptTemplate: promptTemplate)
                        .environmentObject(appModel)
                        .padding(.vertical, 3)
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
                openSettings()
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

            AIReachabilityIndicator(
                status: appModel.aiReachability,
                optionDescription: appModel.activeAIOptionDescription,
                compact: true
            )

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
    }

    private var mainDetail: some View {
        VStack(spacing: 0) {
            GraphPanel(snapshot: appModel.captureService.visualization)
                .frame(height: 104)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Divider()

            TabView(selection: $selectedDetailTab) {
                TranscriptFactCheckPanel(
                    finalized: appModel.transcription.segments,
                    interim: appModel.transcription.interimSegment,
                    factChecks: appModel.factCheck.items,
                    speakerNameItems: appModel.speakerNameEditorItems,
                    currentSpeakerID: appModel.diarization.currentSpeakerID,
                    currentSpeakerLabel: appModel.diarization.currentSpeakerLabel,
                    isDiarizationActive: appModel.diarization.isStarting || appModel.diarization.isRunning,
                    diarizationError: appModel.diarization.lastError,
                    isFactCheckEnabled: appModel.settings.isFactCheckActive,
                    isFactChecking: appModel.factCheck.isRunning,
                    buffer: appModel.transcription.bufferSnapshot,
                    isTranscribing: appModel.transcription.isTranscribing,
                    autoScrollToBottom: $appModel.settings.autoScrollTranscript,
                    hasTranscriptText: !appModel.transcription.transcriptText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty,
                    onCycleSpeaker: appModel.cycleTranscriptSegmentSpeaker,
                    onSetSpeakerName: appModel.setSpeakerName,
                    onResetSpeakerName: appModel.resetSpeakerName,
                    onResetAllSpeakerNames: appModel.resetAllSpeakerNames,
                    onSaveToFile: appModel.saveTranscriptToFile,
                    onExportMarkdown: appModel.saveTranscriptMarkdownToFile,
                    onCopyText: appModel.copyTranscriptText
                )
                .tabItem {
                    Label("Live Transcript", systemImage: "text.alignleft")
                }
                .tag(DetailTab.transcript)

                SummaryPanel(
                    paragraphs: appModel.summary.paragraphs,
                    sentenceCount: appModel.summary.sentenceCount,
                    onSaveToFile: appModel.saveSummaryToFile,
                    onCopyText: appModel.copySummaryText
                )
                .tabItem {
                    Label("Recording Summary", systemImage: "doc.text.magnifyingglass")
                }
                .tag(DetailTab.summary)

                RecentRecordingsView(recordings: appModel.completedRecordings)
                    .tabItem {
                        Label("Recent Recordings", systemImage: "folder")
                    }
                    .tag(DetailTab.recordings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AppVersionFooter: View {
    var body: some View {
        Text(AppVersion.displayText())
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityLabel("Application version")
            .accessibilityValue(AppVersion.displayText())
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
                let sourceActionBusy = appModel.isSourceActionBusy
                let isTranscribingSource = appModel.isTranscribing(source)
                let isRecordingSource = appModel.isRecording(source)

                Button {
                    appModel.toggleTranscribe(for: source)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isTranscribingSource ? "text.bubble.fill" : "text.bubble")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isTranscribingSource ? Color.green : Color.secondary)
                        Text(isTranscribingSource ? "Stop" : "Transcribe")
                            .foregroundStyle(isTranscribingSource ? Color.green : Color.primary)
                    }
                }
                .tint(isTranscribingSource ? .green : .accentColor)
                .disabled(!permissionsOK || (sourceActionBusy && !isTranscribingSource))
                .help(!permissionsOK ? "Microphone and speech recognition permissions are required" : (sourceActionBusy && !isTranscribingSource ? "Another audio source is starting or stopping." : ""))
                .accessibilityValue(isTranscribingSource ? "Active" : "Inactive")

                // Record checkbox
                Toggle(isOn: Binding(
                    get: { appModel.isRecording(source) },
                    set: { _ in appModel.toggleRecord(for: source) }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: isRecordingSource ? "record.circle.fill" : "record.circle")
                            .foregroundStyle(isRecordingSource ? .red : .secondary)
                        Text("Record")
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!permissionsOK || (sourceActionBusy && !isRecordingSource))

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

private struct AIPromptSourceRow: View {
    @EnvironmentObject private var appModel: AppModel
    let promptTemplate: AIPromptTemplateConfiguration

    private var llmName: String {
        appModel.settings.effectiveLLMEndpoint(for: promptTemplate).displayName
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: {
                appModel.settings.aiPromptTemplates
                    .first(where: { $0.id == promptTemplate.id })?
                    .isEnabled ?? promptTemplate.isEnabled
            },
            set: { enabled in
                appModel.setAIPromptEnabled(id: promptTemplate.id, enabled: enabled)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(promptTemplate.isEnabled ? Color.accentColor : Color.secondary)
                    Text(promptTemplate.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Text(llmName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if appModel.settings.useGlobalPromptLLM {
                    Text("Global model")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .help(promptTemplate.isEnabled ? "Disable this AI processing prompt" : "Enable this AI processing prompt")
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

private struct AIReachabilityIndicator: View {
    let status: AIReachabilityStatus
    let optionDescription: String
    let compact: Bool

    private var statusText: String {
        switch status.state {
        case .disabled:
            return "AI Disabled"
        case .untested:
            return "AI Untested"
        case .testing:
            return "Testing AI"
        case .reachable:
            return "AI Ready"
        case .failed:
            return "AI Failed"
        }
    }

    private var statusColor: Color {
        switch status.state {
        case .disabled, .untested:
            return .secondary
        case .testing:
            return .orange
        case .reachable:
            return .green
        case .failed:
            return .red
        }
    }

    private var systemImage: String {
        switch status.state {
        case .disabled:
            return "sparkles.slash"
        case .untested:
            return "questionmark.circle"
        case .testing:
            return "arrow.triangle.2.circlepath"
        case .reachable:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Image(systemName: systemImage)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(optionDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 8)
        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.22))
        )
        .help(status.detail)
    }
}

// MARK: - Settings

private enum SettingsSectionTab: Hashable {
    case general
    case llmModels
    case promptTemplates
}

private struct LLMEndpointSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Picker("Selected LLM", selection: selectedLLMBinding) {
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
                            appModel.removeLLMEndpoint(id: endpoint.id)
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
                appModel.addLLMEndpoint()
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
                appModel.updateLLMEndpoint(updated)
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
                appModel.updateLLMEndpoint(updated)
            }
        )
    }

    private var selectedLLMBinding: Binding<String> {
        Binding(
            get: { appModel.settings.selectedLLMEndpointID },
            set: { id in appModel.setSelectedLLMEndpointID(id) }
        )
    }
}

private struct GlobalPromptLLMControl: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { appModel.settings.useGlobalPromptLLM },
                set: { appModel.setUseGlobalPromptLLM($0) }
            )) {
                Label("Use one model for all prompts", systemImage: "link")
            }
            .toggleStyle(.checkbox)

            Picker("Prompt Model", selection: Binding(
                get: { appModel.settings.globalPromptLLMEndpointID },
                set: { appModel.setGlobalPromptLLMEndpointID($0) }
            )) {
                ForEach(appModel.settings.llmEndpoints) { endpoint in
                    Text(endpoint.displayName).tag(endpoint.id)
                }
            }
            .disabled(!appModel.settings.useGlobalPromptLLM)

            Text(appModel.settings.useGlobalPromptLLM
                ? "All enabled prompts will use \(appModel.settings.globalPromptLLMEndpoint.displayName)."
                : "Each prompt uses its own model selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18))
        )
    }
}

private struct AIPromptTemplateSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(appModel.settings.aiPromptTemplates) { promptTemplate in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Enabled", isOn: boolBinding(for: promptTemplate, keyPath: \.isEnabled))
                            .toggleStyle(.checkbox)
                        Spacer()
                        Button {
                            appModel.removeAIPromptTemplate(id: promptTemplate.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(appModel.settings.aiPromptTemplates.count <= 1)
                        .help("Remove this prompt template")
                    }

                    TextField("Name", text: stringBinding(for: promptTemplate, keyPath: \.name))
                        .textFieldStyle(.roundedBorder)

                    Picker("Model", selection: stringBinding(for: promptTemplate, keyPath: \.llmEndpointID)) {
                        ForEach(appModel.settings.llmEndpoints) { endpoint in
                            Text(endpoint.displayName).tag(endpoint.id)
                        }
                    }
                    .disabled(appModel.settings.useGlobalPromptLLM)
                    if appModel.settings.useGlobalPromptLLM {
                        Text("Using global model: \(appModel.settings.globalPromptLLMEndpoint.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Template")
                            .font(.caption.weight(.semibold))
                            .help("Supports {{sentence}}, {{conversation}}, {{last-3}}, {{last-5}}, {{last-10}}, and {{prompt-state}}.")
                        Spacer()
                        Button("Reset") {
                            appModel.resetAIPromptTemplate(id: promptTemplate.id)
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }

                    TextEditor(text: stringBinding(for: promptTemplate, keyPath: \.template))
                        .font(.caption.monospaced())
                        .frame(minHeight: compact ? 145 : 190)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18))
                        )
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18))
                )
            }

            Button {
                appModel.addAIPromptTemplate()
            } label: {
                Label("Add Prompt", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }

    private func stringBinding(
        for promptTemplate: AIPromptTemplateConfiguration,
        keyPath: WritableKeyPath<AIPromptTemplateConfiguration, String>
    ) -> Binding<String> {
        Binding(
            get: {
                appModel.settings.aiPromptTemplates
                    .first(where: { $0.id == promptTemplate.id })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                var updated = appModel.settings.aiPromptTemplates
                    .first(where: { $0.id == promptTemplate.id }) ?? promptTemplate
                updated[keyPath: keyPath] = value
                appModel.updateAIPromptTemplate(updated)
            }
        )
    }

    private func boolBinding(
        for promptTemplate: AIPromptTemplateConfiguration,
        keyPath: WritableKeyPath<AIPromptTemplateConfiguration, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                appModel.settings.aiPromptTemplates
                    .first(where: { $0.id == promptTemplate.id })?[keyPath: keyPath] ?? false
            },
            set: { value in
                var updated = appModel.settings.aiPromptTemplates
                    .first(where: { $0.id == promptTemplate.id }) ?? promptTemplate
                updated[keyPath: keyPath] = value
                appModel.updateAIPromptTemplate(updated)
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
    let speakerNameItems: [SpeakerNameEditorItem]
    let currentSpeakerID: String?
    let currentSpeakerLabel: String?
    let isDiarizationActive: Bool
    let diarizationError: String?
    let isFactCheckEnabled: Bool
    let isFactChecking: Bool
    let buffer: TranscriptionBufferSnapshot
    let isTranscribing: Bool
    @Binding var autoScrollToBottom: Bool
    let hasTranscriptText: Bool
    let onCycleSpeaker: (UUID) -> Void
    let onSetSpeakerName: (String, String) -> Void
    let onResetSpeakerName: (String) -> Void
    let onResetAllSpeakerNames: () -> Void
    let onSaveToFile: () -> Void
    let onExportMarkdown: () -> Void
    let onCopyText: () -> Void

    @State private var isSpeakerConfigurationExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Transcript", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()

                Toggle(isOn: $autoScrollToBottom) {
                    Label("Auto-scroll", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.checkbox)
                .help("Scroll to the latest transcript text while speech is processed")

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

                Button {
                    onExportMarkdown()
                } label: {
                    Label("ExportMarkdown", systemImage: "doc.richtext")
                }
                .disabled(!hasTranscriptText)
                .help("Export transcript, summary, and AI processing results as Markdown")

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

            HStack(spacing: 8) {
                Image(systemName: "person.wave.2.fill")
                    .foregroundStyle(currentSpeakerColor)
                Text(currentSpeakerStatusText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(currentSpeakerColor)
                Spacer()
                Text("SpeechVAD Sortformer diarization")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(currentSpeakerColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(currentSpeakerColor.opacity(0.25))
            )
            .help(currentSpeakerHelpText)

            if !speakerNameItems.isEmpty {
                speakerNameEditor
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Timestamp")
                                .frame(width: 76, alignment: .leading)
                            Text("Speaker")
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
                                    fallbackSpeakerID: currentSpeakerID,
                                    fallbackSpeakerLabel: currentSpeakerLabel,
                                    factChecks: factChecks(for: segment),
                                    isInterim: false
                                )
                            }
                            if let interim {
                                transcriptRows(
                                    segment: interim,
                                    fallbackSpeakerID: currentSpeakerID,
                                    fallbackSpeakerLabel: currentSpeakerLabel,
                                    factChecks: [],
                                    isInterim: true
                                )
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomScrollID)
                            .gridCellColumns(3)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .onChange(of: finalized.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: interim?.text ?? "") { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
        .padding()
    }

    private var speakerNameEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isSpeakerConfigurationExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button {
                            onResetAllSpeakerNames()
                        } label: {
                            Label("Reset All", systemImage: "arrow.counterclockwise")
                        }
                        .font(.caption)
                        .disabled(!speakerNameItems.contains(where: \.hasCustomName))
                        .help("Reset all speaker names to their generated Speaker N labels")
                    }

                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        ForEach(speakerNameItems) { item in
                            GridRow {
                                Text(item.speakerID)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(speakerColor(for: item.speakerID))
                                    .lineLimit(1)
                                    .frame(width: 88, alignment: .leading)

                                TextField(
                                    item.speakerID,
                                    text: Binding(
                                        get: { item.customName },
                                        set: { onSetSpeakerName(item.speakerID, $0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 140, maxWidth: 260)
                                .help("Enter a display name for \(item.speakerID)")

                                Text(item.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    onResetSpeakerName(item.speakerID)
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .disabled(!item.hasCustomName)
                                .help("Reset \(item.speakerID) to its generated name")
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Label("Speaker Configuration", systemImage: "person.2")
                        .font(.caption.weight(.semibold))
                    Text("\(speakerNameItems.count) detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if speakerNameItems.contains(where: \.hasCustomName) {
                        Text("custom names")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15))
        )
    }

    @ViewBuilder
    private func transcriptRows(
        segment: TranscriptSegment,
        fallbackSpeakerID: String?,
        fallbackSpeakerLabel: String?,
        factChecks: [FactCheckItem],
        isInterim: Bool
    ) -> some View {
        let speakerID = segment.speakerID ?? fallbackSpeakerID
        let speakerLabel = segment.speakerLabel ?? fallbackSpeakerLabel
        GridRow(alignment: .top) {
            Text(timestampText(for: segment.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Button {
                onCycleSpeaker(segment.id)
            } label: {
                Text(speakerLabel ?? "Detecting")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SpeakerLabelButtonStyle(color: speakerColor(for: speakerID ?? speakerLabel)))
            .frame(width: 150, alignment: .leading)
            .disabled(speakerNameItems.isEmpty)
            .help(speakerNameItems.isEmpty ? "No detected speakers to cycle." : "Click to cycle this row through detected speakers.")
            .accessibilityLabel("Speaker \(speakerLabel ?? "Detecting")")
            .accessibilityHint("Cycles this transcript row through detected speakers.")

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
                    factCheckDetail(label: "AI Processing", badge: "Pending", color: .secondary, text: "Will run when the sentence is finalized.")
                } else if !isFactCheckEnabled {
                    factCheckDetail(label: "AI Processing", badge: "Disabled", color: .secondary, text: "No AI prompts are enabled.")
                } else if factChecks.isEmpty {
                    factCheckDetail(label: "AI Processing", badge: "Queued", color: .secondary, text: "Waiting for a complete sentence match.")
                } else {
                    ForEach(factChecks) { item in
                        factCheckDetail(for: item)
                    }
                }
            }
        }
    }

    private func factCheckDetail(for item: FactCheckItem) -> some View {
        let label = item.promptTemplateName
        switch item.state {
        case .queued:
            return factCheckDetail(label: label, badge: "Queued", color: .secondary, text: "Waiting for the selected LLM.")
        case .checking:
            return factCheckDetail(label: label, badge: "Checking", color: .orange, text: "AI request in progress.")
        case .failed(let message):
            return factCheckDetail(label: label, badge: "Failed", color: .red, text: message)
        case .completed(let result):
            return factCheckDetail(label: label, badge: "Result", color: color(for: result.verdict), text: result.displayText)
        }
    }

    private func factCheckDetail(label: String, badge: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard autoScrollToBottom else {
            return
        }

        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(Self.bottomScrollID, anchor: .bottom)
        }
    }

    private var factCheckStatusText: String {
        if !isFactCheckEnabled {
            return "Disabled"
        }
        return isFactChecking ? "Processing" : "Ready"
    }

    private var currentSpeakerStatusText: String {
        if let currentSpeakerLabel, !currentSpeakerLabel.isEmpty {
            return "Current speaker: \(currentSpeakerLabel)"
        }
        if let diarizationError, !diarizationError.isEmpty {
            return "Speaker detection unavailable"
        }
        if isDiarizationActive {
            return "Current speaker: Detecting"
        }
        return "Current speaker: Not active"
    }

    private var currentSpeakerHelpText: String {
        if let diarizationError, !diarizationError.isEmpty {
            return diarizationError
        }
        return "SpeechVAD Sortformer diarization distinguishes anonymous speakers as Speaker 1, Speaker 2, and so on."
    }

    private var currentSpeakerColor: Color {
        if let currentSpeakerID {
            return speakerColor(for: currentSpeakerID)
        }
        if let currentSpeakerLabel {
            return speakerColor(for: currentSpeakerLabel)
        }
        if diarizationError != nil {
            return .orange
        }
        return .secondary
    }

    private func speakerColor(for label: String?) -> Color {
        guard let label,
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .secondary
        }

        let palette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo, .mint]
        let digits = String(label.filter(\.isNumber))
        if let number = Int(digits), number > 0 {
            return palette[(number - 1) % palette.count]
        }

        let checksum = label.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return palette[checksum % palette.count]
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

    private static let bottomScrollID = "transcript-bottom"
}

private struct SpeakerLabelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? color : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(
                color.opacity(isEnabled ? (configuration.isPressed ? 0.22 : 0.10) : 0.05),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(isEnabled ? (configuration.isPressed ? 0.55 : 0.28) : 0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1 : 0.65)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
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
            if recordings.isEmpty {
                ContentUnavailableView(
                    "No Recent Recordings",
                    systemImage: "folder",
                    description: Text("Completed recordings will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
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
        }
        .padding()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedSettingsTab: SettingsSectionTab = .general

    var body: some View {
        TabView(selection: $selectedSettingsTab) {
            ScrollView {
                settingsLeftColumn
                    .padding(.horizontal, 2)
            }
            .tabItem {
                Label("General", systemImage: "slider.horizontal.3")
            }
            .tag(SettingsSectionTab.general)

            ScrollView {
                settingsModelColumn
                    .padding(.horizontal, 2)
            }
            .tabItem {
                Label("LLM Models", systemImage: "server.rack")
            }
            .tag(SettingsSectionTab.llmModels)

            ScrollView {
                settingsPromptColumn
                    .padding(.horizontal, 2)
            }
            .tabItem {
                Label("Prompt Templates", systemImage: "text.badge.plus")
            }
            .tag(SettingsSectionTab.promptTemplates)
        }
        .padding()
        .frame(minWidth: 680, minHeight: 560)
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

                    Label("Apple Speech transcript segmentation", systemImage: "text.quote")
                        .font(.caption)
                    Label("SpeechVAD Sortformer speaker diarization", systemImage: "person.wave.2")
                        .font(.caption)

                    Toggle("Save transcripts automatically", isOn: $appModel.settings.saveTranscriptsAutomatically)
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

    private var settingsModelColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("LLM Models", systemImage: "server.rack")
                        .font(.headline)

                    GlobalPromptLLMControl()
                        .environmentObject(appModel)

                    AIReachabilityIndicator(
                        status: appModel.aiReachability,
                        optionDescription: appModel.activeAIOptionDescription,
                        compact: false
                    )

                    HStack {
                        Button {
                            appModel.testActiveAIReachability()
                        } label: {
                            Label("Test Active AI", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            appModel.testSelectedLLMPlainPrompt()
                        } label: {
                            Label("Test Prompt", systemImage: "message")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            appModel.testSelectedLLMFactCheck()
                        } label: {
                            Label("Test AI Processing", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                    }

                    LLMEndpointSettingsView(compact: true)
                        .environmentObject(appModel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var settingsPromptColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Prompt Templates", systemImage: "text.badge.plus")
                        .font(.headline)

                    AIPromptTemplateSettingsView(compact: true)
                        .environmentObject(appModel)
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
