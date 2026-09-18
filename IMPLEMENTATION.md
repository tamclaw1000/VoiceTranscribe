# VoiceTranscribe Implementation Checklist

This checklist converts `REQUIREMENTS.md` into implementation work for a native Swift macOS application.

## 1. Project Setup

- [x] Create a new macOS app project named `VoiceTranscribe`.
- [x] Use Swift as the implementation language.
- [x] Use SwiftUI for the primary UI.
- [x] Add AppKit bridges only where SwiftUI is insufficient.
- [x] Set the minimum supported macOS version.
- [x] Add microphone usage description to `Info.plist`.
- [x] Add speech recognition usage description to `Info.plist`.
- [x] Define app sandbox and entitlement requirements.
- [x] Add file access entitlement strategy for saving recordings.
- [x] Create a dedicated app group or support directory only if needed.
- [x] Establish project folders for UI, audio, transcription, persistence, settings, and tests.

## 2. Architecture

- [x] Define a `SoundInputSource` model.
- [x] Define a `CaptureSessionState` model.
- [x] Define a `RecordingSession` model.
- [x] Define a `TranscriptSegment` model.
- [x] Define an `AudioDeviceService` responsible for enumerating devices.
- [x] Define an `AudioCaptureService` responsible for source capture.
- [ ] Define an `AudioBufferCoordinator` responsible for distributing captured audio.
- [ ] Define a `VisualizationService` responsible for level and waveform data.
- [x] Define a `RecordingService` responsible for file output.
- [x] Define a `TranscriptionService` protocol.
- [x] Implement an Apple Speech based transcription service.
- [ ] Define a `SessionStore` or persistence layer for metadata.
- [x] Keep capture, file writing, transcription, and UI updates on separate execution paths.

## 3. Permissions

- [x] Request microphone permission before starting capture.
- [x] Request speech recognition permission before starting transcription.
- [x] Show permission state in the UI.
- [x] Handle microphone permission denied state.
- [x] Handle speech recognition permission denied state.
- [x] Provide a button or link to macOS Settings when permissions are missing.
- [x] Prevent capture actions from silently failing when permission is unavailable.

## 4. Input Source Enumeration

- [x] Enumerate built-in microphone devices.
- [x] Enumerate USB microphone devices.
- [x] Enumerate Bluetooth microphone devices.
- [x] Enumerate external audio interfaces.
- [x] Enumerate aggregate input devices.
- [x] Enumerate virtual audio input devices.
- [x] Capture stable device identifier.
- [x] Capture display name.
- [x] Capture manufacturer when available.
- [x] Capture channel count.
- [x] Capture available or current sample rate information.
- [x] Capture whether the device is the system default input.
- [ ] Capture availability and permission-related state.
- [x] Listen for device connect, disconnect, rename, and default-device changes.
- [x] Refresh the UI when the device list changes.
- [x] Handle the no-input-devices state.

## 5. Main Window UI

- [x] Build a primary source list or table.
- [x] Show source name for each input.
- [x] Show device type or transport when available.
- [ ] Show current availability state.
- [x] Show input activity indicator.
- [x] Add Listen action per source.
- [x] Add Record action per source.
- [x] Add Transcribe action per source.
- [x] Show active session state per source.
- [x] Make actions disable correctly when unavailable.
- [x] Ensure list updates do not interrupt active source display.
- [x] Keep controls keyboard accessible.

## 6. Capture Session Lifecycle

- [x] Start capture for a selected source.
- [x] Stop capture for a selected source.
- [x] Handle one active source at a time for version 1 unless multi-source capture is explicitly chosen.
- [x] Reuse one capture path for listen, record, and transcribe consumers.
- [x] Keep capture running while any consumer is active.
- [x] Stop capture only after all consumers for the source have stopped.
- [ ] Handle device removal during active capture.
- [x] Recover cleanly after capture start failure.
- [x] Publish session state changes to the UI.

## 7. Internal Buffering

- [ ] Implement a capture buffer for incoming audio frames.
- [x] Fan out buffered audio to visualization, recording, and transcription consumers.
- [x] Use bounded memory for long sessions.
- [x] Prioritize recording integrity over visualization and transcription.
- [ ] Implement backpressure handling for slow transcription.
- [x] Implement overflow handling for visualization buffers.
- [x] Implement overflow warning state for the UI.
- [x] Ensure file writing does not block audio capture.
- [x] Ensure transcription processing does not block audio capture.
- [ ] Add metrics for buffer depth and dropped non-critical frames.

## 8. Listen Mode

- [x] Start capture when Listen is selected.
- [x] Stop listen consumer when Listen is toggled off.
- [x] Compute current amplitude or RMS level.
- [x] Compute recent waveform or level history.
- [x] Detect and display clipping or peak events.
- [x] Throttle visualization updates to a stable UI frame rate.
- [x] Render a live sound graph.
- [x] Keep listen mode from writing files.
- [ ] Keep listen mode responsive during device changes.

## 9. Recording Mode

- [x] Start a recording session when Record is selected.
- [x] Capture the recording start timestamp.
- [x] Create a recording basename from timestamp and source slug.
- [x] Buffer audio before writing to disk.
- [x] Write audio asynchronously.
- [x] Stop recording when Record is toggled off.
- [x] Capture the recording end timestamp.
- [x] Finalize and close the audio file.
- [x] Save transcript file when transcription was active.
- [x] Save optional metadata file.
- [x] Surface disk write failures.
- [ ] Surface low disk space failures.
- [ ] Verify long recording sessions remain responsive.

## 10. File Naming

- [x] Implement filesystem-safe source slug generation.
- [x] Implement start timestamp format `YYYYMMDDHHMMSS`.
- [x] Decide final interpretation of end timestamp format `HHMMSSS`.
- [x] Implement end timestamp format consistently.
- [x] Use the same basename for audio, transcript, and metadata files.
- [x] Add audio file extension based on selected format.
- [x] Add transcript file extension.
- [x] Add metadata file extension if metadata sidecars are enabled.
- [ ] Prevent filename collisions.
- [x] Add unit tests for timestamp formatting and slug generation.

## 11. Transcription Mode

- [x] Define `TranscriptionService` protocol.
- [x] Implement Apple Speech transcription adapter.
- [x] Start capture when Transcribe is selected.
- [x] Send buffered audio chunks to the transcription service.
- [x] Receive interim transcript results.
- [x] Receive finalized transcript results.
- [x] Stop transcription cleanly when Transcribe is toggled off.
- [x] Handle transcription engine unavailable state.
- [x] Handle transcription authorization failure.
- [x] Handle transcription lag without interrupting recording.
- [x] Save transcript output when recording is active.
- [x] Keep the design open for alternate transcription engines.

## 12. Live Transcript UI

- [x] Create a live transcript panel.
- [x] Render finalized transcript text.
- [x] Render interim transcript text with distinct styling.
- [x] Preserve finalized text while interim text changes.
- [x] Auto-scroll when the user is already near the bottom.
- [ ] Stop forcing scroll when the user scrolls back.
- [x] Show a clear empty state before speech is detected.
- [ ] Optionally show timestamps per finalized segment.
- [ ] Optionally show confidence where available.
- [x] Keep transcript updates incremental and non-blocking.

## 13. Settings

- [x] Add default output folder setting.
- [x] Add audio format setting.
- [x] Add transcription engine setting.
- [x] Add save-transcripts-automatically setting.
- [x] Add start-transcription-with-recording setting.
- [x] Add visualization sensitivity setting.
- [x] Add temporary buffer cleanup setting if temporary files are used.
- [x] Persist settings across app launches.
- [ ] Validate inaccessible output folders.

## 14. Error Handling

- [x] Handle no input devices.
- [ ] Handle unsupported device format.
- [ ] Handle device removal during listen.
- [ ] Handle device removal during recording.
- [ ] Handle device removal during transcription.
- [x] Handle microphone permission denial.
- [x] Handle speech recognition permission denial.
- [x] Handle transcription engine failures.
- [x] Handle disk write failures.
- [ ] Handle low disk space.
- [x] Handle buffer overflow.
- [x] Present recoverable errors without crashing.
- [ ] Log technical details for diagnostics.

## 15. Performance Work

- [ ] Measure capture startup latency.
- [ ] Measure stop/finalize latency.
- [ ] Measure listen graph latency.
- [ ] Measure transcript update latency.
- [ ] Measure memory usage during long recordings.
- [ ] Measure CPU usage during listen only.
- [ ] Measure CPU usage during record and transcribe.
- [x] Throttle UI updates where needed.
- [x] Avoid heavy work on the main actor.
- [ ] Add stress test for slow transcription consumer.
- [ ] Add stress test for slow disk writes.

## 16. Testing

- [ ] Unit test source model mapping.
- [x] Unit test timestamp formatting.
- [x] Unit test source slug generation.
- [x] Unit test recording basename generation.
- [x] Unit test transcript segment merging.
- [x] Unit test buffer overflow behavior.
- [ ] Unit test backpressure behavior.
- [ ] Integration test device enumeration where possible.
- [ ] Integration test capture lifecycle with a mock audio source.
- [ ] Integration test recording file creation.
- [ ] Integration test transcript file creation.
- [ ] UI test source list display.
- [ ] UI test permission denied states.
- [ ] UI test listen, record, and transcribe action state changes.

## 17. Packaging and Release

- [ ] Configure app icon.
- [x] Configure app category and bundle metadata.
- [x] Confirm entitlements for microphone, speech recognition, sandboxing, and file access.
- [x] Sign the application.
- [ ] Notarize the application if distributing outside the Mac App Store.
- [x] Create a first-run permission flow.
- [x] Create a short user-facing help page or README.
- [ ] Verify clean install behavior.
- [ ] Verify upgrade behavior if app settings already exist.

## 18. Version 1 Completion Criteria

- [ ] App launches successfully on supported macOS version.
- [ ] App lists currently available input sources.
- [ ] Source list updates after device connection changes.
- [x] Listen mode shows a live sound graph.
- [ ] Record mode writes an audio file with the required basename.
- [ ] Record mode tracks start and end timestamps.
- [ ] Transcribe mode displays a live transcript.
- [ ] Record plus Transcribe saves transcript output alongside audio.
- [ ] Audio capture remains stable during transcription delays.
- [ ] UI remains responsive during long recordings.
- [ ] Permission failures are handled cleanly.
- [ ] Disk and device errors are handled cleanly.
- [x] Basic unit and integration tests pass.

## 19. v1.1. Implement Permission Requests

- [x] Request recording-device permission lazily the first time the app touches a recording device.
- [x] Cache microphone permission state after the first device-touch permission request.
- [x] Reuse cached permission state for Listen, Record, and Transcribe actions.
- [x] Refresh cached permission state when macOS reports an authorization-state change.
- [x] Avoid prompting for microphone access during passive source-list enumeration.
- [x] Show a clear first-run permission prompt path before capture begins.
- [x] Add tests for first-touch permission request behavior.
- [x] Add tests for cached permission state reuse.

## 20. v1.2. UX and Transcription Feedback Fixes

- [x] Color active Listen action icon and text while listen mode is active.
- [x] Color active Record action icon and text while recording is active.
- [x] Color active Transcribe action icon and text while transcription is active.
- [x] Fix input graph metering so normal speech produces visible movement.
- [x] Support float, int16, and int32 PCM buffers in audio level metering.
- [x] Scale RMS and peak levels for a more readable visual graph.
- [x] Add a transcription buffer status model.
- [x] Display a transcription buffer bar in the live transcript panel.
- [x] Display queued buffer duration while transcription is active.
- [x] Display transcription status text for receiving audio, processing buffer, waiting for audio, and idle states.
- [x] Add tests for audio display-level scaling.
- [x] Add tests for transcription buffer fill clamping.
- [x] Bump app version to `0.1.1` build `2`.

