# VoiceTranscribe Requirements

## 1. Overview

VoiceTranscribe is a native macOS application written in Swift. It enumerates available sound-input sources, lets the user listen to input visually, record selected sources, and display a live transcript while audio is being processed.

The application must prioritize a fast, responsive user experience. Audio capture should run continuously once a source is active, using internal buffering so UI updates, file writes, and transcription work do not block real-time input.

## 2. Goals

- Enumerate all available macOS sound-input sources.
- Present each input source with clear actions: listen, record, and transcribe.
- Provide a real-time sound visualization while listening.
- Record audio continuously using an internal buffer.
- Write recording and transcription output to files with start and end timestamps.
- Display a live transcript as speech is processed.
- Keep capture, visualization, file writing, and transcription responsive under normal desktop load.

## 3. Target Platform

- Platform: macOS 26 or newer.
- Language: Swift.
- UI framework: SwiftUI preferred unless AppKit is required for lower-level audio or window behavior.
- Audio APIs: Core Audio and AVFoundation where appropriate.
- Speech APIs: FluidAudio (Parakeet EOU) by default for responsive streaming transcription, with Apple SpeechTranscriber available as an alternate engine.

## 4. Core User Experience

### 4.1 Main Window

The main window must show all detected sound-input sources in a scannable list or table.

Each source row should include:

- Source name.
- Device type or transport, when available.
- Current availability state.
- Input activity indicator.
- Listen action.
- Record action.
- Transcribe action.

The UI should update when devices are connected, disconnected, enabled, disabled, or renamed.

### 4.2 Source Actions

Each input source must expose these actions:

- Listen: monitor the selected source and show visual audio activity.
- Record: persist captured audio and transcript output to disk.
- Transcribe: process captured audio into a live transcript without necessarily saving a recording unless recording is also active.

The app should allow at least one active source at a time. Multi-source simultaneous capture is desirable, but the first implementation may limit active capture to one source if this keeps the UX fast and reliable.

## 5. Functional Requirements

### 5.1 Enumerate Sound-Input Sources

The application must enumerate all possible sound-input sources available to macOS, including:

- Built-in microphone.
- External USB microphones.
- Bluetooth microphones and headsets.
- Audio interfaces.
- Aggregate devices.
- Virtual audio devices.

The app must detect changes without requiring restart.

For each source, the app should capture:

- Stable device identifier.
- Display name.
- Manufacturer, if available.
- Channel count.
- Supported sample rates, if available.
- Current default-input status.
- Permission or availability status.

### 5.2 Listen Mode

When the user selects Listen for a source, the app must:

- Start live audio capture from that source.
- Display a real-time visual sound graph.
- Show input levels with minimal latency.
- Continue updating the UI smoothly while audio capture runs.
- Allow the user to stop listening.

The visual sound graph should support at least:

- Current amplitude or RMS level.
- Recent waveform or level history.
- Clipping or peak indication.

Listen mode does not need to write audio to disk.

### 5.3 Record Mode

When the user selects Record for a source, the app must:

- Start a recording session using the selected input source.
- Buffer audio internally before writing to disk.
- Write captured audio to a durable file.
- Track the recording start timestamp.
- Track the recording end timestamp.
- Continue capture even if transcription processing lags temporarily.
- Allow the user to stop recording.
- Finalize the output file when recording stops.

The required output filename format is:

```text
YYYYMMDDHHMMSS-HHMMSSS-audiosource
```

Where:

- `YYYYMMDDHHMMSS` is the recording start timestamp.
- `HHMMSSS` is the recording end timestamp segment as requested.
- `audiosource` is a filesystem-safe slug derived from the source display name.

Recommended concrete filename pattern:

```text
20260530142317-1439052-built-in-microphone.m4a
20260530142317-1439052-built-in-microphone.txt
```

The audio and transcript files should share the same timestamp/source basename and use different extensions.

The implementation must define whether the end timestamp segment `HHMMSSS` means:

- `HHMMSSm`, one fractional second digit.
- `HHMMSSmmm`, millisecond precision.
- Another exact timestamp shape.

Until clarified, the recommended interpretation is `HHMMSSm` if the requested seven-character segment must be preserved, or `HHMMSSmmm` if millisecond precision is preferred.

### 5.4 Transcribe Mode

When the user selects Transcribe for a source, the app must:

- Capture audio from the selected source.
- Send buffered audio chunks to the transcription engine.
- Display the transcript live as text becomes available.
- Distinguish interim transcript text from finalized transcript text.
- Continue updating the transcript while audio is processed.
- Allow the user to stop transcription.

If Record and Transcribe are both active, the transcript should be saved alongside the audio recording.

### 5.5 Live Transcript Display

The live transcript view must:

- Show text while audio is being processed.
- Update incrementally without blocking audio capture.
- Preserve finalized text once confirmed.
- Visually distinguish active/interim text from finalized text.
- Preserve the user's scroll position as new transcript text is appended.
- Show a clear empty state before speech is detected.

Optional transcript metadata:

- Timestamp per finalized segment.
- Confidence score, if available.
- Source name.
- Session start/end time.

### 5.6 Recording Summary Display

The main window must include a running summary section for the current recording or transcription session.

The summary section must:

- Accrue finalized transcript sentences as they arrive.
- Organize accumulated sentences into readable paragraphs.
- Update without blocking audio capture, recording, transcription, or fact-checking.
- Reset when a new transcription session starts.
- Provide an editable summary prompt or instruction field in Settings.
- Persist the summary prompt across launches.
- Provide a reset action that restores the default summary prompt.

## 6. Performance and Responsiveness Requirements

The app must be designed so real-time capture remains stable even when transcription or file I/O is slower than incoming audio.

Required behavior:

- Audio capture runs on a real-time appropriate path.
- UI updates are throttled to avoid excessive rendering.
- File writes happen asynchronously.
- Transcription receives buffered chunks asynchronously.
- Backpressure is handled explicitly.
- Temporary transcription delay must not drop recording audio.
- The UI remains responsive during long recordings.

Target responsiveness:

- Source list interactions should feel immediate.
- Listen graph latency should be low enough to feel live.
- Starting and stopping listen/record/transcribe should complete quickly.
- Transcript updates should appear progressively as processing returns results.

## 7. Buffering Requirements

Audio must be buffered internally between capture and downstream consumers.

The buffering design should support:

- A capture buffer for raw or encoded audio frames.
- Independent consumers for visualization, file writing, and transcription.
- Bounded memory usage during long sessions.
- Recovery from temporary downstream stalls.
- Clear handling for overflow conditions.

If a buffer overflow occurs, the application must:

- Preserve recording integrity as the highest priority.
- Report degraded transcription or visualization if needed.
- Surface a non-blocking warning to the user.

## 8. Permissions and Privacy

The app must request and handle macOS microphone and speech-recognition permissions.

The app must:

- Explain why microphone access is required.
- Explain why speech recognition access is required.
- On first launch, if macOS reports microphone or speech-recognition permission as not determined, show the native permission dialogs before the user starts recording.
- After first-launch permission dialogs complete, restart the application automatically so the audio subsystem starts with the updated authorization state.
- Request sound-input recording permission the first time the app touches a recording device.
- Cache the resulting permission state after the first recording-device access so later listen, record, and transcribe actions can use the cached state until macOS reports a change.
- If a rebuilt or resigned app returns to a not-determined macOS permission state, request the native permission dialogs again even if the older first-launch flag exists.
- Handle denied permissions gracefully.
- Provide a route to macOS Settings when permissions are missing.
- Avoid transmitting audio to external services unless the selected transcription engine requires it and the user has opted in.

## 9. File Output Requirements

Recordings should be saved to a user-visible location, configurable in settings.

Each recording session should produce:

- Audio file.
- Transcript file when transcription is active.
- Optional metadata sidecar file.

