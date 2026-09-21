# Linux Version: Web Application in Docker

## Status and purpose

This document explores a Linux version of VoiceTranscribe that runs as a web application in Docker. It is a design and options document, not an implementation checklist or a commitment to one technology choice.

The existing product is a native macOS SwiftUI application for:

- Enumerating audio inputs, including microphones, interfaces, Bluetooth devices, aggregate devices, and virtual devices.
- Showing live input levels and recording audio to disk.
- Transcribing live microphone input and existing audio files.
- Showing interim and finalized transcript text.
- Providing best-effort speaker diarization and session-only voice identity.
- Generating running summaries.
- Running configurable sentence-level AI Prompts through Ollama, OpenAI-compatible endpoints, OpenRouter, Anthropic, and Gemini.
- Running typed Jev queries (Noul, Choice, and Score) per finalized sentence.
- Playing transcript audio and following the playback position through the transcript.
- Exporting Markdown containing details, transcript rows, speaker information, summary, AI results, Jev results, pauses, and file references.

The Linux version should preserve these user-visible workflows where the host and selected backend support them. It should explain unavailable capabilities instead of silently dropping them.

## Recommended direction

The recommended first Linux implementation is a browser client plus a Python service, packaged as a Docker Compose deployment:

```text
Browser
  ├─ Web Audio / MediaRecorder microphone capture
  ├─ optional WebSocket audio upload
  └─ transcript, levels, settings, playback, export UI
       │ HTTPS + WebSocket
       ▼
FastAPI application
  ├─ session and state API
  ├─ WebSocket audio ingestion
  ├─ transcription adapter
  ├─ diarization/identity jobs
  ├─ summary, AI Prompt, and Jev coordinators
  └─ Markdown/export API
       │
       ├─ Redis (optional queue/event bus)
       ├─ PostgreSQL (optional durable metadata)
       ├─ local volume or S3-compatible object storage
       └─ model/runtime containers
```

For an initial single-user deployment, the application can be one container with SQLite, a local filesystem volume, and an in-process job queue. The service boundaries should still be represented by protocols/interfaces so GPU workers, Redis, PostgreSQL, or object storage can be added without changing the product model.

The first transcription backend should be `faster-whisper` or `whisper.cpp` rather than trying to reproduce Apple Speech. The first diarization backend should be optional, offline or asynchronous, and preferably `pyannote.audio` when its model/license and GPU requirements are acceptable. The browser should capture the user's microphone; host-wide system audio and arbitrary device enumeration should be treated as separate, deployment-specific capabilities.

## Product parity and deliberate differences

### Preserve

- One active live input session at a time unless multi-session support is explicitly added.
- Recording independent of transcription and AI delays.
- Interim text visually distinct from finalized text.
- Results associated with transcript sentence occurrences, not normalized sentence text. Repeated words in later segments are different occurrences.
- AI Prompt state serialized per prompt template.
- Jev queries batched per sentence.
- Speaker labels and voice candidates treated as best-effort session data, not biometric identity.
- Prompt enablement governing new work while prior accepted work remains visible.
- Markdown export as a durable record of the session.
- Playback following only when transcript rows have reliable audio positions.
- Nonblocking diarization and identity work so transcript text appears first.

### Change for the web/Linux environment

- The browser, not Docker, normally owns microphone permission and device selection.
- Browser permissions are origin-scoped and may require HTTPS or localhost.
- A browser tab cannot reliably enumerate or capture every Linux input device, PipeWire stream, or system output. Browser capture should be the default; host capture requires an explicit helper or server-side audio source.
- Linux has no Apple SpeechTranscriber equivalent. ASR model downloads, CPU/GPU capacity, language support, and model licenses become deployment concerns.
- Native Finder/System Settings actions become browser downloads, file pickers, and documented host configuration steps.
- A web app is multi-user by nature. Even a single-user deployment should define session ownership, authentication, upload limits, and data deletion.
- The UI should report whether a model is local, remote, CPU-backed, GPU-backed, loading, or unavailable.

## Architecture options

### Option A: Browser microphone plus server-side ASR — recommended

The browser requests microphone access using `getUserMedia`, sends PCM or encoded chunks over WebSocket, and the Docker service performs ASR, diarization, summaries, and AI work.

**Advantages**