## 21. v1.2.1. Continued Bug Fixes

- [x] Force active Listen, Record, and Transcribe button icons to green.
- [x] Use explicit icon/text button labels so active state is visible inside bordered buttons.
- [x] Add a compact state console under each source's input options.
- [x] Output capture state in the source console.
- [x] Output active source modes in the source console.
- [x] Output live RMS and peak levels in the source console.
- [x] Output transcription active, buffer duration, and receiving-audio state in the source console.
- [x] Make the input chart more visibly live with green level bars.
- [x] Add numeric RMS and peak readout above the input chart.
- [x] Bump app version to `1.2.1` build `3`.

## 22. v1.3.0. SpeechTranscriber Migration

- [x] Raise the app minimum platform to macOS 26.
- [x] Replace legacy streaming `SFSpeechRecognizer` transcription with `SpeechTranscriber`.
- [x] Add `SpeechAnalyzer` input stream startup before audio buffers are sent.
- [x] Install or verify the current locale's SpeechTranscriber model before transcription starts.
- [x] Convert captured audio buffers to the analyzer's preferred audio format.
- [x] Deep-copy captured audio buffers before asynchronous transcription processing.
- [x] Deep-copy audio tap buffers before dispatching them to UI, recording, and transcription consumers.
- [x] Feed analyzer input with explicit `CMTime` buffer start times.
- [x] Consume SpeechTranscriber results off the main actor and publish transcript updates back to the UI.
- [x] Preserve existing transcription buffer status display while using SpeechTranscriber.
- [x] Update requirements to state macOS 26 and SpeechTranscriber/SpeechAnalyzer.
- [x] Bump app version to `1.3.0` build `4`.

## 23. v1.3.1. SwiftUI Nested ObservableObject Fix

- [x] Fix: Listen/Record/Transcribe button states not updating when nested services change.
- [x] Root cause: AppModel held `@Published` child ObservableObjects (`captureService`, `recordingService`, `transcription`, `permissionService`), but `@Published` on reference types only fires when the reference is reassigned — not when the child's own `@Published` properties change.
- [x] Fix: In `AppModel.init()`, subscribe to each child's `objectWillChange` publisher via Combine and forward it to `self.objectWillChange`.
- [x] Affected children: `captureService`, `recordingService`, `transcription`, `permissionService`.
- [x] Result: Button labels (Listen→Stop), "Active" indicator, graph panel, and transcript panel all re-render correctly when underlying service state changes.
- [x] Add `import Combine` and `cancellables` storage to `AppModel`.
- [x] Bump app version to `1.3.1` build `5`.

## 24. v1.3.2. Structured Event Tracing

- [x] Create `Trace.swift` utility writing structured JSON-line events to `/tmp/VoiceTranscribe.log`.
- [x] Truncate the log on first open per process lifetime, then append.
- [x] Write asynchronously on a dedicated `DispatchQueue` (`.utility` QoS).
- [x] Provide convenience methods: `event()`, `state()`, `button()`, `audio()`, `file()`.
- [x] Trace button presses: `button.listen.start`, `.stop`, `record.*`, `transcribe.*`.
- [x] Trace audio capture: `capture.starting`, `.started`, `.stopped`, `.error` with sample rate and channel count.
- [x] Trace audio levels: `audio.level` every ~1 second with RMS, peak, display level, and clipping flag.
- [x] Trace recording I/O: `recording.started`, `recording.finalized`, `transcript.saved`, `metadata.saved`, `writeError` with paths and duration.
- [x] Trace transcription: `transcription.starting`, `.started`, `.stopped`, `segmentFinal` with engine name and segment text.
- [x] Trace device changes: `devices.changed` with previous/new count and device names.
- [x] Trace permissions: `permission.mic` with status (`alreadyAuthorized`, `granted`, `denied`).
- [x] Trace errors: `listen.error`, `record.error`, `transcribe.error`, `capture.error`, `record.stopError`.
- [x] View live: `tail -f /tmp/VoiceTranscribe.log`.
- [x] Bump app version to `1.3.2` build `6`.

## 25. v1.3.3. Synchronous Trace + Stderr Echo

- [x] Change Trace from async (`queue.async`) to synchronous (`queue.sync` + `synchronize()`) so events hit disk immediately.
- [x] Echo every trace event to stderr (`[VT] <json>`) so events are visible in Console.app when launched as `.app` bundle.
- [x] Remove unused `lock`, `startedAt`, `state()`, `flush()` from Trace to simplify.
- [x] Bump app version to `1.3.3` build `7`.

## 26. v1.3.4. PCM Recording Format Fix

- [x] Fix: `.wav` and `.caf` recordings unplayable in VLC and most media players.
- [x] Root cause: audio settings used `AVLinearPCMIsNonInterleaved: true` + 32-bit float — valid PCM but virtually no player supports non-interleaved layout.
- [x] Fix: switch to 16-bit integer interleaved PCM (`AVLinearPCMBitDepthKey: 16`, `AVLinearPCMIsFloatKey: false`, `AVLinearPCMIsNonInterleaved: false`).
- [x] `.m4a` (AAC) was never affected — default format remains playable.
- [x] Bump app version to `1.3.4` build `8`.

## 27. v1.3.5. Application Review Fixes

Items identified in `APPLICATION-REVIEW.md` (2026-05-31). (tambookpro4/OpenClaw/Deepseek/deepseek-v4-pro)

### 27a. Dead Setting: visualizationSensitivity

- [ ] Plumb `AppSettings.visualizationSensitivity` into `AudioCaptureService.displayLevel(forRMS:peak:)`.
- [ ] Accept a sensitivity multiplier or exponent parameter.
- [ ] Verify the slider in Settings actually changes the graph appearance.

### 27b. Device Removal During Active Capture

- [ ] Listen for `AVAudioEngineConfigurationChange` notification.
- [ ] When the active input device disappears, cleanly stop capture and notify user.
- [ ] Reset active source UI state after device removal.
- [ ] Trace device removal events.

### 27c. Transcription Buffer Overflows

- [ ] Implement backpressure: drop or throttle incoming audio buffers when `queuedDuration` >= `maxDuration`.
- [ ] Surface buffer-overflow warning to the transcription panel.
- [ ] Trace dropped transcription buffers.

### 27d. Recording Filename Collisions

- [ ] Detect when destination file already exists in `RecordingService.stop()`.
- [ ] Append a disambiguation suffix or UUID before overwriting.
- [ ] Add unit test for collision case.

### 27e. Analyzer Finalization Is Fire-and-Forget

- [ ] Track the finalization Task in a property so `stop()` can await it before a new `start()`.
- [ ] Ensure old analyzer sessions complete before new ones begin.

### 27f. Integration Tests

- [ ] Integration test capture lifecycle with mock audio source.
- [ ] Integration test recording file creation and metadata.
- [ ] Integration test transcription pipeline end-to-end.
- [ ] UI test permission denied states.
- [ ] Performance/stress test for long recordings (≥60 min).

### 27g. Low Disk Space Detection

- [ ] Check available disk space before starting recording.
- [ ] Warn user if free space drops below threshold during recording.
- [ ] Gracefully finalize recording if disk fills mid-session.

### 27h. Unsupported Device Format Handling

- [ ] Detect when `AVAudioEngine` cannot use the selected device's format.
- [ ] Surface a clear error message instead of silent failure.
- [ ] Log format negotiation details for diagnostics.

### 27i. Validate Inaccessible Output Folders

- [ ] Verify output folder exists and is writable before starting recording.
- [ ] Show Settings with a clear error if folder is invalid.
- [ ] Fall back to default folder when configured folder is inaccessible.

### 27j. App Polish

- [ ] Add app icon.
- [ ] Verify clean install behavior (no pre-existing settings).
- [ ] Verify upgrade behavior (settings survive version bumps).
- [ ] Notarize for distribution outside Mac App Store.

### 27k. Performance Benchmarks

- [ ] Measure capture startup latency.
- [ ] Measure stop/finalize latency.
- [ ] Measure memory usage during 60-minute recording.
- [ ] Measure CPU usage during listen-only.
- [ ] Measure CPU usage during record + transcribe.
- [ ] Add stress test for slow transcription consumer.
- [ ] Add stress test for slow disk writes.

## 28. v1.4.0. Simplify UI

### 28a. Combine Listen + Transcribe

- [x] Merge Listen and Transcribe into a single "Transcribe" / "Stop" toggle button.
- [x] Remove listen-only mode — transcription always runs when capture is active.
- [x] Keep the live sound graph visible during active transcription.
- [x] Update `AppModel.toggleListen()` and `AppModel.toggleTranscribe()` into a single `AppModel.toggleTranscribe()` that starts both capture and transcription together.
- [x] Remove the `listen` consumer from `AudioCaptureService`; transcription always consumes audio.
- [x] Green-color the Transcribe button icon and label when active (same as current Listen styling).
- [x] Update `SourceConsoleView` to show only `capture`, `modes`, `rms/peak`, and `transcription` fields.

### 28b. Record as Checkbox

- [x] Replace the Record button with a checkbox toggle.
- [x] Display the in-progress recording filename next to the checkbox when recording is active.
- [x] Make the filename clickable — opens the file's location in Finder.
- [x] After recording stops, show the final basename briefly (5s) then clear it.
- [x] Transcription text is always saved when recording was active (no separate auto-save toggle dependency).

### 28c. Simplified Source Row Layout

- [x] Source name, device info, and default indicator (unchanged).
- [x] Replace Listen + Record + Transcribe button group with Transcribe/Stop button + Record checkbox.
- [x] Move the "Active" indicator next to or within the Transcribe button.
- [x] Ensure layout is clean at narrow widths.

### 28d. Remove Dead Code

- [x] Remove `isListening()` from `AppModel`.
- [x] Remove `toggleListen()` from `AppModel`.
- [x] Remove `SourceAction.listen` from `Models.swift` if no longer referenced.
- [x] Remove `startTranscriptionWithRecording` setting (transcription always runs when capture is active).
- [x] Remove the `saveTranscriptsAutomatically` setting dependency from recording stop logic (transcript always saved when recording).

### 28e. Bump Version

- [x] Bump `CFBundleShortVersionString` to `1.4.0`.
- [x] Bump `CFBundleVersion` to `9`.

## 30. v1.5.0. FluidAudio Integration

### 30a. Review FluidAudio

- [x] Review `external/FluidAudio` architecture and API surface.
- [x] FluidAudio provides Core ML speech processing on Apple Silicon: ASR (Parakeet TDT batch, Parakeet EOU streaming, Nemotron, Qwen3), TTS (Kokoro, PocketTTS, StyleTTS2, Supertonic3), VAD (Silero), and Diarization (pyannote offline).
- [x] ASR API: `StreamingEouAsrManager` is an `actor` with `loadModels(to:)` (auto-downloads from HuggingFace), `process(audioBuffer:)` (streaming with internal conversion), EOU/partial callbacks, and `finish()` for final transcript.
- [x] Model: `parakeet-realtime-eou-120m-coreml` with 160/320/1280ms chunk sizes; 320ms chosen for balanced latency (~630ms audio per chunk, ~5% WER).

### 30b. Pluggable Transcription Engine Architecture

- [x] Add `fluidAudio` case to `TranscriptionEngineKind` enum in `AppSettings.swift`.
- [x] Create `FluidAudioTranscriptionService` conforming to `TranscriptionService` protocol.
  - Uses `StreamingEouAsrManager` (320ms chunks, 1280ms EOU debounce).
  - EOU callback emits finalized `TranscriptSegment`; partial callback emits interim.
  - `start()` creates manager, sets callbacks, calls `loadModels()` (auto-download).
  - `append()` dispatches `process(audioBuffer:)` via fire-and-forget `Task`; the actor serializes concurrent calls.
  - `stop()` calls `finish()` to drain final utterance, then nils the manager.
