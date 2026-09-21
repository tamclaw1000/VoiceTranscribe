# Linux Web Application Implementation Plan

This checklist turns `linux-version-analysis.md` into an incremental implementation plan. It targets a browser client, a Dockerized service, and optional local or remote speech-processing backends. Items should be checked only after implementation and verification.

## 1. Product and platform decisions

- [ ] Confirm that the first release targets a localhost, single-user Docker Compose deployment.
- [ ] Confirm browser microphone capture as the default live-input path.
- [ ] Decide whether host-wide system audio capture is required for the first release.
- [ ] Decide whether a Linux PipeWire helper is in scope or deferred.
- [ ] Choose the supported browsers and minimum versions.
- [ ] Choose CPU-only support requirements.
- [ ] Choose the first GPU target, if any, and document its driver/runtime prerequisites.
- [ ] Decide whether audio may be sent to hosted transcription providers.
- [ ] Decide whether remote LLM and Jev providers are opt-in only.
- [ ] Decide the first retention policy for audio, transcripts, model artifacts, and logs.
- [ ] Decide whether the first release is localhost-only or supports trusted-LAN access.
- [x] Choose the initial ASR backend: `faster-whisper`, `whisper.cpp`, or a hosted adapter.
- [ ] Decide whether diarization is required in the first release or an optional later capability.
- [ ] Decide whether voice identity remains session-only, as in the macOS app.
- [x] Decide whether model weights download on first use or are administrator-provisioned.
- [ ] Record the selected decisions in `linux-version-analysis.md`.

## 2. Repository and project structure

- [x] Create the Linux application directory structure without disturbing the native macOS target.
- [x] Add a Docker Compose project for the CPU single-container profile.
- [ ] Add separate frontend and backend source directories, or document the selected monorepo structure.
- [ ] Add a versioned API/event contract directory.
- [ ] Add test fixtures and deterministic sample audio references.
- [x] Add Linux-specific developer documentation under `docs/linux`.
- [x] Define environment-variable names and provide a sanitized example file.
- [x] Define the local persistent-data directory and backup expectations.
- [ ] Decide whether Linux versions are released independently from macOS versions.

## 3. Platform-neutral domain model

- [ ] Define a session model with owner, lifecycle state, source, format, timestamps, and selected engines.
- [ ] Define live-source and imported-file source models.
- [ ] Define recording state separately from transcription state.
- [ ] Define interim and finalized transcript segment models.
- [ ] Define sentence occurrence identity using `segmentID` and `sentenceIndex`.
- [ ] Define audio-relative offsets and timestamp provenance.
- [ ] Define transcription pause spans.
- [ ] Define summary state and paragraph models.
- [ ] Define AI Prompt configuration, result, queue state, and prompt-state data.
- [ ] Define Jev query configuration, typed answers, result state, and batch identity.
- [ ] Define diarization segments and session-only voice identity tuples.
- [ ] Define canonical speaker/name merging behavior.
- [ ] Define playback target, timeline rows, and followability.
- [ ] Define export metadata and artifact references.
- [ ] Add serialization/deserialization tests for all client-visible models.

## 4. Backend foundation

- [x] Create the HTTP service using the selected backend framework.
- [ ] Add configuration loading with safe defaults and validation.
- [ ] Add structured application logging.
- [ ] Add request IDs, session IDs, and job IDs to logs and responses.
- [x] Add `/health/live` for process liveness.
- [x] Add `/health/ready` for model, storage, and queue readiness.
- [x] Add `GET /api/capabilities`.
- [x] Add API error envelopes with stable error codes and user-safe messages.
- [ ] Add graceful startup and shutdown behavior.
- [ ] Add bounded request body and upload limits.
- [ ] Add API documentation generated from the backend contract.
- [x] Add a fake processing mode for development and browser tests.

## 5. Browser client foundation

