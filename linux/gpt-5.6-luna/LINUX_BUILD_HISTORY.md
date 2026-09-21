# Linux Build History

This file records each implementation phase for the Linux web version. Every completed implementation step must update this file and `LINUX_ARCHITECTURE.md` before the next step begins. The local `linux-implementation-plan.md` is the checklist for this working directory; mark an item complete only after implementation and verification.

## Phase 0 — Design and implementation target

**Status:** Complete

**Source material reviewed:**

- `docs/linux/linux-version-analysis.md`
- `docs/linux/linux-implementation-plan.md`
- Native macOS architecture and requirements documentation

**Selected starting direction:**

- Browser microphone capture rather than direct host audio capture.
- FastAPI backend with a static browser client for the first vertical slice.
- Docker Compose CPU profile with a persistent `/data` volume.
- WebSocket audio/event transport.
- Fake ASR first, with an adapter boundary for `faster-whisper`, `whisper.cpp`, or a hosted provider later.
- Localhost-only default binding.
- Diarization, voice identity, AI Prompts, and Jev deferred behind capability flags.

**Reason:** This provides a runnable, testable end-to-end path without requiring model weights, GPU drivers, Linux audio socket permissions, or provider credentials before the session/event architecture is proven.

## Phase 1 — Dockerized vertical slice

**Status:** Complete

**Implementation location:** `linux/gpt-5.6-luna/`

### Delivered

- FastAPI service in `app/main.py`.
- Browser client in `app/static/`.
- Docker image in `Dockerfile`.
- CPU Compose deployment in `compose.yml`.
- Persistent data volume configuration.
- Browser microphone permission and device enumeration.
- AudioWorklet capture with RMS, peak, and clipping measurements.
- WebSocket binary audio frames and JSON event messages.
- Session creation, snapshot, lifecycle, recording, and transcription endpoints.
- Reconnect replay using monotonically increasing event sequence numbers.
- Recording and transcription represented as independent session states.
- Pause/resume transcription while recording remains available.
- Fake finalized transcript events generated from received audio duration.
- Raw PCM artifact storage and audio download endpoint.
- Markdown export endpoint.
- Capability reporting for implemented and deferred features.
- Contract tests in `tests/test_contract.py`.
- Setup and limitations documented in `README.md`.

### Verification

- `python3 -m py_compile app/main.py tests/test_contract.py` passed.
- `node --check app/static/app.js` passed.
- `docker compose config` passed.
- Docker image build passed.
- Container health/capability smoke test passed on alternate port `18000`; host port `8000` was already occupied by another service.
- Dockerized pytest passed: `2 passed`.
- `git diff --check` passed.

### Known limitations carried forward

- The fake ASR does not recognize speech.
- Raw PCM is not yet wrapped in a broadly playable finalized container.
- Session state is in memory and is not yet durable across service restarts.
- There is no authentication; the service must remain localhost-only.
- The current browser transport is not authenticated and must not be exposed beyond localhost.
- No file upload/import, real ASR, diarization, AI Prompt, Jev, summary, or production playback-following pipeline exists yet.

## Step recording template

Copy this template for every subsequent implementation step, then update `LINUX_ARCHITECTURE.md` in the same change:

```markdown
## Phase N — Short name

**Status:** Complete | In progress | Deferred
**Date:** YYYY-MM-DD

### Goal

...

### Delivered

- ...

### Checklist items completed

- `linux-implementation-plan.md`: section/item references

### Verification

- Commands and results

### Limitations and next step

- ...
```

## Documentation protocol

For every implementation step:

1. Select the checklist items before editing code.
2. Implement the smallest coherent slice.
3. Update `LINUX_ARCHITECTURE.md` with the resulting component/data-flow changes.
4. Update this history with the phase, verification, limitations, and checklist references.
5. Check the corresponding items in the local `linux-implementation-plan.md` copy.
6. Run the relevant tests and build/container checks.
7. Do not mark an item complete based only on code inspection when it requires runtime verification.

## Phase 2 — File import and normalization

**Status:** Complete
**Date:** 2026-09-21

### Goal

Add a useful file-source path before integrating a real speech model: upload audio, validate and inspect it, normalize it for ASR, expose progress/status, and create a separate file-transcription session.

### Delivered

