# AGENTS.md — VoiceTranscribe

Project knowledge for future agents (and future-you). Read before touching code.

## What This Is

VoiceTranscribe is a native macOS SwiftUI app for enumerating audio input devices, monitoring their levels with a live graph, recording to disk, displaying live transcripts, summarizing recordings, and running configurable AI processing prompts over finalized transcript text.

- **Repo:** https://github.com/tamclaw1000/VoiceTranscribe
- **Local:** `~/projects/ai/VoiceTranscribe`
- **Platform:** macOS 26+ (requires SpeechTranscriber API)
- **Language:** Swift (Swift 5 language mode, building with Swift 6.3 toolchain)
- **UI:** SwiftUI (AppKit bridges only for folder picker and privacy settings)

## Architecture

```
VoiceTranscribeApp
  └─ AppModel (@MainActor, ObservableObject) — central orchestrator
       ├─ AudioDeviceService — CoreAudio enumeration, 2s polling timer
       ├─ AudioCaptureService — AVAudioEngine tap → consumer fan-out
       │    ├─ consumers["listen"]      → (noop, viz is automatic)
       │    ├─ consumers["record"]      → RecordingService.consume()
       │    └─ consumers["transcribe"]  → TranscriptionCoordinator.consume()
       ├─ RecordingService — AsyncAudioFileWriter on .utility queue
       ├─ TranscriptionCoordinator
       │    └─ AppleSpeechTranscriptionService — SpeechTranscriber + SpeechAnalyzer
       ├─ SummaryCoordinator — paragraph-form recording summaries
       ├─ FactCheckCoordinator — AI processing queue, prompt templates, batching, prompt state
       ├─ PermissionService — lazy mic/speech auth with caching
       └─ AppSettings — @AppStorage-backed preferences
```

### Data Flow

```
Mic → AVAudioEngine tap → copyBuffer() → DispatchQueue.main
  → process() → metrics + visualization (30fps throttle)
  → fan out to registered consumers (listen/record/transcribe)
```

### Key Design Decisions

1. **Single capture path, multiple consumers.** One `AVAudioEngine` tap feeds all active modes. `AudioCaptureService` fans out copied buffers. Capture stops when no consumers remain (`stopIfUnused()`).

2. **Off-main-actor file writing.** `AsyncAudioFileWriter` uses its own `DispatchQueue` (`.utility` QoS) so disk I/O never blocks the audio tap.

3. **SpeechTranscriber (not SFSpeechRecognizer).** The legacy `SFSpeechRecognizer` is broken for streaming on macOS 26. Migration to `SpeechAnalyzer` + `SpeechTranscriber` happened in v1.3.0. The analyzer stream must be started BEFORE audio buffers are fed. Buffers are resampled via `AVAudioConverter` to the analyzer's preferred format.

4. **Startup + fallback permission model.** Device enumeration is passive, but app startup now requests native microphone/speech dialogs when macOS reports a not-determined state, then relaunches the packaged app so audio starts with fresh authorization. `PermissionService.authorizeFirstRecordingDeviceTouch()` remains the fallback path before capture.

5. **Buffer copying is mandatory.** Tap buffers are transient. Every buffer is deep-copied (`copyBuffer()`, `deepCopy()`) before being handed off to consumers.

6. **AI processing is prompt-template based.** Enabled prompt templates, not a single global AI toggle, determine whether finalized sentences are sent to LLMs. Each prompt can use its own model unless `useGlobalPromptLLM` is enabled.

7. **Global prompt model enables batching.** When all enabled prompts target the global model, multiple prompt questions for the same sentence can be sent in one LLM request and mapped back to individual result rows.

8. **Prompt state is per template.** `{{prompt-state}}` accrues independently for each prompt template, updates from successful responses, resets with AI processing state, and forces that template's calls to run serially.

## Critical Gotchas

### ⚠️ Nested ObservableObject Bug (Fixed in v1.3.1)

**The problem:** AppModel had `@Published` child ObservableObjects (`captureService`, `recordingService`, `transcription`, `permissionService`). When, say, `AudioCaptureService.status` changed, SwiftUI did NOT re-render — because `@Published` on a reference type only fires when the *reference* changes, not when the child's own `@Published` properties change.

**The fix:** In `AppModel.init()`, subscribe to each child's `objectWillChange` and forward to `self.objectWillChange`:

```swift
captureService.objectWillChange.sink { [weak self] _ in
    self?.objectWillChange.send()
}.store(in: &cancellables)
```

**Lesson:** Any time an ObservableObject contains `@Published` child ObservableObjects, you must forward their changes. Otherwise button states, labels, and panels silently fail to update.