- Works on Linux, macOS, and Windows clients.
- Centralizes models and exports in Docker.
- Enables GPU acceleration in one place.
- Keeps transcript and AI behavior consistent across clients.
- Avoids requiring users to install an audio runtime or model set.

**Costs and constraints**

- Browser audio permission and HTTPS must be handled correctly.
- Network latency affects live interim results.
- The server receives sensitive audio and must secure transport and storage.
- Device selection is limited to devices the browser exposes.
- A single server must schedule concurrent model work fairly.

### Option B: Browser capture plus client-side WASM ASR

The browser runs `whisper.cpp` or another WebAssembly/WebGPU model and sends transcript events rather than raw audio where possible.

**Advantages**

- Audio can remain on the client.
- Server CPU/GPU requirements are much lower.
- Offline or disconnected operation is possible after model download.

**Costs and constraints**

- Large model downloads and browser memory limits.
- Performance varies significantly by browser and hardware.
- Diarization and voice embeddings are much harder to run well in-browser.
- Model loading and WebGPU support need a compatibility matrix.
- Cross-browser output may be less consistent.

This is a good future privacy/offline mode, but not the first implementation target.

### Option C: Linux host capture agent plus web UI

A small Linux helper uses PipeWire/ALSA/PulseAudio to enumerate devices and capture system or arbitrary host audio, then streams it to the Docker service.

**Advantages**

- Best parity with the macOS device list.
- Can capture PipeWire nodes, loopbacks, virtual devices, and system monitor sources.
- Avoids relying on browser device enumeration for specialized workflows.

**Costs and constraints**

- Requires an installed native helper, reducing the simplicity of “Docker only.”
- Requires host audio permissions, user-session integration, and potentially PipeWire socket access.
- Packaging and distribution differ across distributions.
- The helper becomes a security-sensitive bridge into host audio.

This should be a separately installable capability, not a requirement for the base web app.

### Option D: Server-side audio source inside Docker

Docker is given access to a host audio socket or device, such as PipeWire, PulseAudio, or `/dev/snd`, and the service captures audio directly.

**Advantages**

- Useful for a server, kiosk, or dedicated recording machine.
- No browser microphone permission is needed for the server source.
- Can support system audio and fixed capture devices.

**Costs and constraints**

- Docker device/socket permissions are distribution-specific.
- `--privileged` is tempting but should be avoided.
- A remote browser user may not be near the server's microphone.
- Host audio session identity and socket authentication must be configured.
- Container portability is worse than browser capture.

Support this as a deployment profile (`server-audio`) after browser capture works.

### Option E: Remote transcription and diarization APIs

The Docker service uploads audio to a hosted provider and consumes results.

**Advantages**

- Minimal local model/GPU setup.
- Potentially high accuracy and broad language coverage.
- Easier first deployment on small Linux hosts.

**Costs and constraints**

- Audio leaves the deployment.
- Ongoing per-minute cost and provider availability.
- Provider-specific timestamps, diarization, rate limits, and retention policies.
- Requires secret management and clear privacy disclosure.

Implement this behind the same transcription/diarization interfaces as local engines. Do not make the product model depend on one provider.

## Audio capture choices on Linux

### Browser APIs

Use `navigator.mediaDevices.getUserMedia({audio: ...})` for the default live path. Use an `AudioWorklet` to obtain predictable PCM frames and calculate RMS/peak/clipping in the browser. `MediaRecorder` is simpler but produces containerized chunks and codec-dependent timing; it is better suited to upload recording than low-latency PCM streaming.

Recommended browser flow:

1. Request permission only when the user starts a live session.
2. Enumerate devices after permission is granted.
3. Let the user select a browser-visible `deviceId`.
4. Capture at the negotiated rate, then resample or normalize on the server.
5. Send sequence-numbered audio frames over an authenticated WebSocket.
6. Show client-side level data immediately while server transcript events arrive asynchronously.
7. Stop and flush the audio stream before finalizing the recording.

The server must not assume that the requested sample rate or channel count was honored. Every session should carry the actual capture format.

### PipeWire

PipeWire is the strongest Linux host-integration target for modern desktop distributions. It can expose microphones, Bluetooth devices, virtual sources, monitor streams, and routing graphs. Use native libraries or a helper process rather than exposing the PipeWire socket broadly to an untrusted application container.