- Added multipart file upload at `POST /api/files`.
- Added extension filtering and a configurable 500 MB upload limit.
- Added FFprobe metadata extraction for duration, sample rate, channels, and codec.
- Added FFmpeg normalization to mono 16 kHz signed PCM WAV.
- Retained original uploads under `/data/files` and generated safe UUID-based artifact names.
- Added file-source list and detail endpoints.
- Added file-transcription endpoint with a separate session and deterministic fake transcript events.
- Added browser file import, metadata cards, status/progress display, and Transcribe File controls.
- Added FFmpeg to the CPU Docker image.
- Added metadata/normalization tests using a generated WAV fixture.

### Checklist items completed

- Local checklist section 8: FFmpeg/PyAV/GStreamer runtime, ASR normalization, original-source retention, initial format support, metadata display, and valid-media test coverage.
- Local checklist section 10: file-transcription job endpoint, progress/status reporting, and audio-relative demo offsets.

### Verification

- Python syntax compilation passed.
- JavaScript syntax checks passed for `app.js` and `audio-worklet.js`.
- Docker Compose configuration passed.
- Docker image rebuilt successfully with FFmpeg.
- Dockerized pytest passed: `4 passed` with one Starlette deprecation warning.

### Limitations and next step

- File transcription still emits deterministic demo text; it does not recognize speech.
- Upload processing is currently in-memory for metadata/state and does not survive service restart.
- File deletion, authenticated access, decoded-duration limits, and durable job queues remain open.
- Next recommended step is a real ASR adapter and durable file/session metadata.

## Phase 3 — Trusted-LAN browser deployment

**Status:** Complete
**Date:** 2026-09-21

### Goal

Make the browser-testable service reachable from the host name `tamclaw` on port `10000`.

### Delivered

- Changed the Compose default binding from localhost port `8000` to `0.0.0.0:10000`.
- Added `VT_BIND_ADDRESS` and `VT_PORT` overrides for alternate network layouts.
- Updated the browser URL, health-check commands, and deployment documentation.
- Updated the architecture record to identify the current deployment as trusted-LAN rather than localhost-only.
- Documented that authentication and HTTPS are still required before exposing the service to an untrusted network.

### Verification

- Compose configuration passes with the new default binding.
- The service was restarted with the new port configuration.
- The browser entry point and capability endpoint were verified at `http://tamclaw:10000/`.

### Limitations and next step

- The service remains unauthenticated and serves plain HTTP.
- Use only a trusted network until the security phase adds authentication and HTTPS.

## Phase 4 — Optional faster-whisper file ASR

**Status:** Complete for the adapter/profile; model-backed runtime verification pending
**Date:** 2026-09-21

### Goal

Add a real local ASR path without making the default browser-test deployment download model weights or require a large ML runtime.

### Delivered

- Added lazy `faster-whisper` model loading for file transcription.
- Added `VT_ASR_ENGINE`, `VT_ASR_MODEL`, and `VT_ASR_COMPUTE_TYPE` configuration.
- Added `requirements-asr.txt` with a pinned optional runtime.
- Added `compose.asr.yml` with an ASR image build, model cache volume, and `small.en`/`int8` defaults.
- Added ASR engine/model/availability information to health and capability responses.
- Preserved fake ASR as the default engine and live-browser fallback.
- Added faster-whisper segment timing fields to file transcript rows.
- Updated the browser status text to show the configured ASR engine/model.

### Checklist items completed

- Local checklist section 1: selected `faster-whisper` as the first local ASR adapter.
- Local checklist section 9: adapter boundary, fake development adapter, model cache/version configuration, and final audio-relative segment output.
- Local checklist section 10: offline file-ASR adapter path and engine-reported segment offsets.
- Local checklist section 16: optional ASR Compose profile and model-cache volume.

### Verification

- Default application syntax checks pass.
- Default Docker Compose build and fake-ASR tests remain the supported verified path: `4 passed` with one Starlette deprecation warning.
- Optional ASR Compose configuration parses and the ASR image builds successfully.
- `faster-whisper` imports successfully in the optional image after adding its missing `requests` runtime dependency.
- A model-backed faster-whisper run has not yet been performed; it requires downloading the selected model.

### Limitations and next step

- Live microphone transcription still uses the fake adapter.
- The optional faster-whisper image is significantly larger and model download is deferred until first use.
- The next recommended step is to run a model-backed file fixture, then add a rolling-window live ASR worker.

## Phase 5 — Rolling-window live ASR

**Status:** Complete for the worker path; model-backed inference pending
**Date:** 2026-09-21

### Goal

Extend the optional faster-whisper adapter from imported files to live microphone audio without blocking recording or the event loop.

### Delivered

