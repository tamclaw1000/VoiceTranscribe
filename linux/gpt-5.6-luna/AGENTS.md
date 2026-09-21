# Linux VoiceTranscribe Local Agent Guide

These instructions apply to the implementation under `linux/gpt-5.6-luna/`.

## Scope

This directory is the Linux web/Docker implementation of VoiceTranscribe. The native macOS SwiftUI application remains outside this directory and must not be changed as part of Linux work unless a task explicitly requires cross-platform documentation or shared behavior.

The current deployment is:

- FastAPI/Uvicorn backend.
- Static browser client with AudioWorklet capture.
- Docker Compose CPU profile.
- Trusted-LAN binding at `https://tamclaw:10000/` by default; Traefik can terminate public HTTPS and use an HTTP upstream.
- Faster-whisper file and rolling-window live ASR by default.
- Fake ASR is an opt-in deterministic development mode.
- No authentication; HTTPS is provided by the default development certificate or by the shared Traefik edge.

## Required process for every implementation step

1. Read `LINUX_ARCHITECTURE.md`, `LINUX_BUILD_HISTORY.md`, and the local `linux-implementation-plan.md` before editing.
2. Select the checklist items that the step will address.
3. Implement the smallest coherent vertical slice.
4. Keep the default browser deployment lightweight and runnable without model weights whenever possible.
5. Update `LINUX_ARCHITECTURE.md` in the same step:
   - Add or revise components.
   - Describe data-flow changes.
   - Describe state, persistence, and API/event changes.
   - Record deployment/security implications.
   - Record deferred work and newly discovered risks.
6. Append a numbered phase entry to `LINUX_BUILD_HISTORY.md` in the same step.
7. Check off only checklist items that are implemented and verified in the local copy of `linux-implementation-plan.md`.
8. Do not check off work that is merely planned, code-reviewed, or available only behind an unverified configuration.
9. Update `README.md` when setup, commands, deployment profiles, capabilities, limitations, or user-visible behavior changes.
10. Run the relevant checks before considering the step complete.

## Checklist rules

- The authoritative progress checklist for this implementation is `linux-implementation-plan.md` in this directory.
- The design/source checklist is `../../docs/linux/linux-implementation-plan.md`; do not silently alter it while tracking local progress.
- Keep the local copy structurally aligned with the source checklist when adding future checklist items.
- Use `[x]` only for completed, tested work.
- Keep incomplete, model-dependent, security-dependent, and manually unverified items as `[ ]`.
- Record partial completion and limitations in `LINUX_BUILD_HISTORY.md` rather than overstating checklist coverage.

## Version and build metadata

- Current version: `0.2.0`.
- Current build: `31`.
- Runtime configuration names are `VT_VERSION` and `VT_BUILD`.
- The values must appear consistently in:
  - `compose.yml` defaults.
  - `/api/health/ready`.
  - `/api/capabilities`.
  - The browser header.
  - `README.md` when the release metadata changes.
  - The relevant `LINUX_BUILD_HISTORY.md` phase.
- Every implementation iteration increments the build number, even when the marketing version stays the same.
- When code is released, increment the version/build intentionally and document why. Do not silently change only one surface.

## Default and optional Docker profiles

### Default browser-test profile

Run from this directory:

```sh
docker compose -f compose.yml up -d --build
```

It uses HTTPS by default with a persistent development certificate. Open `https://tamclaw:10000/` and accept the certificate warning before granting microphone access. Set `VT_HTTPS=false` only for HTTP/API diagnostics. It uses faster-whisper by default and may download model weights on first use. For deterministic development checks, set `VT_ASR_ENGINE=fake`. Verify:

```sh
curl --fail http://tamclaw:10000/api/health/live
curl --fail http://tamclaw:10000/api/health/ready
curl --fail http://tamclaw:10000/api/capabilities
```

The service is intentionally exposed on all interfaces at port `10000` for the current trusted-LAN setup. The default service uses HTTPS; behind Traefik, use `compose.traefik.yml` so Traefik terminates public HTTPS and forwards HTTP to the host port. Do not expose it to an untrusted network until authentication is implemented.

### Optional faster-whisper profile

```sh
docker compose -f compose.yml -f compose.asr.yml build
docker compose -f compose.yml -f compose.asr.yml up -d
```

The model cache is stored in the `voice-transcribe-models` volume. Override `VT_ASR_MODEL` or `VT_ASR_COMPUTE_TYPE` for hardware-specific tuning. Model-backed verification must be recorded with the selected model and runtime.

## Verification requirements

Before marking a step complete, run checks appropriate to the change. Normally include:

```sh
python3 -m py_compile app/main.py tests/*.py
node --check app/static/app.js
node --check app/static/audio-worklet.js
docker compose -f compose.yml config
docker compose -f compose.yml -f compose.asr.yml config
docker compose -f compose.yml build
docker run --rm -v "$PWD":/src -w /src gpt-56-luna-voice-transcribe pytest -q
git diff --check
```

If tests create root-owned cache files through Docker, remove only generated artifacts such as `__pycache__`, `.pytest_cache`, and test data. Do not remove user data or Docker volumes without explicit instruction.

For browser/runtime changes, also verify:

- The service is running at `http://tamclaw:10000/`.
- The health endpoint reports the expected version/build and engine.
- The browser HTML includes the changed surface.
- Any capability-disabled state is visible and truthful.

Warnings from dependency tooling should be recorded but treated separately from failures unless they block the requested work.

## Architecture and product invariants

- Recording must continue when transcription, diarization, or AI work is delayed.
- Paused transcription must not feed paused audio to ASR, but recording may continue.
- Interim text must not become finalized AI work.
- Sentence-level results must be keyed by occurrence, not normalized text alone.
- Audio-relative offsets, not processing timestamps, drive playback following.
- Diarization and voice identity are best-effort and must not block transcript text.
- API keys must not appear in browser state, logs, or Markdown exports.
- The default service is currently unauthenticated; do not represent it as production-safe.
- A feature that produces per-sentence results must account for configuration, selection, rendering, and export surfaces.

## File ownership guide

| File | Responsibility |
|---|---|
| `app/main.py` | API, session state, file import, ASR adapters, WebSocket events, export |
| `app/static/index.html` | Browser structure and user-visible controls |
| `app/static/app.js` | Browser state, capture, WebSocket lifecycle, rendering |
| `app/static/audio-worklet.js` | Browser PCM frames and level metrics |
| `compose.yml` | Default trusted-LAN CPU deployment |
| `compose.asr.yml` | Optional faster-whisper deployment |
| `compose.traefik.yml` | HTTP upstream override when Traefik terminates public HTTPS |
| `Dockerfile` | Shared image build and optional ASR installation |
| `LINUX_ARCHITECTURE.md` | Current technical architecture and data flow |
| `LINUX_BUILD_HISTORY.md` | Chronological implementation record |
| `linux-implementation-plan.md` | Local checked progress checklist |
| `README.md` | Setup, runtime commands, capabilities, and limitations |
| `tests/` | Contract, media, API, and adapter tests |

## Git and worktree hygiene

- Work only in the `linux-version` worktree unless explicitly instructed otherwise.
- Check `git status -sb` before and after changes.
- Do not overwrite unrelated untracked files. A root-level `sync_local_integrations.py` file has appeared during this work and is not part of the Linux implementation.
- Do not commit, merge, push, deploy, or delete branches unless explicitly requested.
- Keep generated caches and local model/data volumes out of Git.