PipeWire is appropriate for:

- A host capture agent.
- A dedicated server capture profile.
- System-output or application-loopback capture.

It is not a substitute for browser capture for users connecting to a remote Docker host.

### PulseAudio

PulseAudio remains common and may be present through PipeWire's compatibility layer. It can be supported by a helper or server profile, but it should not be the only native integration target.

### ALSA

ALSA provides low-level device access and is useful for dedicated hardware or minimal servers. Direct ALSA capture usually has weaker device/routing semantics than PipeWire and is not ideal for a general desktop device browser.

### WebRTC audio transport

A WebRTC track can replace a custom WebSocket for low-latency audio and network adaptation. It adds signaling, ICE/STUN/TURN, and lifecycle complexity but is attractive for remote clients, packet loss, and future multi-party sessions. Start with WebSocket PCM for a controlled LAN/single-user deployment; retain a transport interface so WebRTC can be introduced later.

### Audio format contract

Internally normalize live audio to mono, 16 kHz, signed float PCM for ASR/diarization unless a selected engine requires another format. Preserve the original or archival recording format separately. Never use the visualization stream as the authoritative recording or transcription stream.

## Transcription engine options

| Engine | Live ASR | File ASR | Offline | Diarization | Main tradeoff |
|---|---:|---:|---:|---:|---|
| `faster-whisper` / CTranslate2 | Yes | Yes | Yes | No | Strong quality and speed; Python/CUDA/runtime packaging required |
| `whisper.cpp` | Yes | Yes | Yes | No | Simple native deployment and CPU support; integration work for streaming/features |
| `whisperX` | Indirect | Yes | Yes | Via pyannote | Strong alignment/word timestamps; heavier batch pipeline |
| Vosk/Kaldi | Yes | Yes | Yes | Limited | Lightweight streaming; generally lower modern ASR quality |
| NVIDIA NeMo | Yes | Yes | Yes | Some models | Powerful GPU ecosystem; large operational footprint |
| Hosted API | Provider-dependent | Yes | No | Provider-dependent | Low local setup; privacy, cost, and availability concerns |
| Browser WASM/WebGPU Whisper | Yes | Yes | Yes | No | Private client-side path; browser variability and model size |

### Recommended ASR split

- **Live microphone:** `faster-whisper` small/base model on GPU when available, or `whisper.cpp`/CPU fallback. Use a VAD or short rolling windows and emit interim updates without treating them as final.
- **Imported files:** offline `faster-whisper` with word or segment timestamps. File processing can be faster than real time and should expose progress separately from transcription completion.
- **Fallback:** a hosted adapter or a smaller CPU model when local model resources are unavailable.

The product should expose engine status and model identity in diagnostics and exports. A transcription engine failure should not corrupt an already finalized recording.

### Sentence boundaries and timestamps

Whisper-style engines commonly return segments and word timestamps rather than Apple Speech sentence boundaries. Define a platform-neutral finalization layer:

- Keep decoder segments and word timestamps internally.
- Use punctuation plus a sentence splitter to produce complete sentence occurrences.
- Never queue interim or incomplete fragments for AI Prompts or Jev.
- Preserve `segmentID` and `sentenceIndex` keys exactly as the current occurrence model requires.
- Store audio-relative offsets for imported files and live recordings.
- Make the source of each timestamp explicit: audio offset, wall-clock anchor, or processing time.

## Diarization and voice identity options

### `pyannote.audio`

The most direct general-purpose option for speaker diarization. It offers strong pretrained pipelines but may require model access approval, a Hugging Face token, substantial memory, and GPU acceleration for comfortable performance.

Use it asynchronously when possible:

- Live transcript text appears first.
- Diarization updates annotate existing rows later.
- Final file diarization can refine labels after recording stops.
- Export includes both row annotations and a time-based speaker timeline.

### SpeechBrain

Provides speaker recognition and diarization building blocks with a broad Python ecosystem. It can be easier to customize than a single pipeline, but assembling VAD, embeddings, clustering, and alignment increases implementation work.

### NVIDIA NeMo

A strong option for GPU-oriented deployments and advanced diarization, but operationally heavier and less suitable as the default Docker image for CPU users.

### `whisperX` alignment + pyannote

