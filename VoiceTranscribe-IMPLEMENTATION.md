# VoiceTranscribe Implementation Checklist

This checklist converts `VoiceTranscribe-REQUIREMENTS.md` into implementation work for a native Swift macOS application.

## 1. Project Setup

- [x] Create a new macOS app project named `VoiceTranscribe`.
- [x] Use Swift as the implementation language.
- [x] Use SwiftUI for the primary UI.
- [x] Add AppKit bridges only where SwiftUI is insufficient.
- [x] Set the minimum supported macOS version.
- [x] Add microphone usage description to `Info.plist`.
- [x] Add speech recognition usage description to `Info.plist`.
- [x] Define app sandbox and entitlement requirements.
- [x] Add file access entitlement strategy for saving recordings.
- [x] Create a dedicated app group or support directory only if needed.
- [x] Establish project folders for UI, audio, transcription, persistence, settings, and tests.

## 2. Architecture

- [x] Define a `SoundInputSource` model.
- [x] Define a `CaptureSessionState` model.
- [x] Define a `RecordingSession` model.
- [x] Define a `TranscriptSegment` model.
- [x] Define an `AudioDeviceService` responsible for enumerating devices.
- [x] Define an `AudioCaptureService` responsible for source capture.
- [ ] Define an `AudioBufferCoordinator` responsible for distributing captured audio.
- [ ] Define a `VisualizationService` responsible for level and waveform data.
- [x] Define a `RecordingService` responsible for file output.
- [x] Define a `TranscriptionService` protocol.
- [x] Implement an Apple Speech based transcription service.
- [ ] Define a `SessionStore` or persistence layer for metadata.
- [x] Keep capture, file writing, transcription, and UI updates on separate execution paths.

## 3. Permissions

- [x] Request microphone permission before starting capture.
- [x] Request speech recognition permission before starting transcription.
- [x] Show permission state in the UI.
- [x] Handle microphone permission denied state.
- [x] Handle speech recognition permission denied state.
- [x] Provide a button or link to macOS Settings when permissions are missing.
- [x] Prevent capture actions from silently failing when permission is unavailable.

## 4. Input Source Enumeration

- [x] Enumerate built-in microphone devices.
- [x] Enumerate USB microphone devices.
- [x] Enumerate Bluetooth microphone devices.
- [x] Enumerate external audio interfaces.
- [x] Enumerate aggregate input devices.
- [x] Enumerate virtual audio input devices.
- [x] Capture stable device identifier.
- [x] Capture display name.
- [x] Capture manufacturer when available.
- [x] Capture channel count.
- [x] Capture available or current sample rate information.
- [x] Capture whether the device is the system default input.
- [ ] Capture availability and permission-related state.
- [x] Listen for device connect, disconnect, rename, and default-device changes.
- [x] Refresh the UI when the device list changes.
- [x] Handle the no-input-devices state.

## 5. Main Window UI

- [x] Build a primary source list or table.
- [x] Show source name for each input.
- [x] Show device type or transport when available.
- [ ] Show current availability state.
- [ ] Show input activity indicator.
- [x] Add Listen action per source.
- [x] Add Record action per source.
- [x] Add Transcribe action per source.
- [x] Show active session state per source.
- [x] Make actions disable correctly when unavailable.
- [x] Ensure list updates do not interrupt active source display.
- [x] Keep controls keyboard accessible.

## 6. Capture Session Lifecycle

- [x] Start capture for a selected source.
- [x] Stop capture for a selected source.
- [x] Handle one active source at a time for version 1 unless multi-source capture is explicitly chosen.
- [x] Reuse one capture path for listen, record, and transcribe consumers.
- [x] Keep capture running while any consumer is active.
- [x] Stop capture only after all consumers for the source have stopped.
- [ ] Handle device removal during active capture.
- [x] Recover cleanly after capture start failure.
- [x] Publish session state changes to the UI.

## 7. Internal Buffering

- [ ] Implement a capture buffer for incoming audio frames.
- [x] Fan out buffered audio to visualization, recording, and transcription consumers.
- [x] Use bounded memory for long sessions.
- [x] Prioritize recording integrity over visualization and transcription.
- [ ] Implement backpressure handling for slow transcription.
- [x] Implement overflow handling for visualization buffers.
- [x] Implement overflow warning state for the UI.
- [x] Ensure file writing does not block audio capture.
- [x] Ensure transcription processing does not block audio capture.
- [ ] Add metrics for buffer depth and dropped non-critical frames.

## 8. Listen Mode

- [x] Start capture when Listen is selected.
- [x] Stop listen consumer when Listen is toggled off.
- [x] Compute current amplitude or RMS level.
- [x] Compute recent waveform or level history.
- [x] Detect and display clipping or peak events.
- [x] Throttle visualization updates to a stable UI frame rate.
- [x] Render a live sound graph.
- [x] Keep listen mode from writing files.
- [ ] Keep listen mode responsive during device changes.

## 9. Recording Mode

- [x] Start a recording session when Record is selected.
- [x] Capture the recording start timestamp.
- [x] Create a recording basename from timestamp and source slug.
- [x] Buffer audio before writing to disk.
- [x] Write audio asynchronously.
- [x] Stop recording when Record is toggled off.
- [x] Capture the recording end timestamp.
- [x] Finalize and close the audio file.
- [x] Save transcript file when transcription was active.
- [x] Save optional metadata file.
- [x] Surface disk write failures.
- [ ] Surface low disk space failures.
- [ ] Verify long recording sessions remain responsive.

## 10. File Naming

