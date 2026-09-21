# ARCHITECTURE.md — VoiceTranscribe

Project architecture notes and build history for future agents (and future-you). Read before touching code.

## What This Is

VoiceTranscribe is a native macOS SwiftUI app for enumerating audio input devices, monitoring their levels with a live graph, recording to disk, displaying live transcripts with live SpeechVAD Sortformer speaker diarization plus session-only WeSpeaker voice identity, summarizing recordings, and running configurable AI processing prompts over finalized transcript text.

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
       ├─ DiarizationCoordinator — SpeechVAD Sortformer speaker timeline + transcript annotation
       │    └─ VoiceIdentityService — SpeechVAD WeSpeaker embeddings + session-local voice matching
       ├─ SummaryCoordinator — paragraph-form recording summaries
       ├─ AIPromptCoordinator — AI processing queue, prompt templates, batching, prompt state
       ├─ JevCoordinator — Jev (TypeSafe System One) queue, batches all enabled queries per sentence into one call
       ├─ PermissionService — lazy mic/speech auth with caching
       └─ AppSettings — @AppStorage-backed preferences
```

### Data Flow

```
Mic → AVAudioEngine tap → copyBuffer() → Task { @MainActor }
  → process() → metrics + visualization (30fps throttle)
  → fan out to registered consumers (listen/record/transcribe)