- Added per-session live PCM buffering and ASR cursor state.
- Added ten-second rolling inference windows for `VT_ASR_ENGINE=faster-whisper`.
- Added Float32 browser-frame to signed PCM WAV conversion before inference.
- Ran model inference through `asyncio.to_thread` so the WebSocket/event loop remains responsive.
- Added session-relative audio-offset correction for each live window.
- Preserved paused audio in the recording while advancing the ASR cursor without sending it to inference.
- Added final partial-window draining when live transcription stops.
- Preserved fake live ASR behavior in the default profile.
- Added conversion coverage to the file-import test suite.

### Checklist items completed

- Local checklist section 9: selected local ASR adapter, incoming audio normalization, finalized audio-relative rows, and safe final draining.
- Local checklist section 6: low-latency AudioWorklet frames now have a server-side ASR normalization path.

### Verification

- Python syntax checks passed.
- JavaScript syntax checks passed.
- Default Dockerized pytest passed: `5 passed` with one Starlette deprecation warning.
- Default Docker image rebuilt successfully.
- Optional ASR image rebuilt successfully and imports faster-whisper.
- Default service was restarted on `http://tamclaw:10000/` and reports `asrEngine: fake`.

### Limitations and next step

- The faster-whisper model has not been downloaded or run against a real live fixture yet.
- The default browser deployment still uses fake ASR.

## Phase 6 — Version and build metadata

**Status:** Complete
**Date:** 2026-09-21

### Goal

Add explicit Linux application version and build metadata that is consistent across Docker, APIs, and the browser UI.

### Delivered

- Added version `0.1.0` and build `1` defaults.
- Added `VT_VERSION` and `VT_BUILD` environment overrides.
- Exposed metadata from `/api/health/ready` and `/api/capabilities`.
- Displayed version/build in the browser header.
- Added contract coverage for the metadata responses.
- Documented release metadata in `README.md` and `LINUX_ARCHITECTURE.md`.

### Verification

- Python syntax and Dockerized contract tests pass.
- Compose version/build environment defaults parse successfully.
- Browser metadata is sourced from the capabilities response rather than duplicated in JavaScript.

### Limitations and next step

- Release version/build values are manually managed until a release automation process is added.

## Phase 7 — Durable SQLite metadata

**Status:** Complete
**Date:** 2026-09-21

### Goal

Keep completed session metadata and imported file-source metadata across container restarts without introducing PostgreSQL or Redis into the single-user profile.

### Delivered

- Added `/data/voice-transcribe.sqlite3` initialization with session and file-source tables.
- Persisted session lifecycle state and finalized transcript rows.
- Persisted file paths, media metadata, normalization status, progress, errors, and linked transcription sessions.
- Reloaded completed sessions and file sources at process startup.
- Converted interrupted `normalizing`/`transcribing` file states to an explicit restart failure instead of falsely resuming them.
- Kept active WebSocket clients, event replay buffers, and live capture state process-local.
- Added a persistence reload contract test.

### Checklist items completed

- Local checklist section 2: local persistent-data directory and backup expectations.
- Local checklist section 15: session metadata repository and SQLite-backed metadata.
- Local checklist section 16: persistent `/data` volume now contains metadata as well as artifacts.

### Verification

- Python syntax checks passed.
- Default Dockerized pytest passed: `7 passed` with one Starlette deprecation warning.
- Compose profiles validate successfully.
- A container restart test preserved a created session through the SQLite volume.
- Default service remains available at `http://tamclaw:10000/`.

### Limitations and next step

- Active recording and WebSocket clients do not survive a process restart.
- Event replay history is still in memory and is not reconstructed from SQLite.
- There is no migration framework or PostgreSQL profile yet.

## Phase 8 — Enable live faster-whisper transcription

**Status:** Complete; model-backed file warm-up verified, browser microphone session still requires manual acoustic verification
**Date:** 2026-09-21

### Goal

Make real local transcription the default service behavior instead of fake demo output.

### Delivered

- Changed the default Docker image to install faster-whisper.
- Changed the default Compose service to use `VT_ASR_ENGINE=faster-whisper`.
- Added the persistent model-cache volume to the default deployment.
- Bumped Linux metadata to version `0.2.0`, build `2`.
- Kept `VT_ASR_ENGINE=fake` as an explicit deterministic development override.
- Updated README, local AGENTS, architecture, and runtime status messaging.
- Preserved ten-second rolling-window live ASR and final partial-window draining.

### Verification

