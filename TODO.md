
# BUGS
- [x] Changing the speaker drop-down ends up changing the voice currently speaking
- [x] Application sometimes crashes when switching or toggling transcription
- [x] Application sometimes doesn't pick up sounds until after restart. This mostly happens on initial launch.
- [x] Typing a speaker name that matches another speaker's name merges that row into the other one while typing, and the type-in field loses focus
- [x] Not visually confirmed in the running app: sidebar tabs (v2.4.44), the Voice Identification pane with its existing-name dropdown and merge toggle (v2.4.45)
- [x] `.gitignore` had `sources/`, which on this case-insensitive filesystem also matches `Sources/`, so brand-new files under `Sources/VoiceTranscribe/` were silently ignored and needed `git add -f`. Fixed in v2.4.47 by deleting the rule: it matched no directory that exists here and none was ever committed, so it had outlived whatever it was added for. `/sources/` is not a working replacement — with `core.ignoreCase` every spelling still matches `Sources/` — so removal is the only fix at this level. While it lived it cost two files: `VoiceIdentityService.swift` (v2.4.42) and `AudioPlaybackService.swift` (v2.4.47), each shipped untracked until force-added.
- [x] Imported audio files play back but the transcript cannot follow them (v2.4.47). Fixed the same session: the rows' *timestamps* are processing time, but the engine also reports each row's position on the audio's own timeline, so imported files now follow and jump exactly (`IMPLEMENTATION.md` #111g). Verified on `samples/star-trek-first-120s.wav`: first line at 3.00s, last at 117.84s.
- [ ] Most tests still assert on background work using fixed `Task.sleep` budgets (13 sites), so the suite can flake under load. Only `aiPromptCoordinatorBatchesPromptQuestionsWhenEnabled` was hardened in v2.4.47 (`waitUntil`); the rest should follow.
- [ ] Not visually confirmed in the running app: the playback bar, the playhead highlight and centered follow scroll, and click-a-timestamp-to-play (v2.4.47)

# NEW FEATURES
- [ ] Save / Restore voice patterns.
- [ ] Color the graph according to the color of the Assigned Speaker.
- [x] Ensure all speakers have different colors.
- [x] In Voice Indentification tab, allow changing to known Speaker rather than only allowing name.
- [x] Add a toggle to merge all Speaker/Voice combinations assigned the same name into one speaker.
- [x] Add feature to allow loadinging of it's own recordings
- [x] Add feature to pause transcription.
- [x] Move sub-panes in the left-hand section into two tabs. One for the Microphones, and another for the AI selection. The AI selection should also show the sub-pane for the current recordings 
- [x] Show Speaker / Voice in the transcript display. Done in v2.4.47: the speaker cell shows the label on one line and the row's raw `Speaker N / Voice M` pair beneath it whenever the pair says something the label does not, and the Markdown export appends the pair to named rows (`IMPLEMENTATION.md` #110). Not yet seen rendering.
- [ ] Read audio directly from AVI files, without an ffmpeg step in front. Measured while scoping it, so none of this needs re-deriving: AVFoundation cannot open the AVI at all (`isReadable: false`, zero tracks, duration 0), so the existing `AVAssetReader` fallback throws and the app reports "Could not read …"; CoreAudio cannot open the extracted raw `.ac3` either (`afinfo` fails, `AVURLAsset` reports a track with no codecs and `startReading` fails with -12138). But the same AC-3 bitstream decodes fine inside `.mov`/`.mp4` (307,098 frames), and `AVAssetWriter` accepts an AC-3 format description (`canAdd: true`, 600 frames muxed and re-read). Plan: an in-app RIFF/AVI demux — the container's own codec tag is zeros, so the codec must be sniffed from the bytes — plus a remux to a temp file, then the existing decode path. `scripts/extract-audio` is the workaround until then.