```

### Voice Processing Pipeline

VoiceTranscribe uses a split voice-processing pipeline: Apple provides speech-to-text and sentence timing, while SpeechVAD provides best-effort speaker diarization and session-local voice identity. These paths run from the same copied `AVAudioPCMBuffer` stream but are intentionally separate so diarization or voice-embedding latency/failure does not block transcript text.

1. **Audio capture and fan-out — AVFoundation/CoreAudio.** `AudioCaptureService` owns one `AVAudioEngine` input tap for the selected source, including physical microphones and virtual devices such as BlackHole. It deep-copies every tap buffer, computes RMS/peak visualization metrics, and fans buffers out to registered consumers (`record`, `transcribe`, and `diarize`). Source switches must stop active consumers first because all modes share this capture service. Live transcription can be paused without tearing anything down: pause removes the `transcribe` and `diarize` consumers from the fan-out while `record` stays registered, so audio captured while paused reaches the saved recording but never reaches Apple Speech or Sortformer.

2. **Recording — AVFoundation.** `RecordingService` writes copied buffers through `AsyncAudioFileWriter` on a utility queue. Recording is independent of transcription and diarization; it can run at the same time because it is just another capture consumer.

3. **Speech transcription — Apple Speech.** `TranscriptionCoordinator` uses `AppleSpeechTranscriptionService`, backed by Apple's `SpeechAnalyzer` and `SpeechTranscriber` APIs. Incoming buffers are normalized/resampled into the analyzer's preferred format, and Apple Speech produces partial and finalized transcript segments. This is the authoritative source for spoken text and sentence boundaries.

4. **Speaker diarization — SpeechVAD Sortformer.** `DiarizationCoordinator` uses `SpeechSwiftSortformerDiarizationEngine`, which wraps SpeechVAD's `SortformerStreamingSession`. Audio is downmixed to mono, resampled to 16 kHz, and pushed into Sortformer. Sortformer returns whole-stream speaker time ranges keyed by session-local speaker slots. The app maps those integer slots to `Speaker N`, maintains a separate speaker timeline, and annotates transcript rows with the latest finalized diarization label when Apple Speech produces a segment.

5. **Voice identity — SpeechVAD WeSpeaker + app matcher.** `VoiceIdentityService` is always enabled during a transcription session. It buffers the same 16 kHz mono audio used for diarization, extracts WeSpeaker CoreML embeddings from sufficiently long finalized diarization ranges, and matches them against an in-memory `VoiceIdentityMatcher`. Matches produce session-only `Voice N` labels and confidence scores. Nothing is persisted across app runs or sessions.

6. **Voice display corrections — app layer.** Speaker slots, voice labels, and row-level corrections are managed in `AppModel`, `TranscriptionCoordinator`, and `DiarizationCoordinator`, not by the diarization library. The user-facing identity unit is the observed tuple `Speaker N / Voice M`, with `Speaker N / no voice` used for segments that do not have an embedding identity. Naming a tuple changes display/export labels for matching transcript and diarization rows, and names may be reused across tuples — with same-named merging on, that is what folds several tuples into one canonical speaker (decision 15). A transcript row's speaker label opens correction actions that assign the row to an observed tuple, cycle through tuples, or force a fresh `Voice N` under the row's current speaker slot when Sortformer under-counts speakers.

7. **AI processing — configured LLM endpoints.** `AIPromptCoordinator` listens to finalized transcript sentences, applies enabled prompt templates, performs prompt substitutions such as `{{sentence}}`, `{{conversation}}`, and `{{prompt-state}}`, and queues model calls.

8. **Jev — structured decisions.** `JevCoordinator` listens to the same finalized transcript sentences and, for every enabled Jev query (Noul yes/no, Choice categorical, or Score rubric), batches them into a single `POST /v1/systemone` call per sentence against TypeSafe's Jev API, since Jev's wire format natively answers multiple typed questions in one request. Unlike AI Processing, Jev returns typed answers (a probability, a selected label, or a rubric score) with confidence, not prose.

9. **Summary and export — app layer.** `SummaryCoordinator`, `TranscriptDocument`, and `MarkdownExportService` consume finalized transcript segments, speaker labels, voice identity labels, AI Processing results, Jev results, prompt state, and diarization timelines. Markdown exports include the transcript table (with an AI Processing column and a Jev column), a separate speaker timeline when diarization segments are available, an "AI RESULTS" section, and a "JEV RESULTS" section.

10. **Playback and transcript follow — AVFoundation.** `AudioPlaybackService` plays the audio the on-screen transcript belongs to, and `AppModel` maps the playhead onto the transcript through a `TranscriptAudioTarget` anchor (the wall-clock instant equal to audio offset zero) plus the pure `TranscriptPlaybackTimeline`. A recording this app made is placed by an exact anchor, because `RecordingService` opens the file at `RecordingSession.startDate` and writes every captured buffer in real time; an imported file has no such anchor, but is placed by each row's engine-reported position on that file's own timeline, so both follow (see decision 16).

Current limitation: SpeechVAD Sortformer provides session-local speaker slots, not persistent voice identity. WeSpeaker identity matching improves same-session distinction when Sortformer reuses a `Speaker N` slot, but it is best-effort, depends on usable diarized audio windows, and intentionally resets for each transcription session. Manual tuple names are display corrections, not biometric identity assertions; multiple generated tuples can share the same human name when the matcher over-splits a speaker.

### Key Design Decisions

1. **Single capture path, multiple consumers.** One `AVAudioEngine` tap feeds all active modes. `AudioCaptureService` fans out copied buffers. Capture stops when no consumers remain (`stopIfUnused()`).

2. **Off-main-actor file writing.** `AsyncAudioFileWriter` uses its own `DispatchQueue` (`.utility` QoS) so disk I/O never blocks the audio tap.

3. **SpeechTranscriber (not SFSpeechRecognizer).** The legacy `SFSpeechRecognizer` is broken for streaming on macOS 26. Migration to `SpeechAnalyzer` + `SpeechTranscriber` happened in v1.3.0. The analyzer stream must be started BEFORE audio buffers are fed. Buffers are resampled via `AVAudioConverter` to the analyzer's preferred format.

4. **Startup + fallback permission model.** Device enumeration is passive, but app startup now requests native microphone/speech dialogs when macOS reports a not-determined state, then relaunches the packaged app so audio starts with fresh authorization. `PermissionService.authorizeFirstRecordingDeviceTouch()` remains the fallback path before capture.

5. **Buffer copying is mandatory.** Tap buffers are transient. Every buffer is deep-copied (`copyBuffer()`, `deepCopy()`) before being handed off to consumers.

6. **AI processing is prompt-template based.** Enabled prompt templates, not a single global AI toggle, determine whether finalized sentences are sent to LLMs. Each prompt can use its own model unless `useGlobalPromptLLM` is enabled.

7. **Global prompt model enables batching.** When all enabled prompts target the global model, multiple prompt questions for the same sentence can be sent in one LLM request and mapped back to individual result rows.

8. **Prompt state is per template.** `{{prompt-state}}` accrues independently for each prompt template, updates from successful responses, resets with AI processing state, and forces that template's calls to run serially.

9. **Diarization and identity are live and best-effort.** SpeechVAD Sortformer streaming diarization runs alongside Apple Speech transcription. WeSpeaker identity matching runs asynchronously over diarized audio ranges. Transcript rows get the latest finalized speaker/voice label when the ASR segment arrives, while Markdown export also includes the diarizer's separate speaker timeline for time-based review.

10. **Jev batches per sentence, not per query.** `JevCoordinator` groups every enabled query for one finalized sentence under a shared `batchGroupID` and always sends them in one API call, unlike `AIPromptCoordinator` where batching across prompt templates is opt-in and requires a shared model. Jev has no free-text prompt-state chaining equivalent.

11. **A per-sentence AI result feature has four touch points, not one.** AI Processing and Jev both prove this out: each needed (a) a Settings tab for configuration, (b) a sidebar section (`ContentView.sourceList`) so results can be toggled per item, (c) a transcript-row block in `TranscriptAIPromptPanel` so results are visible live, and (d) a column/section in `MarkdownExportService` so results survive into the exported record — these are the four technical pillars `AGENTS.md` asks every such feature to check. It is easy to build (a)–(c) by mirroring the UI and forget (d), since the export path is a separate call site (`AppModel.saveTranscriptMarkdownToFile`) not reachable by browsing the live view tree — this happened once already with the initial Jev integration (v2.4.39) and was fixed in the following release.

12. **Sentence-level results are keyed by occurrence, not text.** `AIPromptCoordinator.sentenceOccurrences(in:)` turns a finalized `TranscriptSegment` into `SentenceOccurrence` values (`segmentID` + `sentenceIndex` + text). AI Processing and Jev dedupe repeat submissions of the same occurrence, but repeated identical spoken text in later segments intentionally produces new result items. UI display and Markdown export must match results to transcript rows by `segmentID` first, using normalized text only as a fallback for legacy items that predate occurrence metadata.

13. **Pause withholds buffers instead of stopping the pipeline.** `TranscriptionCoordinator.pause()` flips `isPaused`, which makes `consume(buffer:time:)` drop buffers while leaving the engine, its analyzer input stream, and the in-flight interim utterance alive. Resume therefore continues the same sentence, and the paused interval produces no transcript rows because the audio was never fed — instead of stopping and restarting the coordinator, which would discard interim text and pay analyzer startup again. Each pause is recorded as a `TranscriptionPauseSpan` so the live transcript can interleave pause markers and Markdown export can report the gap. Recording is deliberately left running, so a paused session's audio file keeps its full duration while its transcript has a hole in it.

14. **The left sidebar is tabbed, and sections must choose a tab.** `ContentView` renders exactly one of `microphoneSections` or `aiSelectionSections` under a segmented `SidebarTab` picker: **Microphones** holds the device list and File Sources, **AI Selection** holds AI Prompts and Jev Queries. The tab is pure view state (`@State selectedSidebarTab`) — no model, no persistence — so it does not affect what is enabled or transcribed. This matters for decision 11's pillar (b): a new per-sentence AI feature no longer just appends a sidebar section, it also decides which tab that section belongs to. Audio-input sections belong to Microphones; anything about prompts, queries, or models belongs to AI Selection. The tab is expected to stay cheap: it groups existing sections, and per-recording status stays with the recording controls in the Microphones tab rather than in AI configuration.

15. **Speaker identity is canonical by name, and still session-only.** `CanonicalSpeakerResolver` folds `Speaker N / Voice M` combos into canonical speakers: with `mergeSameNamedSpeakers` on, combos the user named the same (case- and whitespace-insensitive) share one `canonicalID`, one pane row, one transcript color, and one coalesced `# SPEAKERS` run. A name the user picked from the existing-name list also takes that row's type-in field away (`SpeakerNameOrigin.picked`), leaving the dropdown showing the chosen name, so a quick pick cannot be overwritten by a stray keystroke; **Custom…** or resetting brings typing back. The resolver is pure and value-typed and `editorItems()` builds the pane rows from it, which is why the grouping and lock rules are unit-tested instead of living in view code. The pane and the transcript row's speaker menu both render that same grouped list, so a speaker is listed once in each; assigning a merged entry uses its first combo, and the entry's help text names the combos behind it. Row identity is the row's first combo, never the canonical id: canonical ids contain the assigned name, so keying `ForEach` on them rebuilt the row on every keystroke and stole focus from the type-in field. Keep `observedVoiceCorrectionItems` (never merged) for operations that must visit every combo individually, such as resetting all names. The merge flag is also the one setting stored as `@Published` + explicit `UserDefaults` rather than `@AppStorage`, because it changes derived view data and `@AppStorage` in an `ObservableObject` publishes nothing. Nothing here is persisted — closing the app discards names, locks, and merges along with the rest of voice identity.

