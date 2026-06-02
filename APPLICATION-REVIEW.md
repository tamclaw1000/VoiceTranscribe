# VoiceTranscribe — Application Review

**Date:** 2026-05-31  
**Version:** 1.3.4 (Build 8)  
**Reviewer:** Oswald (via Codex)

---

## Build & Tests: ✅ Pass

- `swift build` — clean, 0.13s
- `swift test` — all 10 tests pass

---

## What's Good

### Architecture Is Clean

Single capture path fans out to three independent consumers (listen, record, transcribe) via a consumer registry pattern. Good separation: `AudioCaptureService` owns capture, `RecordingService` owns file I/O, `TranscriptionCoordinator` owns transcription lifecycle. All services are `@MainActor` where appropriate.

### SpeechTranscriber Migration Is Solid

Moving from the broken-on-macOS-26 `SFSpeechRecognizer` to `SpeechAnalyzer` + `SpeechTranscriber` was the right call. Format conversion, model installation, and proper async stream setup are all handled correctly.

### Buffer Copying Discipline

Every buffer is deep-copied at every boundary — tap → process, process → consumers, consumer → async writer/analyzer. This is correct and necessary for Core Audio tap callbacks.

### Trace Infrastructure Is Excellent

JSON-line logging to `/tmp/VoiceTranscribe.log` with synchronous writes and stderr echo covers every lifecycle event, button press, audio level sample, and error. Great for debugging.

### Lazy Permission Model Is Well Thought Out

Device enumeration never triggers a mic prompt. `authorizeFirstRecordingDeviceTouch()` requests once, caches the result, and never re-prompts. Mock provider enables testability.

### ObservableObject Forwarding Fix (v1.3.1)

This is documented clearly in AGENTS.md and correctly implemented with Combine subscriptions in `AppModel.init()`.

### Documentation Is Thorough

REQUIREMENTS.md, IMPLEMENTATION.md (with 26 versioned sections), and AGENTS.md provide clear project knowledge.

---

## Issues & Gaps

### 1. Dead Setting: `visualizationSensitivity`

**Severity: Medium**

Defined in `AppSettings`, has a UI slider, but **never applied anywhere**. The display level calculation in `AudioCaptureService.displayLevel(forRMS:peak:)` is hardcoded:

```swift
return min(pow(blended, 0.35), 1.0)
```

Needs to accept a sensitivity/multiplier parameter and plumb `settings.visualizationSensitivity` through.

### 2. Device Removal During Active Capture

**Severity: High**

If a USB mic is unplugged during capture, `AVAudioEngine` will likely fire an error or stop the tap. There's no handler for `AVAudioEngineConfigurationChange` or `audioEngineConfigurationChange` notification, and no observer on the selected `AudioDeviceID`. The app would surface a cryptic error or hang rather than cleanly stopping and notifying the user.

### 3. Transcription Buffer Overflow Is Measured but Not Acted On

**Severity: Medium**

`TranscriptionCoordinator.consume()` caps `queuedDuration` at 10s for display purposes, but **continues to feed buffers to the transcription service regardless**. If the analyzer is backlogged, buffers pile up unbounded in memory. The requirements call for explicit backpressure handling. At minimum, the app should drop or throttle buffers when the queue is full.

### 4. Missing Integration Tests

**Severity: Medium**

All 10 tests are unit tests for pure functions and permission behavior. Missing:

- Integration test of capture lifecycle with mock audio
- Integration test of recording file creation
- Integration test of transcription pipeline
- UI tests for permission denied states
- Performance/stress tests for long recordings

### 5. RecordingService Doesn't Prevent Collisions

**Severity: Low**

`moveReplacingExisting` just clobbers the destination. If two recordings finish in the same second (unlikely but possible with the 7-char end timestamp at tenths precision), one silently overwrites the other. Append a counter or UUID when a collision is detected.

### 6. `analyzer.finalizeAndFinishThroughEndOfInput()` Is Fire-and-Forget

**Severity: Low**

In `AppleSpeechTranscriptionService.stop()`:

```swift
Task {
    try? await analyzer?.finalizeAndFinishThroughEndOfInput()
}
```

The `stop()` method returns before the analyzer finishes. If a user hits Transcribe again quickly, the new `start()` → `stop()` call sets `self.analyzer = nil` while the previous Task still has a reference. The old analyzer reference survives (retained by the Task), so this is safe, but the finalization is not guaranteed to complete before a new session starts. Consider tracking with a task handle and awaiting it.

### 7. Unchecked Implementation Items

A fair number of checklist items from `IMPLEMENTATION.md` remain open:

| Category | Count Open |
|----------|-----------|
| Device removal / error handling | 5 |
| Testing (integration, UI, stress) | 13 |
| Performance measurement | 8 |
| Packaging & release | 5 |
| Version 1 completion criteria | 10 |

The most impactful gaps: device removal during active capture, low disk space detection, unsupported device format handling, and validation of inaccessible output folders.

---

## File-by-File Notes

| File | Notes |
|------|-------|
| `AppModel.swift` | Clean orchestrator. Combine subscriptions correct. `ensureCapture()` permission gating is good. |
| `AudioCaptureService.swift` | Solid capture. `displayLevel()` needs sensitivity. Metrics handle all PCM formats. Consumer fan-out correct. |
| `AudioDeviceService.swift` | 2s polling is pragmatic. Transport type labels are complete. Missing: Core Audio property listener notifications for device changes. |
| `RecordingService.swift` | Async writer on `.utility` queue is correct. PCM config (16-bit interleaved) is VLC-compatible. Missing: collision handling. |
| `TranscriptionService.swift` | SpeechTranscriber pipeline is well done. Format conversion, model install, async stream orchestration all correct. | 
| `PermissionService.swift` | Lazy model is well implemented. Mock support enables testing. `openSystemPrivacySettings()` uses correct URL. |
| `Trace.swift` | Excellent. Synchronous writes, stderr echo, sorted keys. Covers all key events. |
| `Models.swift` | Clean data types. `TranscriptionBufferSnapshot.fillFraction` is properly clamped. |
| `Utilities.swift` | `FileNamer` handles slug generation and timestamp formatting correctly. `BoundedBuffer` tracks drops. `TranscriptDocument` merges correctly. |
| `AppSettings.swift` | Clean `@AppStorage` usage. `visualizationSensitivity` is stored but unused. |
| `Views.swift` | Good SwiftUI composition. SourceRow is clear. GraphPanel canvas rendering is efficient. TranscriptPanel auto-scroll is smart. SettingsView has proper folder picker. |
| `Tests/VoiceTranscribeTests.swift` | 10 good unit tests with fake permission provider. Missing integration and UI tests. |

---

## Summary

VoiceTranscribe is a well-structured v1 with solid fundamentals. The code quality is good — clean architecture, proper concurrency discipline, good tracing, and clear documentation.

**Top priorities before real-world use:**

1. Handle device removal during active capture (crash risk)
2. Fix dead `visualizationSensitivity` setting
3. Add buffer backpressure for transcription overflow (memory risk)
4. Detect and handle low disk space

**Nice-to-have for v1.4+:**

5. Integration tests for capture/recording/transcription pipelines
6. Performance benchmarks for long recordings
7. App icon and notarization
8. Filename collision avoidance
