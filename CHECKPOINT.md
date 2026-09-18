# VoiceTranscribe Checkpoint

Last updated: 2026-09-18

## Repository State

- Current branch: `feature/jev-integration` (uncommitted work in progress)
- `main` state: synchronized with `origin/main` at `59edef9 Merge hide-empty-ai-processing`
- Latest tag: `v2.4.38`
- App version on `main`: `2.4.38`, bundle build `81`
- App version in the current working tree (uncommitted, on `feature/jev-integration`): `2.4.39`, bundle build `82`
- Merged-and-cleaned-up branches still present locally/remotely: `fix/transcribe-restart-crash-debounce`, `chore/agents-md-cross-tool-support`, `feature/hide-empty-ai-processing` (all merged into `main`, not deleted)
- Repo-root operating guide is now `AGENTS.md` (cross-tool standard, read natively by Codex/opencode/etc.), with `CLAUDE.md` as a symlink to it so Claude Code also auto-loads it. The old `AGENT.md` (singular, no tool read it automatically) is gone.

Local working tree notes:

- `samples/` is intentionally untracked. Contains generated/manual sample material, including large media files.
- `docs/claude-jev-integration-plan.md` is untracked and not part of any commit — it's an automatic copy of a plan-mode plan (harness/hook behavior, not something written by hand), left untracked deliberately since it wasn't clear it should be permanent project documentation.
- **Known repo bug**: `.gitignore` has `sources/` (lowercase), which on this case-insensitive filesystem also matches `Sources/`. Any *new* file added under `Sources/VoiceTranscribe/` is silently treated as ignored — `git status` won't even list it. Modifications to already-tracked files under `Sources/` are unaffected (`git add -u` works fine), but a brand-new file needs `git add -f <path>` explicitly, or the `.gitignore` pattern should be fixed to `/sources/` or removed if it's stale. Bit twice this session (`AppSettings`/`Views` changes were fine; `JevService.swift`, a new file, needed `-f`).
- Jev API key: for local testing, a real `JEV_API_KEY` lives in `~/projects/ai/jev/play1/.env` (a separate, unrelated sample project) and was manually typed into VoiceTranscribe's own Settings → Jev Configuration during verification. It is stored in this machine's `UserDefaults` only (`jevAPIKey`), never committed to the repo.

## Current System Summary

VoiceTranscribe is a native macOS SwiftUI app for recording audio sources, live transcription, file transcription, speaker diarization, session-only voice identity, transcript export, AI summaries, configurable sentence-level free-text AI processing (AI Prompts), and — new this session, in progress — Jev (TypeSafe System One) structured-decision queries (Noul/Choice/Score).

The current speech pipeline is split:

- Apple Speech provides authoritative transcription text and sentence boundaries.
- SpeechVAD Sortformer provides live diarization speaker slots.
- SpeechVAD WeSpeaker provides session-only voice embeddings for best-effort voice identity.
- The app layer combines these into user-editable observed voice tuples such as `Speaker 1 / Voice 2`.

The diarization and voice identity path is intentionally best-effort and does not block Apple Speech transcript display.

Two parallel AI backends now run per finalized transcript sentence:

- **AI Prompts / FactCheckCoordinator** — free-text LLM prompts (Ollama/OpenAI-compatible/OpenRouter/Anthropic/Gemini), one HTTP call per enabled prompt template (with opt-in cross-template batching when they share a model).
- **Jev Queries / JevCoordinator** (in progress, uncommitted) — structured typed questions against TypeSafe's Jev API, always batching every enabled query for a sentence into a single `POST /v1/systemone` call.

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
- The AI Processing per-row transcript block is hidden entirely (not just shown as "Disabled") when no prompt templates are enabled.
- Settings are split into General, LLM Models, Prompt Templates, and (new, in progress) Jev Configuration.
- **In progress on `feature/jev-integration` (uncommitted)**: Jev Queries — one or many structured queries (Noul yes/no, Choice categorical, Score rubric), configured in the new Jev Configuration settings tab, toggled from a new sidebar "Jev Queries" section (mirrors AI Prompts, hidden when empty), with results intended to render under each transcript row the same way AI Processing results do. Settings UI (connection fields, per-type criteria editors, sidebar section) is visually verified. The live transcript-row rendering with a real Jev API response has **not** been visually confirmed yet — see Suggested Next Steps.
- Build scripts perform clean builds and refresh the packaged app.

