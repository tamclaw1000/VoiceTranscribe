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
- Live results are finalized window segments; interim decoder text, VAD-driven boundaries, and model-backed performance metrics remain open.
