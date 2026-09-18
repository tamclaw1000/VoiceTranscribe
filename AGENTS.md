# AGENT.md - VoiceTranscribe Best Practices

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

## Documentation

- Update `REQUIREMENTS.md` for product or UI behavior changes.
- Update `ARCHITECTURE.md` for technical workflow, data flow, dependency, or service changes.
- Update `ARCHITECTURE.md` whenever build scripts, launch flow, packaging behavior, dependencies, or version/build history change.

## Git Hygiene

- Check `git status -sb` before editing and before committing.
- Do not revert unrelated changes.
- Commit only once the build and relevant tests pass, or clearly note any verification that could not be run.