### ⚠️ AVAudioEngine Tap Must Copy Buffers

Tap callback buffers are transient — they're invalidated after the callback returns. Always `memcpy` or `deepCopy()` before fanning out to async consumers. RecordingService and TranscriptionService both do their own copies too.

### ⚠️ SpeechAnalyzer Input Stream Ordering

The analyzer stream must be started (`analyzer.start(inputSequence:)`) BEFORE any audio buffers are sent. Getting this order wrong causes silent transcription failures.

### ⚠️ AI Processing Labels

The Swift type names still include historical `FactCheck` names, but visible UI and documentation should say **AI Processing** unless specifically describing the old implementation. Avoid reintroducing user-facing "Fact Check" labels.

### ⚠️ Stateful Prompt Queueing

Prompts that include `{{prompt-state}}` must not be batched or run concurrently for the same template. Inject prompt state immediately before the request is sent, then update it from the successful response before the next stateful call for that template.

### ⚠️ Version Bumps Are Manual

Version numbers live in `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`). Every code change section in `IMPLEMENTATION.md` should end with a bump. If the plist says 1.3.0 but the checklist says 1.3.2, someone forgot.

### ⚠️ IMPLEMENTATION.md IS the Changelog — Do NOT Create a Separate CHANGELOG.md

This project tracks versioned work exclusively in `IMPLEMENTATION.md`. Each version is a numbered section with checklists. There is NO `CHANGELOG.md` file — do not create one. When adding a new version:

1. Add a new numbered section to `IMPLEMENTATION.md` (e.g., `## 30. v1.5.0. Feature Name`).
2. Use checked-off `- [x]` items describing what was done.
3. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
4. Add a row to the Version History table in THIS file (AGENTS.md).

That's it. No other files need version info.

## Tracing

Traces are **always-on** and write to `/tmp/VoiceTranscribe.log` as JSON lines (one per event):

```sh
tail -f /tmp/VoiceTranscribe.log
```

No CLI flag needed. The `Trace.swift` utility fires on every:
- Button press (`button.listen.start`, `record.*`, `transcribe.*`)
- Audio level sample (~every 1s: RMS, peak, display level, clipping)
- Capture lifecycle (`capture.starting`, `.started`, `.stopped`, `.error`)
- Recording I/O (`recording.started`, `.finalized`, `transcript.saved`, `.metadata.saved`)
- Transcription event (`transcription.starting`, `.started`, `.stopped`, `segmentFinal`)
- AI processing event (`factCheck.*` historical trace names, including prompt/template/model queue activity)
- Device change (`devices.changed`)
- Permission state (`permission.mic`)
- Error (various `.error` events)

## Build & Launch

```sh
cd ~/projects/ai/VoiceTranscribe
swift build
open "$(swift build --show-bin-path)/VoiceTranscribe"
```

Package as .app:
```sh
./scripts/package-app.sh
# → dist/VoiceTranscribe.app
```

Run tests:
```sh
swift test
```

## Key Files

| File | Purpose |
|------|---------|
| `AppModel.swift` | Orchestrator, button handlers, permission gating, Combine subscriptions |
| `AudioCaptureService.swift` | AVAudioEngine tap, metrics, visualization, consumer fan-out |
| `AudioDeviceService.swift` | CoreAudio enumeration, 2s polling, transport labels |
| `RecordingService.swift` | Async file writing, basename generation, metadata JSON |
| `TranscriptionService.swift` | SpeechTranscriber pipeline, format conversion, coordinator |
| `FactCheckService.swift` | AI processing LLM clients, queueing, prompt substitutions, batching, prompt state |
| `PermissionService.swift` | Lazy mic/speech auth with caching and mock support |
| `Trace.swift` | JSON-line event logger to `/tmp/VoiceTranscribe.log` |
| `Models.swift` | Data types: SoundInputSource, RecordingSession, TranscriptSegment, etc. |
| `Utilities.swift` | FileNamer, BoundedBuffer, TranscriptDocument |
| `AppSettings.swift` | @AppStorage preferences, output folder, format |
| `Views.swift` | All SwiftUI views: ContentView, SourceRow, GraphPanel, Transcript/AI processing panels, SettingsView |
| `Resources/Info.plist` | Bundle metadata, permissions strings, version numbers |
| `REQUIREMENTS.md` | Full product requirements |
| `IMPLEMENTATION.md` | Versioned implementation checklist |

## Version History