Useful for file transcription when accurate word alignment and speaker attribution are more important than low latency. It is a good batch profile, not the first live-streaming implementation.

### Lightweight clustering

VAD plus speaker embeddings (for example, SpeechBrain ECAPA or resemblyzer-style embeddings) with online clustering can provide a lower-resource best-effort identity layer. Accuracy and speaker-change timing will be weaker than a dedicated diarization pipeline. Keep labels explicitly session-local (`Speaker 1`, `Voice 1`) and expose confidence/limitations.

### Identity model

Retain the current conceptual model:

```text
observed tuple = diarizer speaker slot + optional voice embedding identity
canonical display speaker = optional user name, with optional same-name merge
```

Do not persist biometric embeddings by default. If a future “save voice patterns” feature is added, require an explicit opt-in, encryption, retention/deletion controls, and a clear explanation that embeddings are not guaranteed identity proof.

## Web application stack options

### Backend

**Python + FastAPI — recommended**

- Good ecosystem for Whisper, pyannote, PyTorch, audio decoding, and background jobs.
- Native WebSocket support.
- Easy Docker GPU images and operational tooling.
- Pydantic models can define the JSON contract.

**TypeScript + Node.js**

- Strong frontend/backend type sharing and WebSocket ergonomics.
- Audio/model work usually moves to Python workers or native subprocesses.
- Good choice if the ML service is deliberately separate.

**Go/Rust gateway plus Python workers**

- Excellent long-running service and concurrency characteristics.
- Adds service boundaries and language complexity.
- Appropriate for a larger multi-tenant deployment, not the first migration.

### Frontend

**React + TypeScript** is the pragmatic default for a rich transcript grid, settings, playback controls, WebSocket state, and accessible forms.

Alternatives:

- Vue or Svelte for a smaller client bundle and simpler component model.
- Server-rendered HTML with progressive enhancement for a minimal CPU-only deployment.
- PWA packaging for installability, with the understanding that it does not grant extra host audio permissions.

Frontend state should model the current app's session objects rather than mirror backend internals: sources, recording, transcript segments, pause spans, prompt results, Jev results, playback, and speaker resolutions.

### Storage

| Need | Single-user default | Larger deployment options |
|---|---|---|
| Session metadata | SQLite volume | PostgreSQL |
| Audio and exports | Bind-mounted volume | S3/MinIO |
| Job queue | In-process asyncio queue | Redis + Celery/RQ/Arq |
| Events | WebSocket from process | Redis pub/sub or durable event log |
| Secrets | Docker secrets/.env outside repo | Vault/Kubernetes secrets |

Do not put API keys in browser local storage or Markdown exports. The current macOS implementation stores keys in UserDefaults; the Linux version should improve this by storing them server-side encrypted or using an external secret provider.

## Container and deployment profiles

### CPU single-container profile

- One web/API container.
- SQLite and `/data` bind mount.
- Small Whisper model.
- Optional local diarization disabled or queued after transcription.
- Browser microphone capture.
- Suitable for a laptop, home server, or evaluation.

### GPU Compose profile

- API container with CUDA/ROCm-compatible runtime as appropriate.
- Dedicated transcription/diarization worker.
- Model cache volume.
- Redis queue and PostgreSQL metadata store.
- Browser capture or host capture profile.
- Use `NVIDIA_VISIBLE_DEVICES`/Compose GPU reservations only in the GPU profile; CPU users should not need GPU packages.

### Production multi-user profile

- Reverse proxy terminating HTTPS.
- API replicas behind sticky or reconnect-safe WebSocket routing.
- Dedicated worker replicas with explicit concurrency limits.
- PostgreSQL, Redis, and S3-compatible storage.
- Authentication, per-user quotas, audit logging, retention policies, and metrics.
- Separate model-serving pool if model loading cost is high.

### Host audio profile

A separate Compose override or helper service receives a PipeWire/PulseAudio socket or a carefully scoped ALSA device. Document the exact host commands per distribution. Do not make the base image require `privileged: true`; expose only the required device/socket and group permissions.

### Model cache and licensing

Model weights should be downloaded at startup or during an explicit setup action into a persistent cache. Report download progress and checksum/version. Do not bake large weights into the default application image unless there is a compelling offline distribution requirement. Record model name, version, source, license, and runtime in session metadata.

## API and event contract

A transport-neutral API should include:

- `GET /api/capabilities` — browser capture, host capture, engines, models, diarization, GPU, export formats.
- `GET /api/sources` — browser/session sources and optional host sources.
- `POST /api/sessions` — create a recording/transcription session.
- `POST /api/sessions/{id}/recording/start` and `/stop`.
- `POST /api/sessions/{id}/transcription/start`, `/pause`, `/resume`, and `/stop`.
- `POST /api/files` — upload/import audio with size and format validation.
- `POST /api/files/{id}/transcribe` — start file processing.
- `GET /api/sessions/{id}/export/markdown` — generate/download Markdown.
- `GET /api/sessions/{id}/audio` — authenticated playback/range requests.
- `WS /api/sessions/{id}/events` — transcript, levels, state, diarization, AI Prompt, Jev, and job events.
- `WS /api/sessions/{id}/audio` or a WebRTC signaling endpoint — live capture transport.

Example event envelope:

```json
{
  "type": "transcript.segment.final",
  "sessionId": "…",
  "sequence": 42,
  "occurredAt": "2026-09-20T12:34:56Z",
  "payload": {
    "segmentId": "…",
    "sentenceIndex": 0,
    "text": "A finalized sentence.",
    "audioOffset": 12.84,
    "speakerId": "Speaker 1"
  }
}
```

Every client-visible event should include a session ID and monotonically increasing sequence number. On reconnect, the client should request events or a state snapshot from a known sequence so a temporary browser/network failure does not duplicate results or lose final transcript rows.

## Session and concurrency design

The current macOS app is effectively single-user and main-actor coordinated. The web version must make ownership explicit:

- Every session has an owner, lifecycle state, source, capture format, selected engine/model, and creation time.
- Audio ingestion, recording, and transcription have independent states.
- A session can continue recording if transcription or AI processing is delayed.
- Each prompt template has serialized stateful work, while unrelated prompt work may run concurrently.
- Jev requests batch all enabled queries for one sentence.
- Job queues must enforce global and per-user limits to prevent one large file from exhausting the server.
- Cancellation must stop new work, allow safe finalization of current audio, and preserve completed results.
- Browser reconnects must be idempotent; `start` and `stop` commands need request IDs or state checks.

Redis-backed jobs are optional for the single-container version but should be the migration path for long file transcription, diarization, summaries, and exports.

## UI mapping

| macOS surface | Linux web equivalent |
|---|---|
| Microphone/source sidebar | Browser device picker plus optional host-source list |
| File Sources | Upload/drop area and imported-file list |
| Live Transcript | Virtualized transcript table with interim/final rows |
| Recording Summary | Summary tab with streaming updates |
| Recent Recordings | Session/library view backed by `/data` or object storage |
| Settings | Web settings routes/modal; capability and model status visible |
| Finder reveal | Download/open URL or “show path” only for local server administrators |
| Apple permission flow | Browser permission prompt plus host-configuration instructions |
| Live graph | AudioWorklet client levels, with server health/queue indicators |
| Pause transcription | WebSocket command; recording remains active |
| Voice Identification pane | Right-side responsive panel or drawer |
| Export Markdown | Authenticated generated download |
| `/tmp/VoiceTranscribe.log` | Structured container logs plus optional downloadable session diagnostics |

Use a virtualized transcript list for long sessions. Keep auto-scroll/follow behavior separate from playback follow, just as the current app does. Playback should use the session audio URL and the same timeline abstraction; never infer imported-file positions from server processing timestamps.

## File and media handling

Use a dedicated decoder/normalizer such as FFmpeg, GStreamer, or PyAV inside a controlled container for broad input support. FFmpeg is the most practical default for WAV, M4A, MP3, FLAC, WebM, AVI, and other containers. Validate MIME type, extension, duration, channel count, and decoded frame limits before processing.

Recommended stages:

1. Upload to a temporary object or volume location.
2. Validate container and decodeability.
3. Normalize a transcription copy to mono/16 kHz PCM.
4. Keep the source file for playback when safe and permitted.
5. Write recording and transcript artifacts atomically.
6. Add checksums, duration, source metadata, and model metadata.
7. Enforce quotas and cleanup policies.

Never trust a client-provided filename or path. Generate collision-resistant IDs and display names separately.

## Security and privacy

