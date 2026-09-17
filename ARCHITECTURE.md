# VoiceTranscribe Architecture

This document summarizes the current technical implementation so another agent can safely resume work. It complements `AGENTS.md`, `REQUIREMENTS.md`, and the versioned checklist in `IMPLEMENTATION.md`.

## Runtime Shape

VoiceTranscribe is a native macOS SwiftUI executable package.

- Package: `Package.swift`
- Executable target: `VoiceTranscribe`
- Test target: `VoiceTranscribeTests`
- Minimum platform: macOS 26
- Swift tools: 6.3
- Swift language mode: 5
- Local dependencies: `external/FluidAudio`, `external/speech-swift-worktree`

The application is centered on `AppModel`, a `@MainActor ObservableObject` that owns the user workflow and all long-lived services.

```text
VoiceTranscribeApp
  -> ContentView / SettingsView
     -> AppModel
        -> AudioDeviceService
        -> PermissionService
        -> AppSettings
        -> AudioCaptureService
        -> RecordingService
        -> TranscriptionCoordinator
           -> AppleSpeechTranscriptionService
           -> FluidAudioTranscriptionService
        -> DiarizationCoordinator
           -> SpeechVAD SortformerStreamingSession
        -> SummaryCoordinator
        -> FactCheckCoordinator
           -> OllamaFactCheckService
        -> MarkdownExportService
```

`AppModel` forwards `objectWillChange` from nested observable services. This is required because `@Published` reference-type children do not automatically make SwiftUI re-render when the child publishes internally.

## Source Files

| File | Main Responsibility |
| --- | --- |
| `VoiceTranscribeApp.swift` | App entry point, top-level model injection, Settings scene. |
| `Views.swift` | SwiftUI main split view, source rows, graph, transcript/AI rows, settings tabs. |
| `AppModel.swift` | User actions, workflow orchestration, permission flow, recording/transcription/file actions, export. |
| `AppSettings.swift` | Persisted settings, LLM endpoint config, prompt templates, global prompt model routing. |
| `Models.swift` | Core value types: sources, sessions, transcript segments, visualization, file sources. |
| `AudioDeviceService.swift` | CoreAudio input-device enumeration and polling. |
| `AudioCaptureService.swift` | `AVAudioEngine` input tap, source selection, buffer copying, visualization, consumer fan-out. |
| `RecordingService.swift` | Audio file creation/finalization, async writer queue, recording metadata. |
| `TranscriptionService.swift` | Transcription protocol, Apple Speech implementation, coordinator/state. |
| `FluidAudioTranscriptionService.swift` | FluidAudio Parakeet EOU streaming ASR implementation and model download/load path. |
| `DiarizationService.swift` | SpeechVAD Sortformer live diarization wrapper, speaker timeline state, transcript speaker annotations. |
| `SummaryService.swift` | Paragraph-form transcript summary/organization. |
| `FactCheckService.swift` | AI processing model clients, prompt rendering, sentence queue, batching, prompt state. |
| `MarkdownExportService.swift` | Markdown transcript/session export. |
| `PermissionService.swift` | Microphone and speech permission state/request helpers. |
| `Trace.swift` | JSON-line tracing to `/tmp/VoiceTranscribe.log`. |
| `Utilities.swift` | File naming, bounded buffer, transcript document helpers. |

## UI Composition

`ContentView` is a `NavigationSplitView`.

Left pane:

- `Microphones` section: live CoreAudio devices.
- `File Sources` section: user-loaded audio files.
- `AI Prompts` section: prompt-template enable toggles and effective model names.
- Pinned version footer.
- Toolbar `Refresh` button.

Right pane:

- Settings/status bar.
- `GraphPanel` for input level history.
- Tabbed detail area:
  - `Live Transcript` with timestamp, speaker, text, and AI result rows.
  - `Recording Summary` in current code. Requirements now target `Transcript Paragraphs` plus a separate `AI Summary`.
  - `Recent Recordings`

Settings exists in two surfaces:

- `SettingsSheet`: modal sheet launched from the main window.
- `SettingsView`: standalone macOS Settings scene.