- [x] Create the web application shell and routing structure.
- [x] Add session creation and session selection.
- [x] Add capability detection and unavailable-feature messaging.
- [x] Add a responsive source/sidebar layout.
- [ ] Add Live Transcript, Summary, Recent Recordings, and Settings views.
- [x] Add an accessible notification/error surface.
- [x] Add reconnecting WebSocket state with visible connection status.
- [x] Add event sequence tracking and state-snapshot recovery.
- [ ] Add a virtualized transcript list for long sessions.
- [ ] Preserve prompt and Jev result association by occurrence identity.
- [ ] Add browser-level tests for the basic navigation and empty states.

## 6. Browser microphone capture

- [x] Request microphone permission only when the user starts live capture.
- [x] Enumerate browser-visible audio devices after permission is granted.
- [x] Display device name, availability, and selected-device state.
- [ ] Handle permission denied and permission revoked states.
- [x] Use `AudioWorklet` or an equivalent low-latency capture path.
- [x] Calculate client-side RMS, peak, and clipping indicators.
- [x] Capture actual negotiated sample rate and channel count.
- [ ] Convert or resample frames as required by the transport contract.
- [x] Add sequence numbers and timestamps to audio frames.
- [ ] Stream frames over an authenticated WebSocket.
- [x] Flush pending frames before stopping a session.
- [x] Handle browser tab suspension, device unplug, and input-track termination.
- [ ] Add a browser fake-audio test source for deterministic tests.
- [x] Document HTTPS requirements for non-localhost microphone capture.

## 7. Recording pipeline

- [x] Implement a recording writer independent of transcription and AI jobs.
- [x] Preserve audio when transcription is slow or unavailable.
- [x] Store the actual capture format and session start/end timestamps.
- [ ] Generate collision-resistant artifact IDs and safe display filenames.
- [ ] Write recording data atomically or finalize it through a safe temporary path.
- [ ] Surface recording write failures immediately.
- [ ] Detect insufficient storage before recording starts.
- [ ] Monitor storage during recording.
- [ ] Finalize an incomplete recording safely if storage fills or the client disconnects.
- [ ] Add recording metadata with source, duration, format, checksum, and runtime details.
- [ ] Add a Recent Recordings/library endpoint and UI.
- [ ] Add download and authenticated playback for finalized audio.
- [ ] Test recording while transcription and downstream processing are delayed.

## 8. Audio file import and normalization

- [ ] Add browser upload and drag-and-drop controls.
- [ ] Enforce upload size, duration, and decoded-frame limits.
- [ ] Validate MIME type, extension, container, and decodeability.
- [x] Add FFmpeg, PyAV, or GStreamer to the controlled media-processing image.
- [x] Normalize ASR input to mono, 16 kHz PCM where required.
- [x] Preserve the original source when permitted for playback.
- [ ] Track normalization progress and failures.
- [x] Support the initial chosen format set: WAV, M4A, MP3, FLAC, and other selected formats.
- [ ] Decide whether AVI and video-container extraction are supported directly.
- [x] Add imported-file metadata and duration display.
- [x] Add file removal and cleanup behavior.
- [ ] Add tests for malformed, oversized, unsupported, and valid media.

## 9. Live transcription

- [x] Define a transcription adapter protocol.
- [x] Implement the selected local ASR adapter.
- [x] Implement a fake ASR adapter for tests and development.
- [x] Add model download, cache, version, and readiness handling.
- [ ] Add CPU fallback behavior when the preferred runtime is unavailable.
- [x] Normalize incoming audio frames for the selected ASR engine.
- [ ] Emit interim transcript events without treating them as final work.
- [x] Emit finalized segments with audio-relative offsets.
- [ ] Implement punctuation and sentence-boundary finalization.
- [ ] Preserve segment and sentence occurrence identities.
- [ ] Distinguish audio processing progress from transcript completion.
- [x] Add transcription pause/resume while recording continues.
- [x] Add cancellation and safe final drain behavior.
- [ ] Prevent stale events from a prior session entering a later session.
- [ ] Add metrics for audio lag, queue depth, real-time factor, and dropped frames.
- [ ] Test slow ASR consumers without stopping recording.

## 10. File transcription