Minimum requirements before exposing beyond localhost:

- HTTPS, including secure WebSockets.
- Authentication and session ownership.
- CSRF protection for cookie-based commands, or carefully scoped bearer tokens.
- Upload size, duration, and decompression-bomb limits.
- Path traversal protection and safe generated filenames.
- No API keys in browser code, logs, exports, or event payloads.
- Encryption at rest or documented filesystem controls for audio and transcripts.
- Configurable retention and “delete session and artifacts” operation.
- Redaction policy for logs; transcript text should not be logged by default.
- Rate limits for model tests, file uploads, and prompt/Jev requests.
- Dependency and model provenance tracking.
- Explicit disclosure when remote ASR/LLM providers receive audio or transcript text.

For local Docker use, bind the service to `127.0.0.1` by default. A reverse proxy and authentication are mandatory when binding to a LAN or public interface.

## Observability and diagnostics

Replace the single local trace file with structured JSON logs containing request/session/job IDs. Useful event families include:

- `capture.started`, `capture.stopped`, `capture.format`, `capture.error`.
- `audio.frame.received`, `audio.frame.dropped`, `audio.queue.depth`.
- `recording.started`, `recording.finalized`, `recording.write_error`.
- `transcription.started`, `transcription.partial`, `transcription.final`, `transcription.failed`.
- `diarization.started`, `diarization.update`, `diarization.failed`.
- `ai_prompt.queued`, `ai_prompt.started`, `ai_prompt.completed`, `ai_prompt.failed`.
- `jev.queued`, `jev.batch.started`, `jev.batch.completed`, `jev.failed`.
- `export.started`, `export.completed`, `export.failed`.

Expose operational metrics for active sessions, audio lag, dropped frames, queue depth, model load time, transcription real-time factor, GPU/CPU/memory use, and storage remaining. A health endpoint should distinguish process health, model readiness, queue availability, and storage readiness.

## Testing strategy

### Unit tests

Port the existing pure behavior first:

- Sentence splitting, occurrence identity, and duplicate suppression.
- Prompt substitutions and prompt-state serialization.
- Jev request batching and typed response parsing.
- Markdown export including speaker, AI, Jev, pause, summary, and file sections.
- Playback timeline mapping for anchored recordings and imported audio offsets.
- Canonical speaker merging and name editing rules.
- Filename safety, collision avoidance, and path validation.

### Integration tests

- WebSocket frame ordering and reconnect from a sequence number.
- Browser-format audio normalization.
- Recording finalization after transcription failure.
- Slow ASR consumer while recording continues.
- Model unavailable, download interrupted, and GPU absent paths.
- File upload/decode/normalization for supported formats.
- Concurrent sessions and queue limits.
- API-key failure and remote provider timeout.

### End-to-end tests

Run Playwright or an equivalent browser suite for:

- Permission denied and permission recovery.
- Device selection and live level display.
- Record + transcribe, pause/resume, and stop/finalize.
- File import and progress.
- Playback, scrub, timestamp jump, and follow highlighting.
- Prompt/Jev enablement and result association on repeated sentences.
- Markdown download and artifact contents.
- Reconnect after temporarily closing/reloading the tab.

Use deterministic fixture audio and fake ASR/LLM/Jev adapters for most CI tests. Keep model-backed tests as an opt-in job because weights and GPU availability make them unsuitable for every pull request.

## Migration plan

### Phase 0 — contracts and capability discovery

- Define platform-neutral session, source, transcript, result, speaker, playback, and export models.
- Add a capability document/API rather than assuming macOS capabilities.
- Decide whether the first deployment is localhost-only and single-user.
- Establish model and data licensing decisions.

### Phase 1 — vertical slice

- Create React/TypeScript client and FastAPI service.
- Add browser microphone capture, WebSocket audio upload, client levels, and a fake transcription adapter.
- Implement recording to a Docker volume and live/final transcript events.
- Add session state, reconnect behavior, and basic Markdown export.

### Phase 2 — local transcription and files

- Integrate `faster-whisper` or `whisper.cpp`.
- Add model cache/status and CPU fallback.
- Add file upload, FFmpeg/PyAV normalization, progress, and imported-file playback.
- Implement audio-relative timestamps and sentence occurrence keys.

### Phase 3 — product behavior parity