- [x] Add `setEngine(_:)` to `TranscriptionCoordinator` — stops active transcription before swapping services.
- [x] Add `FluidAudio` as local package dependency in `Package.swift` (`external/FluidAudio`).
- [x] `AppModel.init()` reads persisted engine preference to construct the correct initial service.

### 30c. Engine Picker Behavior

- [x] Settings engine `Picker` calls `appModel.transcription.setEngine(newEngine)` before persisting the setting — stops any active transcription on switch.
- [x] Engine picker is `.disabled()` while `appModel.transcription.isTranscribing` — cannot change engines mid-transcription.
- [x] Engine choice persists across app launches via `@AppStorage("transcriptionEngine")`.

### 30d. FluidAudio Dependency

- [x] Added `external/FluidAudio` (swift-tools-version 6.0, macOS 14+) as local path dependency.
- [x] VoiceTranscribe target depends on `FluidAudio` product.
- [x] FluidAudio imports: `FluidAudio` (ASR, AudioConverter, ModelRegistry).

### 30e. Bump Version

- [x] Bump `CFBundleShortVersionString` to `1.5.0`.
- [x] Bump `CFBundleVersion` to `10`.

## 31. v1.5.1. BUGS

### 31a. FluidAudio Transcript Punctuation

- [x] Root cause: Parakeet EOU model does not emit punctuation tokens (`.`, `?`, `!`).
- [x] Each EOU boundary is a natural utterance end — added `addSentencePunctuation()` post-processing to `FluidAudioTranscriptionService`.
- [x] Capitalizes first letter and appends a period if the text doesn't already end with sentence punctuation.
- [x] Applied to both EOU callback (`setEouCallback`) and final drain (`finish()` in `stop()`).

### 31b. Status Console Shows for All Sources

- [x] Root cause: `SourceConsoleView` read `appModel.captureService.visualization` and `appModel.transcription.bufferSnapshot` directly — global state shown identically for every source row.
- [x] Fix: only use live `visualization` and `bufferSnapshot` when `isActiveSource` is true; use zeroed `VisualizationSnapshot()` / `TranscriptionBufferSnapshot()` for inactive rows.
- [x] Same guard applied to `isTranscribing` — only shows "active" for the active source.

### 31c. Bump Version

- [x] Bump `CFBundleShortVersionString` to `1.5.1`.
- [x] Bump `CFBundleVersion` to `11`.

## 31d. v1.5.2. Punctuation Debugging

- [x] Added diagnostic traces to `FluidAudioTranscriptionService.stop()` and `addSentencePunctuation()` to trace the punctuation pipeline.
- [x] Bump `CFBundleShortVersionString` to `1.5.2`.
- [x] Bump `CFBundleVersion` to `12`.

## 31e. v1.5.3. Comprehensive Transcription Tracing

- [x] Added trace for EOU callback entry (`fluidAudio.eou.raw`), skip (`fluidAudio.eou.skip`), and punctuated output (`fluidAudio.eou.punctuated`).
- [x] Added trace for partial callback (`fluidAudio.partial`).
- [x] Added trace for `stop()` entry (`fluidAudio.stop.enter`) with manager state.
- [x] Added intermediate `fluidAudio.stop.trimmed` trace to see raw vs trimmed text.
- [x] Added `transcription.segmentPartial` trace in `TranscriptionCoordinator.apply()` — partial/interim segments now traced.
- [x] Bump `CFBundleShortVersionString` to `1.5.3`.
- [x] Bump `CFBundleVersion` to `13`.
- [ ] After testing: check `/tmp/VoiceTranscribe.log` for `fluidAudio.*` events to diagnose punctuation pipeline.

## 31f. v1.5.4. Real-Time Sentence Boundary Detection

- [x] Import `NaturalLanguage` framework.
- [x] Added `committedEndIndex` to track which portion of accumulated text has been emitted as finalized segments.
- [x] Added `splitSentences()` — uses `NLTokenizer(unit: .sentence)` to detect sentence boundaries in real-time partial text.
- [x] Partial callback now commits complete sentences as finalized segments (with punctuation) and keeps the last incomplete sentence as interim.
- [x] Requires at least 2 detected sentences before committing the first one, reducing false sentence splits.
- [x] Resets `committedEndIndex` on each new `start()`.
- [x] Bump `CFBundleShortVersionString` to `1.5.4`.
- [x] Bump `CFBundleVersion` to `14`.
- [x] Confirmed `finish()` drain at Stop produces punctuated text: `fluidAudio.stop.punctuated` trace shows full transcript with capitalization and period.
- [ ] NLTokenizer failed to find sentence boundaries in unpunctuated ASR text — no `fluidAudio.sentence` events during live transcription.

## 31g. v1.5.5. Length-Based Live Sentence Commit

- [x] Replaced NLTokenizer-based sentence detection with length-based commit strategy.
- [x] Commits accumulated text as a finalized sentence once 50+ new characters accumulate (with word-boundary split).
- [x] Removed `import NaturalLanguage` dependency.
- [x] Bump `CFBundleShortVersionString` to `1.5.5`.
- [x] Bump `CFBundleVersion` to `15`.
- [ ] After testing: check `/tmp/VoiceTranscribe.log` for `fluidAudio.sentence` events showing real-time sentence commits.


## 32. v1.6.0. Settings Popup and First-Run Access Flow

### 32a. Consolidate Buttons into Settings Popup

- [x] Move the Engine and Access Request Buttons, and the Apple Settings button into a single Settings button that brings up a pop-up.
- [x] The pop-up should contain: transcription engine picker, microphone permission request, speech recognition permission request, and a link to Apple System Settings.
- [x] Each permission item shows current authorization state (granted / denied / not determined).
- [x] The Apple Settings link opens `x-apple.systempreferences:com.apple.preference.security?Privacy`.
- [x] Settings popup implemented as `SettingsSheet` presented via `.sheet()` modifier.

### 32b. First-Run Access Prompt

- [x] When the application first launches, bring up the Settings pop-up automatically.
- [x] Request the user to set approvals if either microphone or speech recognition has not already been granted.
- [x] Track first-launch state with `@AppStorage("hasCompletedPermissionsSetup")` so the pop-up only auto-opens when permissions are missing.
- [x] Do not auto-open the pop-up on subsequent launches once both permissions are granted.
- [x] `markPermissionsSetupComplete()` called on Done when both permissions are granted.

### 32c. Disable All Buttons Until Approved

- [x] Disable all action buttons (Transcribe, Record) until both microphone and speech recognition permissions have been granted.
- [x] Show a clear message or badge on disabled buttons indicating permissions are required.
- [x] Re-enable buttons automatically when permissions are granted (via authorization-state change listener).
- [x] Ensure the Settings button remains enabled at all times so the user can resolve permissions.
- [x] Orange warning with "Microphone & Speech access required" shown in settingsBar when permissions are missing.

### 32d. Bump Version

- [x] Bump `CFBundleShortVersionString` to `1.6.0`.
- [x] Bump `CFBundleVersion` to `16`.

## 33. v1.7.0. File Input Source

### 33a. File as Input Source

- [x] Add the ability to load an audio file as an input source.
- [x] Add a "Load File…" button or menu item to browse for audio files (WAV, M4A, CAF, MP3, FLAC).
- [x] Loaded file appears in the source list as a virtual input source with its filename as the display name.
- [x] Show file metadata in the source subtitle: duration, format, sample rate, channel count.
- [x] Multiple files can be loaded simultaneously; each appears as a separate row.
- [x] Add a remove/close button to unload a file source.

### 33b. File Source — Transcribe Only

- [x] File input sources only have a Transcribe button (no Record checkbox).
- [x] Record is not applicable to file sources — the file is already the recording.
- [x] Clicking Transcribe on a file source processes the entire file through the selected transcription engine.
- [x] Show progress (elapsed / total duration) during file transcription.
- [x] Transcription results appear in the live transcript panel as finalized segments.

### 33c. Auto-Select Last Recording

- [x] After a recording session completes, the recorded file is automatically loaded as a file input source.
- [x] The most recently recorded file becomes the selected/active file source.
- [x] Previous file sources are retained unless manually removed.
- [x] Auto-loaded recording files use the same basename as the recording.

### 33d. Bump Version

- [x] Bump `CFBundleShortVersionString` to `1.7.0`.
- [x] Bump `CFBundleVersion` to `17`.



## 35. v1.8.0. Sherpa-Onnx Integration

### 35a. Add Sherpa-Onnx as Git Submodule

- [ ] Add `https://github.com/k2-fsa/sherpa-onnx` as a git submodule at `external/sherpa-onnx`.
- [ ] Build the C library (`libsherpa-onnx.a`) for macOS arm64.
- [ ] Create a `module.modulemap` for C interop (`SherpaOnnx` umbrella module).
- [ ] Add the C header search paths and library link flags to `Package.swift`.
- [ ] Verify the Swift API wrapper helpers (`SherpaOnnx.swift`) compile with the project.

### 35b. Review Sherpa-Onnx API Surface

- [ ] Study `SherpaOnnxOnlineRecognizer` for streaming ASR: `create()`, `acceptWaveform()`, `decode()`, `getResult()`, `isEndpoint()`, `inputReady()`, `reset()`.
- [ ] Study `SherpaOnnxOfflineRecognizer` for file-based ASR: `create()`, `decode()`, `getResult()`.
- [ ] Study speaker diarization: `SherpaOnnxOfflineDiarizer` with `create()`, `process()`, `getResults()`, sample rate requirements.
- [ ] Study VAD: `SherpaOnnxSileroVad` with `create()`, `acceptWaveform()`, `isSpeech()`, configurable window size.
- [ ] Study punctuation: `SherpaOnnxOfflinePunctuation` for post-processing ASR output.
- [ ] Identify required model files and download sources (HuggingFace repos).

### 35c. Sherpa-Onnx Streaming ASR Engine

- [ ] Add `sherpaOnnx` case to `TranscriptionEngineKind` enum.
- [ ] Create `SherpaOnnxTranscriptionService` conforming to `TranscriptionService` protocol.
  - [ ] `start()` — initialize `SherpaOnnxOnlineRecognizer` with transducer/zipformer2 model config, load tokens, set 16kHz feature config.
  - [ ] `append(buffer:)` — convert `AVAudioPCMBuffer` to float samples, call `acceptWaveform()`, loop `decode()` + `getResult()` for partial/final tokens.
  - [ ] `stop()` — call `inputFinished()` + final `decode()`, drain remaining results, release recognizer.
- [ ] Support model download on first use: auto-fetch `.onnx` encoder/decoder/joiner + `tokens.txt` from HuggingFace (e.g., `sherpa-onnx-zipformer-en-2023-06-26`).
- [ ] Persist downloaded models to `~/Library/Application Support/VoiceTranscribe/sherpa-models/`.

### 35d. Sherpa-Onnx Offline ASR for File Sources

- [ ] Create `SherpaOnnxOfflineTranscriptionService` for file transcription.
  - [ ] `transcribeFile(url:)` — read file with `AVAudioFile`, resample to 16kHz mono if needed, create `SherpaOnnxOfflineRecognizer`, call `decode()`.
  - [ ] Return `[TranscriptSegment]` with word-level timestamps when available.
- [ ] Use offline ASR for file input sources when sherpa-onnx is the selected engine (faster than simulated streaming).

### 35e. Speaker Diarization

- [ ] Create `SherpaOnnxDiarizationService` wrapping `SherpaOnnxOfflineDiarizer`.
  - [ ] Accept an audio file URL, process with `SherpaOnnxOfflineDiarizer`, return `[DiarizerSegment]` (speaker label, start time, end time).
  - [ ] Run diarization on a background actor to avoid blocking UI.