- Default image built successfully with faster-whisper.
- Service restarted at `http://tamclaw:10000/`.
- `/api/health/ready` reports `version: 0.2.0`, `build: 2`, `asrEngine: faster-whisper`, `asrAvailable: true`.
- A one-second WAV fixture was uploaded and completed through the real model-backed file transcription API, warming the `small.en` model successfully.
- Default Dockerized test suite remains available with deterministic fake mode when no ASR environment override is set.

### Limitations and next step

- Live microphone recognition through the browser has not been manually confirmed with spoken audio in this session.
- The first live result is emitted after a ten-second window; interim decoder text is not yet shown.
- Browser UI now exposes ASR queued/running/ready/failed status and processed-window counts.
- Model download, CPU usage, and transcription latency should be measured on the target host.
- Next recommended step is manual browser speech verification followed by VAD/interim improvements.

## Phase 9 — Live ASR observability

**Status:** Complete
**Date:** 2026-09-21

### Goal

Make rolling-window ASR progress and failures visible in the browser instead of leaving the user with an unexplained wait.

### Delivered

- Added ASR status and processed-window fields to session snapshots.
- Added queued, started, completed, and failed ASR events.
- Added browser ASR status display with window counts and error text.
- Added a session contract assertion for the initial ASR state.

### Verification

- Python syntax checks passed.
- JavaScript syntax checks passed.
- Dockerized tests passed: `7 passed` with one Starlette deprecation warning.
- Default service rebuilt and restarted at `http://tamclaw:10000/`.
- Health, browser HTML, and ASR status surface verified.

### Remaining work

- Add runtime verification for a real spoken browser window.

## Build 3 — Per-iteration build bump

**Status:** Complete
**Date:** 2026-09-21

The live-ASR observability iteration increments the Linux build number from `2` to `3` while keeping version `0.2.0`. Future implementation iterations must increment `VT_BUILD` and update the runtime, browser, README, architecture, and history metadata together.
- Live results are finalized window segments; interim decoder text, VAD-driven boundaries, and model-backed performance metrics remain open.

## Phase 10 — API error envelopes and request IDs

**Status:** Complete
**Date:** 2026-09-21

### Goal

Make backend failures consistently consumable by the browser and diagnosable by an operator without exposing internal exception details.

### Delivered

- Added a stable JSON error envelope with `code`, user-safe `message`, and `requestId` fields.
- Added request-ID middleware that generates an ID when absent and returns it in `X-Request-ID`.
- Preserved caller-supplied `X-Request-ID` values for client/server correlation.
- Added normalized handlers for HTTP errors and Pydantic validation failures.
- Kept unexpected failures behind a generic `internal_error` response.
- Bumped Linux build metadata from `3` to `4` while keeping version `0.2.0`.

### Checklist items completed

- Local checklist section 4: API error envelopes with stable error codes and user-safe messages.

### Verification

- Python syntax checks passed.
- Contract tests cover missing-resource, validation, generated-request-ID, and caller-supplied-request-ID behavior.
- Compose configuration and Docker tests passed.

### Limitations and next step

- Request IDs are response/correlation metadata only; structured request/session/job logging and authentication remain open.
- Next recommended step is to harden recording/file lifecycle behavior or add browser end-to-end coverage.

## Phase 11 — Explicit artifact deletion

**Status:** Complete
**Date:** 2026-09-21

### Goal

Give users an explicit, safe way to remove imported files and completed sessions while preventing deletion races with active recording or transcription.

### Delivered

- Added `DELETE /api/files/{file_id}` for imported-file metadata and original/normalized artifact cleanup.
- Added `DELETE /api/sessions/{session_id}` for session metadata, PCM recording, live-window artifacts, and linked file-session cleanup.
- Rejected deletion while recording, transcription, normalization, or live ASR work is active.
- Restricted artifact removal to paths below the configured `/data` directory.
- Added a browser Delete control for imported file cards.
- Bumped Linux build metadata from `4` to `5` while keeping version `0.2.0`.

### Checklist items completed

- Local checklist section 8: file removal and cleanup behavior.
- Local checklist section 15: session deletion and artifact cleanup.

### Verification

- Python and JavaScript syntax checks passed.
- Dockerized contract/media tests passed, including session artifact deletion.
- Compose configuration passed.
- Live service restarted at `http://tamclaw:10000/` and reports build `5`.

### Limitations and next step

- Retention/expiry cleanup jobs are not implemented.
- Deletion is not authenticated; the service remains trusted-LAN-only.
- Next recommended step is browser end-to-end coverage or recording metadata/playback hardening.

## Phase 12 — File transcription result visibility