Both use tabs for `General`, `LLM Models`, and `Prompt Templates`. The standalone Settings window exposes output folder, audio format, automatic transcript saving, and visualization sensitivity; the sheet focuses on permissions, transcription engine, summary prompt, LLMs, and prompts.

## Data Ownership

`AppModel` owns session-level state:

- Active source identity via `AudioCaptureService.activeSource`.
- Completed recordings.
- Loaded file sources.
- Active file transcription ID/progress.
- Current transcript source name.
- User-facing message string.
- Recently active recording filename/path for Finder reveal.

`AudioCaptureService` owns live capture state:

- Capture status.
- Active source.
- Registered audio consumers.
- Visualization snapshot and bounded level history.

`RecordingService` owns active recording state:

- Current `RecordingSession`.
- Async writer.
- Last writer error.

`TranscriptionCoordinator` owns transcript state:

- Finalized `TranscriptSegment` array.
- Current interim segment.
- `TranscriptDocument` merge state.
- Buffer snapshot.
- Selected transcription service instance.

`DiarizationCoordinator` owns speaker state:

- Live speaker timeline segments.
- Current/latest speaker annotation.
- SpeechVAD Sortformer streaming session lifecycle.
- Snapshot replacement and trace dedupe for repeated timeline updates.

`FactCheckCoordinator` owns AI processing state:

- Visible `FactCheckItem` rows.
- Queue worker count and worker tasks.
- Prompt-state dictionary keyed by prompt template ID.
- Deduplication keys by prompt template and normalized sentence.

`SummaryCoordinator` owns paragraph-form summary state:

- Paragraphs.
- Sentence count.
- Current summary prompt behavior.

`AppSettings` owns persisted configuration:

- Output folder path.
- Audio format.
- Transcription engine.
- Automatic transcript saving.
- Visualization sensitivity.
- LLM endpoint configurations.
- Selected LLM endpoint.
- Global prompt model flag and model ID.
- AI prompt templates.
- Summary prompt.
- Transcript auto-scroll.

Most settings are stored with `@AppStorage`, including JSON-encoded arrays for LLM endpoints and prompt templates.

## Audio Capture Flow

Live microphone workflow:

```text
User presses Transcribe or Record
  -> AppModel ensures permissions
  -> AppModel.ensureCapture(source)
  -> AudioCaptureService.start(source)
     -> select CoreAudio input device on AVAudioEngine input node
     -> install tap on input bus
     -> deep-copy tap buffer
     -> DispatchQueue.main
     -> AudioCaptureService.process(buffer,time)
        -> compute RMS/peak/display level
        -> update VisualizationSnapshot at 30 fps
        -> fan copied buffer to registered consumers
```

Consumers are keyed by string IDs:

- `"listen"`: no-op consumer used to keep visualization active.
- `"record"`: `RecordingService.consume`.
- `"diarize"`: `DiarizationCoordinator.consume`.
- `"transcribe"`: `TranscriptionCoordinator.consume`.

Capture stops only when all consumers are removed and `stopIfUnused()` sees an empty consumer registry.

Important invariant: audio tap buffers are transient. Every path copies buffers before retaining, dispatching, writing, or transcribing them.

## Recording Flow

Start:

```text
User checks Record
  -> AppModel.toggleRecord
  -> ensure permissions and capture
  -> RecordingService.start(source,inputFormat,outputFolder,outputFormat)
     -> create output folder
     -> build in-progress basename
     -> create AVAudioFile
     -> create AsyncAudioFileWriter
  -> AudioCaptureService.addConsumer("record")
```

Write:

```text
AudioCaptureService.process
  -> "record" consumer
  -> RecordingService.consume
  -> deepCopy buffer
  -> AsyncAudioFileWriter.write on utility DispatchQueue
```

Stop:

```text
User unchecks Record
  -> remove "record" consumer
  -> RecordingService.stop(transcriptText,saveTranscript,engine)
     -> drain writer queue
     -> rename audio from in-progress basename to final basename
     -> optionally write transcript .txt
     -> write metadata .json
     -> return finalized RecordingSession
  -> AppModel adds completed recording to recent recordings
  -> AppModel may add completed audio as a file source
```

Known technical gap: `RecordingService.moveReplacingExisting` currently removes an existing destination before moving. Requirements call for collision-safe filenames.

