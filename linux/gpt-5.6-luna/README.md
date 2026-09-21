# VoiceTranscribe Linux — GPT-5.6 Luna Vertical Slice

This directory contains the Linux implementation from `docs/linux/linux-implementation-plan.md`.

Current release metadata: **version 0.1.0, build 1**. The browser header and health/capability APIs expose the same values. Override them with `VT_VERSION` and `VT_BUILD` when packaging a release.

## Included

- Docker Compose CPU deployment.
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
- Explicit version/build metadata in Docker, APIs, and the browser header.

The fake adapter is intentional. It makes the default vertical slice testable without downloading model weights. An optional `faster-whisper` profile is available for real local file transcription.

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

## Optional faster-whisper ASR profile

The default service uses fake ASR. To build and run the real local file-ASR profile:

```sh
docker compose -f compose.yml -f compose.asr.yml build
docker compose -f compose.yml -f compose.asr.yml up -d
```

The profile defaults to the `small.en` model with `int8` compute. Override the model before starting if needed:

```sh
VT_ASR_MODEL=base.en docker compose -f compose.yml -f compose.asr.yml up -d
```

The model is downloaded on first file transcription and stored in the `voice-transcribe-models` volume. Browser microphone transcription remains on the fake adapter until a live rolling-window worker is implemented.

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

- Default live and file sessions use fake ASR and do not recognize speech. The optional faster-whisper profile performs real file transcription.
- Diarization, voice identity, AI Prompts, and Jev are capability-disabled.
- Raw microphone PCM is stored for the first slice; a production build needs a finalized playable container and format metadata.
- File transcription currently emits demo text after FFmpeg normalization; it does not recognize the uploaded speech.
- The current event store is in memory and is intended for a single process. Redis/PostgreSQL/object storage belong to later deployment profiles.
- Authentication is not included. The service is currently unauthenticated; only expose it on a trusted network until authentication and HTTPS are implemented.
- The browser must use HTTPS, or localhost, for microphone access.