- [ ] Integrate diarization into the recording workflow: after recording stops, optionally run diarization on the saved file.
- [ ] Align diarization speaker segments with transcription word/segment timestamps.
- [ ] Display speaker-attributed transcript: prefix segments with speaker label (e.g., "Speaker 0: …", "Speaker 1: …").
- [ ] Color-code transcript segments by speaker.

### 35f. Voice Activity Detection (VAD)

- [ ] Create `SherpaOnnxVADService` wrapping `SherpaOnnxSileroVad`.
  - [ ] Feed the live audio stream through VAD before ASR — only forward speech frames.
  - [ ] Use VAD to trigger automatic utterance boundaries (replace or complement current EOU/timeout approach).
- [ ] Trace VAD events: `vad.speech.start`, `vad.speech.end` with timestamps.

### 35g. Punctuation Post-Processing

- [ ] Create `SherpaOnnxPunctuationService` wrapping `SherpaOnnxOfflinePunctuation`.
  - [ ] Apply punctuation to ASR output segments (both streaming final and offline).
  - [ ] Replace current heuristic punctuation (`addSentencePunctuation`) with model-based approach.
- [ ] Handle punctuation model download on first use.

### 35h. Models and Bundling

- [ ] Define a `SherpaOnnxModelRegistry` listing required models (ASR encoder/decoder/joiner, diarizer, VAD, punctuation).
- [ ] Add model download management: check local cache, download from HuggingFace with progress, verify checksums.
- [ ] Graceful fallback when models are unavailable (degrade to Apple Speech).

### 35i. Bump Version

- [ ] Bump `CFBundleShortVersionString` to `1.8.0`.
- [ ] Bump `CFBundleVersion` to `18`.


## 36. v1.xx.0. Speaker Diarization (Legacy FluidAudio)

### 36a. Research FluidAudio Diarizer

- [ ] FluidAudio provides `Diarizer` protocol with streaming `addAudio()/process()` → `DiarizerTimelineUpdate`.
- [ ] `SortformerDiarizer`: 4-speaker streaming diarization, ~11% DER on DI-HARD III, real-time on Apple Silicon.
- [ ] Also available: `LSEENDDiarizer`, `OfflineDiarizerManager` (pyannote-based).
- [ ] Sortformer downloads models from HuggingFace (`FluidInference/sortformer-diarizer-coreml`).
- [ ] `DiarizerTimeline` produces `DiarizerSegment` with speaker label, start/end times, confidence.

### 36b. Integrate Diarizer into Capture Pipeline

- [ ] Add `SortformerDiarizer` instance to `AppModel` or `AudioCaptureService`.
- [ ] Feed the same audio stream to both ASR and diarizer in parallel.
- [ ] Diarizer emits `DiarizerTimelineUpdate` containing speaker-labeled speech segments.
- [ ] Align `TranscriptSegment` timestamps with `DiarizerSegment` time ranges to assign speaker labels.

### 36c. Display Speaker-Attributed Transcript

- [ ] Add speaker label prefix to transcript segments (e.g., "Speaker A: ..." or "👤 A: ...").
- [ ] Color-code segments by speaker for visual differentiation.
- [ ] Support speaker enrollment: record a short clip to name a speaker ("John") instead of "Speaker A".

### 36d. Performance and UX

- [ ] Ensure diarizer doesn't block the main thread — run inference on a background actor.
- [ ] Model download on first use (like FluidAudio ASR models).
- [ ] Graceful fallback when diarizer is unavailable or fails.
- [ ] Diarizer off by default; toggle in Settings popup (v1.6.0).

## 37. v2.0.0. Fact-Check Pane

### 37a. Fact-Check UI

- [x] Add a fact-check pane directly under the live transcription pane.
- [x] Display fact-check rows in transcript sentence order.
- [x] Show each original finalized sentence next to its fact-check result.
- [x] Show row states: queued, checking, completed, failed.
- [x] Keep the fact-check pane scrollable and responsive during long sessions.
- [x] Preserve completed fact-check results while new transcript text arrives.
- [x] Add empty state text when no complete sentences have been fact-checked yet.

### 37b. Sentence Extraction and Queueing

- [x] Detect complete finalized transcript sentences from `TranscriptSegment` updates.
- [x] Queue each complete sentence exactly once for fact-checking.
- [x] Avoid sending interim transcript text to the fact-check engine.
- [x] Serialize rapid sentence submissions through one internal fact-check queue.
- [x] Track sentence IDs so updates and results remain associated with the correct transcript sentence.
- [x] Add tests for sentence extraction, duplicate suppression, and queue ordering.

### 37c. Ollama Fact-Check Service

- [x] Create `FactCheckService` protocol for sentence-level fact checking.
- [x] Create `OllamaFactCheckService` implementation using the local Ollama HTTP API.
- [x] Use model `igorls/gemma-4-12B-it-heretic-GGUF` by default.
- [x] Add configurable Ollama endpoint with default `http://localhost:11434`.
- [x] Limit concurrent Ollama requests to protect UI responsiveness.
- [x] Add timeout handling for slow or unavailable local model responses.
- [x] Surface clear error states when Ollama is not running or the model is unavailable.
- [x] Trace fact-check lifecycle events: queued, request started, response received, parse failed, request failed.

### 37d. Fact-Check Prompt and Parsing

- [x] Define a prompt that asks the model to fact-check one transcribed sentence.
- [x] Instruct the model to treat the sentence as a potentially imperfect transcript.
- [x] Instruct the model to evaluate only factual claims present in the sentence.
- [x] Instruct the model to classify subjective, command, filler, or non-factual text as `not_factual`.
- [x] Require structured JSON output with `sentence`, `verdict`, `confidence`, `explanation`, and optional `notes`.
- [x] Parse model responses into a `FactCheckResult` model.
- [x] Gracefully handle malformed JSON by showing a failed parse state and raw response excerpt.
- [x] Add tests for prompt construction and response parsing.

### 37e. App Integration

- [x] Add fact-check coordinator owned by `AppModel`.
- [x] Subscribe the fact-check coordinator to finalized transcript sentences.
- [x] Forward nested fact-check coordinator state changes through `AppModel.objectWillChange`.
- [x] Ensure fact checking never blocks audio capture, recording, or transcription.
- [x] Reset fact-check state when a new transcription session starts.
- [ ] Save fact-check results alongside transcript metadata if enabled.

### 37f. Settings

- [x] Add setting for enabling/disabling fact checking.
- [x] Add setting for Ollama endpoint URL.
- [x] Add setting for Ollama model name, defaulting to `igorls/gemma-4-12B-it-heretic-GGUF`.
- [x] Add a "Test Ollama" action to verify connectivity and model availability.
- [x] Persist fact-check settings with `@AppStorage`.

### 37g. Version

- [x] Bump `CFBundleShortVersionString` to `2.0.0`.
- [x] Bump `CFBundleVersion` to `18`.

## 38. v2.0.1. Fact-Check Result Display Fix

### 38a. Ollama Response Handling

- [x] Accept strict JSON fact-check responses.
- [x] Accept JSON wrapped in Markdown code fences.
- [x] Extract embedded JSON when Ollama returns surrounding prose.
- [x] Fall back to displaying plain text Ollama responses instead of failing with a format error.
- [x] Trace when raw Ollama text is used as the displayed result.

### 38b. Fact-Check UI

- [x] Display the fact-check result body directly rather than presenting only the verdict badge.
- [x] Keep structured verdict and confidence information inside the result text when available.
- [x] Show raw local model output as the result when the model does not return structured JSON.

### 38c. Tests and Version

- [x] Add tests for fenced JSON and plain text Ollama responses.
- [x] Bump `CFBundleShortVersionString` to `2.0.1`.
- [x] Bump `CFBundleVersion` to `19`.

## 39. v2.0.2. Editable Ollama Prompt

### 39a. Prompt Settings

- [x] Add a persisted fact-check prompt template setting.
- [x] Reveal the prompt template in the Settings popup.
- [x] Reveal the prompt template in the full Settings view.
- [x] Add a reset action that restores the default prompt.
- [x] Keep the default prompt available for first launch and reset behavior.

### 39b. Prompt Rendering

- [x] Pass the current prompt template into every Ollama fact-check request.
- [x] Replace `{{sentence}}` with the finalized transcript sentence when present.
- [x] Append the finalized transcript sentence automatically when the prompt has no placeholder.
- [x] Preserve the prompt template captured when each sentence is queued.

### 39c. Tests and Version

- [x] Add tests for prompt placeholder replacement.
- [x] Add tests for automatic sentence appending when the placeholder is missing.
- [x] Bump `CFBundleShortVersionString` to `2.0.2`.
- [x] Bump `CFBundleVersion` to `20`.

## 40. v2.0.3. Combined Transcript and Fact-Check Grid

### 40a. Unified Transcript Pane

- [x] Replace separate transcript and fact-check panes with one combined transcript grid.
- [x] Show finalized transcript entries as two-line grid groups.
- [x] Render line 1 as timestamp, audio source, and transcript text.
- [x] Render line 2 with blank timestamp/source columns and fact-check output in the text column.
- [x] Keep interim transcript text in the same grid with a pending fact-check state.

### 40b. Source and Fact-Check Association

- [x] Track the active transcript source name for live microphone sessions.
- [x] Track the active transcript source name for file transcription sessions.
- [x] Match fact-check results back to transcript rows by normalized sentence text.
- [x] Support transcript segments containing multiple complete sentences.
- [x] Preserve existing queued, checking, result, disabled, and failed fact-check states in the combined row.

### 40c. Tests and Version

- [x] Verify the app builds with the combined SwiftUI grid.
- [x] Verify the existing fact-check and transcription tests still pass.
- [x] Bump `CFBundleShortVersionString` to `2.0.3`.
- [x] Bump `CFBundleVersion` to `21`.

## 41. v2.0.4. Transcription Engine Regression Fix

### 41a. Engine Default

- [x] Change the default transcription engine from Apple Speech to FluidAudio.
- [x] Use FluidAudio as the fallback when no transcription engine preference exists.
- [x] Add a one-time migration from the old Apple Speech default to FluidAudio for existing installs.
- [x] Keep Apple Speech selectable manually in Settings after migration.

### 41b. Diagnostics

- [x] Add trace events when audio buffers reach the transcription coordinator.
- [x] Include engine, sample rate, channel count, and buffer duration in transcription buffer traces.
- [x] Add a regression test for the FluidAudio default engine.

### 41c. Version

- [x] Bump `CFBundleShortVersionString` to `2.0.4`.
- [x] Bump `CFBundleVersion` to `22`.

## 42. v2.0.5. Running Recording Summary

### 42a. Summary State

- [x] Add a summary coordinator owned by `AppModel`.
- [x] Accrue finalized transcript sentences into summary state.
- [x] Suppress duplicate finalized sentences before summarizing.
- [x] Organize accrued sentences into readable paragraphs.
- [x] Reset summary state when a new microphone transcription session starts.
- [x] Reset summary state when a new file transcription session starts.

### 42b. Summary UI

- [x] Add a Recording Summary section under the transcript/fact-check grid.
- [x] Show a clear empty state before finalized transcript sentences exist.
- [x] Show the number of accrued sentences.
- [x] Render summary paragraphs in a scrollable section.
- [x] Stop forcing transcript scroll position when new text is appended.

### 42c. Settings

- [x] Add a persisted summary prompt/instruction setting.
- [x] Add a summary prompt editor to the Settings popup.
- [x] Add a summary prompt editor to the full Settings view.
- [x] Add a reset action for the default summary prompt.

### 42d. Tests and Version

- [x] Add tests for summary paragraph grouping.
- [x] Add tests for default summary prompt content.
- [x] Bump `CFBundleShortVersionString` to `2.0.5`.
- [x] Bump `CFBundleVersion` to `23`.

