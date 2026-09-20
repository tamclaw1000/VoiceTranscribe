# AGENTS.md - VoiceTranscribe Best Practices

Use this as the quick operating guide before making changes in this repo.

## Branching

- Develop every new user main request on a new feature branch and worktree. 
- Start from an up-to-date `main` unless the user explicitly asks to continue another branch.
- Use descriptive branch names, for example `feature/nonblocking-diarization` or `fix/prompt-template-editing`.
- Do not merge or push unless the user asks for it.
- Delete a branch as soon as it is merged (`git branch -d <branch>`) instead of leaving the ref behind; see Close Out Task step 8 for the full sequence.

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
- Keep visible UI labels on "AI Processing". The code was renamed off the historical `FactCheck` naming in v2.4.41 (`AIPromptService.swift`, `AIPromptCoordinator`, etc.) to match; do not reintroduce `FactCheck`-prefixed names.
- Keep prompt-state processing serial per prompt template.
- Use existing SwiftUI patterns in `Views.swift` and app orchestration patterns in `AppModel.swift`.

## Feature Surface Checklist

Any feature that produces a per-sentence or per-item result — AI Processing and Jev are the two existing examples — touches four separate technical pillars, not one. Before calling such a feature done, explicitly check all four, because each lives in a different file and none of them are reachable by browsing from the others:

1. **Settings tab** (`SettingsView` in `Views.swift`) — where the feature is configured.
2. **Sidebar section** (`ContentView.sourceList` in `Views.swift`) — where each item is enabled/disabled.
3. **Transcript-row rendering** (`TranscriptAIPromptPanel.transcriptRows` in `Views.swift`) — where live results are shown.
4. **Markdown export** (`MarkdownExportService.swift`, wired from `AppModel.saveTranscriptMarkdownToFile`) — where results are written to the exported record.

Pillar 4 is the one most likely to be missed: it is a separate call site, invoked by a save-panel button handler, not part of the live SwiftUI view tree the other three pillars share — so implementing 1–3 by mirroring existing UI will not naturally lead you to it. This happened for real with the initial Jev integration (v2.4.39; fixed in the next release) — treat that as the standing example of what "forgot a pillar" looks like, not a hypothetical.

When planning a new per-sentence/per-item result feature, name all four pillars in the plan up front, and verify each one — including a manual check that the exported Markdown actually contains the new feature's results — before considering the feature complete.

## Documentation

- Update `REQUIREMENTS.md` for product or UI behavior changes.
- Update `ARCHITECTURE.md` for technical workflow, data flow, dependency, or service changes.
- Update `ARCHITECTURE.md` whenever build scripts, launch flow, packaging behavior, dependencies, or version/build history change.
- Update `CHECKPOINT.md` to allow other agents/sessions to be able to quickly pick up the current state of the project.

## Git

- Check `git status -sb` before editing and before committing.
- Do not revert unrelated changes.
- Commit only once the build and relevant tests pass, or clearly note any verification that could not be run.
- There is one shared working tree per checkout — uncommitted changes (staged or not) follow you across `git checkout`, they don't stay "on" the branch you made them on. Before switching away from a branch with uncommitted work you want to keep separate, `git stash push` it first (and `git stash pop` it back after returning), rather than assuming the other branch's working tree will be clean.

## Close Out Task

Run this only when the user explicitly asks to close out, finish, or ship the current task — never automatically at the end of a change, and never merge or push without being asked (see Branching).

1. **Update docs.** Add a new numbered section to `IMPLEMENTATION.md` describing what changed. Add a row to `ARCHITECTURE.md`'s Version History table, and update any architecture prose the change affects (diagram, pipeline description, key design decisions, file table). Update `REQUIREMENTS.md` if product/UI behavior changed.
2. **Bump the version.** `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, matching the version/build named in the `IMPLEMENTATION.md`/`ARCHITECTURE.md` entries from step 1.
3. **Verify.** Run `swift test` (all tests pass) and `./build.sh` (clean build, no new warnings). Do not proceed to committing on a failing build or failing tests.
4. **Check in changes.** Stage and commit. New files under `Sources/VoiceTranscribe/` need `git add -f <path>` — `.gitignore`'s `sources/` entry matches `Sources/` too on this case-insensitive filesystem, so `git status` won't even list a new file there as untracked. Write a commit message explaining why, not just what.
5. **Merge to `main`.** `git checkout main`, `git fetch origin main` and confirm it still matches `origin/main` before merging (someone else, or you in an earlier session, may have moved it). `git merge --no-ff <branch> -m "Merge <description>"` — this repo's history uses explicit merge commits, not fast-forwards or squashes.
6. **Tag the release.** `git tag -a v<version> -m "v<version> - <one-line summary>"`.
7. **Push.** `git push origin main --follow-tags`.
8. **Delete the branch.** Remove the now-merged branch so dead refs don't accumulate: `git branch -d <branch>`, plus `git push origin --delete <branch>` if it was ever pushed. Use plain `-d`, never `-D` — it refuses to delete anything not fully merged, so it cannot silently drop work. Deleting the label loses nothing: the merge commit's second parent is the old branch tip, so `git branch <branch> <merge-sha>^2` rebuilds it at any time. If the branch is checked out in another worktree, `git -C <worktree> checkout --detach` frees the name without disturbing that worktree's files or build cache.