## Transcription Flow

`TranscriptionService` protocol:

```swift
protocol TranscriptionService {
    var engineName: String { get }
    func start(onSegment: @escaping (TranscriptSegment) -> Void) async throws
    func append(_ buffer: AVAudioPCMBuffer)
    func stop()
}
```

`TranscriptionCoordinator` wraps the selected service. It resets transcript state on start, calls the service, and applies incoming segments:

- Final segments are appended to `segments` and `TranscriptDocument`.
- Interim segments update `interimSegment`.
- Final segments trigger `onFinalSegment`, which `AppModel` wires to AI processing and summary updates.
- Buffer status is tracked with `TranscriptionBufferSnapshot`.

### Apple Speech

`AppleSpeechTranscriptionService` uses:

- `SpeechTranscriber`
- `SpeechAnalyzer`
- `AnalyzerInput`
- `AVAudioConverter`

Startup sequence:

1. Check speech authorization.
2. Check `SpeechTranscriber.isAvailable`.
3. Ensure language model is installed.
4. Get analyzer-compatible audio format.
5. Create analyzer input stream.
6. Start result task over `transcriber.results`.
7. Create raw-buffer stream and conversion task.
8. Start analyzer before audio buffers are fed.

Stop finishes raw stream and asks analyzer to finalize through end of input.

### FluidAudio

`FluidAudioTranscriptionService` uses `StreamingEouAsrManager` with `.ms320` chunk size and EOU debounce of 1280 ms.

Startup sequence:

1. Create manager.
2. Register EOU and partial callbacks before loading models.
3. Verify/download Parakeet EOU model files.
4. Load models from `~/Library/Application Support/FluidAudio/Models/parakeet-eou-streaming/320ms/`.

EOU callback trims text, capitalizes, appends punctuation if needed, and emits a final `TranscriptSegment`.

Partial callback emits non-final segments.

Stop drains `mgr.finish()` and emits any final trailing utterance.

## Diarization Flow

`DiarizationCoordinator` runs SpeechVAD Sortformer streaming diarization in parallel with Apple Speech transcription for live microphone and file-source transcription.

Startup:

```text
AppModel.startTranscriptionConsumer
  -> DiarizationCoordinator.start()
     -> SpeechSwiftSortformerDiarizationEngine actor
     -> SortformerStreamingSession.fromPretrained(config: .streaming)
  -> AudioCaptureService.addConsumer("diarize")
  -> TranscriptionCoordinator.start()
```

Processing:

```text
AudioCaptureService.process
  -> "diarize" consumer
  -> downmix AVAudioPCMBuffer to mono Float samples
  -> resample to 16 kHz mono with AudioFileLoader
  -> SortformerStreamingSession.push(audio:)
  -> replace whole-stream SpeakerDiarizationSegment snapshot
  -> publish SpeakerDiarizationSegment timeline
```

`TranscriptionCoordinator` has a `speakerProvider` callback. When a transcript segment is applied, the coordinator asks `DiarizationCoordinator` for the current speaker and stores `speakerID`/`speakerName` on the `TranscriptSegment`. This is a best-effort live annotation based on the latest finalized diarization update. The complete diarization timeline remains available separately for exports.

Stop:

```text
AppModel.stopTranscription
  -> remove "diarize" consumer
  -> DiarizationCoordinator.stop()
     -> finalizeSession()
     -> merge remaining speaker timeline segments
```

## File Transcription Flow

File sources are represented by `FileInputSource`.

`FileInputSource.from(url:)` first tries `AVAudioFile`; if that fails, it falls back to `AVURLAsset` for compressed formats.

The AppModel file path reads audio with an asset reader, feeds copied buffers through diarization and transcription, and updates `fileTranscriptionProgress`. Only one file source is transcribed at a time.

File sources are not recorded. They reuse transcript display, summary, and AI processing once transcript segments are emitted.

## AI Processing Flow

Historical code names use `FactCheck`; user-facing text should say `AI Processing`.

Final transcript segment path:

```text
TranscriptionCoordinator.apply(final segment)
  -> AppModel.transcription.onFinalSegment
     -> settings.effectiveEnabledAIPromptTemplates
     -> FactCheckCoordinator.enqueueTranscriptSegment(...)
     -> SummaryCoordinator.enqueueTranscriptSegment(...)
```