- [x] Add a file-transcription job endpoint.
- [x] Run file ASR through an offline adapter where appropriate.
- [x] Report queued, loading, processing, finalizing, completed, and failed states.
- [x] Report progress only when a reliable denominator exists.
- [x] Preserve engine-reported word or segment audio offsets.
- [ ] Ensure file processing timestamps are never used as audio positions.
- [x] Allow playback before or after export only when the source file is finalized and readable.
- [x] Add retry behavior for recoverable model or worker failures.
- [ ] Add concurrent-job limits and per-user quotas.
- [ ] Test files that finish decoding before transcription and AI work finish.

## 11. Diarization and voice identity

- [ ] Define a diarization adapter protocol.
- [ ] Implement a capability-disabled path that leaves transcript text available.
- [ ] Evaluate `pyannote.audio`, SpeechBrain, and NeMo against CPU/GPU targets.
- [ ] Resolve model access, license, and token requirements.
- [ ] Implement asynchronous diarization updates.
- [ ] Align diarization time ranges with transcript audio offsets.
- [ ] Add session-local speaker slots.
- [ ] Add optional voice embeddings and confidence values.
- [ ] Keep embeddings in memory by default and discard them at session end.
- [ ] Add the observed `Speaker N / Voice M` tuple model.
- [ ] Add manual row correction and forced-new-voice behavior.
- [ ] Add naming, existing-name selection, reset, and same-name merge behavior.
- [ ] Add a speaker timeline to the session and Markdown export.
- [ ] Ensure diarization failure never blocks transcript display or recording finalization.
- [ ] Add tests for delayed updates, missing identity, over-splitting, and under-splitting.

## 12. Playback and transcript following

- [x] Add authenticated range-capable audio playback.
- [x] Add play/pause, scrubber, elapsed time, and duration.
- [ ] Define playback timeline rows shared by the transcript and player.
- [ ] Use recording wall-clock anchors when the service recorded the audio in real time.
- [ ] Use engine-reported audio offsets for imported files.
- [ ] Mark following unavailable when no reliable row placement exists.
- [ ] Make timestamp/row jumps seek without unexpectedly starting playback, except where product behavior explicitly requires play-from-row.
- [ ] Highlight and scroll the active transcript row during playback.
- [ ] Suspend bottom auto-scroll while playback follow is active.
- [ ] Preserve playback state across normal browser reconnects where possible.
- [ ] Test gaps, pause spans, missing offsets, and out-of-range seeks.

## 13. Summaries and AI Prompts

- [ ] Port summary paragraph accumulation and duplicate suppression.
- [ ] Add summary prompt/model configuration.
- [ ] Add summary progress, failure, retry, and export behavior.
- [ ] Define a server-side LLM endpoint configuration model.
- [ ] Support Ollama, OpenAI-compatible, OpenRouter, Anthropic, and Gemini adapters as selected.
- [ ] Keep API keys server-side and masked in settings.
- [ ] Implement supported prompt placeholders.
- [ ] Implement per-template `prompt-state`.
- [ ] Serialize stateful prompt work per template.
- [ ] Batch prompts targeting a shared global model where appropriate.
- [ ] Limit global and per-session LLM concurrency.
- [ ] Preserve completed results when prompts are later disabled.
- [ ] Add diagnostics/model-test behavior without exposing secrets.
- [ ] Add AI metadata and prompt-state sections to Markdown export.
- [ ] Test provider timeouts, malformed responses, retries, and cancellation.

## 14. Jev structured queries

- [ ] Define Jev configuration and query models in the web API.
- [ ] Add server-side API-key and base-URL configuration.
- [ ] Add Noul, Choice, and Score query editors.
- [ ] Validate Choice and Score criteria before dispatch.
- [ ] Add Jev query enable/disable controls in the AI Selection view.
- [ ] Batch all enabled Jev queries for one sentence occurrence into one request.
- [ ] Map typed answers back to query IDs.
- [ ] Add queued, running, completed, and failed states.
- [ ] Preserve results for repeated identical sentences at different occurrences.
- [ ] Add Jev result rendering beneath transcript rows.
- [ ] Add Jev metadata/results to Markdown export.
- [ ] Test missing keys, invalid criteria, API failures, and partial/missing answers.