16. **Transcript follow has two sources of position, because a transcript row has two clocks.** `TranscriptPlaybackTimeline` maps a playback position to a transcript row and back. A row carries a wall-clock `timestamp`, which is meaningless as a position in the audio unless something ties the two clocks together — so a row is placed by whichever of two facts is available. For audio the app wrote in real time, `TranscriptAudioTarget.anchorDate` supplies it: `RecordingService` starts the file at `RecordingSession.startDate` and writes every captured buffer as it arrives, so `segment.timestamp - anchorDate` is the row's true position in the file, pause markers included (paused audio is in the file but not in the transcript, which is exactly where the marker belongs). An imported file has no anchor, because it is fed to the recognizer as fast as it can be read and its rows are stamped with the moment Apple Speech returned them — processing time, not file position (`REQUIREMENTS.md` §7). Such a row still carries the engine's own placement on the audio's timeline, requested through `attributeOptions: [.audioTimeRange]` and kept as `TranscriptSegment.audioOffset`: measured from the start of the audio fed to the analyzer, which the app feeds with a cumulative `bufferStartTime` from zero, so for an imported file it is that file's own timeline at its real speed. Imported audio therefore follows exactly, on the engine's placement; the anchor wins when both exist, being derived from the file itself. Only finalized files can be played at all: an in-progress `.m4a` has no `moov` atom, so `AVAudioPlayer` refuses it. The timeline's row ids are built by the same helpers the transcript pane uses for its `ForEach` ids, so the rows it names are the rows the pane can scroll to; while following, the pane scrolls to the playhead and bottom-scrolling is suppressed rather than fighting it. Opening the target's file lives in one place (`AppModel.ensureTranscriptPlaybackLoaded()`), shared by playing, scrubbing, and jump-to-row, because loading lazily per entry point meant a scrubber drag before the first press of play silently moved nothing; `AudioPlaybackService` additionally remembers a position requested before any file was open. A transcript row's timestamp is a button that plays from that row — visibly a button, since a plain-looking timestamp gives no sign it can be clicked — and scrubbing repositions without starting playback. While playback is engaged the same timeline supplies the transcript's time column, so rows read as positions in the audio (heading **Playback**) instead of clock times — the rule is `TranscriptPlaybackState.isShowingAudioTime` (`canFollow && (isPlaying || currentTime > 0)`), which keeps a merely-finished recording on clock time and keeps audio whose rows cannot be placed on clock time too. Followability itself is `transcriptPlaybackTimeline != nil` rather than a flag on the file, because whether the rows carry positions is a fact about the transcript: that one expression is what enables following, the playhead highlight, jump-to-row, and the audio-time column together. Pause markers report their time in the same clock the column is using, so "at" never disagrees with the timestamps beside it.

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

