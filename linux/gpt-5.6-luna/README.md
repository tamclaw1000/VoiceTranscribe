# VoiceTranscribe Linux — GPT-5.6 Luna Vertical Slice

This directory contains the Linux implementation from `docs/linux/linux-implementation-plan.md`.

Current release metadata: **version 0.2.0, build 6**. The browser header and health/capability APIs expose the same values. Override them with `VT_VERSION` and `VT_BUILD` when packaging a release.

## Included

- Docker Compose CPU deployment with faster-whisper live ASR enabled.
- Browser microphone permission and device selection.
- AudioWorklet RMS/peak/clipping metering.
- WebSocket audio frame transport.
- Session and reconnect-safe event envelopes.
- Independent recording and transcription state.
- Raw PCM recording in the Docker data volume.
- Audio file upload with extension/size validation and FFmpeg probing.
- FFmpeg normalization to mono 16 kHz PCM WAV artifacts.
- File-source metadata and fake file-transcription progress.
- Pause/resume transcription semantics.
- A fake transcription adapter that emits a demo finalized sentence every five seconds of audio.
- Session Markdown export.
- Health, readiness, capabilities, session, recording, and transcription endpoints.
- Stable JSON API error envelopes with request IDs in responses and `X-Request-ID` headers.
- Explicit version/build metadata in Docker, APIs, and the browser header.
- SQLite metadata persistence for completed sessions and imported file sources.
- Session and imported-file deletion with data-volume artifact cleanup.
- File-transcription status polling and transcript results displayed directly in the file card.

The default deployment now uses `faster-whisper` for real local file and rolling-window live transcription. Model weights are downloaded into the persistent model volume on first use. Fake ASR remains available by setting `VT_ASR_ENGINE=fake` for deterministic development tests.

## Run with Docker

From this directory:

```sh
docker compose -f compose.yml up --build
```

Open <http://tamclaw:10000/> and grant microphone permission. Compose binds to all host interfaces on port `10000` by default so another machine can reach the service. Audio and session artifacts are stored in the `voice-transcribe-data` Docker volume.

Stop the service with:

```sh
docker compose -f compose.yml down
```

Add `-v` only when intentionally deleting the stored audio volume.

## Optional fake-ASR development mode

The production/test deployment uses faster-whisper. To use deterministic fake output without model downloads:

```sh
VT_ASR_ENGINE=fake docker compose -f compose.yml up -d --build
```

## faster-whisper ASR profile

The default service now uses the real local ASR path:

```sh
docker compose -f compose.yml -f compose.asr.yml build
docker compose -f compose.yml -f compose.asr.yml up -d
```

The service defaults to the `small.en` model with `int8` compute. Override the model before starting if needed:

```sh
VT_ASR_MODEL=base.en docker compose -f compose.yml -f compose.asr.yml up -d
```

The model is downloaded on first file transcription and stored in the `voice-transcribe-models` volume. Browser microphone transcription uses the rolling-window worker. The first request downloads the selected model if it is not already in the model volume.

## Run locally

With Python 3.12 or newer:

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

## API smoke test

```sh
curl http://tamclaw:10000/api/health/live
curl http://tamclaw:10000/api/health/ready
curl http://tamclaw:10000/api/capabilities
```

## Current limitations

- The fake-ASR mode is opt-in for deterministic tests. The default service uses faster-whisper and requires model download on first use.
- Diarization, voice identity, AI Prompts, and Jev are capability-disabled.
- Raw microphone PCM is stored for the first slice; a production build needs a finalized playable container and format metadata.
- File transcription uses faster-whisper by default and downloads the configured model on first use.
- Live event replay and active WebSocket state remain in memory for one process. SQLite preserves completed session/file metadata; Redis/PostgreSQL belong to later deployment profiles.
- Authentication is not included. The service is currently unauthenticated; only expose it on a trusted network until authentication and HTTPS are implemented.
- Deletion is explicit and refuses active recording/transcription jobs; retention automation is not yet implemented.
- File transcription is asynchronous; the browser shows queued/processing/completed/failed status and finalized segment text when available.
- Request IDs improve diagnostics but are not an authentication or authorization mechanism.
- The browser must use HTTPS, or localhost, for microphone access.