## 15. Export and persistence

- [x] Implement a session metadata repository.
- [x] Start with SQLite and a bind-mounted data volume, if selected.
- [ ] Define a migration path to PostgreSQL.
- [x] Store audio, normalized audio, transcript, metadata, and export artifact references.
- [ ] Add authenticated Markdown export.
- [ ] Include details, recording rows, speaker labels/pairs, pauses, summary, AI results, Jev results, and file references.
- [ ] Exclude API keys, secrets, and sensitive diagnostics from exports.
- [ ] Make export generation idempotent and safe for concurrent requests.
- [x] Add session deletion and artifact cleanup.
- [ ] Add retention/expiry cleanup jobs.
- [ ] Test export contents manually against a completed fixture session.

## 16. Docker and deployment profiles

### CPU profile

- [x] Create the minimal application image.
- [x] Add a persistent `/data` volume.
- [x] Add SQLite configuration.
- [x] Add model-cache volume configuration.
- [x] Verify CPU-only startup without GPU packages.
- [x] Verify health checks and graceful shutdown.
- [ ] Document `docker compose up` and browser access.

### GPU profile

- [ ] Create the selected CUDA/ROCm runtime profile.
- [ ] Document host driver and container-runtime prerequisites.
- [ ] Add worker concurrency and GPU memory controls.
- [ ] Verify model loading and fallback behavior.
- [ ] Measure transcription real-time factor and memory use.
- [ ] Confirm CPU users are not forced to install GPU dependencies.

### Host-audio profile

- [ ] Decide whether PipeWire, PulseAudio, or ALSA is supported first.
- [ ] Create a narrowly scoped helper or override service.
- [ ] Avoid `privileged: true` unless explicitly justified and documented.
- [ ] Scope device/socket access and group permissions.
- [ ] Add host-source enumeration and source identity handling.
- [ ] Test device removal, routing changes, and server restart.
- [ ] Document distribution-specific setup and teardown.

### Multi-user profile

- [ ] Add PostgreSQL configuration.
- [ ] Add Redis and worker configuration.
- [ ] Add object-storage configuration.
- [x] Add reverse proxy and HTTPS configuration.
- [ ] Add authentication and session ownership.
- [ ] Add per-user limits, quotas, and retention.
- [ ] Verify WebSocket routing and reconnect behavior across replicas.

## 17. Security and privacy

- [x] Bind the default local deployment to localhost.
- [x] Require HTTPS for non-localhost microphone access.
- [ ] Add authentication before LAN/public exposure.
- [ ] Protect WebSocket commands and session ownership.
- [ ] Add CSRF protection or scoped bearer-token handling.
- [ ] Validate filenames and prevent path traversal.
- [ ] Enforce upload and decompression limits.
- [ ] Keep provider keys out of browser state, logs, events, and exports.
- [ ] Encrypt or otherwise protect stored audio and transcripts.
- [ ] Add explicit delete-session behavior.
- [ ] Redact transcript/audio content from routine logs.
- [ ] Document remote-provider data flows.
- [ ] Track dependency, model, and license provenance.
- [ ] Review container privileges and exposed ports.
- [ ] Add a security review before any public deployment.

## 18. Observability and operations

- [x] Add structured JSON logs with request/session/job IDs.
- [ ] Add capture, recording, transcription, diarization, AI, Jev, and export event families.
- [ ] Add active-session, queue-depth, audio-lag, dropped-frame, and storage metrics.
- [ ] Add model-load and real-time-factor metrics.
- [ ] Add CPU, memory, GPU, and worker metrics.
- [ ] Add a diagnostics view or downloadable redacted session diagnostics.
- [ ] Add log rotation and retention configuration.
- [ ] Add startup checks for storage, models, provider configuration, and queues.
- [x] Add alerts or clear operator messages for degraded capabilities.