## 43. v2.0.6. First-Launch Permission Relaunch

### 43a. Startup Permission Flow

- [x] Add an app startup permission flow owned by `AppModel`.
- [x] Request the native microphone permission dialog on launch when macOS reports a not-determined state.
- [x] Request the native speech-recognition permission dialog on launch when macOS reports a not-determined state.
- [x] Continue to request native dialogs if a rebuilt/resigned app returns to not-determined permissions.
- [x] Preserve the existing device-touch permission fallback before capture starts.

### 43b. Automatic Restart

- [x] Relaunch the packaged `.app` automatically after startup permission dialogs complete.
- [x] Persist permission-flow state before restarting to avoid restart loops.
- [x] Show a manual restart message when running outside an `.app` bundle.
- [x] Trace first-launch permission and app-restart events.

### 43c. Version

- [x] Bump `CFBundleShortVersionString` to `2.0.6`.
- [x] Bump `CFBundleVersion` to `24`.

## 44. v2.0.7. Stop Fact-Checking Transcript Fragments

### 44a. Regression Cause

- [x] Confirmed via `/tmp/VoiceTranscribe.log` that FluidAudio partial text was being committed as finalized transcript text every 50 characters.
- [x] Confirmed the length-based commit path added punctuation to fragments, making them look like complete sentences.
- [x] Confirmed those artificial sentences were then queued for fact-checking.

### 44b. Fix

- [x] Remove length-based finalization from FluidAudio partial callbacks.
- [x] Keep FluidAudio partial callback output as interim transcript text only.
- [x] Preserve final transcript/fact-check flow for actual EOU callback and final drain output.
- [x] Update requirements so partial transcript fragments must not be fact-checked.

### 44c. Version

- [x] Bump `CFBundleShortVersionString` to `2.0.7`.
- [x] Bump `CFBundleVersion` to `25`.

## 45. v2.0.8. Transcript Export Actions

### 45a. Recording Transcript Save

- [x] Save the recording transcript whenever transcript text exists, even if transcription was stopped before recording.
- [x] Preserve the existing shared basename for recording audio, transcript text, and metadata files.

### 45b. Manual Transcript Export

- [x] Add `CopyText` to copy the current transcript text to the clipboard.
- [x] Add `SaveToFile` to export the current transcript text through a save panel.
- [x] Disable transcript export actions until transcript text is available.

### 45c. Version

- [x] Bump `CFBundleShortVersionString` to `2.0.8`.
- [x] Bump `CFBundleVersion` to `26`.

## 46. v2.0.9. Summary Export Actions

### 46a. Manual Summary Export

- [x] Add `CopyText` to copy the current recording summary to the clipboard.
- [x] Add `SaveToFile` to export the current recording summary through a save panel.
- [x] Disable summary export actions until summary text is available.

### 46b. Version

- [x] Bump `CFBundleShortVersionString` to `2.0.9`.
- [x] Bump `CFBundleVersion` to `27`.

## 47. v2.1.0. Multiple LLM Endpoints

### 47a. LLM Configuration

- [x] Add a persisted list of LLM endpoint configurations, each with name, endpoint URL, and model.
- [x] Migrate the previous single Ollama endpoint/model settings into the default LLM entry.
- [x] Track the selected LLM endpoint independently from the configured endpoint list.
- [x] Sanitize empty endpoint lists and blank endpoint fields back to usable defaults.

### 47b. Fact-Check Routing

- [x] Route live fact-check requests through the selected LLM endpoint.
- [x] Store endpoint and model on queued fact-check items so existing queued work keeps its original routing.
- [x] Update the connectivity test to target the selected LLM.

### 47c. Settings UI

- [x] Replace single Ollama endpoint/model fields with an editable LLM list.
- [x] Add a selected-LLM picker.
- [x] Add controls to add and remove configured LLM endpoints.

### 47d. Tests and Version

- [x] Add tests for LLM endpoint defaults and sanitization.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.1.0`.
- [x] Bump `CFBundleVersion` to `28`.

## 48. v2.1.1. Two-Column Settings Sheet

### 48a. Settings Layout

- [x] Split the Settings sheet into left and right columns.
- [x] Keep transcription, permissions, and summary settings on the left.
- [x] Move LLM fact-checking configuration to the right column.
- [x] Add independent scrolling for each column so the dialog fits shorter screens.

### 48b. Version

- [x] Bump `CFBundleShortVersionString` to `2.1.1`.
- [x] Bump `CFBundleVersion` to `29`.

## 49. v2.2.0. LLM Provider API Types

### 49a. Provider Configuration

- [x] Add an API type to each configured LLM endpoint.
- [x] Support Ollama, OpenAI-compatible chat completions, Anthropic Messages, and Gemini generateContent endpoints.
- [x] Add an optional API key field to each LLM endpoint configuration.
- [x] Infer OpenAI-compatible routing for legacy remote LLM endpoints and Ollama routing for legacy local endpoints.

### 49b. Provider Routing

- [x] Route fact-check requests through provider-specific URL paths, headers, request bodies, and response parsers.
- [x] Preserve existing Ollama `/api/generate` behavior.
- [x] Use bearer auth for OpenAI-compatible endpoints.
- [x] Use `x-api-key` plus `anthropic-version` for Anthropic endpoints.
- [x] Use Gemini `models/{model}:generateContent` requests with API-key query support.

### 49c. Tests and Version

- [x] Add tests for legacy local and remote provider inference.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.2.0`.
- [x] Bump `CFBundleVersion` to `30`.

## 50. v2.2.1. Plain LLM Prompt Test

### 50a. LLM Diagnostics

- [x] Add a selected-LLM prompt test using `Hello, what is 10 * 20?`.
- [x] Reuse provider-specific LLM routing without fact-check JSON parsing.
- [x] Display the raw selected-LLM response in the app message.
- [x] Keep the existing fact-check test as a separate diagnostic action.

### 50b. Version

- [x] Bump `CFBundleShortVersionString` to `2.2.1`.
- [x] Bump `CFBundleVersion` to `31`.

## 51. v2.2.2. LLM Test Diagnostics

### 51a. Settings Test UX

- [x] Move LLM test buttons to the top of the LLM settings panel.
- [x] Present LLM test results from the Settings sheet so results appear before closing the modal.

### 51b. Request Diagnostics

- [x] Keep JSON response formatting for fact-check requests.
- [x] Do not force JSON response formatting for the plain arithmetic prompt test.
- [x] Include LLM HTTP response bodies in surfaced HTTP errors.

### 51c. Version

- [x] Bump `CFBundleShortVersionString` to `2.2.2`.
- [x] Bump `CFBundleVersion` to `32`.

## 52. v2.2.3. OpenRouter Endpoint Repair

### 52a. OpenRouter Configuration

- [x] Add OpenRouter as a first-class LLM API type with default endpoint `https://openrouter.ai/api`.
- [x] Detect legacy OpenRouter endpoints when loading saved LLM configurations.
- [x] Repair mismatched profiles that saved an OpenRouter model against an OpenCode endpoint.

### 52b. Request Routing

- [x] Route OpenRouter through OpenAI-compatible chat completions.
- [x] Accept OpenAI-compatible base URLs that already include `/v1` or `/v1/chat/completions`.
- [x] Preserve `openrouter/free` as the model ID without rewriting the slash.

### 52c. Tests and Version

- [x] Add tests for OpenRouter provider inference and endpoint repair.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.2.3`.
- [x] Bump `CFBundleVersion` to `33`.

## 53. v2.2.4. AI Toggle

### 53a. Global AI Control

- [x] Add a persisted `aiEnabled` setting.
- [x] Add a top-bar AI toggle for quick access.
- [x] Add AI enable toggles to the Settings fact-checking sections.

### 53b. Fact-Check Gating

- [x] Gate live LLM fact-checking behind both the global AI toggle and the fact-check toggle.
- [x] Disable fact-check test buttons when AI is off.
- [x] Return a clear message if an LLM test is invoked while AI is disabled.

### 53c. Tests and Version

- [x] Add tests for effective AI/fact-check state.
- [x] Add tests for disabled fact-check queue behavior.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.2.4`.
- [x] Bump `CFBundleVersion` to `34`.

## 54. v2.2.5. AI Toggle Visibility

### 54a. Main Window

- [x] Move the global AI toggle next to the Settings button so it is not hidden at the far right edge of the split view.
- [x] Add the same labelled AI switch to the live transcript/fact-check header.
- [x] Keep both switches bound to the same persisted `aiEnabled` setting.

### 54b. Version

- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.2.5`.
- [x] Bump `CFBundleVersion` to `35`.

## 55. v2.2.6. Split Menu Settings Window

### 55a. macOS Settings View

- [x] Split the macOS app Settings/options window into two scrollable columns.
- [x] Move output, transcription, summary, and visualization controls to the left column.
- [x] Move AI, LLM endpoint, test, and fact-check prompt controls to the right column.
- [x] Widen the app Settings scene so it does not render as the old single long page.

### 55b. Version

- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.2.6`.
- [x] Bump `CFBundleVersion` to `36`.

## 56. v2.2.7. Restart and Menu Settings Repair

### 56a. Relaunch Flow

- [x] Fix automatic restart after permission prompts so it launches a fresh app instance.
- [x] Avoid activating the current app instance and then terminating it.
- [x] Trace successful fresh-instance launch attempts.

### 56b. Version

- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.2.7`.
- [x] Bump `CFBundleVersion` to `37`.

## 57. v2.2.8. Markdown Transcript Export

### 57a. Requirements

- [x] Add Markdown export for the current transcript session.
- [x] Include a `# DETAILS` section with recording time, location, source, duration, transcription engine, and export timestamp.
- [x] Include a `# RECORDING` section with a Markdown table: `date time | length | text`.
- [x] Include the current summary when summary text is available.
- [x] Include fact-check results when fact-check items are available.
- [x] Include related audio, transcript, and metadata file paths when a recording session exists.
- [x] Use `Not specified` for location until the app collects recording location explicitly.
- [x] Escape Markdown table delimiters and line breaks in exported transcript and fact-check text.

### 57b. Implementation

- [x] Add `MarkdownExportService` and `MarkdownExportContext`.
- [x] Compute transcript row length from the next segment timestamp or session end time.
- [x] Add `AppModel.saveTranscriptMarkdownToFile()`.
- [x] Add an Export Markdown button to the combined transcript/fact-check pane.
- [x] Add unit coverage for Markdown export details, recording table, summary, fact checks, file paths, and table escaping.

### 57c. Version

- [x] Bump `CFBundleShortVersionString` to `2.2.8`.
- [x] Bump `CFBundleVersion` to `38`.

## 58. v2.2.9. Sidebar Version Footer

### 58a. Left Pane UI

- [x] Show the current application version at the bottom of the left source pane.
- [x] Read version and build from the app bundle instead of hardcoding display text.
- [x] Keep the source list scrollable while the version footer remains pinned.
- [x] Add unit coverage for version display formatting.

### 58b. Version

- [x] Bump `CFBundleShortVersionString` to `2.2.9`.
- [x] Bump `CFBundleVersion` to `39`.

## 59. v2.3.0. AI Results in Markdown Export

### 59a. Export Content

- [x] Add a dedicated `# AI RESULTS` section to Markdown exports.
- [x] Include AI enabled and fact-check enabled state.
- [x] Include selected LLM display name, provider, endpoint, and model.
- [x] Include generated summary output.
- [x] Include generated fact-check output.
- [x] Include the fact-check prompt used at export time.
- [x] Include the summary prompt used at export time.
- [x] Exclude API keys from exported Markdown.

### 59b. Tests and Version

- [x] Update Markdown export tests for AI result metadata and prompts.
- [x] Bump `CFBundleShortVersionString` to `2.3.0`.
- [x] Bump `CFBundleVersion` to `40`.

