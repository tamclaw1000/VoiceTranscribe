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
- Speech APIs: Apple SpeechTranscriber and SpeechAnalyzer by default, with a design that can support alternate transcription engines later.

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
- Auto-scroll by default while allowing the user to scroll back without fighting the UI.
- Show a clear empty state before speech is detected.

Optional transcript metadata:

- Timestamp per finalized segment.
- Confidence score, if available.
- Source name.
- Session start/end time.

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
- Request sound-input recording permission the first time the app touches a recording device.
- Cache the resulting permission state after the first recording-device access so later listen, record, and transcribe actions can use the cached state until macOS reports a change.
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

## 14. Open Questions

- Should the app support multiple simultaneous active input sources in version 1?
- Should recordings default to compressed `.m4a` or lossless `.wav`/`.caf`?
- Should transcription be local-only, Apple Speech-based, cloud-based, or pluggable?
- Should `HHMMSSS` in the filename mean seven total characters or millisecond precision?
- Should transcripts be saved automatically for every recording or only when Transcribe is active?
