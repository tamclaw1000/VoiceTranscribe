# VoiceTranscribe Checkpoint

Last updated: 2026-09-17

## Repository State

- Current branch: `main`
- Remote state: `main` is synchronized with `origin/main`
- Latest merge commit: `317623b Merge feature/voice-identity`
- Latest feature commit: `56ab3e4 Add session voice identity workflow`
- Latest tag: `v2.4.35`
- App version: `2.4.35`
- Bundle build: `78`
- Feature branch preserved on remote: `feature/voice-identity`

Local working tree notes:

- `samples/` is intentionally untracked. It contains generated/manual sample material, including large media files.
- `speaker-location-screenshot.png` deletion was not committed. It is preserved in `stash@{0}` as `preserve local screenshot deletion before voice identity merge`.

## Current System Summary

VoiceTranscribe is a native macOS SwiftUI app for recording audio sources, live transcription, file transcription, speaker diarization, session-only voice identity, transcript export, AI summaries, and configurable sentence-level AI processing.

The current speech pipeline is split:

- Apple Speech provides authoritative transcription text and sentence boundaries.
- SpeechVAD Sortformer provides live diarization speaker slots.
- SpeechVAD WeSpeaker provides session-only voice embeddings for best-effort voice identity.
- The app layer combines these into user-editable observed voice tuples such as `Speaker 1 / Voice 2`.

The diarization and voice identity path is intentionally best-effort and does not block Apple Speech transcript display.

## Implemented Capabilities

- Audio input enumeration for microphones, virtual devices, and loaded files.
- Live input visualization with RMS/peak/clipping state.
- Recording to disk with recent recordings.
- Live transcription and file transcription through Apple Speech.
- SpeechVAD Sortformer diarization alongside transcription.
- SpeechVAD WeSpeaker voice identity matching within the current session only.
- Transcript rows show timestamp, speaker/voice identity, and transcript text.
- Speaker labels can be clicked to correct identity:
  - assign any observed voice tuple,
  - cycle through observed tuples,
  - force a new `Voice N` for the row.
- Voice candidates can be named and reset.
- Voice Identification is in a collapsible right-hand pane.
- Left source/navigation pane is pinned visible with the right voice pane present.
- Markdown export includes transcript rows, AI processing output, prompt states, and diarization timeline data.
- AI processing supports multiple LLM endpoints, multiple prompt templates, prompt enablement, global model override, batching, queueing, and prompt state.
- Settings are split into General, LLM Models, and Prompt Templates.
- Build scripts perform clean builds and refresh the packaged app.

## Important Files

- `ARCHITECTURE.md` - authoritative architecture notes and version history.
- `IMPLEMENTATION.md` - project changelog/checklist. Do not create a separate changelog.
- `REQUIREMENTS.md` - product-facing functional requirements and UI/UX behavior.
- `Sources/VoiceTranscribe/AppModel.swift` - central app orchestration.
- `Sources/VoiceTranscribe/TranscriptionService.swift` - Apple Speech pipeline.
- `Sources/VoiceTranscribe/DiarizationService.swift` - SpeechVAD Sortformer integration.
- `Sources/VoiceTranscribe/VoiceIdentityService.swift` - SpeechVAD WeSpeaker matching.
- `Sources/VoiceTranscribe/FactCheckService.swift` - AI processing implementation; historical type names still use `FactCheck`.
- `Sources/VoiceTranscribe/Views.swift` - SwiftUI UI.
- `scripts/extract-star-trek-sample.sh` - helper to extract a sample audio file from local media.

## Build and Test

Common commands:

```sh
./build.sh
./run.sh
swift test
./scripts/package-app.sh
```

Project convention:

- Always run a clean build for app changes.
- Always refresh the packaged app after a build.
- Bump `Resources/Info.plist` version/build for code changes.
- Update `IMPLEMENTATION.md` and `ARCHITECTURE.md` for released work.
- New user requests should start on a new feature branch.

Last known verification before merge:

- `swift test` passed with 52 tests.
- `./build.sh` completed and packaged `dist/VoiceTranscribe.app`.
- `git diff --check` passed.

## Known Constraints and Risks

- Sortformer speaker labels are session-local diarization slots, not stable human identities.
- WeSpeaker matching is session-only and best-effort; it can over-split or under-split speakers depending on audio quality and diarization windows.
- User naming/correction changes display/export labels only; it is not biometric identification.
- File and live transcription rely on Apple Speech for sentence boundaries because FluidAudio-style diarization was not reliable for segmentation.
- Prompt/AI type names still include historical `FactCheck` identifiers in code and traces, while UI/docs should say `AI Processing`.
- `/tmp/VoiceTranscribe.log` is the primary trace log and should include transcription, diarization, and voice identity events.

## Suggested Next Steps

- Test the `v2.4.35` build against live BlackHole input and loaded sample files.
- Review whether the right-hand Voice Identification pane needs resizing behavior after real usage.
- Continue improving voice identity correction UX if Sortformer/WeSpeaker produce too many candidate tuples.
- Consider adding a compact debug view for diarization and voice identity events currently visible only in `/tmp/VoiceTranscribe.log`.