## 60. v2.3.1. Single-Table AI Export

### 60a. Markdown Format

- [x] Move sentence-level fact-check output into the main `# RECORDING` table.
- [x] Add an `AI result` column beside each transcript row.
- [x] Remove the separate `# FACT CHECKS` table from Markdown export.
- [x] Remove the duplicate fact-check results list from `# AI RESULTS`.
- [x] Keep AI endpoint metadata, selected model, and prompts in `# AI RESULTS`.
- [x] Update requirements to require one recording table for transcript and AI result output.

### 60b. Tests and Version

- [x] Update Markdown export tests for the single-table format.
- [x] Bump `CFBundleShortVersionString` to `2.3.1`.
- [x] Bump `CFBundleVersion` to `41`.

## 61. v2.3.2. LLM Compatibility and Tabbed Panels

### 61a. LLM Compatibility

- [x] Normalize literal escaped slashes in saved LLM endpoint and model values.
- [x] Simplify OpenAI-compatible request bodies to `model` plus `messages`.
- [x] Stop sending protocol-level `response_format` and `temperature` parameters to OpenAI-compatible providers.
- [x] Verify configured OpenRouter, LiteLLM, DeepSeek, and OpenAI endpoints respond successfully with the simplified request shape.

### 61b. Main Window Layout

- [x] Shrink the voice chart height.
- [x] Move Live Transcript into a tab.
- [x] Move Recording Summary into a tab.
- [x] Move Recent Recordings into a tab with an empty state.

### 61c. Tests and Version

- [x] Add coverage for escaped-slash LLM configuration normalization.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.3.2`.
- [x] Bump `CFBundleVersion` to `42`.

## 62. v2.4.0. Multi-Prompt AI Processing

### 62a. Prompt Templates

- [x] Add multiple named AI prompt templates.
- [x] Store prompt templates with their enabled state and selected LLM endpoint.
- [x] Migrate the existing fact-check prompt into the new prompt-template list.
- [x] Add prompt-template creation, deletion, editing, reset, and model assignment controls.

### 62b. Main Window Layout

- [x] Replace the global AI on/off switch with per-prompt toggles.
- [x] Move prompt toggles into the left pane with Microphones and File Sources.
- [x] Split Settings into general settings, LLM model configuration, and prompt-template columns.
- [x] Rename visible fact-check labels to AI Processing.
- [x] Add a persisted transcript auto-scroll toggle.

### 62c. Processing Queue

- [x] Fan out each finalized complete sentence to every enabled prompt template.
- [x] Route each prompt through its selected LLM endpoint.
- [x] Deduplicate queued work by prompt template and normalized sentence.
- [x] Process queued AI calls with up to three concurrent workers.

### 62d. Tests and Version

- [x] Add coverage for prompt-template enablement, multi-prompt fan-out, and three-call concurrency.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.0`.
- [x] Bump `CFBundleVersion` to `43`.

## 63. v2.4.1. Tabbed Settings Options

### 63a. Settings Layout

- [x] Replace the three-column Settings sheet with General, LLM Models, and Prompt Templates tabs.
- [x] Apply the same tabbed options layout to the standalone Settings window.
- [x] Keep each tab vertically scrollable so long model and prompt lists fit smaller screens.

### 63b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.1`.
- [x] Bump `CFBundleVersion` to `44`.

## 64. v2.4.2. Prompt Template Refresh Fix

### 64a. Prompt Template UI

- [x] Forward `AppSettings.objectWillChange` through `AppModel` so settings-backed lists refresh.
- [x] Route prompt-template add, remove, reset, and edit actions through `AppModel`.
- [x] Explicitly publish prompt-template mutations before writing computed `@AppStorage` JSON state.
- [x] Trace prompt-template add, remove, and reset actions.

### 64b. Tests and Version

- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.2`.
- [x] Bump `CFBundleVersion` to `45`.

## 65. v2.4.3. Global Prompt Model Override

### 65a. Model and Prompt Refresh

- [x] Route LLM endpoint add, edit, remove, and selected-model changes through `AppModel`.
- [x] Explicitly publish LLM endpoint mutations before writing computed `@AppStorage` JSON state.
- [x] Enable newly added prompt templates by default.

### 65b. Global Prompt Model

- [x] Add a persisted toggle for using one model across all prompts.
- [x] Add a global prompt-model picker in the LLM Models tab.
- [x] Disable per-prompt model pickers while the global prompt model is active.
- [x] Route live AI processing and Markdown export metadata through the effective prompt model.
- [x] Show global model status in the prompt sidebar and prompt editor.

### 65c. Tests and Version

- [x] Add coverage for global model override routing.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.3`.
- [x] Bump `CFBundleVersion` to `46`.

## 66. v2.4.4. Conversation Prompt Placeholders

### 66a. Prompt Context

- [x] Add a timestamped AI prompt context built from finalized transcript segments.
- [x] Split finalized transcript segments into timestamped sentence entries for prompt context.
- [x] Pass conversation context into every queued AI processing request.

### 66b. Template Substitutions

- [x] Keep `{{sentence}}` substitution support.
- [x] Add `{{conversation}}` substitution for the full timestamped transcript context.
- [x] Add `{{last-3}}`, `{{last-5}}`, and `{{last-10}}` substitutions for recent timestamped transcript entries.
- [x] Accept the malformed `{{last-3}` variant as a forgiving alias.
- [x] Add prompt editor tooltip documentation for supported placeholders.

### 66c. Tests and Version

- [x] Add coverage for conversation, last-N, malformed last-3, and segment splitting substitutions.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.4`.
- [x] Bump `CFBundleVersion` to `47`.

## 67. v2.4.5. Batched Prompt Questions

### 67a. Global Model Batching

- [x] Add a batch AI processing request path for multiple prompt questions targeting the same model.
- [x] Enable prompt batching when the global prompt model option is active.
- [x] Keep one visible AI result row per prompt while sending a single combined LLM request.
- [x] Parse combined JSON batch responses back into individual prompt results.
- [x] Fall back to per-item failures when a batch response omits a prompt result.

### 67b. Queue Behavior

- [x] Reserve queued batch groups before awaiting the LLM so workers do not split one batch into separate calls.
- [x] Batch only when every queued prompt question is routed to the same LLM endpoint.
- [x] Preserve the existing three-worker queue limit for separate sentences and non-batched prompt work.

### 67c. Tests and Version

- [x] Add coverage proving three prompt questions are sent as one batch call.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.5`.
- [x] Bump `CFBundleVersion` to `48`.

## 68. v2.4.6. Prompt State Substitution

### 68a. Prompt State

- [x] Add `{{prompt-state}}` substitution support.
- [x] Maintain accumulated state independently for each prompt template.
- [x] Update prompt state from each successful prompt response.
- [x] Clear prompt state when AI processing state is reset for a new session.

### 68b. Queue Ordering

- [x] Inject current prompt state immediately before sending each AI request.
- [x] Serialize concurrent calls for prompt templates that use `{{prompt-state}}`.
- [x] Preserve batching and three-worker concurrency for prompts that do not use prompt state.

### 68c. Tests and Version

- [x] Add coverage for `{{prompt-state}}` rendering.
- [x] Add coverage for state accrual between successive prompt calls.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.6`.
- [x] Bump `CFBundleVersion` to `49`.

## 69. v2.4.7. Prompt State Markdown Export

### 69a. Export Content

- [x] Include non-empty accumulated prompt states in Markdown transcript exports.
- [x] Preserve prompt-template display names with each exported prompt state.
- [x] Omit empty prompt states from the export.

### 69b. Tests and Version

- [x] Add Markdown export coverage for prompt states.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.7`.
- [x] Bump `CFBundleVersion` to `50`.

## 70. v2.4.8. Live Speaker Diarization

### 70a. FluidAudio Pipeline

- [x] Add a live FluidAudio LS-EEND diarization coordinator.
- [x] Feed copied live microphone buffers to diarization in parallel with transcription.
- [x] Feed copied file-transcription buffers to diarization in parallel with transcription.
- [x] Finalize and merge diarization timeline updates when transcription stops.
- [x] Continue transcription without speaker labels when diarization startup fails.

### 70b. Transcript Annotation and Export

- [x] Add speaker fields to transcript segments and speaker timeline models.
- [x] Annotate live transcript rows with speaker labels when available.
- [x] Include speaker labels in copied and saved transcript text.
- [x] Add a speaker column and speaker timeline to Markdown exports.

### 70c. Docs, Tests, and Version

- [x] Update README, requirements, architecture notes, and agent handoff notes for diarization.
- [x] Add coverage for speaker labels in text and Markdown exports.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.8`.
- [x] Bump `CFBundleVersion` to `51`.

## 71. v2.4.9. Root App Launcher

### 71a. Launch Script

- [x] Add root `run.sh` to package and launch `dist/VoiceTranscribe.app`.
- [x] Support `./run.sh --no-build` for relaunching an existing packaged app.
- [x] Update README and agent launch instructions to use the packaged app launcher.

### 71b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.9`.
- [x] Bump `CFBundleVersion` to `52`.

## 72. v2.4.10. Speaker Placement in Live Transcript

### 72a. Live Transcript UI

- [x] Move speaker labels from a separate Live Transcript column to a line under Audio Source.
- [x] Keep unknown speaker state visible under the source name.
- [x] Update layout documentation for the source-plus-speaker row design.

### 72b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.10`.
- [x] Bump `CFBundleVersion` to `53`.

## 73. v2.4.11. Visible Current Speaker Status

### 73a. Live Transcript UI

- [x] Add a prominent current-speaker indicator to the Live Transcript toolbar.
- [x] Show diarization detecting, unavailable, and inactive states.
- [x] Use the current diarized speaker as the interim-row speaker fallback.
- [x] Document that diarization labels are anonymous speakers such as `Speaker 1`.

### 73b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.11`.
- [x] Bump `CFBundleVersion` to `54`.

## 74. v2.4.12. Prompt Template Space Editing Fix

### 74a. Prompt Template Editing

- [x] Preserve prompt template text exactly while editing instead of trimming on every keystroke.
- [x] Preserve prompt template names while editing, while still falling back when the trimmed name is empty.
- [x] Keep fallback default prompt behavior for truly empty templates.

### 74b. Tests and Version

- [x] Add regression coverage proving prompt template names and text preserve trailing spaces during sanitization.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.12`.
- [x] Bump `CFBundleVersion` to `55`.

## 75. v2.4.13. Always-Visible Speaker Status

### 75a. Live Transcript UI

- [x] Move current-speaker status out of the crowded toolbar.
- [x] Add a full-width Live Transcript speaker-detection strip that is visible before and during transcription.
- [x] Show inactive, detecting, unavailable, and current-speaker states in that strip.

### 75b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.13`.
- [x] Bump `CFBundleVersion` to `56`.

## 76. v2.4.14. Speaker-Only Transcript Column

### 76a. Live Transcript UI

- [x] Replace the Live Transcript `Audio Source` column with a `Speaker` column.
- [x] Display only the speaker label or `Detecting` in transcript rows.
- [x] Keep the full-width current-speaker status strip above the transcript grid.

### 76b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.14`.
- [x] Bump `CFBundleVersion` to `57`.

## 77. v2.4.15. Clean Package Build Path

### 77a. Packaging

- [x] Resolve the SwiftPM build product directory with `swift build --show-bin-path`.
- [x] Avoid packaging stale or missing executables when Swift places clean-build products outside the old architecture-specific path.
- [x] Rebuild and relaunch the packaged app after verifying the executable no longer contains the old Live Transcript `Audio Source` label.

### 77b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.15`.
- [x] Bump `CFBundleVersion` to `58`.

## 78. v2.4.16. Always-Clean Package Builds

### 78a. Packaging