Suggested formats:

- Audio: `.m4a` using AAC for compact storage, or `.caf`/`.wav` when lossless capture is required.
- Transcript: `.txt` for plain transcript, optionally `.json` for timestamps and metadata.
- Metadata: `.json`.

Each output should include or reference:

- Source identifier.
- Source display name.
- Start timestamp.
- End timestamp.
- Duration.
- Audio format.
- Transcription engine.

### 9.1 Markdown Export

The app must allow the user to export the current transcript session to a Markdown file.

The Markdown export must include:

- Details section.
- Recording section.
- Recording date and time.
- Recording location when known, or `Not specified` when the app has not collected a location.
- Recording table with one row per finalized transcript segment.

Required Markdown shape:

```markdown
# DETAILS

- Time of recording: start and end time
- Location of recording: location or Not specified

# RECORDING

| date time | length | text | AI result |
| --- | ---: | --- | --- |
```

The export should also include these sections when data is available:

- Summary: the current paragraph-form recording summary.
- AI result column: sentence-level fact-check results shown in the app, aligned with the transcript row they belong to.
- AI results: generated summary output, active AI endpoint metadata, selected model, and prompts used for generation.
- Files: paths to related audio, transcript, and metadata files.
- Audio source and transcription engine.
- Export timestamp.

The app must escape Markdown table delimiters in transcript and fact-check text so exported tables remain readable.

The Markdown export must not create a second fact-check table. Fact-check results belong in the single `# RECORDING` table. The AI results section must make clear whether AI and fact-checking were enabled at export time, which provider/model was selected, and what fact-check and summary prompts were used. API keys must not be exported.

## 10. Error Handling

The app must handle:

- No input devices available.
- Device removed during active capture.
- Microphone permission denied.
- Speech recognition permission denied.
- Transcription engine unavailable.
- Disk write failure.
- Low disk space.
- Buffer overflow.
- Unsupported device format.

Errors should be presented in plain language and should not crash the app.

## 11. Settings

The app should include settings for:

- Default output folder.
- Preferred audio format.
- Preferred transcription engine.
- Whether to save transcripts automatically.
- Whether to start transcription automatically when recording.
- Visualization sensitivity.
- Retention or cleanup policy for temporary buffers.

## 12. Non-Goals for Initial Version

The first version does not need to include:

- Audio editing.
- Speaker diarization.
- Cloud account sync.
- Multi-user collaboration.
- Advanced transcript search.
- Automatic meeting detection.

These can be considered future enhancements.

## 13. Acceptance Criteria

- The app lists all currently available macOS sound-input sources.
- Connecting or disconnecting an input device updates the source list.
- The user can start Listen on a source and see a live sound graph.
- The user can start Record on a source and stop it later.
- Recording creates output files using the required timestamp/source naming pattern.
- Recording output includes start and end timestamps.
- The user can start Transcribe and see live transcript text appear while audio is processed.
- Long-running recording remains responsive.
- Transcription delays do not block or stop audio recording.
- Permission denial states are handled without crashing.

## 14. v1.4.0 UI Simplification

### 14.1 Combined Listen + Transcribe

Listen and Transcribe are merged into a single button per source. Toggling it on starts capture with transcription always active; toggling it off stops both. There is no listen-only mode — transcription is always running when the source is active.

- The button label toggles between "Transcribe" and "Stop".
- The live sound graph remains visible while active.
- The live transcript panel updates while active.
- Stopping ends capture and transcription together.

### 14.2 Record as Checkbox

Recording is a separate toggle (checkbox) that can be enabled or disabled independently of transcription. When recording is enabled:

- A filename is displayed showing the current in-progress recording basename.
- Clicking the filename reveals it in Finder.
- When recording is stopped, the filename is replaced with the final basename for a brief period, then returns to no filename shown.
- Transcription text is saved alongside the recording when both are active.

### 14.3 Simplified Source Row Layout

Each source row shows:

- Source name, device info, and default indicator (unchanged).
- A Transcribe/Stop toggle button.
- A Record checkbox with filename display when active.
- Active state indicator.

## 15. v2.0.0 Fact-Check Pane

### 15.1 Fact-Check Pane Placement

The main window must display transcript and fact-check output in a single combined pane.

The combined pane should:

- Remain visually associated with the live transcript.
- Show fact-check results in the same order as the transcribed sentences.
- Preserve results after the related transcript sentence is finalized.
- Clearly show pending, checking, completed, and failed states.
- Avoid blocking live transcription, audio capture, or recording.

Transcript entries must use a grid layout:

- Line 1: Timestamp | Audio Source | Text
- Line 2: blank timestamp/source columns | Fact Check result

### 15.2 Sentence-Level Fact Checking

The app must fact-check finalized transcript sentences.

When a full sentence is available:

- Extract the finalized sentence from the transcript stream.
- Queue the sentence for fact-checking.
- Send only complete sentences to the fact-check engine.
- Do not fact-check live partial transcript fragments.
- Do not synthesize punctuation on partial transcript fragments just to make them eligible for fact-checking.
- Avoid repeatedly fact-checking the same sentence.
- Display the original sentence with its fact-check result.

Fact-check output should include:

- Verdict, such as supported, questionable, false, unverifiable, or not factual.
- Short explanation.
- Confidence or certainty level when available.
- Any notable assumptions or missing context.
- Error state if the local model fails or times out.

### 15.3 Local LLM Fact-Check Engine

Fact-checking must use a local Ollama-compatible LLM endpoint by default.

The default local model must be:

```text
igorls/gemma-4-12B-it-heretic-GGUF
```

The app must:

- Connect to a local Ollama HTTP API endpoint.
- Allow the user to configure multiple named LLM endpoints.
- Store each LLM endpoint with a display name, API type, base endpoint URL, model name, and optional API key.
- Allow the user to select which configured LLM endpoint is used for fact-check requests.
- Use the selected LLM endpoint and model for fact-check requests.
- Support Ollama-compatible, OpenAI-compatible, Anthropic Messages, and Gemini generateContent API shapes.
- Let the user view and edit the prompt template used for fact-check requests.
- Persist the prompt template across launches.
- Provide a way to restore the default fact-check prompt.
- Keep fact-checking local by default.
- Process fact-check requests asynchronously.
- Limit concurrent fact-check requests so the UI remains responsive.
- Surface a clear status when Ollama is unavailable, the model is missing, or a request times out.

### 15.4 Fact-Check Prompt Requirements

Each fact-check request must use a prompt that asks the model to evaluate the factual correctness of the transcribed sentence.

The prompt must be user-editable in Settings. If the edited prompt does not include a sentence placeholder, the app must append the transcript sentence automatically before sending the request to Ollama.

The prompt must instruct the model to:

- Treat the sentence as a possibly imperfect transcript.
- Check only factual claims present in the sentence.
- Avoid adding unrelated claims.
- Return structured output suitable for UI rendering.
- Mark subjective, opinion, command, filler, or non-factual text as not factual rather than false.
- Use unverifiable when the claim cannot be checked from the model's knowledge alone.

Recommended response schema:

```json
{
  "sentence": "original sentence",
  "verdict": "supported | questionable | false | unverifiable | not_factual",
  "confidence": "low | medium | high",
  "explanation": "short explanation",
  "notes": ["optional note"]
}
```

## 16. Open Questions

- Should the app support multiple simultaneous active input sources in version 1?
- Should recordings default to compressed `.m4a` or lossless `.wav`/`.caf`?
- Should transcription be local-only, Apple Speech-based, cloud-based, or pluggable?
- Should `HHMMSSS` in the filename mean seven total characters or millisecond precision?
- Should transcripts be saved automatically for every recording or only when Transcribe is active?
- Should fact-check results be saved alongside transcripts and recording metadata?
- Should the fact-check pane support multiple named prompt presets?
