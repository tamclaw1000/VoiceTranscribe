# Linux Architecture

This is the living architecture record for the Linux web implementation in `linux/gpt-5.6-luna`. It describes the current implementation, not the full future product. Update this file after every implementation step, together with `LINUX_BUILD_HISTORY.md` and the local checklist.

## Current scope

The current build is a single-user, trusted-LAN Docker Compose deployment. It accepts browser microphone audio and uploaded audio files, records live PCM, normalizes imported media through FFmpeg, publishes live events, exports Markdown, and uses faster-whisper file and rolling-window live ASR by default. Fake ASR is an opt-in deterministic development mode; advanced per-sentence features are deferred.

## Runtime topology

```text
Browser
  ├─ getUserMedia microphone permission/device selection
  ├─ AudioWorklet PCM capture
  ├─ local RMS/peak/clipping meter
  ├─ WebSocket binary audio frames
  ├─ WebSocket JSON event consumer
  └─ multipart audio file upload
       │
       ▼
FastAPI / Uvicorn container
  ├─ HTTP session, file, and lifecycle API
  ├─ WebSocket event/audio endpoint
  ├─ in-memory Session and FileSource registries backed by SQLite metadata
  ├─ recording writer → /data/<session-id>.pcm
  ├─ FFmpeg probe/normalizer → /data/files/<file-id>-16k-mono.wav
  ├─ configurable fake/faster-whisper ASR adapters
  ├─ bounded event replay list
  └─ Markdown export
       │
       ▼
Docker persistent volume: /data
```

## Components

### Browser client

`app/static/index.html`, `styles.css`, and `app.js` provide the first web surface. The client owns browser permissions and browser-visible device selection. `audio-worklet.js` copies each input block, calculates level metrics, and sends the PCM block to the main thread. The client sends level messages and binary audio messages separately so visual feedback does not depend on ASR latency.

The client tracks `lastSequence` and reconnects the event WebSocket with `?after=<sequence>`. Duplicate or older events are ignored. This is the first version of reconnect-safe event delivery; durable event storage is a later phase.

### FastAPI application

`app/main.py` owns the first service boundary. HTTP endpoints create and inspect sessions, control recording/transcription, report capabilities, accept file uploads, return file metadata/audio, and generate Markdown. The WebSocket endpoint accepts binary audio and JSON client-level messages and broadcasts server events to connected clients.

### File import and normalization

`FileSource` tracks the original upload, safe generated storage path, FFprobe metadata, normalized artifact, progress, status, error, and any file-transcription session. Uploads are extension-filtered and size-limited, written below `/data/files`, probed with `ffprobe`, and normalized with `ffmpeg` to mono 16 kHz signed PCM WAV. The original is retained for later playback or reprocessing. The file-transcription job selects the configured adapter: deterministic fake text in the default image, or lazy faster-whisper inference in the optional ASR image. The normalized artifact and file-session contract provide audio-relative offsets for either path.

The WebSocket path selects the rolling-window faster-whisper worker by default or fake finalization in development mode. File transcription uses the same lazy model loader. Both paths preserve the session/event contract; the live worker processes ten-second windows, emits audio-relative offsets, and publishes queued/running/completed/failed ASR status.

### Session state

SQLite metadata is stored at `/data/voice-transcribe.sqlite3`. Completed session snapshots and imported file-source metadata are written as state changes and reloaded on process startup. Active capture connections and WebSocket replay events are intentionally not restored; interrupted in-progress work is reported as failed or idle rather than falsely resumed.

Each session contains:

- Stable session ID and creation time.
- Source display name.
- Negotiated sample rate and channel count.
- Independent recording/transcription/paused flags.
- Received audio byte count.
- Finalized transcript segment occurrences.
- Monotonically increasing event sequence.
- A bounded in-memory event replay list.
- Connected WebSocket clients.

The server records raw Float32 PCM bytes in the first slice. The session's `audioOffset` values are derived from the configured audio format and fake five-second blocks; real engines must provide or calculate authoritative audio-relative offsets.

### Event contract

Every server event has this envelope:

```json
{
  "type": "transcript.segment.final",
  "sessionId": "…",
  "sequence": 42,
  "occurredAt": "2026-09-21T00:00:00+00:00",
  "payload": {}
}
```

Current event families include:

