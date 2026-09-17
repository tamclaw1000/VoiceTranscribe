# Add Diarization Handoff

This document captures the current speaker diarization work so it can be rolled back safely or reimplemented by another agent without rediscovering the same issues.

## Goal

Add live speaker diarization to VoiceTranscribe so the Live Transcript view and exports identify anonymous speakers such as `Speaker 1`, `Speaker 2`, etc.

The target product behavior is:

- Run diarization alongside live microphone transcription and file transcription.
- Show the current speaker in the Live Transcript UI.
- Add a `Speaker` column to transcript rows.
- Include speaker labels in plain text and Markdown exports.
- Preserve a separate speaker timeline in Markdown exports.

## Current State

The codebase currently contains a partial implementation:

- `Sources/VoiceTranscribe/DiarizationService.swift`
  - Adds `DiarizationCoordinator`.
  - Uses FluidAudio `LSEENDDiarizer(variant: .dihard3)`.
  - Converts incoming audio buffers to mono float samples.
  - Emits `SpeakerDiarizationSegment` values.
  - Tracks `currentSpeakerLabel`.
  - Logs `diarization.*` trace events.

- `Sources/VoiceTranscribe/AppModel.swift`
  - Owns `@Published var diarization`.
  - Starts diarization when transcription starts.
  - Adds a live capture consumer named `diarize`.
  - Feeds file-transcription buffers into diarization.
  - Exports `diarization.segments` to Markdown.
  - Provides `transcription.speakerProvider` from the diarizer's latest speaker.

- `Sources/VoiceTranscribe/TranscriptionService.swift`
  - `TranscriptionCoordinator` has `speakerProvider`.
  - Each transcript segment is annotated with the current speaker when it is applied.
  - Current correction suppresses stale FluidAudio partials that repeat the latest finalized text.

- `Sources/VoiceTranscribe/Models.swift`
  - `TranscriptSegment` has `speakerID`, `speakerName`, `speakerLabel`, and `textWithSpeaker`.
  - Adds `SpeakerDiarizationSegment`.

- `Sources/VoiceTranscribe/Utilities.swift`
  - `TranscriptDocument.plainText` uses `textWithSpeaker`.

- `Sources/VoiceTranscribe/MarkdownExportService.swift`
  - Adds speaker column to transcript table.
  - Adds `# SPEAKERS` timeline.

- `Sources/VoiceTranscribe/Views.swift`
  - Live Transcript grid currently uses `Timestamp | Speaker | Text`.
  - Shows a full-width current-speaker status strip.

- `Tests/VoiceTranscribeTests/VoiceTranscribeTests.swift`
  - Has tests for speaker labels in transcript text and Markdown export.
  - Has a regression test for stale FluidAudio partial suppression:
    `fluidAudioStalePartialAfterFinalSegmentIsSuppressed`.

## What Worked

- FluidAudio diarization does produce speaker timeline segments.
- Trace output confirms `diarization.segment` events such as:

```json
{"event":"diarization.segment","speaker":"Speaker 1","start":"0.20","end":"6.30"}
{"event":"diarization.segment","speaker":"Speaker 2","start":"21.00","end":"22.30"}
```

- The UI can display the speaker column and current speaker status.
- Markdown export can include:
  - Speaker label per transcript row.
  - A separate speaker timeline.
- Plain text export can include speaker prefixes.

## What Failed

The hard problem is alignment between ASR output and diarization output.

The current implementation assigns each ASR segment the latest diarizer speaker at the moment the ASR segment arrives:

```swift
transcription.speakerProvider = { [weak self] in
    self?.diarization.annotationForCurrentSpeaker()
}
```

That is not reliable enough because:

- FluidAudio ASR partials are cumulative.
- Partial text can keep repeating after a speaker transition.
- Diarization can advance to a new speaker while ASR is still reporting text from the previous utterance.
- Assigning "latest diarized speaker" at ASR callback time can attach the wrong speaker to a sentence.

Example trace behavior:

- ASR partial repeats the same long text for many seconds.
- Diarization changes from `Speaker 1` to `Speaker 2`.
- The same ASR text then appears under `Speaker 2`.
- A prior attempted fallback finalized stalled partials, which made this worse by creating repeated finalized rows under different speakers.

The fallback finalization was removed in v2.4.18. Final transcript rows should come from FluidAudio EOU/final callbacks only.

## Current Mitigation

The current `TranscriptionCoordinator` suppresses stale partials that repeat the latest finalized text:

- If the latest finalized normalized text has the partial as a prefix, suppress the partial.
- If the partial has the latest finalized normalized text as a prefix, suppress the partial.
- Exact duplicate final segments are also suppressed.