| Version | Build | What Changed |
|---------|-------|-------------|
| 2.4.6 | 49 | Added per-prompt accumulated `{{prompt-state}}` substitution |
| 2.4.5 | 48 | Batched multiple prompt questions into one LLM request when using a global prompt model |
| 2.4.4 | 47 | Added timestamped conversation prompt placeholders for AI processing |
| 2.4.3 | 46 | Fixed LLM model list refresh, enabled new prompts by default, and added a global model override for all prompts |
| 2.4.2 | 45 | Fixed prompt-template mutations to refresh the UI immediately |
| 2.4.1 | 44 | Moved Settings options into General, LLM Models, and Prompt Templates tabs |
| 2.4.0 | 43 | Added multiple named AI prompt templates, per-prompt model selection, prompt toggles, three-call AI queue, and transcript auto-scroll |
| 2.3.2 | 42 | Simplified OpenAI-compatible LLM requests, normalized saved endpoint strings, and moved main panels into tabs |
| 2.3.1 | 41 | Combined transcript and AI result output into one Markdown recording table |
| 2.3.0 | 40 | Added AI result metadata, prompts, summary, and fact-check output to Markdown exports |
| 2.2.9 | 39 | Added a pinned version footer to the source sidebar |
| 2.2.8 | 38 | Added Markdown export for transcript sessions |
| 2.2.7 | 37 | Fixed permission-flow relaunch to start a fresh app instance |
| 2.2.6 | 36 | Split the macOS menu Settings window into the same two-column options layout |
| 2.2.5 | 35 | Made the AI toggle visible in the main settings bar and transcript header |
| 2.2.4 | 34 | Added a global AI toggle that gates LLM fact-checking and LLM tests |
| 2.2.3 | 33 | Added first-class OpenRouter configuration and repaired OpenRouter/OpenCode endpoint mismatches |
| 2.2.2 | 32 | Moved LLM test buttons to top, fixed modal result display, improved LLM HTTP errors |
| 2.2.1 | 31 | Added a plain selected-LLM prompt test for `Hello, what is 10 * 20?` |
| 2.2.0 | 30 | Added LLM API types for Ollama, OpenAI-compatible, Anthropic, and Gemini endpoints |
| 2.1.1 | 29 | Split Settings sheet into two columns and moved LLM configuration to the right |
| 2.1.0 | 28 | Multiple configurable LLM endpoints with selected endpoint routing for fact-checking |
| 2.0.9 | 27 | Added CopyText and SaveToFile actions to the Recording Summary |
| 2.0.8 | 26 | Transcript text saves after transcription stops; added CopyText and SaveToFile actions |
| 2.0.7 | 25 | Removed FluidAudio length-based partial finalization so fragments are not fact-checked |
| 2.0.6 | 24 | First-launch native permission prompts with automatic app relaunch |
| 2.0.5 | 23 | Running recording summary, editable summary prompt, transcript grid no longer auto-scrolls |
| 2.0.4 | 22 | Default/migrate transcription engine to FluidAudio and trace transcription buffer intake |
| 2.0.3 | 21 | Combined live transcript and fact-check output into one timestamp/source/text grid |
| 2.0.2 | 20 | Editable Ollama fact-check prompt template in Settings |
| 2.0.1 | 19 | Fact-check result display accepts raw Ollama prose and fenced JSON responses |
| 2.0.0 | 18 | Fact-check pane backed by local Ollama model `igorls/gemma-4-12B-it-heretic-GGUF` |
| 1.7.0 | 17 | File input sources: load audio files, transcribe files, auto-load recordings |
| 1.6.0 | 16 | Settings popup, first-run access flow, disable buttons until permissions granted |
| 1.5.4 | 14 | Real-time sentence boundary detection (NLTokenizer) / length-based commit (1.5.5) |
| 1.5.1 | 11 | Fixed FluidAudio model verification (partial downloads), cleaned cache, bumped version |
| 1.5.0 | 10 | FluidAudio integration: Parakeet EOU streaming ASR, pluggable engine architecture, engine picker in Settings |
| 1.4.0 | 9 | Simplified UI: merged Listen+Transcribe, Record→checkbox with filename + Finder reveal |
| 1.3.4 | 8 | PCM recording fix: 16-bit interleaved (VLC-compatible) |
| 1.3.3 | 7 | Synchronous trace writes + stderr echo |
| 1.3.2 | 6 | Structured event tracing (`Trace.swift`) |
| 1.3.1 | 5 | Fixed nested ObservableObject SwiftUI bug |
| 1.3.0 | 4 | Migrated from SFSpeechRecognizer to SpeechTranscriber |
| 1.2.1 | 3 | Green icons, state console, live RMS/peak readout |
| 1.2.0 | 2 | UX fixes, transcription buffer bar, audio level scaling |
| 1.1.0 | 1 | Lazy permission requests with caching |
| 1.0.0 | — | Initial implementation |
