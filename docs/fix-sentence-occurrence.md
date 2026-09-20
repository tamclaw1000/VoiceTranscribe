# Sentence Occurrence Result Identity Fix

## Summary

Release `v2.4.42` fixed duplicate/misplaced AI Processing and Jev results by changing sentence-level result identity from normalized sentence text to a concrete transcript occurrence.

Before this change, both AI Processing and Jev deduplicated work with keys based mainly on normalized sentence text. That suppressed legitimate repeated speech such as two separate `Confirmed.` transcript rows, and it also made UI/export matching ambiguous because a result could attach to every row with the same text. The fix is to treat each finalized transcript segment's complete sentence as a `SentenceOccurrence` identified by:

- `segmentID`
- `sentenceIndex`
- `text`
- `timestamp`

This preserves repeated identical spoken sentences while still suppressing repeat submissions of the same segment occurrence.

## Root Cause

The previous implementation used normalized sentence text as the stable identity for per-sentence AI work:

- `AIPromptCoordinator` deduped prompt work by prompt-template ID plus normalized sentence text.
- `JevCoordinator` deduped query work by query ID plus normalized sentence text.
- Live transcript rendering matched result rows back to transcript rows by normalized text.
- Markdown export used the same text-based matching.

That was too coarse. In normal speech, repeated short sentences are common. If the speaker says `Confirmed.` twice, those are two distinct transcript events and should each be eligible for AI Processing and Jev. Text-only identity cannot distinguish them.

The bug also explained why the UI could appear to display multiple calls/results for the same transcription row: result lookup was text-based, so a result for one occurrence could match another row containing the same sentence.

## Changes Made

### AIPromptService.swift

Added `SentenceOccurrence` and routed finalized transcript segments through `AIPromptCoordinator.sentenceOccurrences(in:)`.

AI Processing dedupe changed from:

```swift
promptTemplate.id + normalizedSentence
```

to:

```swift
promptTemplate.id + segmentID + sentenceIndex
```

`AIPromptItem` now carries optional `segmentID` and `sentenceIndex` metadata so existing manually constructed or legacy in-memory items remain source-compatible.

The sentence parser was also hardened. The replacement scanner avoids splitting on:

- ellipses, such as `It appears to be... humanoid.`
- common abbreviations, such as `Mr.`, `Dr.`, and `Capt.`
- decimal-style periods
- punctuation-only fragments

### JevService.swift

Jev now uses the same `SentenceOccurrence` identity as AI Processing.

Jev dedupe changed from:

```swift
query.id + normalizedSentence
```

to:

```swift
query.id + segmentID + sentenceIndex
```

Jev still batches all enabled queries for one sentence occurrence into one TypeSafe System One request.

### Views.swift

Live transcript result lookup now prefers exact `segmentID` matching for both AI Processing and Jev. Normalized text matching remains only as a fallback for legacy items that do not carry occurrence metadata.

### MarkdownExportService.swift

Markdown export now uses the same matching behavior as the live UI:

1. Match AI/Jev results to a transcript segment by `segmentID`.
2. Fall back to normalized text matching only when an item has no `segmentID`.

This prevents a result for one repeated sentence from appearing in another repeated sentence's exported table row.

### VoiceIdentityService.swift

`VoiceIdentityService.swift` was force-added to Git during this closeout. The file was required by tracked diarization code, but the repo's case-insensitive ignore pattern hid new files under `Sources/`. Clean worktrees could not compile until this source file was tracked.

## Tests Added

The release added or updated tests covering:

- sentence parsing with ellipses, abbreviations, and decimal-like periods
- AI Processing suppressing duplicate submission of the same occurrence
- AI Processing preserving repeated identical sentences from different segments
- Jev suppressing duplicate submission of the same occurrence
- Jev preserving repeated identical sentences from different segments
- Markdown export matching AI results by segment occurrence before falling back to text

Verification for the release:

- `swift test` passed with 63 tests.
- `./build.sh` passed on the feature branch.
- `./build.sh` passed again after merge to `main`.

## Release References

- Feature commit: `ea11308 Preserve repeated sentence results by occurrence`
- Merge commit: `2c3340d Merge sentence occurrence result identity`
- Tag: `v2.4.42`

## Follow-Up Considerations

Text fallback is intentionally still present for legacy/runtime compatibility. New sentence-level result features should not rely on text identity. They should use the occurrence metadata path from the start:

- Settings/configuration
- Sidebar enablement
- Transcript-row rendering
- Markdown export

This matches the four-pillar feature checklist in `AGENTS.md`.