## 19. Testing

### Unit tests

- [ ] Test platform-neutral model encoding and decoding.
- [ ] Test sentence splitting and occurrence identity.
- [ ] Test duplicate suppression without suppressing repeated occurrences.
- [ ] Test prompt placeholders and prompt-state ordering.
- [ ] Test Jev batching and typed response parsing.
- [ ] Test canonical speaker merging and naming rules.
- [ ] Test playback timeline mapping.
- [ ] Test export sections and secret exclusion.
- [ ] Test safe filenames, collision avoidance, and path validation.

### Integration tests

- [x] Test WebSocket frame order and reconnect recovery.
- [ ] Test browser-format normalization.
- [ ] Test recording while ASR is slow or unavailable.
- [ ] Test finalization after client disconnect.
- [ ] Test model download/cache failures.
- [ ] Test CPU fallback and GPU absence.
- [ ] Test media upload and decode failures.
- [ ] Test queue limits and cancellation.
- [ ] Test concurrent sessions.
- [ ] Test provider timeout and invalid-key behavior.

### Browser end-to-end tests

- [ ] Test microphone permission grant and denial.
- [ ] Test device selection and level visualization.
- [ ] Test record, transcribe, pause, resume, and stop.
- [ ] Test file upload and processing progress.
- [ ] Test playback, scrubbing, row jump, and follow highlighting.
- [ ] Test AI Prompt and Jev enablement.
- [ ] Test repeated identical sentences.
- [ ] Test Markdown download and contents.
- [ ] Test reload/reconnect without duplicate rows or results.
- [ ] Test responsive layout and keyboard accessibility.

## 20. Documentation and release readiness

- [x] Add Linux setup instructions for CPU Docker Compose.
- [x] Add model download and licensing instructions.
- [ ] Add optional GPU setup instructions.
- [x] Add browser permission and HTTPS troubleshooting.
- [ ] Add optional PipeWire/host-audio instructions.
- [ ] Add configuration reference and secret-management guidance.
- [ ] Add backup, retention, and deletion instructions.
- [ ] Add troubleshooting for audio lag, missing devices, model failures, and storage.
- [ ] Document supported input formats and limits.
- [ ] Document privacy behavior for local and remote providers.
- [ ] Update `linux-version-analysis.md` with decisions that changed during implementation.
- [ ] Update `REQUIREMENTS.md` when Linux behavior becomes product behavior.
- [ ] Update `ARCHITECTURE.md` when the Linux architecture is implemented.
- [ ] Update `CHECKPOINT.md` with the verified deployment profile.
- [ ] Record deferred risks in `TODO.md`.
- [ ] Publish a versioned Docker image or reproducible build instructions.
- [ ] Verify a clean install on a supported Linux distribution.
- [ ] Verify backup/restore of the persistent data volume.
- [ ] Verify CPU-only operation before calling the first release complete.

## 21. First-release acceptance checklist

- [ ] `docker compose up` starts a health-checked service using documented commands.
- [ ] The browser can request microphone access and display available browser-visible inputs.
- [ ] Live levels appear without waiting for ASR.
- [ ] Recording continues when ASR or downstream processing is delayed.
- [ ] Interim and finalized transcript rows are distinct.
- [ ] Browser reconnect does not lose or duplicate finalized rows.
- [ ] Imported audio can be validated, normalized, transcribed, and played.
- [ ] Imported transcript rows follow playback using reliable audio offsets.
- [ ] Pause/resume leaves a recording gap marker without transcribing paused audio.
- [ ] Summary, AI Prompt, and Jev features expose clear disabled/unavailable states.
- [ ] Results are keyed by sentence occurrence and exported correctly.
- [ ] API keys are not exposed in browser state, logs, or Markdown.
- [ ] Session deletion removes configured artifacts.
- [ ] CPU-only operation passes the documented smoke test.
- [ ] Security and privacy documentation is complete for the chosen deployment scope.
- [ ] Unit, integration, and browser end-to-end tests pass.