### ⚠️ Capture Source Switches Must Be Serialized

`AudioCaptureService` is shared by listen, record, and transcription modes. Before switching from one physical/virtual input source to another, stop active recording/transcription consumers, stop the engine, then start the new source. The capture service uses a `captureGeneration` guard so queued tap callbacks from an old source are ignored after a stop or switch.

### ⚠️ SpeechAnalyzer Input Stream Ordering

The analyzer stream must be started (`analyzer.start(inputSequence:)`) BEFORE any audio buffers are sent. Getting this order wrong causes silent transcription failures.

### ⚠️ AI Processing Labels

Visible UI and documentation say **AI Processing**. The Swift types were renamed to match in v2.4.41 (`AIPromptService.swift`, `AIPromptCoordinator`, `AIPromptItem`, etc. — see Version History); avoid reintroducing `FactCheck`-prefixed names or user-facing "Fact Check" labels.

### ⚠️ Stateful Prompt Queueing

Prompts that include `{{prompt-state}}` must not be batched or run concurrently for the same template. Inject prompt state immediately before the request is sent, then update it from the successful response before the next stateful call for that template.

### ⚠️ Version Bumps Are Manual

Version numbers live in `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`). Every code change section in `IMPLEMENTATION.md` should end with a bump. If the plist says 1.3.0 but the checklist says 1.3.2, someone forgot.

### ⚠️ IMPLEMENTATION.md IS the Changelog — Do NOT Create a Separate CHANGELOG.md

This project tracks versioned work exclusively in `IMPLEMENTATION.md`. Each version is a numbered section with checklists. There is NO `CHANGELOG.md` file — do not create one. When adding a new version:

1. Add a new numbered section to `IMPLEMENTATION.md` (e.g., `## 30. v1.5.0. Feature Name`).
2. Use checked-off `- [x]` items describing what was done.
3. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
4. Add a row to the Version History table in THIS file (`ARCHITECTURE.md`).

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
- AI processing event (`aiPrompt.*` trace names, including prompt/template/model queue activity)
- Jev event (`jev.*` trace names, including query queue/batch activity)
- Diarization event (`diarization.*`)
- Voice identity event (`voiceIdentity.*`)
- Device change (`devices.changed`)
- Permission state (`permission.mic`)
- Error (various `.error` events)

## Build & Launch

```sh
cd ~/projects/ai/VoiceTranscribe
./scripts/build.sh
./scripts/run.sh
```

`./scripts/build.sh` always performs a clean SwiftPM build and refreshes the packaged app at `dist/VoiceTranscribe.app`. It validates its prerequisites (package manifest, sibling prepare script, `external/` dependency checkouts) before running `swift package clean`, because SwiftPM resolves the package by walking up from the current directory — a clean that runs before validation would delete the build products of a checkout that cannot rebuild. `CONFIGURATION` is exported so the packaging step builds and copies the same configuration. All three scripts resolve the repo root from their own location, so they work from any working directory.

Refresh only the .app package from the current build:
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
| `AudioPlaybackService.swift` | AVAudioPlayer playback of the transcript's audio: load, play/pause, seek, position publishing for the transcript follow |
| `TranscriptionService.swift` | SpeechTranscriber pipeline, format conversion, coordinator |
| `DiarizationService.swift` | SpeechVAD Sortformer speaker diarization, speaker timeline, transcript annotations |
| `VoiceIdentityService.swift` | SpeechVAD WeSpeaker embedding extraction and session-local voice matching |
| `AIPromptService.swift` | AI processing LLM clients, queueing, prompt substitutions, batching, prompt state |
| `JevService.swift` | Jev (TypeSafe System One) client, wire structs, `JevCoordinator` queueing/batching |
| `PermissionService.swift` | Lazy mic/speech auth with caching and mock support |
| `Trace.swift` | JSON-line event logger to `/tmp/VoiceTranscribe.log` |
| `Models.swift` | Data types: SoundInputSource, RecordingSession, TranscriptSegment, etc. |
| `Utilities.swift` | FileNamer, BoundedBuffer, TranscriptDocument |
| `AppSettings.swift` | @AppStorage preferences, output folder, format |
| `MarkdownExportService.swift` | Builds the Markdown export document — transcript table, speaker timeline, summary, AI Processing results, Jev results, file references. Any feature that produces a per-sentence result (like AI Processing or Jev) must add a column/section here, not just a transcript-row UI — see Key Design Decision below. |
| `Views.swift` | All SwiftUI views: ContentView, SourceRow, GraphPanel, Transcript/AI processing panels, SettingsView |
| `Resources/Info.plist` | Bundle metadata, permissions strings, version numbers |
| `REQUIREMENTS.md` | Full product requirements |
| `IMPLEMENTATION.md` | Versioned implementation checklist |

## Version History

