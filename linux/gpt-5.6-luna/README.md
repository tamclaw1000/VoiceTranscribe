# VoiceTranscribe Linux — GPT-5.6 Luna Vertical Slice

This directory contains the Linux implementation from `docs/linux/linux-implementation-plan.md`.

Current release metadata: **version 0.2.0, build 21**. The browser header and health/capability APIs expose the same values. Override them with `VT_VERSION` and `VT_BUILD` when packaging a release.

## Included

- Docker Compose CPU deployment with faster-whisper live ASR enabled.
- Browser microphone permission and device selection.
- AudioWorklet RMS/peak/clipping metering.
- WebSocket audio frame transport with Uvicorn protocol keepalive and reconnect replay.
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
- Native browser playback controls for each imported original audio file.
- Timestamped imported transcript rows that highlight during playback and seek without autoplay when clicked.
- Main-panel imported-file review layout, separate from session controls and capture meters.
- HTTPS-by-default Docker startup with a persistent development certificate for browser microphone access.
- Explicit WebSocket ping intervals and clean disconnect handling for direct and Traefik deployments.
- Accessible live notification surface for microphone, upload, transcription, deletion, and connection errors.
- Negotiated microphone device, sample-rate, channel, and input-track diagnostics.
- Retry controls for failed imported-file transcription jobs without re-uploading the source.
- Sequenced and timestamped microphone audio frames with server acknowledgements.
- Bounded audio-frame flush before stopping a live session.

The default deployment now uses `faster-whisper` for real local file and rolling-window live transcription. Model weights are downloaded into the persistent model volume on first use. Fake ASR remains available by setting `VT_ASR_ENGINE=fake` for deterministic development tests.

## Run with Docker

From this directory:

```sh
docker compose -f compose.yml up --build
```

Open <https://tamclaw:10000/> in Edge and grant microphone permission. The first visit uses a development certificate; choose the certificate warning's advanced/continue option, then reload and allow microphone access. Compose binds to all host interfaces on port `10000` by default so another machine can reach the service. Audio, session artifacts, and the certificate are stored in Docker volumes.

For HTTP-only API diagnostics, use `VT_HTTPS=false`; browser microphone capture will not work from the non-localhost HTTP URL.

When using the shared Traefik reverse proxy, run:

```sh
docker compose -f compose.yml -f compose.traefik.yml up -d --build
```

This keeps the public URL on HTTPS while using HTTP for the private host-gateway upstream. The Compose service also reports Docker health from `/api/health/live`, allows a 30-second graceful stop window, and keeps WebSocket connections alive with configurable `VT_WS_PING_INTERVAL` and `VT_WS_PING_TIMEOUT` values.

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
- Live event replay and active WebSocket state remain in memory for one process. SQLite preserves completed session/file metadata; Redis/PostgreSQL belong to later deployment profiles. The browser reconnects with its last sequence, while Uvicorn protocol pings keep an idle proxy route open.
- Authentication is not included. The service is currently unauthenticated; only expose it on a trusted network until authentication is implemented.
- Deletion is explicit and refuses active recording/transcription jobs; retention automation is not yet implemented.
- File transcription is asynchronous; the browser shows queued/loading/transcribing/finalizing/completed/failed status and finalized segment text when available. Failed jobs can be retried when the normalized artifact remains available.
- Playback is available for finalized imported originals; timestamped rows follow that playback. Raw live PCM still needs a finalized container for broad browser compatibility.
- Request IDs improve diagnostics but are not an authentication or authorization mechanism.
- The browser notification surface announces important success, warning, and error states, but it is not a replacement for authentication or server-side alerting.
- If the selected microphone is unplugged or its permission is revoked during capture, the session is stopped and the browser displays a persistent diagnostic.
- Audio-frame sequence/timestamp values are transport diagnostics only; they are not authentication or authorization controls.
- Stop waits briefly for outstanding frame acknowledgements and reports any unacknowledged frames instead of silently discarding the count.
- Backgrounding the capture tab produces a visible warning; return the tab to the foreground to restore the event connection promptly and avoid browser throttling delays.
- The Capture panel displays the most recent client-to-server audio acknowledgement latency using the existing frame timestamp contract.
- The Capture panel counts observed gaps in acknowledged audio-frame sequence numbers and total acknowledgements, shows capture uptime, counts rendered events, and records reconnects so transport loss or stalled processing is visible instead of silent.
- HTTPS is enabled by default for microphone access. The generated development certificate is not publicly trusted; production deployments should replace it with a certificate trusted by the client.