AI queue steps:

1. Ignore disabled AI or non-final segments.
2. Build `FactCheckPromptContext` from transcript conversation.
3. Resolve each enabled prompt's effective LLM endpoint.
4. Extract complete sentences using `.`, `?`, and `!`.
5. Deduplicate by `promptTemplateID|normalizedSentence`.
6. Queue one `FactCheckItem` per sentence and prompt.
7. Start up to three workers.

Prompt placeholders:

- `{{sentence}}`
- `{{conversation}}`
- `{{last-3}}`
- `{{last-5}}`
- `{{last-10}}`
- `{{prompt-state}}`

If a prompt contains no supported placeholder, the current sentence is appended automatically.

Prompt state:

- Stored per prompt template ID.
- Injected immediately before sending.
- Updated from successful result display text.
- Cleared on coordinator reset.
- Stateful prompts are serialized by template ID so they do not race against stale state.

Batching:

- Enabled when `useGlobalPromptLLM` is on and multiple prompts route to the same model for the same sentence.
- A shared `batchGroupID` groups queued items.
- `BatchFactCheckPrompt.render` asks the model to return JSON answers by prompt item ID.
- Missing batch answers become per-item failures.

## LLM Provider Adapters

`OllamaFactCheckService` handles all provider request/response shapes despite the historical name.

Supported providers:

| Provider | Request Shape | Auth |
| --- | --- | --- |
| Ollama | `POST /api/generate` | Optional bearer token |
| OpenAI-compatible | `POST /v1/chat/completions` | Bearer token |
| OpenRouter | OpenAI-compatible chat completions plus `X-Title` | Bearer token |
| Anthropic | `POST /v1/messages` | `x-api-key` |
| Gemini | `POST /v1beta/models/{model}:generateContent` | Query `key` |

OpenAI-compatible requests intentionally send only `model` and `messages` for broad proxy/router compatibility.

Response parsing:

- Strict JSON `FactCheckResult` is accepted.
- Fenced JSON is accepted.
- JSON embedded inside prose is attempted.
- Plain text falls back to an `.unverifiable` result with `rawResponse`, so arbitrary prompt output can display unchanged.

## Markdown Export

`MarkdownExportService.makeDocument` builds a snapshot from:

- `MarkdownExportContext`
- Finalized transcript segments.
- Speaker diarization segments.
- AI result items.
- Summary paragraphs.

Sections:

- `# DETAILS`
- `# RECORDING`
- `# SPEAKERS` when speaker timeline segments exist.
- `# SUMMARY` when summary text exists.
- `# AI RESULTS`
- `# FILES` when related URLs exist.

The recording table has one row per finalized segment, including speaker labels and associated AI result text in the `AI result` cell.

`# SPEAKERS` contains diarized speaker start/end offsets, labels, and confidence values when the diarizer returns a speaker timeline.

`# AI RESULTS` includes:

- AI enabled flag.
- LLM endpoint/provider/base URL/model.
- Summary result.
- Non-empty prompt states.
- AI processing prompt templates.
- Summary prompt.

API keys are not exported.

Markdown table cells escape backslashes, pipes, line breaks, and carriage returns.

## Persistence and Files

Settings:

- `AppSettings` uses `@AppStorage`/UserDefaults.
- Complex settings are JSON-encoded strings behind computed properties.
- LLM endpoints are sanitized on read/write.
- Prompt templates are sanitized on read/write.

Recording output:

- Default output folder is managed by settings.
- Audio extensions: `.m4a`, `.caf`, `.wav`.
- Transcript extension: `.txt`.
- Metadata extension: `.json`.
- Metadata dates are ISO-8601 encoded.

FluidAudio models:

- Downloaded under user Application Support.
- Verified by checking `coremldata.bin` files and `vocab.json`.
- Partial model folders are removed before fresh download.

Logs:

- `/tmp/VoiceTranscribe.log`
- JSON lines.
- Always on.

## External Frameworks and Libraries

Apple frameworks:

- SwiftUI: UI.
- Combine: nested observable forwarding.
- AppKit: save/open panels, Finder reveal, app restart, privacy settings.
- AVFoundation: audio engine, buffers, audio files, assets, asset reader.
- AudioToolbox/CoreAudio: audio device IDs, input-device selection.
- Speech: `SpeechTranscriber`, `SpeechAnalyzer`, speech authorization.
- CoreMedia: buffer timestamps for analyzer input and asset duration.
- UniformTypeIdentifiers: save panel content types.

Third-party/local:

- `external/FluidAudio`: Parakeet EOU streaming ASR, model download utilities, Core ML model runtime.
- `external/speech-swift-worktree`: SpeechVAD Sortformer streaming diarization and AudioCommon resampling/model download utilities.

Network:

- LLM calls use `URLSession.shared.data(for:)`.
- Ollama defaults to local `http://localhost:11434`.
- Remote providers can be configured by the user.

## Permissions and Startup

`AppModel.runFirstLaunchPermissionFlowIfNeeded()`:

1. Refresh permission state.
2. If mic or speech permission is `notDetermined`, request native dialogs.
3. Persist setup state.
4. Relaunch the packaged `.app` with `/usr/bin/open -n`.
5. Terminate the current app instance.

Fallback permission checks run before capture through `PermissionService.authorizeFirstRecordingDeviceTouch()`.

If not running as an `.app` bundle, the app cannot relaunch itself and instead asks the user to restart manually.

## Diagnostics

Tracing is the primary debugging interface.

```sh
tail -f /tmp/VoiceTranscribe.log
```

Useful event families:

- `permission.*`
- `capture.*`
- `recording.*`
- `transcript.*`
- `transcription.*`
- `fluidAudio.*`
- `diarization.*`
- `factCheck.*`
- `llm.*`
- `summary.*`
- `settings.*`

Tests use Swift Testing in `Tests/VoiceTranscribeTests/VoiceTranscribeTests.swift`.

Current coverage includes:

- File naming.
- Transcript document merging.
- Permission service behavior.
- LLM endpoint sanitization and provider repair.
- Prompt rendering placeholders.
- Prompt state accrual.
- AI queue concurrency.
- Batch prompt calls.
- Markdown export.
- Speaker labels in text and Markdown export.

## Common Change Points

Add a new LLM provider:

1. Add case to `LLMProviderKind`.
2. Add default endpoint and display name.
3. Add request builder in `OllamaFactCheckService.generate`.
4. Add response parser.
5. Add tests for request path/auth/model handling.

Add a prompt placeholder:

1. Update `FactCheckPrompt.render`.
2. Update prompt editor help in `Views.swift`.
3. Update README/REQUIREMENTS if user-facing.
4. Add tests.

Add a transcription engine:

1. Add case to `TranscriptionEngineKind`.
2. Implement `TranscriptionService`.
3. Route in `AppModel.makeInitialService` and `TranscriptionCoordinator.makeService`.
4. Add UI label and tests where possible.

Change transcript row behavior:

1. Update `TranscriptFactCheckPanel` in `Views.swift`.
2. Check `MarkdownExportService` if export semantics also change.
3. Check `REQUIREMENTS.md` UI/UX section.

Change recording filenames:

1. Update `FileNamer` in `Utilities.swift`.
2. Update `RecordingService.stop`.
3. Update tests for basename/timestamps.
4. Ensure audio, transcript, and metadata basenames remain aligned.

## Known Implementation Risks

- `RecordingService.moveReplacingExisting` overwrites existing destination files; requirements call for collision-safe names.
- `visualizationSensitivity` is persisted and shown but not currently applied by `AudioCaptureService.displayLevel`.
- Device removal during active capture needs stronger handling.
- Transcription backpressure is mostly represented as UI buffer state; slow downstream consumers need explicit policy.
- Swift type names and trace names still use `FactCheck` for generic AI processing.
- Requirements now call for a target UI split between `Transcript Paragraphs` and `AI Summary`; current UI still has `Recording Summary`.

## Build, Test, Package

```sh
./build.sh
swift test
./scripts/package-app.sh
```

The packaged app is written to:

```text
dist/VoiceTranscribe.app
```

Run the packaged app:

```sh
open -n dist/VoiceTranscribe.app
```