| Version | Build | What Changed |
|---------|-------|-------------|
| 2.4.46 | 89 | Added playback of the audio the on-screen transcript belongs to, with the live transcript following the playhead — scrolling to and highlighting the row being played, and jumping the audio from a clicked timestamp. Following is exact for app-recorded audio (placed by the file's wall-clock anchor) and for imported files (placed by each row's engine-reported position in the file) |
| 2.4.45 | 88 | Voice Identification can set a speaker from a list of names already assigned this session (which locks the type-in field), and a "merge same-named speakers" toggle folds every combo sharing a name into one speaker across the pane, transcript colors, and the exported speaker timeline |
| 2.4.44 | 87 | Split the left sidebar into two tabs — Microphones (devices + file sources) and AI Selection (AI Prompts + Jev Queries) — so AI configuration no longer competes for vertical space with the device list |
| 2.4.43 | 86 | Added pause/resume for live transcription: buffers are withheld from the `transcribe` and `diarize` consumers while recording keeps running, the live transcript interleaves pause markers, and Markdown export records the gaps in a `# PAUSES` table |
| 2.4.42 | 85 | Keyed AI Processing and Jev result rows by transcript sentence occurrence instead of normalized text; improved sentence splitting around ellipses, abbreviations, and decimals; fixed clean worktree builds by tracking `VoiceIdentityService.swift` |
| 2.4.41 | 84 | Renamed the historical `FactCheck`-prefixed AI Processing code (file, types, coordinator, trace events, tests) to `AIPrompt`, matching the UI label; removed dead legacy `@AppStorage` settings/reset code uncovered along the way |
| 2.4.40 | 83 | Fixed Markdown export missing AI Processing/Jev results (a pillar the v2.4.39 Jev integration forgot); added a "Feature Surface Checklist" to AGENTS.md so future per-sentence-result features cover all four touch points |
| 2.4.39 | 82 | Added Jev (TypeSafe System One) as a new AI backend: Jev Configuration settings tab, one-or-many Jev Queries (Noul/Choice/Score primitives), a sidebar "Jev Queries" section, and per-sentence transcript results |
| 2.4.38 | 81 | Hid the per-row "AI Processing: Disabled" block from the transcript when no AI Processing prompt templates are enabled |
| 2.4.37 | 80 | Widened the transcribe restart cooldown from 0.3s to 2.0s after build 79's shorter cooldown failed to prevent a repeat of the same SIGSEGV crash; confirmed fixed against a live repro |
| 2.4.36 | 79 | Added a 0.3s cooldown before a transcribe restart re-engages capture, to mitigate a SIGSEGV crash in AppKit hit-testing triggered by rapid stop→restart state churn (insufficient, see 2.4.37) |
| 2.4.35 | 78 | Pinned the main NavigationSplitView to keep the left source sidebar visible alongside the right voice pane |
| 2.4.34 | 77 | Moved Voice Identification from the transcript stack into a collapsible right-hand pane |
| 2.4.33 | 76 | Treated observed `Speaker N / Voice M` tuples as editable voice candidates with row correction and forced-new-voice actions |
| 2.4.32 | 75 | Added file-transcription diarization readiness ordering and expanded diarization/voice identity tracing |
| 2.4.31 | 74 | Fixed stop-transcription crash by rejecting late Sortformer pushes after diarization shutdown starts |
| 2.4.30 | 73 | Added always-on session-only WeSpeaker voice identity labels on top of SpeechVAD Sortformer speaker slots |
| 2.4.29 | 72 | Hardened BlackHole/microphone capture switching to stop active modes cleanly and ignore stale tap buffers |
| 2.4.28 | 71 | Added click-to-cycle speaker correction for individual Live Transcript rows |
| 2.4.27 | 70 | Added Live Transcript speaker-name editing with per-speaker and reset-all controls |
| 2.4.26 | 69 | Downmixed multichannel capture buffers before Apple Speech analysis so BlackHole and aggregate-device input can transcribe reliably |
| 2.4.25 | 68 | Runs an active AI health test when AI processing is re-enabled from a disabled state |
| 2.4.24 | 67 | Temporarily disabled automatic app relaunch after permission prompts to test whether it is still required |
| 2.4.23 | 66 | Made the standard build script always refresh the packaged app bundle |
| 2.4.22 | 65 | Added wider default window sizing, shared Settings entry point, per-speaker colors, and launch-time AI reachability status |
| 2.4.21 | 64 | Made SpeechVAD diarization startup nonblocking so Apple Speech transcript text appears immediately |
| 2.4.20 | 63 | Replaced FluidAudio diarization with SpeechVAD Sortformer streaming diarization |
| 2.4.19 | 62 | Fixed transcript processing to Apple Speech while keeping FluidAudio speaker diarization |
| 2.4.18 | 61 | Removed stalled partial finalization and suppressed stale FluidAudio partial repeats |
| 2.4.17 | 60 | Added fallback finalization for stalled FluidAudio interim transcript segments |
| 2.4.16 | 59 | Made packaged app builds run `swift package clean` before compiling |
| 2.4.15 | 58 | Fixed packaging to use SwiftPM's actual build product path after clean builds |
| 2.4.14 | 57 | Replaced the Live Transcript audio-source column with a speaker column |
| 2.4.13 | 56 | Moved current-speaker status to a full-width Live Transcript strip |
| 2.4.12 | 55 | Fixed prompt template editing so typed spaces are preserved |
| 2.4.11 | 54 | Added a prominent current-speaker indicator in Live Transcript |
| 2.4.10 | 53 | Moved Live Transcript speaker labels under the audio source |
| 2.4.9 | 52 | Added a root launcher script for packaged app rebuild and launch |
| 2.4.8 | 51 | Added live FluidAudio speaker diarization with transcript and export annotations |
| 2.4.7 | 50 | Added accumulated prompt-state output to Markdown transcript exports |
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