## Important Files

- `ARCHITECTURE.md` - authoritative architecture notes and version history.
- `IMPLEMENTATION.md` - project changelog/checklist. Do not create a separate changelog.
- `REQUIREMENTS.md` - product-facing functional requirements and UI/UX behavior.
- `AGENTS.md` (symlinked as `CLAUDE.md`) - repo operating guide: branching, build/test, versioning, git hygiene.
- `Sources/VoiceTranscribe/AppModel.swift` - central app orchestration.
- `Sources/VoiceTranscribe/TranscriptionService.swift` - Apple Speech pipeline.
- `Sources/VoiceTranscribe/DiarizationService.swift` - SpeechVAD Sortformer integration.
- `Sources/VoiceTranscribe/VoiceIdentityService.swift` - SpeechVAD WeSpeaker matching.
- `Sources/VoiceTranscribe/FactCheckService.swift` - AI Prompts (free-text LLM) implementation; historical type names still use `FactCheck`.
- `Sources/VoiceTranscribe/JevService.swift` - Jev (TypeSafe System One) implementation: wire structs, `TypeSafeJevService`, `JevCoordinator`. New this session, uncommitted.
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
- New user requests should start on a new feature branch off an up-to-date `main`.

Last known verification (on `feature/jev-integration`, uncommitted):

- `swift test` passed with 58 tests (52 pre-existing + 6 new Jev tests).
- `./build.sh` completed and packaged `dist/VoiceTranscribe.app`, no new warnings.
- `git diff --check` not yet re-run since the last doc edits.
- Manual UI verification: Settings → Jev Configuration (connection fields, Noul editor, Choice editor incl. validation) and sidebar "Jev Queries" section (hidden-when-empty, correct rows once populated) all confirmed via screenshots. Transcript-row rendering with a real Jev response is **not yet confirmed** — live-transcription audio routing (BlackHole / physical-mic acoustic pickup) wasn't successfully completed in the verification session.

## Known Constraints and Risks

- Sortformer speaker labels are session-local diarization slots, not stable human identities.
- WeSpeaker matching is session-only and best-effort; it can over-split or under-split speakers depending on audio quality and diarization windows.
- User naming/correction changes display/export labels only; it is not biometric identification.
- File and live transcription rely on Apple Speech for sentence boundaries because FluidAudio-style diarization was not reliable for segmentation.
- Prompt/AI type names still include historical `FactCheck` identifiers in code and traces, while UI/docs should say `AI Processing`.
- `/tmp/VoiceTranscribe.log` is the primary trace log and should include transcription, diarization, voice identity, AI Processing, and (new) Jev events (`jev.request.started`, `jev.response.received`, `jev.queued`, `jev.completed`, `jev.failed`).
- All LLM/Jev API keys are stored in plaintext in `UserDefaults` (no Keychain anywhere in this app) — a known, accepted, pre-existing risk, not something introduced this session.
- The `.gitignore` `sources/`-vs-`Sources/` case-collision bug (see Local working tree notes above) is unresolved; new files under `Sources/` need `git add -f`.

## Suggested Next Steps

- **Finish verifying Jev end-to-end**: get a real live transcription through (fix BlackHole routing or use a loaded sample file instead of live capture) and confirm the per-row Jev result block actually renders correctly for a completed Noul/Choice/Score answer, and for a failed request (e.g. bad API key). Then commit, merge `feature/jev-integration` into `main`, tag, and push, following this session's established pattern.
- Consider fixing the `.gitignore` `sources/` collision properly (change to `/sources/` or remove if stale) rather than working around it with `-f` each time.
- Test the current `main` build (`v2.4.38`) plus the in-progress Jev build against live BlackHole input and loaded sample files together.
- Review whether the right-hand Voice Identification pane needs resizing behavior after real usage.
- Continue improving voice identity correction UX if Sortformer/WeSpeaker produce too many candidate tuples.
- Consider adding a compact debug view for diarization, voice identity, AI Processing, and Jev events currently visible only in `/tmp/VoiceTranscribe.log`.