- [x] Run `swift package clean` before every packaged app build.
- [x] Ensure `./run.sh` uses a clean build whenever it rebuilds through `scripts/package-app.sh`.

### 78b. Version

- [x] Bump `CFBundleShortVersionString` to `2.4.16`.
- [x] Bump `CFBundleVersion` to `59`.

## 79. v2.4.17. Stalled FluidAudio Partial Finalization

### 79a. Transcription Finalization

- [x] Add a FluidAudio-only fallback that finalizes a stable interim transcript segment after a short stall.
- [x] Capitalize and punctuate fallback-finalized interim text so AI processing receives complete sentences.
- [x] Suppress duplicate final segments if FluidAudio later emits the same utterance through its EOU callback.
- [x] Keep Apple Speech transcription behavior unchanged.

### 79b. Tests and Version

- [x] Add regression coverage for a stalled FluidAudio partial becoming a finalized transcript segment.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.17`.
- [x] Bump `CFBundleVersion` to `60`.

## 80. v2.4.18. FluidAudio Stale Partial Suppression

### 80a. Transcription Finalization

- [x] Remove stalled-interim fallback finalization because FluidAudio partials are cumulative and can cross speaker boundaries.
- [x] Suppress stale partial transcript updates that repeat the latest finalized utterance.
- [x] Suppress exact duplicate final transcript segments.
- [x] Keep finalized transcript text driven by FluidAudio EOU callbacks.

### 80b. Tests and Version

- [x] Replace the stalled-finalization regression test with stale-partial suppression coverage.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.18`.
- [x] Bump `CFBundleVersion` to `61`.

## 81. v2.4.19. Apple Speech Transcript Pipeline

### 81a. Transcription and Diarization

- [x] Make Apple Speech the fixed live transcript engine so transcript rows use Apple's finalized segment boundaries.
- [x] Keep FluidAudio in the live pipeline for speaker diarization only.
- [x] Replace transcription engine pickers with a read-only pipeline summary in Settings.
- [x] Migrate saved transcription-engine preferences back to Apple Speech.

### 81b. Tests and Version

- [x] Update default transcription engine regression coverage.
- [x] Verify the test suite passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.19`.
- [x] Bump `CFBundleVersion` to `62`.

## 82. v2.4.20. SpeechVAD Sortformer Diarization

### 82a. Diarization

- [x] Add the local `speech-swift` checkout as a SwiftPM dependency for `SpeechVAD` and `AudioCommon`.
- [x] Replace the live FluidAudio diarization engine with SpeechVAD Sortformer streaming diarization.
- [x] Keep Apple Speech as the transcript segmentation engine while preserving the existing speaker annotation/export surface.
- [x] Update build scripts to resolve and patch the MLX checkout before clean builds so generated Metal sources do not break the Xcode Metal wrapper.
- [x] Add a root `build.sh` clean-build helper.

### 82b. Tests and Version

- [x] Verify `./build.sh` succeeds.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.20`.
- [x] Bump `CFBundleVersion` to `63`.

## 83. v2.4.21. Nonblocking Diarization Startup

### 83a. Latency

- [x] Start Apple Speech transcription before SpeechVAD Sortformer diarization startup.
- [x] Launch diarization model loading in a background task so first transcript text is not blocked by model download/load/CoreML warmup.
- [x] Cancel pending diarization startup when live or file transcription stops.
- [x] Feed transcription before diarization for live and file audio buffers.
- [x] Dispatch capture consumers in a stable priority order: transcribe, record, diarize, then any remaining consumers.

### 83b. Tests and Version

- [x] Verify `./build.sh` succeeds.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.21`.
- [x] Bump `CFBundleVersion` to `64`.

## 84. v2.4.22. App Cleanup and AI Status

### 84a. UI Cleanup

- [x] Increase the default main window size so the source list, input level chart, and content tabs fit with less crowding.
- [x] Route the main-window Settings gear through the same Settings window used by the app menu.
- [x] Add permission controls to the shared Settings General tab so both Settings entry points expose the same recovery path.
- [x] Color speaker labels consistently per speaker in the current-speaker strip and Live Transcript speaker column.

### 84b. AI Status

- [x] Run an active AI route health test at launch when AI prompts are enabled.
- [x] Add a visible AI status indicator showing disabled, untested, testing, ready, or failed state.
- [x] Show the active AI option currently in use, including global-model and mixed-model configurations.
- [x] Add a manual Test Active AI action in the LLM Models settings tab.

### 84c. Tests and Version

- [x] Verify `./build.sh` succeeds.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.22`.
- [x] Bump `CFBundleVersion` to `65`.

## 85. v2.4.23. Build Packages App Bundle

### 85a. Build Scripts

- [x] Make `./build.sh` run the required clean SwiftPM build and refresh `dist/VoiceTranscribe.app`.
- [x] Add a no-rebuild packaging path so `build.sh` does not compile the project twice.
- [x] Keep `./scripts/package-app.sh` available for explicitly rebuilding or refreshing the app bundle.
- [x] Update `ARCHITECTURE.md` and `AGENT.md` build guidance to state that `./build.sh` always refreshes the packaged app.

### 85b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Bump `CFBundleShortVersionString` to `2.4.23`.
- [x] Bump `CFBundleVersion` to `66`.

## 86. v2.4.24. Permission Restart Experiment

### 86a. Permission Flow

- [x] Comment out the automatic app relaunch after first-launch microphone or speech permission prompts.
- [x] Keep `restartAfterPermissionDialog()` intact so the relaunch can be restored quickly if macOS still requires it.
- [x] Add a trace event when the restart is intentionally skipped for this experiment.

### 86b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.24`.
- [x] Bump `CFBundleVersion` to `67`.

## 87. v2.4.25. AI Enable Health Test

### 87a. AI Status

- [x] Run the active AI reachability test when AI processing changes from disabled to enabled.
- [x] Apply the transition test for all prompt activation paths, including the sidebar toggle, global prompt toggle, prompt settings edits, and adding a prompt.
- [x] Cancel any in-flight AI health test when AI processing becomes disabled.

### 87b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.25`.
- [x] Bump `CFBundleVersion` to `68`.

## 88. v2.4.26. Multichannel Speech Input Normalization

### 88a. Apple Speech Input

- [x] Downmix multichannel capture buffers to mono before feeding Apple Speech's `SpeechAnalyzer`.
- [x] Preserve sample-rate conversion from the normalized mono stream into the analyzer's preferred format.
- [x] Add trace events for the analyzer format, converter setup, and conversion failures to make BlackHole or aggregate-device routing issues visible.

### 88b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.26`.
- [x] Bump `CFBundleVersion` to `69`.

## 89. v2.4.27. Editable Speaker Names

### 89a. Speaker Controls

- [x] Add a Live Transcript speaker editor that lists detected generated speaker IDs.
- [x] Allow each detected speaker to be renamed with a custom display name.
- [x] Add per-speaker reset controls and a reset-all action to restore generated `Speaker N` labels.
- [x] Keep speaker colors stable by generated speaker ID even after display names change.

### 89b. Transcript and Export Propagation

- [x] Apply renamed speaker labels to existing finalized transcript rows, interim text, current-speaker status, and diarization timeline rows.
- [x] Include renamed speaker labels in plain transcript text and Markdown export tables.
- [x] Preserve generated speaker IDs internally so reset returns to `Speaker N`.

### 89c. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.27`.
- [x] Bump `CFBundleVersion` to `70`.

## 90. v2.4.28. Transcript Speaker Cycling

### 90a. Live Transcript Corrections

- [x] Make each transcript row's speaker label clickable when detected speakers are available.
- [x] Cycle the clicked row through the current generated speaker IDs using the stable speaker sort order.
- [x] Preserve custom speaker names when a row is reassigned to a renamed speaker.
- [x] Store the correction on the individual transcript segment so Copy Text, Save to File, and Markdown export use the corrected label.
- [x] Collapse the speaker rename/reset controls behind a Speaker Configuration disclosure panel.
- [x] Suppress the first-launch permission success alert when permissions are granted or updated.

### 90b. Tests and Version

- [x] Add coverage for individual segment speaker reassignment in transcript documents and the transcription coordinator.
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.28`.
- [x] Bump `CFBundleVersion` to `71`.

## 91. v2.4.29. Capture Source Switching Crash Fix

### 91a. BlackHole and Microphone Switching

- [x] Review the `VoiceTranscribe-2026-09-17-171854.ips` crash report and identify a main-thread SwiftUI/AppKit hit-testing crash during source toggling.
- [x] Prevent new source actions while recording/transcription/capture switching is already starting.
- [x] Allow active source controls to stop while blocking inactive source starts during transitions.
- [x] Stop active recording/transcription modes cleanly before switching the shared `AudioCaptureService` to a different input device.
- [x] Ignore queued audio tap buffers from stale capture generations after a source is stopped or switched.
- [x] Replace the audio tap's `MainActor.assumeIsolated` handoff with an explicit `Task { @MainActor }` handoff.

### 91b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.29`.
- [x] Bump `CFBundleVersion` to `72`.

## 92. v2.4.30. Session Voice Identity

### 92a. WeSpeaker Identity Layer

- [x] Add an always-on, session-only `VoiceIdentityService` using SpeechVAD WeSpeaker CoreML embeddings.
- [x] Buffer 16 kHz mono session audio alongside Sortformer diarization without blocking Apple Speech transcript output.
- [x] Extract embeddings for sufficiently long finalized diarization ranges and assign in-memory `Voice N` identities.
- [x] Keep Sortformer `Speaker N` slots as source diarization labels while adding `voiceID`, `voiceName`, and `voiceConfidence` fields to transcript and timeline segments.
- [x] Prefer manual speaker names, then automatic voice labels, then raw speaker slots in transcript/export display.
- [x] Clear automatic voice identity from an individual transcript row when the user manually cycles that row's speaker.
- [x] Add tests for session voice matching and transcript display precedence.

### 92b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.30`.
- [x] Bump `CFBundleVersion` to `73`.

## 93. v2.4.31. Stop Transcription Crash Fix

### 93a. Diarization Shutdown Race

- [x] Review `VoiceTranscribe-2026-09-17-202500.ips` and identify a `SortformerStreamingSession.push(audio:) after finish()` assertion during transcription stop.
- [x] Make `SpeechSwiftSortformerDiarizationEngine` reject late `process` calls once shutdown begins.
- [x] Clear the Sortformer session after finalization so no finished session can receive future audio.
- [x] Add a transcription session token so late Apple Speech callbacks after stop are ignored instead of appending stale transcript rows.

### 93b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.31`.
- [x] Bump `CFBundleVersion` to `74`.

## 94. v2.4.32. File Diarization Trace Coverage

### 94a. File Processing Diagnostics

- [x] Review the 120-second Star Trek sample processing trace and confirm file-mode diarization can be missed when file audio is fed before Sortformer startup completes.
- [x] Start file-mode diarization synchronously before feeding audio buffers so short samples do not race model startup.
- [x] Add file feed start/progress/completion trace events with method, sample format, buffer counts, frame counts, and progress.
- [x] Add diarization buffer consumed/ignored trace events to show whether audio reached Sortformer.
- [x] Add voice identity queued, skipped, embedding-created, and assignment match-type trace events.

### 94b. Tests and Version

- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify `swift test` passes.
- [x] Bump `CFBundleShortVersionString` to `2.4.32`.
- [x] Bump `CFBundleVersion` to `75`.

## 95. v2.4.33. Observed Voice Tuple Corrections

### 95a. Speaker/Voice Tuple UI

