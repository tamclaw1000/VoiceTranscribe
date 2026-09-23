# Voice identity telemetry review: 2026-09-22 Star Trek run

## Evidence reviewed

- `/tmp/VoiceTranscribe.log` (JSON lines). The `star-trek-first-120s` file run began at `2026-09-23T00:59:12Z` (19:59:12 CDT) and completed at `00:59:56Z`; earlier lines belong to a different audio source.
- `20260922200520-star-trek-first-120s.txt`, saved at `01:05:44Z`.
- `20260922200547-star-trek-first-120s.md`, saved at `01:06:05Z`.

The filename timestamps reflect when the save dialogs were opened, not necessarily when the files were written. The sample is 120 seconds of audio but took about 44 seconds to process; the Markdown DETAILS duration (`0:39`) uses transcript wall-clock timestamps, whereas its SPEAKERS timeline spans audio offsets through `2:00`. Do not align those two clocks by their printed times.

## What the trace establishes

- Apple Speech finalized 28 rows for this file. At finalization, 19 events said `speaker: nil`, five said `Unidentified audio`, and four had generated `Person N` labels (three distinct numbers). None had the final human names. The rows were relabeled by export time, but the trace does not show when each edit occurred.
- In this run, WeSpeaker queued 16 embedding attempts: eight `voiceIdentity.assigned` events (five new profiles, three matches), eight `voiceIdentity.match.deferred` events, and 22 short-range `voiceIdentity.skipped` events. These describe automatic voice evidence, not the user's person assignments.
- Playback was used for review between about 20:00 and 20:04 CDT, including seeks to audio offsets 34.32, 37.50, 48.12, 51.96, 57.48, 87.12, 91.56, 102.96, 108.66, and 112.50 seconds. The seeks give review locations and row IDs, but no edit event links a seek to a correction.
- Both exports label the transcript with Picard, Worf, Data, Riker, and Guest. The Markdown speaker timeline also has named audio ranges and many `Unidentified audio` ranges. The transcript has more named rows than the named ranges alone explain (for example, Worf appears repeatedly in transcript rows but only one short timeline range is labeled Worf). This is consistent with row-only corrections or other label backfill, but the exact action cannot be proven from these files.
- The text export has 29 lines; the Markdown table has 28 finalized rows. The text export includes the trailing interim line `I'm the owner and operator`, because `TranscriptDocument.plainText` appends `interim`; Markdown export receives `transcription.segments` (finalized only). This is an export-scope difference, not evidence of another identity edit.

## What cannot be reconstructed

The current user-facing person actions in `AppModel`/`DiarizationCoordinator` (`create`, `rename`, assign one or selected ranges, row-only override, mark unidentified, restore automatic, merge, undo) do not call `Trace.event`. The older tuple-naming trace events are not emitted by the new pane. The log therefore cannot tell the order or time of name entry, which range IDs or row IDs were selected, whether a label came from an automatic match or a manual override, whether several ranges were assigned together, whether people were merged, or whether an edit was undone. The exports are final-state snapshots and omit person UUIDs and assignment-source flags. Five final names must not be equated with the five automatic `Voice N` profiles.

**Conclusion:** telemetry is adequate for diagnosing the automatic diarization/embedding path and where playback was used, but not for replaying or auditing how the user made these assignments.

Implementation follow-up is tracked in `TODO.md` under `# BUGS`.