**Status:** Complete
**Date:** 2026-09-21

### Goal

Make imported-file transcription visibly useful in the browser instead of showing only a progress percentage.

### Delivered

- Marked a file job `queued` synchronously before scheduling its background transcription task, preventing the UI from missing the processing transition.
- Extended file-source snapshots with linked finalized transcript segments.
- Added browser polling for `queued`, `normalizing`, and `transcribing` states.
- Added finalized segment text and audio offsets directly to each completed file card.
- Added a completion message showing the number of produced segments.
- Bumped Linux build metadata from `5` to `6` while keeping version `0.2.0`.

### Checklist items completed

- No new checklist item was marked complete; this phase fixes the observable behavior of the already-implemented file transcription job path.

### Verification

- Python and JavaScript syntax checks passed.
- Contract/media tests cover linked file transcript exposure and passed in Docker.
- Fake-ASR file flow was used for deterministic regression coverage.
- Live service reports build `6` after rebuild and restart.

### Limitations and next step

- The default faster-whisper profile still requires model inference and may take time before results appear.
- Full browser automation and playback of imported source files remain open checklist items.

## Phase 13 — File job lifecycle states

**Status:** Complete
**Date:** 2026-09-21

### Goal

Expose meaningful file-transcription phases so users can tell whether the service is waiting, loading the model, decoding, finalizing results, or has failed.

### Delivered

- Added persisted `queued`, `loading`, `transcribing`, and `finalizing` file states before terminal `completed`/`failed` states.
- Updated restart recovery so every nonterminal file job state is marked failed after interruption.
- Extended browser polling to retain the file card through every nonterminal phase.
- Bumped Linux build metadata from `6` to `7` while keeping version `0.2.0`.

### Checklist items completed

- Local checklist section 10: queued, loading, processing, finalizing, completed, and failed file-transcription status reporting.

### Verification

- Python and JavaScript syntax checks passed.
- Dockerized tests and Compose validation passed.
- Live service reports build `7` after rebuild and restart.

### Limitations and next step

- Progress remains phase-based rather than a precise model-level denominator during loading or decoding.
- Full browser end-to-end automation and playback remain open.

## Phase 14 — Imported-file playback

**Status:** Complete
**Date:** 2026-09-21

### Goal

Allow users to listen to the imported source while reviewing its transcription instead of treating transcription as a text-only result.

### Delivered

- Added `GET /api/files/{file_id}/audio` for finalized imported originals.
- Returned the original media MIME type and filename through `FileResponse`.
- Added native browser play/pause, scrubber, elapsed-time, and duration controls to each file card.
- Exposed the file audio URL in file-source snapshots.
- Kept original playback media separate from mono 16 kHz normalized ASR artifacts.
- Bumped Linux build metadata from `7` to `8` while keeping version `0.2.0`.

### Checklist items completed

- Local checklist section 10: playback is available when the imported source is finalized/readable.
- Local checklist section 12: native play/pause, scrubber, elapsed-time, and duration controls.

### Verification

- Python and JavaScript syntax checks passed.
- Dockerized file-import test verifies the audio endpoint and MIME type.
- Docker build and Compose validation passed.
- Live service reports build `8` after rebuild and restart.

### Limitations and next step

- Live microphone recordings remain raw PCM and are not yet broadly browser-playable.
- Transcript-row seeking/follow highlighting and authenticated playback remain open.

## Phase 15 — Imported transcript playback following

**Status:** Complete
**Date:** 2026-09-21

### Goal

Connect imported transcript rows to the audio player so reviewing a transcription is time-aware rather than a static text display.

### Delivered

- Replaced the static file transcript text block with timestamped selectable rows.
- Highlighted the row whose audio-relative offset contains the current player time.
- Added row seeking without automatically starting playback.
- Used `audioEndOffset` when available and the next segment offset as a fallback boundary.
- Bumped Linux build metadata from `8` to `9` while keeping version `0.2.0`.

### Checklist items completed

- No new checklist item was marked complete; this phase extends the imported-file playback behavior already verified in Phase 14.

### Verification

- Python and JavaScript syntax checks passed.
- Dockerized tests passed.
- Compose validation passed.
- Served browser JavaScript includes active-row highlighting and non-autoplay row seeking.
- Live service reports build `9` after rebuild and restart.

### Limitations and next step

- Live-recording transcript following is still deferred until recordings use a broadly playable finalized container and reliable wall-clock anchors.
- Active-row auto-scroll, authenticated playback, and full browser E2E coverage remain open.