- [x] Implement filesystem-safe source slug generation.
- [x] Implement start timestamp format `YYYYMMDDHHMMSS`.
- [x] Decide final interpretation of end timestamp format `HHMMSSS`.
- [x] Implement end timestamp format consistently.
- [x] Use the same basename for audio, transcript, and metadata files.
- [x] Add audio file extension based on selected format.
- [x] Add transcript file extension.
- [x] Add metadata file extension if metadata sidecars are enabled.
- [ ] Prevent filename collisions.
- [x] Add unit tests for timestamp formatting and slug generation.

## 11. Transcription Mode

- [x] Define `TranscriptionService` protocol.
- [x] Implement Apple Speech transcription adapter.
- [x] Start capture when Transcribe is selected.
- [x] Send buffered audio chunks to the transcription service.
- [x] Receive interim transcript results.
- [x] Receive finalized transcript results.
- [x] Stop transcription cleanly when Transcribe is toggled off.
- [x] Handle transcription engine unavailable state.
- [x] Handle transcription authorization failure.
- [x] Handle transcription lag without interrupting recording.
- [x] Save transcript output when recording is active.
- [x] Keep the design open for alternate transcription engines.

## 12. Live Transcript UI

- [x] Create a live transcript panel.
- [x] Render finalized transcript text.
- [x] Render interim transcript text with distinct styling.
- [x] Preserve finalized text while interim text changes.
- [x] Auto-scroll when the user is already near the bottom.
- [ ] Stop forcing scroll when the user scrolls back.
- [x] Show a clear empty state before speech is detected.
- [ ] Optionally show timestamps per finalized segment.
- [ ] Optionally show confidence where available.
- [x] Keep transcript updates incremental and non-blocking.

## 13. Settings

- [x] Add default output folder setting.
- [x] Add audio format setting.
- [x] Add transcription engine setting.
- [x] Add save-transcripts-automatically setting.
- [x] Add start-transcription-with-recording setting.
- [x] Add visualization sensitivity setting.
- [x] Add temporary buffer cleanup setting if temporary files are used.
- [x] Persist settings across app launches.
- [ ] Validate inaccessible output folders.

## 14. Error Handling

- [x] Handle no input devices.
- [ ] Handle unsupported device format.
- [ ] Handle device removal during listen.
- [ ] Handle device removal during recording.
- [ ] Handle device removal during transcription.
- [x] Handle microphone permission denial.
- [x] Handle speech recognition permission denial.
- [x] Handle transcription engine failures.
- [x] Handle disk write failures.
- [ ] Handle low disk space.
- [x] Handle buffer overflow.
- [x] Present recoverable errors without crashing.
- [ ] Log technical details for diagnostics.

## 15. Performance Work

- [ ] Measure capture startup latency.
- [ ] Measure stop/finalize latency.
- [ ] Measure listen graph latency.
- [ ] Measure transcript update latency.
- [ ] Measure memory usage during long recordings.
- [ ] Measure CPU usage during listen only.
- [ ] Measure CPU usage during record and transcribe.
- [x] Throttle UI updates where needed.
- [x] Avoid heavy work on the main actor.
- [ ] Add stress test for slow transcription consumer.
- [ ] Add stress test for slow disk writes.

## 16. Testing

- [ ] Unit test source model mapping.
- [x] Unit test timestamp formatting.
- [x] Unit test source slug generation.
- [x] Unit test recording basename generation.
- [x] Unit test transcript segment merging.
- [x] Unit test buffer overflow behavior.
- [ ] Unit test backpressure behavior.
- [ ] Integration test device enumeration where possible.
- [ ] Integration test capture lifecycle with a mock audio source.
- [ ] Integration test recording file creation.
- [ ] Integration test transcript file creation.
- [ ] UI test source list display.
- [ ] UI test permission denied states.
- [ ] UI test listen, record, and transcribe action state changes.

## 17. Packaging and Release

- [ ] Configure app icon.
- [x] Configure app category and bundle metadata.
- [x] Confirm entitlements for microphone, speech recognition, sandboxing, and file access.
- [x] Sign the application.
- [ ] Notarize the application if distributing outside the Mac App Store.
- [x] Create a first-run permission flow.
- [x] Create a short user-facing help page or README.
- [ ] Verify clean install behavior.
- [ ] Verify upgrade behavior if app settings already exist.

## 18. Version 1 Completion Criteria

- [ ] App launches successfully on supported macOS version.
- [ ] App lists currently available input sources.
- [ ] Source list updates after device connection changes.
- [ ] Listen mode shows a live sound graph.
- [ ] Record mode writes an audio file with the required basename.
- [ ] Record mode tracks start and end timestamps.
- [ ] Transcribe mode displays a live transcript.
- [ ] Record plus Transcribe saves transcript output alongside audio.
- [ ] Audio capture remains stable during transcription delays.
- [ ] UI remains responsive during long recordings.
- [ ] Permission failures are handled cleanly.
- [ ] Disk and device errors are handled cleanly.
- [x] Basic unit and integration tests pass.

## 19. v1.1. Implement Permission Requests

- [x] Request recording-device permission lazily the first time the app touches a recording device.
- [x] Cache microphone permission state after the first device-touch permission request.
- [x] Reuse cached permission state for Listen, Record, and Transcribe actions.
- [x] Refresh cached permission state when macOS reports an authorization-state change.
- [x] Avoid prompting for microphone access during passive source-list enumeration.
- [x] Show a clear first-run permission prompt path before capture begins.
- [x] Add tests for first-touch permission request behavior.
- [x] Add tests for cached permission state reuse.
