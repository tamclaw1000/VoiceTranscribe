# VoiceTranscribe Application Review

**Date:** 2026-09-16
**Version:** 2.4.14 (Build 57)
**Reviewer:** Codex

## Build And Tests

- `swift test` passed: 42 tests.
- `./scripts/package-app.sh` completed and produced `dist/VoiceTranscribe.app`.
- `git diff --check` passed after the v2.4.6 implementation work.

## Current Feature State

VoiceTranscribe is now a transcription and AI processing app rather than a single-purpose fact-checking prototype. The main flow supports audio source selection, live levels, recording, transcription, live FluidAudio speaker diarization, recording summaries, Markdown export, and configurable prompt-driven AI processing.

The main window uses a left source pane with microphone, file-source, and prompt-template controls. The detail area is split into tabs for Live Transcript, Recording Summary, and Recent Recordings. The Live Transcript tab includes timestamp, speaker, a current-speaker status, text, AI results, copy, save, Markdown export, and auto-scroll controls. The Recording Summary tab includes copy and save controls.

## AI Processing

AI processing is controlled by named prompt templates. Each enabled prompt runs against finalized complete transcript sentences. Disabling all prompts disables AI processing.

Implemented behavior:

- Multiple named prompt templates with add, edit, remove, reset, and enable controls.
- Per-prompt model selection.
- A global prompt-model toggle that routes all prompts through one selected model.
- Batching of multiple prompt questions into one LLM call when a global prompt model is active.
- A processing queue capped at three simultaneous LLM calls.
- Per-template `{{prompt-state}}` accumulation for stateful prompts.
- Timestamped transcript context placeholders: `{{conversation}}`, `{{last-3}}`, `{{last-5}}`, and `{{last-10}}`.
- Provider support for Ollama, OpenAI-compatible chat completions, OpenRouter, Anthropic Messages, and Gemini `generateContent`.
- LLM diagnostics for the selected endpoint using `Hello, what is 10 * 20?`.

Historical Swift names still include `FactCheck` in several types and trace events, but visible UI should say "AI Processing".

## Documentation State

The durable docs now reflect the current app:

- `README.md`: current overview, features, live speaker diarization, AI processing, prompt placeholders, exports, build/test/package/launch commands, and logs.
- `REQUIREMENTS.md`: updated AI processing requirements, tabbed settings, prompt templates, LLM providers, batching, prompt state, auto-scroll, speaker diarization, and Markdown export behavior.
- `IMPLEMENTATION.md`: current versioned implementation checklist through v2.4.8.
- `AGENTS.md`: current handoff notes, architecture, AI gotchas, key files, and version history.

## Remaining Risks

Device removal during active capture remains a high-priority runtime risk. The requirements and checklist still call this out as incomplete for listen, record, and transcription paths.

Transcription backpressure is still incomplete. The app has bounded visualization behavior and non-blocking file writing, but slow transcription consumers can still require more explicit throttling or dropping behavior.

Speaker labels are currently best-effort live annotations based on the latest finalized FluidAudio diarization update. More precise overlap alignment needs transcript segment audio offsets or word-level timing.

Output-path validation and low-disk-space handling remain incomplete. Disk write failures are surfaced, but proactive validation would make long recordings safer.

Filename collision avoidance is still open. Current timestamp/source basenames are usually unique, but a counter or UUID suffix should be added before overwriting an existing destination.

`visualizationSensitivity` is still persisted and shown in Settings, but the display-level calculation remains hardcoded in `AudioCaptureService.displayLevel(forRMS:peak:)`.

## Test Gaps

The current test suite has good coverage for pure utilities, Markdown export, permission behavior, prompt substitution, LLM request routing, prompt enablement, batching, prompt state, and AI queue concurrency.

Higher-risk areas still need integration or UI coverage:

- Capture lifecycle with mock audio.
- Recording file creation and finalization.
- Transcription pipeline behavior under load.
- Diarization model availability, alignment accuracy, and long-session performance.
- Permission-denied and rebuild/relaunch flows.
- Device unplug during active capture.
- Long recording performance.

## File Notes

| File | Notes |
|------|-------|
| `AppModel.swift` | Central orchestrator for source actions, settings mutations, transcript handling, summary generation, AI queue reset, export, and nested object forwarding. |
| `AudioCaptureService.swift` | Owns AVAudioEngine tap, copied buffer fan-out, metrics, and graph history. `visualizationSensitivity` is not yet applied. |
| `AudioDeviceService.swift` | CoreAudio enumeration and polling. Active-device removal handling remains the main gap. |
| `RecordingService.swift` | Async file writing, basename generation, metadata, transcript save path. Needs collision protection and stronger disk-space handling. |
| `TranscriptionService.swift` | SpeechTranscriber pipeline and FluidAudio integration path. Analyzer ordering and buffer copying remain critical. |
| `DiarizationService.swift` | FluidAudio LS-EEND speaker timeline processing and live transcript speaker annotation. Alignment remains best-effort without audio-offset transcript segments. |
| `FactCheckService.swift` | Despite the historical name, this owns AI processing clients, provider adapters, prompt substitutions, batching, queueing, and prompt state. |
| `MarkdownExportService.swift` | Exports details, transcript rows with speaker labels and AI results, speaker timeline, summary, AI metadata/prompts, and file references without API keys. |
| `AppSettings.swift` | Persists audio, transcript, LLM endpoint, prompt template, global prompt model, and auto-scroll settings. |
| `Views.swift` | Main SwiftUI surface, tabbed detail area, tabbed settings, prompt controls, LLM controls, transcript and summary actions. |
| `Tests/VoiceTranscribeTests.swift` | 42 tests, including recent AI processing behavior. |

## Top Priorities

1. Handle device removal during active capture.
2. Add explicit transcription backpressure behavior.
3. Add audio-offset transcript timing to improve speaker/transcript alignment.
4. Validate output folders and low disk space before long recordings.
5. Apply `visualizationSensitivity` to the graph display calculation or remove the setting.