- [x] Treat each observed `Speaker N / Voice M` pair as an editable voice candidate, with `Speaker N / no voice` for rows that do not have a voice embedding.
- [x] Rename the collapsible speaker panel to Voice Identification and allow tuple-level naming/reset with segment counts and duration hints.
- [x] Change transcript row speaker labels into correction menus that can assign any observed tuple, cycle tuples, or force a new `Voice N` under the row's current speaker.
- [x] Preserve raw `Voice N` labels in transcript display and Markdown export when no manual human name has been assigned.
- [x] Add trace events for observed voice naming, row tuple assignment, and forced voice creation.

### 95b. Tests and Version

- [x] Add coverage for tuple-level naming and row identity reassignment.
- [x] Verify `swift test` passes.
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Bump `CFBundleShortVersionString` to `2.4.33`.
- [x] Bump `CFBundleVersion` to `76`.

## 96. v2.4.34. Voice Identification Side Pane

### 96a. Live Transcript Layout

- [x] Move Voice Identification out of the Live Transcript vertical content stack.
- [x] Add a right-hand Voices rail that expands into a fixed-width Voice Identification pane.
- [x] Keep tuple naming, reset, segment count, and duration controls available inside the right pane.
- [x] Preserve the transcript table's vertical space when the voice pane is collapsed.

### 96b. Tests and Version

- [x] Verify `swift test` passes.
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Bump `CFBundleShortVersionString` to `2.4.34`.
- [x] Bump `CFBundleVersion` to `77`.

## 97. v2.4.35. Main Sidebar Visibility

### 97a. Split View Layout

- [x] Bind the main `NavigationSplitView` column visibility to prefer all columns.
- [x] Give the left source sidebar an explicit min/ideal/max width so the right Voice Identification pane does not cause it to collapse unexpectedly.

### 97b. Tests and Version

- [x] Verify `swift test` passes.
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Bump `CFBundleShortVersionString` to `2.4.35`.
- [x] Bump `CFBundleVersion` to `78`.

## 98. v2.4.36. Transcribe Restart Debounce

### 98a. Crash Fix

- [x] Diagnose repeated `SIGSEGV` crashes (fault address `0x141300b9`, same across multiple launches) traced to AppKit hit-testing/cursor tracking walking a view during `MainActor.assumeIsolated` shortly after rapid transcribe stop→restart on the same source.
- [x] Add a cooldown in `AppModel.toggleTranscribe(for:)` so a restart waits out a minimum gap (0.3s) after the prior stop before re-engaging capture/transcription/diarization, reducing the state-churn window that appears to trigger the crash.
- [ ] Superseded: build 79 crashed again with the identical fault address. Telemetry showed the stop/start clicks were already >0.3s apart, so the cooldown never engaged; see 99a.

### 98b. Tests and Version

- [x] Verify `swift test` passes (52 tests).
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Bump `CFBundleShortVersionString` to `2.4.36`.
- [x] Bump `CFBundleVersion` to `79`.

## 99. v2.4.37. Widen Transcribe Restart Cooldown

### 99a. Crash Fix Revision

- [x] Build 79's 0.3s click-to-click cooldown did not prevent a repeat crash with the identical fault address (`0x141300b9`); the `transcribe.restart.cooldown` trace event was absent from telemetry, confirming the cooldown never engaged because the actual stop/start clicks were already spaced more than 0.3s apart.
- [x] Widen `AppModel.transcriptionRestartCooldown` from 0.3s to 2.0s, matching the observed gap between a transcribe restart and the crash in telemetry, rather than sizing the window to click-to-click latency.
- [x] Confirmed fixed against a live repro (stop→immediate restart→mouse move on BlackHole 2ch, previously reliable). The underlying crash is inside Apple's SwiftUI/AppKit hit-testing code (`NSViewResponder.platformCurrentEvent.getter` / `MainActor.assumeIsolated`); this remains a mitigation of the trigger window, not a fix of the root cause, so watch for recurrence under different timing.

### 99b. Tests and Version

- [x] Verify `swift test` passes.
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Bump `CFBundleShortVersionString` to `2.4.37`.
- [x] Bump `CFBundleVersion` to `80`.

## 100. v2.4.38. Hide Empty AI Processing Rows

### 100a. Transcript Display

- [x] Stop showing an "AI Processing … Disabled … No AI prompts are enabled." block under every transcript row when there are zero enabled AI Processing prompt templates (`settings.isFactCheckActive == false`).
- [x] In `TranscriptFactCheckPanel.transcriptRows` (`Views.swift`), wrap the per-row AI Processing `GridRow` in `if isFactCheckEnabled { ... }` so the whole row (not just its text) is omitted, instead of replacing its content with a "Disabled" state.
- [x] Leave the compact "AI Disabled" status indicator in the Live Transcript panel header as-is; it is a single indicator, not repeated clutter, and still communicates the global state.

### 100b. Tests and Version

- [x] Verify `swift test` passes (52 tests).
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`.
- [x] Verify visually: launched the app with `aiEnabled=false`, transcribed live audio, confirmed transcript rows render with no AI Processing block beneath them.
- [x] Bump `CFBundleShortVersionString` to `2.4.38`.
- [x] Bump `CFBundleVersion` to `81`.

## 101. v2.4.39. Jev (TypeSafe System One) Integration

### 101a. Jev Backend

- [x] Add `JevQueryConfiguration`/`JevPrimitiveType`/`JevChoiceCriterion` data model (`AppSettings.swift`), JSON-persisted in `UserDefaults` via `@AppStorage("jevQueriesJSON")`, matching the `AIPromptTemplateConfiguration` pattern. Starts empty (no seeded default query), unlike AI Prompts, since Jev has no zero-config provider.
- [x] Add `jevAPIKey`/`jevBaseURL`/`jevModel` `@AppStorage` fields (plaintext, matching every other LLM endpoint's key storage in this app).
- [x] Add `Sources/VoiceTranscribe/JevService.swift`: `TypeSafeJevService` (`POST {baseURL}/v1/systemone`, `Authorization: Bearer`), request/response wire structs for the Noul/Choice/Score primitive shapes, and `JevCoordinator` — a worker-pool coordinator that batches every enabled query for one finalized sentence into a single Jev API call (Jev's `questions` dict is natively multi-question, so this is more efficient than the AI Prompts system's one-call-per-template approach).
- [x] Wire `JevCoordinator` into `AppModel` alongside `FactCheckCoordinator`: enqueue on `transcription.onFinalSegment`, reset on every transcribe-restart/file-transcription-start site.

### 101b. Settings and Sidebar

- [x] Add a "Jev Configuration" settings tab: connection fields (Base URL, Model, API Key) plus a `JevQuerySettingsView` CRUD list, one card per query with a primitive-type picker and a type-conditional criteria editor (Noul: true/false descriptions; Choice: dynamic option/description rows; Score: dynamic ordered level rows).
- [x] Add a "Jev Queries" section to the left-hand sidebar, below "AI Prompts", with an enable/disable checkbox per query (only shown once at least one query exists).

### 101c. Transcript Rendering

- [x] Append a second, Jev-specific result block under each finalized transcript row (below the existing AI Processing block), reusing the existing `factCheckDetail(label:badge:color:text:)` row renderer. Only rendered when at least one Jev query is enabled.
- [x] Type-specific summary text: Noul shows P(yes) with a confident/ambiguous hint; Choice shows the selected label and confidence; Score shows the value, confidence, and the nearest rubric level's description.

### 101d. Tests and Version

- [x] Verify `swift test` passes (58 tests: 52 existing + 6 new — sanitizer, `isRunnable`, request-encoding-per-primitive-type, response-decoding-per-answer-type, and two `JevCoordinator` batching/dedup tests).
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`, no new warnings.
- [x] Bump `CFBundleShortVersionString` to `2.4.39`.
- [x] Bump `CFBundleVersion` to `82`.

### 101e. Manual Verification (partial — see gaps below)

- [x] Launched `dist/VoiceTranscribe.app`, opened Settings → Jev Configuration with a real API key from `~/projects/ai/jev/play1/.env`. Connection fields (Base URL, Model, API Key) render and persist correctly.
- [x] Added a Noul query ("Urgency") and confirmed its true/false-description editor renders and edits correctly.
- [x] Added a Choice query ("Team"), confirmed switching the primitive-type picker swaps in the Choice editor (dynamic option/description rows, "Add Option", trash-to-remove), filled in two options, confirmed the "need at least 2" hint clears once valid.
- [x] Confirmed the sidebar "Jev Queries" section is absent with zero queries and appears correctly (checkbox, name, primitive-type subtitle) once queries exist, right below "AI Prompts" — both enabled queries showed up correctly.
- [ ] **Not confirmed**: the Score query criteria editor (same code path as Choice, not independently exercised), and the actual per-row transcript result block with a real Jev API response. Live transcription in this session was blocked by audio-routing issues in the test environment (BlackHole needed routed system audio; the fallback of playing a sample video through physical speakers for mic pickup wasn't completed before the session moved on) — no finalized transcript sentence was produced, so the `jevDetail`/`factCheckDetail` rendering path for a real `.completed`/`.failed` Jev answer was never visually exercised, only code-reviewed and unit-tested (request/response shape tests in `VoiceTranscribeTests.swift`).
- Follow-up: re-run the live-transcription pass (BlackHole with routed audio, or a loaded sample file) to see an actual Jev result render under a transcript row before considering this feature fully UI-verified end-to-end.

## 102. v2.4.40. Fix Markdown Export Missing AI Prompt/Jev Results

### 102a. Root Cause

- The Jev integration (v2.4.39) covered the Settings tab, sidebar section, and transcript-row rendering, but never touched `MarkdownExportService.swift` — a separate call site (`AppModel.saveTranscriptMarkdownToFile`) not reachable by browsing the live SwiftUI view tree the other three pillars share. See `ARCHITECTURE.md` Key Design Decision 11 and the new `AGENTS.md` "Feature Surface Checklist" section for the fix to the underlying process gap.

### 102b. Code

- [x] Extracted `JevAnswer.displayText` (`JevService.swift`) out of a private `Views.swift` function, so the transcript-row UI and the Markdown export render identical result text from one source instead of two copies that could drift.
- [x] `MarkdownExportService.makeDocument` now takes `jevResults: [JevResultItem]`, adds a "Jev result" column to the `# RECORDING` table (mirroring the existing "AI result" column via a parallel `jevText`/`jevResultsForSegment` pair), and appends a new `# JEV RESULTS` section (enabled/base URL/model plus per-query details) mirroring the existing `# AI RESULTS` section.
- [x] `MarkdownExportContext` gained `jevEnabled`/`jevBaseURL`/`jevModel`/`jevQueryDetails` fields (all defaulted, so the existing test's context literal didn't need updating).
- [x] `AppModel.saveTranscriptMarkdownToFile`/`markdownExportContext()` now pass `jev.items` and populate the new context fields from `settings`.

### 102c. Documentation

- [x] `ARCHITECTURE.md`: added `JevService.swift` and `MarkdownExportService.swift` to the file table (both were missing — `JevService.swift` was itself an oversight from v2.4.39), updated Key Design Decision 9 to mention Jev results/the JEV RESULTS section, and added Key Design Decision 11 naming the four technical pillars (Settings tab, sidebar section, transcript-row rendering, Markdown export) any per-sentence-result feature must cover.
- [x] `AGENTS.md` (symlinked as `CLAUDE.md`): added a "Feature Surface Checklist" section instructing future features to name and verify all four pillars up front, specifically flagging Markdown export as the one most likely to be missed and citing this exact incident as the standing example.

### 102d. Tests and Version

- [x] Added `markdownExportIncludesJevResults` test covering the new table column and `# JEV RESULTS` section.
- [x] Verify `swift test` passes (59 tests: 58 existing + 1 new).
- [x] Verify `./build.sh` succeeds and emits `dist/VoiceTranscribe.app`, no new warnings.
- [x] Bump `CFBundleShortVersionString` to `2.4.40`.
- [x] Bump `CFBundleVersion` to `83`.