- Add summaries, AI Prompts, model endpoints, prompt state, queue limits, and Markdown AI sections.
- Add Jev configuration and per-sentence batching.
- Add pause/resume semantics and separate recording/transcription lifecycle.
- Add playback-following with an explicit timeline.

### Phase 4 — diarization and identity

- Add asynchronous pyannote/SpeechBrain adapter behind a capability flag.
- Add speaker timeline updates and transcript annotation.
- Add session-only embeddings, tuple correction, naming, and same-name merge.
- Add final file refinement without delaying live transcript text.

### Phase 5 — deployment profiles

- Publish CPU Compose and GPU Compose profiles.
- Add PostgreSQL/Redis/object-storage profile.
- Add optional PipeWire host capture agent/profile.
- Add authentication, retention, metrics, and secure reverse-proxy documentation.

### Phase 6 — optional privacy/offline modes

- Evaluate browser WASM/WebGPU ASR.
- Add a local-only mode that disables remote providers.
- Add encrypted local storage and explicit voice-pattern consent if that feature is pursued.

## Key decisions still requiring product input

1. **Primary capture:** browser microphone only, or must the first release capture host/system audio?
2. **Deployment scope:** localhost single user, trusted LAN, or internet-facing multi-user service?
3. **Privacy boundary:** must audio stay local, or are remote ASR/LLM providers acceptable as opt-in adapters?
4. **Hardware target:** CPU-only, NVIDIA CUDA, AMD ROCm, or all of them?
5. **ASR default:** fastest small local model, highest-quality local model, or hosted provider?
6. **Diarization:** required in the first release, or optional post-processing after transcription?
7. **Persistence:** ephemeral sessions, local library, or multi-user durable archive?
8. **Host helper:** is installing a PipeWire capture agent acceptable for full device parity?
9. **Authentication:** no auth on localhost, password/passkey for LAN, or full account system?
10. **Voice patterns:** session-only as today, or an explicit encrypted opt-in for reusable patterns?
11. **Compatibility:** target modern Chromium only initially, or Firefox/Safari support too?
12. **Model distribution:** download on first use, administrator-provisioned models, or prebuilt model images?

## Suggested initial decisions

For the lowest-risk first release:

- Localhost single-user Docker Compose.
- Browser microphone capture with WebSocket PCM frames.
- FastAPI + React/TypeScript.
- `faster-whisper` with a small/base model and CPU fallback.
- FFmpeg/PyAV for file normalization.
- SQLite plus a bind-mounted `/data` volume.
- In-process bounded queues, with Redis-compatible interfaces reserved for the next profile.
- Diarization disabled by default and added asynchronously as an optional capability.
- AI Prompt and Jev providers configured server-side; API keys never sent to the browser or exports.
- HTTPS instructions for non-localhost deployments.
- No host PipeWire access in the base container; document it as a later helper/profile.

This path delivers the core recording/transcription/export experience without making Docker users solve Linux audio routing, GPU drivers, distributed jobs, and biometric-data policy all at once.

## Definition of done for the first Linux release

- `docker compose up` starts a documented, health-checked service.
- A browser can request microphone access, show levels, and select an available input.
- Live recording continues when transcription, diarization, or AI work is delayed.
- Interim and finalized transcript events render correctly and survive reconnect.
- Imported audio can be normalized, transcribed, played, and followed using reliable audio offsets.
- Prompt and Jev results are keyed by sentence occurrence and exported to Markdown.
- Summary, pause, speaker, and file metadata are retained in the session record.
- The UI reports unavailable capabilities and model readiness clearly.
- Audio, transcript, and API secrets are protected by documented local/network controls.
- CPU-only operation works; GPU acceleration is an optional, tested profile.
- Unit, integration, and browser tests cover the critical session and export paths.

## Relationship to existing documentation

- `REQUIREMENTS.md` remains the product behavior source of truth and should be updated when Linux-specific behavior is selected.
- `ARCHITECTURE.md` remains authoritative for the current native macOS implementation; this document describes a future platform architecture rather than replacing it.
- `IMPLEMENTATION.md` should receive numbered implementation sections only when Linux work is actually implemented.
- `CHECKPOINT.md` should record which Linux phase is complete and which deployment profile was verified.
- `TODO.md` should record unresolved Linux risks or capabilities that were intentionally deferred.