- `session.created`
- `recording.started`
- `recording.finalized`
- `transcription.started`
- `transcription.paused`
- `transcription.resumed`
- `transcription.completed`
- `transcript.segment.final`
- `audio.level`
- `audio.ack`
- `asr.window.queued`
- `asr.window.started`
- `asr.window.completed`
- `transcription.failed` with live ASR scope

Deletion endpoints are `DELETE /api/files/{file_id}` and `DELETE /api/sessions/{session_id}`. They remove SQLite metadata and artifacts below `/data`; deletion is rejected while recording or transcription is active. A file deletion also removes its linked completed/failed transcription session.

HTTP failures use a stable envelope: `{ "error": { "code": "…", "message": "…", "requestId": "…" } }`. Every HTTP response includes the same request ID in `X-Request-ID`; a caller-provided header is preserved for log/request correlation. Validation failures use `validation_error`, missing resources use `not_found`, and other handled request failures use `request_failed`.

## Data flow and lifecycle

1. The browser requests microphone permission and enumerates available input devices.
2. The browser creates a session with its capture format.
3. The browser opens the event WebSocket and replays events after its last sequence on reconnect.
4. Recording and transcription are started through separate HTTP commands.
5. AudioWorklet blocks are copied and sent as WebSocket binary frames.
6. The server writes frames when recording is active and increments the session byte count.
7. The fake live adapter emits a finalized sentence approximately every five seconds of received audio while transcription is active and not paused.
8. Uploaded files are probed, normalized, and exposed as file sources; starting file transcription creates a separate session and selects fake or faster-whisper inference by `VT_ASR_ENGINE`.
9. The faster-whisper adapter loads `VT_ASR_MODEL` lazily, uses word/segment timing, and emits audio-relative final rows; model weights live in `/data/models`.
10. Live faster-whisper mode accumulates ten-second non-paused windows, converts Float32 browser frames to signed PCM WAV, runs inference off the event loop, and offsets rows to the session timeline.
11. Paused live audio remains in the recording but advances the ASR cursor without entering an inference window; stop drains one final partial window.
12. The server broadcasts transcript, level, and file lifecycle events; the browser updates its transcript, meter, and file-source status.
13. Stop commands finalize live transcription and recording independently.
14. Markdown export reads the in-memory session and references the persisted PCM or normalized file artifact.
15. Explicit deletion removes session/file metadata and data-volume artifacts; active work must be stopped first.

## Deployment profile

- Image: `python:3.12-slim` plus the Debian FFmpeg runtime.
- Service: FastAPI/Uvicorn.
- Storage: Docker volume mounted at `/data`, including SQLite metadata, audio artifacts, normalized files, and optional model cache.
- Application metadata: version `0.2.0`, build `5`, configurable with `VT_VERSION` and `VT_BUILD`.
- Default host binding: `0.0.0.0:10000` (`http://tamclaw:10000/`).
- Override with `VT_BIND_ADDRESS` and `VT_PORT` when a different interface/port is required.
- Default runtime mode: CPU, faster-whisper, single process, lazy model download.
- Optional development mode: `VT_ASR_ENGINE=fake` for deterministic output without model weights.
- No host PipeWire/PulseAudio/ALSA access.
- No authentication or HTTPS; this deployment must remain on a trusted network until the security phase is implemented.

## Deferred architecture

The following interfaces should be added without changing the browser session/event model:

- Improved live ASR segmentation, interim text, VAD tuning, durable job execution, full structured request logging, and automated retention cleanup.
- PostgreSQL migration for multi-user/durable deployments; the current SQLite metadata repository is implemented.
- Redis-backed job/event coordination for long-running work.
- Asynchronous diarization and session-only voice identity.
- Summary, AI Prompt, and Jev coordinators.
- Playable finalized container artifacts and playback timeline follow.
- Authentication, HTTPS/reverse proxy, retention, and secret management remain deferred and are required before untrusted/LAN-wide exposure.
- Optional PipeWire host-capture helper.
- GPU-specific worker profile.

## Architecture update rule

Every implementation step must update this document with:

- New or changed components.
- Data-flow changes.
- State and persistence changes.
- API/event contract changes.
- Deployment/security implications.
- Deferred work or newly discovered risks.

The corresponding entry in `LINUX_BUILD_HISTORY.md` must identify the checklist items and verification commands. The local `linux-implementation-plan.md` copy is the authoritative progress checklist for this working directory.
