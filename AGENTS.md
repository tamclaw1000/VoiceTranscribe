# AGENTS.md - VoiceTranscribe Best Practices

Use this as the quick operating guide before making changes in this repo.

## Branching

- Develop every new user request on a new feature branch.
- Start from an up-to-date `main` unless the user explicitly asks to continue another branch.
- Use descriptive branch names, for example `feature/nonblocking-diarization` or `fix/prompt-template-editing`.
- Do not merge or push unless the user asks for it.

## Build And Test

- Run `./build.sh` for app builds. The script performs the required clean build path and refreshes `dist/VoiceTranscribe.app`.
- Run `swift test` before committing code changes.
- Use `./scripts/package-app.sh` only when explicitly refreshing the app bundle outside the normal build flow.
- Treat dependency warnings as separate cleanup unless they block the requested work.

## Versioning

- Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` for code changes.
- Record versioned work in `IMPLEMENTATION.md`; do not create a separate changelog.
- Add a matching row to the Version History table in `ARCHITECTURE.md`.
- Keep `ARCHITECTURE.md` current between builds as the project architecture notes and build-history document.

## Implementation

- Preserve Apple Speech as the main transcription path unless the request is explicitly about changing transcription engines.
- Keep diarization best-effort and nonblocking so transcript text appears as soon as Apple Speech produces it.
- Copy audio buffers before handing them to async consumers.
- Keep visible UI labels on "AI Processing"; only use historical `FactCheck` names when referring to existing type or trace names.
- Keep prompt-state processing serial per prompt template.
- Use existing SwiftUI patterns in `Views.swift` and app orchestration patterns in `AppModel.swift`.

## Feature Surface Checklist

Any feature that produces a per-sentence or per-item result — AI Processing and Jev are the two existing examples — touches four separate technical pillars, not one. Before calling such a feature done, explicitly check all four, because each lives in a different file and none of them are reachable by browsing from the others:

1. **Settings tab** (`SettingsView` in `Views.swift`) — where the feature is configured.
2. **Sidebar section** (`ContentView.sourceList` in `Views.swift`) — where each item is enabled/disabled.
3. **Transcript-row rendering** (`TranscriptFactCheckPanel.transcriptRows` in `Views.swift`) — where live results are shown.
4. **Markdown export** (`MarkdownExportService.swift`, wired from `AppModel.saveTranscriptMarkdownToFile`) — where results are written to the exported record.

Pillar 4 is the one most likely to be missed: it is a separate call site, invoked by a save-panel button handler, not part of the live SwiftUI view tree the other three pillars share — so implementing 1–3 by mirroring existing UI will not naturally lead you to it. This happened for real with the initial Jev integration (v2.4.39; fixed in the next release) — treat that as the standing example of what "forgot a pillar" looks like, not a hypothetical.

When planning a new per-sentence/per-item result feature, name all four pillars in the plan up front, and verify each one — including a manual check that the exported Markdown actually contains the new feature's results — before considering the feature complete.

## Documentation

- Update `REQUIREMENTS.md` for product or UI behavior changes.
- Update `ARCHITECTURE.md` for technical workflow, data flow, dependency, or service changes.
- Update `ARCHITECTURE.md` whenever build scripts, launch flow, packaging behavior, dependencies, or version/build history change.

## Git Hygiene

- Check `git status -sb` before editing and before committing.
- Do not revert unrelated changes.
- Commit only once the build and relevant tests pass, or clearly note any verification that could not be run.
