# VoiceTranscribe Implementation Checklist

This checklist converts `VoiceTranscribe-REQUIREMENTS.md` into implementation work for a native Swift macOS application.

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

## 34. v1.8.0. Speaker Diarization

### 34a. Research FluidAudio Diarizer

- [ ] FluidAudio provides `Diarizer` protocol with streaming `addAudio()/process()` → `DiarizerTimelineUpdate`.
- [ ] `SortformerDiarizer`: 4-speaker streaming diarization, ~11% DER on DI-HARD III, real-time on Apple Silicon.
- [ ] Also available: `LSEENDDiarizer`, `OfflineDiarizerManager` (pyannote-based).
- [ ] Sortformer downloads models from HuggingFace (`FluidInference/sortformer-diarizer-coreml`).
- [ ] `DiarizerTimeline` produces `DiarizerSegment` with speaker label, start/end times, confidence.

### 34b. Integrate Diarizer into Capture Pipeline

- [ ] Add `SortformerDiarizer` instance to `AppModel` or `AudioCaptureService`.
- [ ] Feed the same audio stream to both ASR and diarizer in parallel.
- [ ] Diarizer emits `DiarizerTimelineUpdate` containing speaker-labeled speech segments.
- [ ] Align `TranscriptSegment` timestamps with `DiarizerSegment` time ranges to assign speaker labels.

### 34c. Display Speaker-Attributed Transcript

- [ ] Add speaker label prefix to transcript segments (e.g., "Speaker A: ..." or "👤 A: ...").
- [ ] Color-code segments by speaker for visual differentiation.
- [ ] Support speaker enrollment: record a short clip to name a speaker ("John") instead of "Speaker A".

### 34d. Performance and UX

- [ ] Ensure diarizer doesn't block the main thread — run inference on a background actor.
- [ ] Model download on first use (like FluidAudio ASR models).
- [ ] Graceful fallback when diarizer is unavailable or fails.
- [ ] Diarizer off by default; toggle in Settings popup (v1.6.0).
	