# VoiceTranscribe

VoiceTranscribe is a native macOS SwiftUI application for enumerating sound-input sources, listening with a live level graph, recording audio, and displaying live transcripts through Apple Speech.

## Build

```sh
swift build
```

## Test

```sh
swift test
```

## Package a Local App Bundle

```sh
./scripts/package-app.sh
```

The packaged app is written to:

```text
dist/VoiceTranscribe.app
```

The local bundle includes microphone and speech-recognition permission descriptions and is ad-hoc signed for local development.