This prevents one class of repeated rows, but it does not solve correct time-based speaker assignment.

## Recommended Reimplementation

Do not assign speaker by "latest diarizer speaker at ASR callback time."

Instead:

1. Track timing for ASR segments.
   - Each transcript segment needs a start/end time or at least an approximate audio clock range.
   - `AVAudioTime` from capture can be converted into an app-relative audio clock.
   - FluidAudio ASR callbacks may need an utterance start estimate from the streaming manager or coordinator.

2. Track diarization segments by time.
   - `SpeakerDiarizationSegment` already has `startTime` and `endTime`.

3. Assign speaker by overlap.
   - For each finalized transcript segment, choose the speaker segment with maximum overlap against the ASR segment time range.
   - If no reliable overlap exists, show `Unknown` or leave speaker blank.

4. Keep partial transcript display separate from final transcript speaker assignment.
   - Partials can show `Detecting` or current speaker as a hint.
   - Final rows should be assigned only by time overlap.

5. Preserve diarization timeline even when row attribution is uncertain.
   - The timeline is still useful for export/review.

## Safer UI Behavior

If diarization is not time-aligned, the UI should avoid presenting speaker labels as authoritative.

Recommended labels:

- Current speaker strip: `Current speaker: Speaker N`
- Interim rows: `Detecting`
- Final rows:
  - `Speaker N` only when assigned by time overlap.
  - `Unknown` when the overlap is ambiguous.

Avoid repeatedly attaching the latest current speaker to old ASR partials.

## Possible Rollback Scope

If rolling back the diarization feature entirely, likely revert or remove:

- `Sources/VoiceTranscribe/DiarizationService.swift`
- `AppModel.diarization`
- `transcription.speakerProvider`
- `captureService.addConsumer(id: "diarize")`
- file-transcription calls to `diarization.consume`
- Markdown speaker timeline additions
- `TranscriptSegment` speaker fields if not needed
- Live Transcript speaker column/current-speaker strip
- speaker-related tests

Keep if useful:

- `run.sh`
- `scripts/package-app.sh` clean-build and `--show-bin-path` fixes
- prompt template space editing fix
- prompt-state export work
- other non-diarization LLM/prompt changes

## Important Trace Events

Use these while debugging:

```sh
tail -f /tmp/VoiceTranscribe.log
```

Relevant events:

- `diarization.starting`
- `diarization.started`
- `diarization.segment`
- `diarization.processError`
- `diarization.stopped`
- `fluidAudio.partial`
- `fluidAudio.eou.raw`
- `fluidAudio.eou.punctuated`
- `transcription.segmentPartial`
- `transcription.segmentPartial.staleSuppressed`
- `transcription.segmentFinal`
- `transcription.segmentFinal.duplicateSuppressed`

## Lessons Learned

- Diarization is time-based; transcript callbacks are text/event-based. Bridging them requires explicit timestamps.
- FluidAudio ASR partials should not be treated as final text.
- Repeated cumulative partials can cross speaker changes and must not be used for speaker attribution.
- A "latest speaker" heuristic is okay for a current-speaker indicator, but not for persisted transcript labels.
- Any future implementation should include tests for:
  - ASR final text whose diarization speaker changes before callback arrival.
  - Repeated cumulative partials after a final segment.
  - Final transcript speaker assignment by timeline overlap.
  - Ambiguous/no-overlap speaker assignment.

## Soniqo speech-swift Trial Notes

Attempted direct SwiftPM integration of `https://github.com/soniqo/speech-swift` on the `wip/add-diarization-current` branch.

Relevant API:

- Product: `SpeechVAD`
- Streaming class: `SortformerStreamingSession`
- Loader: `SortformerStreamingSession.fromPretrained(config: .streaming, ...)`
- Push audio with `push(audio:)`, finalize with `finish()`
- Input requirement: 16 kHz mono `Float` PCM
- Output: whole-stream `DiarizationResult` snapshots with `DiarizedSegment.startTime`, `endTime`, and `speakerId`

Blocker:

- Adding `SpeechVAD` through SwiftPM pulls in `MLXCommon` and the `mlx-swift` package even though the Sortformer streaming path itself is CoreML-based.
- `swift test` failed during transitive `mlx-swift` Metal compilation before app code compiled.
- Because of that package-level dependency graph, direct `SpeechVAD` import is not currently a viable drop-in for this app.

Possible paths:

- Ask upstream for a CoreML-only Sortformer product that excludes `MLXCommon`.
- Vendor a small, attributed subset of Sortformer code plus the required model downloader/error helpers into this repo.
- Keep Apple Speech for transcript boundaries and use any future Sortformer integration only as a side-channel diarizer that emits time-aligned speaker timeline snapshots.
