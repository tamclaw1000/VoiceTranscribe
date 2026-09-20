# Jev (TypeSafe System One) Integration

## Context

VoiceTranscribe currently has one AI backend concept — free-text LLM "AI Prompts" (Ollama/OpenAI/OpenRouter/Anthropic/Gemini) that run per finalized sentence and render prose verdicts under each transcript row. The user wants to add **Jev**, TypeSafe's "System One" API — a structurally different kind of AI call that answers narrow typed questions (Noul = yes/no probability, Choice = categorical selection, Score = ordered rubric) instead of generating text. This isn't a new provider on the existing LLM system (the wire format and result shape are fundamentally different — typed answers with confidence/probabilities, not prose), so it needs its own parallel data model, network client, and coordinator, built to match the *patterns* already established for AI Prompts (config-as-JSON-in-UserDefaults, coordinator-with-worker-pool, settings tab, sidebar checklist, per-row transcript rendering) rather than bolting onto FactCheckService.

Reference implementation: `~/projects/ai/jev/play1` (Streamlit harness). Docs: https://docs.typesafe.ai/introduction.

**Confirmed wire format** (read directly from the installed `typesafe_sdk` Python package — `_core/constants.py`, `_core/endpoints.py`, `_core/question_types.py`, `_core/response_types.py` — more reliable than doc prose):

- `POST {baseURL}/v1/systemone` (default baseURL `https://api.typesafe.ai`), `Authorization: Bearer <key>`, `Content-Type: application/json`.
- Request body: `{"state": <string>, "model": <string>, "questions": {"<id>": {"type": "noul"|"choice"|"score", "instructions": <string?>, "criteria": <varies>}}}`.
  - Noul criteria (optional): `{"true": <string?>, "false": <string?>}`.
  - Choice criteria (required): `{"<label>": "<description>", ...}` (≥2 entries).
  - Score criteria (required): `["<level 0 desc>", "<level 1 desc>", ...]` ordered, ≥2 entries.
- Response body: `{"model": string, "usage": {"input_tokens": int?, "output_tokens": int?}, "answers": {"<id>": {...}}}`.
  - Noul answer: `{"type":"noul","noul": <0-1 float>}`.
  - Choice answer: `{"type":"choice","choice": <label>,"confidence": <float>,"probabilities": {label: float}}`.
  - Score answer: `{"type":"score","score": <float>,"confidence": <float>,"legend": {"0": desc, ...},"probabilities": {"0": float, ...}}` (JSON object keys are always strings; decode as `[String: Double]`/`[String: String]`, no need to coerce to Int).
- Errors: HTTP 401 (bad key), 422 (validation), 429/529 (rate limit/overload) — surfaced as an error string, same pattern as `FactCheckError`.
- **Key insight for efficiency**: Jev's `questions` dict natively supports multiple typed questions in *one* request. Unlike the existing AI Prompts system (one HTTP call per prompt template per sentence, with opt-in batching), Jev integration should **always batch every enabled query for a given sentence into a single `system_one` call** — one round-trip evaluates all of them server-side. This reuses `FactCheckCoordinator`'s existing `batchGroupID` grouping mechanism, just unconditionally instead of opt-in.

API key handling: user confirmed — match the existing (insecure but consistent) pattern used by every other LLM endpoint: plaintext inside a JSON blob in `UserDefaults` via `@AppStorage`. No Keychain.

## Architecture patterns being mirrored (exact file:line references)

- **Config-as-JSON-array pattern**: `AIPromptTemplateConfiguration` (`AppSettings.swift:229-305`) — `Identifiable, Codable, Equatable` struct, `static sanitized(_:)` for dedupe/fill-blanks, persisted via `@AppStorage("...JSON") private var` + a computed get/set property (`aiPromptTemplates`, `AppSettings.swift:406-438`) that decodes/sanitizes on read and re-encodes on write.
- **Coordinator/worker-pool pattern**: `FactCheckCoordinator` (`FactCheckService.swift:732-1008`) — `@Published items`, dedupe by `"\(templateID)|\(normalizedSentence)"`, `maxConcurrentRequests = 3` worker pool, `nextQueuedBatch()` groups by `batchGroupID`, `enqueueTranscriptSegment(...)` called from `AppModel`'s `transcription.onFinalSegment` closure (`AppModel.swift:193-208`).
- **Networking pattern**: `OllamaFactCheckService` (`FactCheckService.swift:175-421`) — raw `URLSession.shared`, per-provider `URLRequest` builders, `Codable` request/response structs, HTTP-status + JSON-decode error handling via a `LocalizedError` enum (`FactCheckError`, line 1010).
- **Settings tab pattern**: `SettingsSectionTab` enum (`Views.swift:524-528`) + `TabView` in `SettingsView.body` (`Views.swift:1548-1579`), each tab a `ScrollView` wrapping a computed column property (`settingsModelColumn`/`settingsPromptColumn`, lines 1737-1797) that embeds a dedicated per-item settings view (`AIPromptTemplateSettingsView`, lines 665-775) using `stringBinding(for:keyPath:)`/`boolBinding(for:keyPath:)` helpers.
- **Sidebar checklist pattern**: `Section("AI Prompts")` in `ContentView.sourceList` (`Views.swift:102-108`) rendering `AIPromptSourceRow` (`Views.swift:386-428`) — a `Toggle` bound through an `AppModel` wrapper function.
- **Per-row transcript rendering pattern**: `TranscriptFactCheckPanel.transcriptRows` (`Views.swift:1142-1221`) — a second `GridRow` gated by `if isFactCheckEnabled { ... }` (the "hide empty AI processing" change from this session), rendering `ForEach(factChecks) { factCheckDetail(for: item) }`; low-level renderer `factCheckDetail(label:badge:color:text:)` (line 1237) is generic enough to reuse as-is (its name is fact-check-specific but its signature isn't).
- **AppModel wrapper pattern**: thin functions like `setAIPromptEnabled`/`updateAIPromptTemplate`/`addAIPromptTemplate`/`removeAIPromptTemplate` (`AppModel.swift:587-641`) — `objectWillChange.send()`, call into `settings.*`, emit a `Trace.event`.
- **Reset-on-restart pattern**: `factCheck.reset()` is called at every capture-restart site (`AppModel.swift:933` transcribe restart, `:1385` file transcription start) — grep `factCheck.reset()` for the full list and mirror each with `jev.reset()`.

Deliberate deviation from the mirrored pattern: `aiPromptTemplates` always seeds one default template (Ollama has a zero-config localhost default). Jev has no zero-config default (requires a real API key), so `jevQueries` starts **empty** by default — no seeded query. This also means, consistent with the "hide empty AI Processing" work just shipped, the new sidebar "Jev Queries" section and the transcript's Jev result block should only render when there's actually something to show.

## Implementation

### 1. Data model — `AppSettings.swift`

- `enum JevPrimitiveType: String, Codable, CaseIterable, Identifiable` — `.noul`, `.choice`, `.score`, with `displayName`.
- `struct JevChoiceCriterion: Identifiable, Codable, Equatable` — `id, label, description` (ordered array, not a dict, so the settings UI can edit rows in place).
- `struct JevQueryConfiguration: Identifiable, Codable, Equatable` — `id, name, isEnabled, primitiveType, instructions, noulTrueDescription, noulFalseDescription, choiceCriteria: [JevChoiceCriterion], scoreCriteria: [String]`. `displayName` computed (blank → "Jev Query N"). `static sanitized(_:)` mirroring `AIPromptTemplateConfiguration.sanitized` (dedupe IDs, fill blank names). `var isRunnable: Bool` (noul always true; choice needs ≥2 criteria with non-empty labels; score needs ≥2 non-empty levels) — used to skip malformed queries at dispatch time rather than crash/error.
- On `AppSettings`: `@AppStorage("jevAPIKey")`, `@AppStorage("jevBaseURL") = "https://api.typesafe.ai"`, `@AppStorage("jevModel") = "jev-latest"`, `@AppStorage("jevQueriesJSON") private`. Computed `jevQueries: [JevQueryConfiguration]` get/set (empty JSON → `[]`, no seeded default). `enabledJevQueries` (filter `isEnabled && isRunnable`). `isJevActive: Bool { !enabledJevQueries.isEmpty }`.
- CRUD on `AppSettings`: `updateJevQuery(_:)`, `addJevQuery()`, `removeJevQuery(id:)` (mirrors the AI-prompt trio; no "keep at least 1" floor needed since empty is a valid, intentional state here).

### 2. Networking + coordinator — new file `Sources/VoiceTranscribe/JevService.swift`

- Wire-format `Encodable`/`Decodable` structs for the request/response shapes above (private to the file, like `OllamaGenerateRequest` etc.).
- Public result model: `enum JevAnswer: Equatable` (`.noul(probability:)`, `.choice(selected:confidence:probabilities:)`, `.score(value:confidence:legend:probabilities:)`), `enum JevQueryState: Equatable` (`.queued/.checking/.completed(JevAnswer)/.failed(String)`), `struct JevResultItem: Identifiable, Equatable` (`id, sentence, queryID, queryName, batchGroupID, var state, createdAt`) — same shape as `FactCheckItem`.
- `protocol JevService { func evaluate(sentence: String, queries: [JevQueryConfiguration], apiKey: String, baseURL: String, model: String) async throws -> [String: JevAnswer] }` (keyed by query id) — one call answers every query for that sentence.
- `struct TypeSafeJevService: JevService` — builds the `POST /v1/systemone` request, `Authorization: Bearer`, decodes the response, maps `answers` back by query id. Missing-key/empty-key guard throws `JevError.missingAPIKey` before making the call (mirrors how other services fail fast on missing config).
- `enum JevError: LocalizedError` — `missingAPIKey, invalidResponse, httpStatus(Int, String?), missingAnswer(String)`.
- `@MainActor final class JevCoordinator: ObservableObject` — `@Published items: [JevResultItem]`, `isRunning`, `lastError`. `enqueueTranscriptSegment(_:enabled:queries:apiKey:baseURL:model:)`: dedupe key `"\(query.id)|\(normalizedSentence)"` (same normalization helper, reuse `FactCheckCoordinator.normalizedSentence`/`completeSentences` — they're already `nonisolated static`, callable cross-type), one `batchGroupID` per sentence shared by all its query items. Worker pool copied from `FactCheckCoordinator` (`maxConcurrentRequests = 3`, `nextQueuedBatch()` groups by `batchGroupID`), but the batch call is always the one `service.evaluate(sentence:queries:...)` — no per-item fallback branch needed since Jev's API is batch-native. `reset()` mirrors `FactCheckCoordinator.reset()`.

### 3. AppModel wiring — `AppModel.swift`

- `@Published var jev = JevCoordinator()`; add to the `objectWillChange` sink block (mirrors `factCheck.objectWillChange.sink`, `AppModel.swift:227-229`).
- In `transcription.onFinalSegment` (`AppModel.swift:193-208`), add a parallel call: `self.jev.enqueueTranscriptSegment(segment, enabled: self.settings.isJevActive, queries: self.settings.enabledJevQueries, apiKey: self.settings.jevAPIKey, baseURL: self.settings.jevBaseURL, model: self.settings.jevModel)`.
- Add `self.jev.reset()` next to every existing `self.factCheck.reset()` call site.
- New wrapper functions mirroring `AppModel.swift:587-641`: `setJevQueryEnabled(id:enabled:)`, `updateJevQuery(_:)`, `addJevQuery()`, `removeJevQuery(id:)` — each `objectWillChange.send()` + call `settings.*` + `Trace.event`. **Not** wired into `handleAIActivationChange`/`aiReachability` — that subsystem is scoped to the free-text LLM/AI-Prompts feature; Jev gets its own independent, simpler lifecycle (no "Test Active AI" style reachability ping for v1).

### 4. Settings UI — `Views.swift`

- `SettingsSectionTab` (`Views.swift:524-528`): add `case jevConfiguration`.
- `SettingsView.body` (`Views.swift:1548-1579`): add a 4th tab, `Label("Jev Configuration", systemImage: "cube.transparent")`, wrapping a new `settingsJevColumn` computed property (mirrors `settingsModelColumn`/`settingsPromptColumn`, lines 1737-1797).
- `settingsJevColumn`: one `GroupBox` with connection fields (`TextField` Base URL bound to `appModel.settings.jevBaseURL`, model `Picker`/custom-text hybrid like the play1 sidebar's `MODEL_OPTIONS` pattern, `SecureField` API Key bound to `jevAPIKey`), then a second `GroupBox` embedding a new `JevQuerySettingsView(compact: true)`.
- New `struct JevQuerySettingsView: View` mirroring `AIPromptTemplateSettingsView` (`Views.swift:665-775`): per-query card with Enabled checkbox + trash button, Name `TextField`, primitive-type `Picker`, Instructions `TextField`, and a `@ViewBuilder` criteria editor that switches on `primitiveType`:
  - `.noul`: two optional `TextField`s (true/false description).
  - `.choice`: `ForEach(choiceCriteria)` rows of (label `TextField`, description `TextField`, trash button) + "Add Option" button (array manipulation via a binding helper, same `stringBinding(for:keyPath:)` idiom generalized to array element bindings).
  - `.score`: `ForEach(scoreCriteria.indices)` rows of a single description `TextField` + trash button + "Add Level" button.
- "Add Jev Query" button → `appModel.addJevQuery()`.

### 5. Sidebar — `Views.swift` `ContentView.sourceList`

- Right after `Section("AI Prompts")` (`Views.swift:102-108`): `if !appModel.settings.jevQueries.isEmpty { Section("Jev Queries") { ForEach(appModel.settings.jevQueries) { query in JevQuerySourceRow(query: query).environmentObject(appModel).padding(.vertical, 3) } } }`.
- New `private struct JevQuerySourceRow: View` mirroring `AIPromptSourceRow` (`Views.swift:386-428`): `Toggle` bound through `appModel.setJevQueryEnabled(id:enabled:)`, row shows a distinct icon (e.g. `"questionmark.diamond"`) + `query.displayName` + `query.primitiveType.displayName` as the caption line (parallel to how `AIPromptSourceRow` shows the resolved LLM name).

### 6. Transcript row rendering — `Views.swift` `TranscriptFactCheckPanel`

- New parameters threaded from `ContentView.mainDetail`'s `TranscriptFactCheckPanel(...)` call (`Views.swift:164-190`): `jevResults: appModel.jev.items`, `isJevEnabled: appModel.settings.isJevActive`.
- New `jevResults(for segment:)` helper mirroring `factChecks(for:)` (`Views.swift:1257-1270`) — same normalized-sentence matching.
- In `transcriptRows` (`Views.swift:1142-1221`), append a second `if isJevEnabled { GridRow { ... } }` block right after the existing AI-Processing `GridRow`, structurally identical (interim → "Pending", empty → "Queued", else `ForEach(jevItems) { jevDetail(for: item) }`).
- New `jevDetail(for item: JevResultItem) -> some View`, switching on `item.state`/`JevAnswer` to produce label/badge/color/text, then **reusing the existing** `factCheckDetail(label:badge:color:text:)` renderer (`Views.swift:1237`, already generic despite its name) rather than duplicating the visual row code:
  - `.noul(p)`: badge = "Result", text = `"P(yes): \(p as %) "` + a one-line "far from 0.5 → confident / close to 0.5 → ambiguous" hint (mirrors the play1 UI's framing).
  - `.choice(selected, confidence, _)`: text = `"\(selected) (\(confidence as %) confidence)"`.
  - `.score(value, confidence, legend, _)`: text = `"\(value, 2dp) (\(confidence as %) confidence)"`, appending the nearest legend description if present.
  - `.failed(message)`: badge = "Failed", color `.red`.

### 7. Docs/version (per `AGENTS.md`)

- Bump `Resources/Info.plist` (`CFBundleShortVersionString`/`CFBundleVersion`).
- New numbered section in `IMPLEMENTATION.md`, new row in `ARCHITECTURE.md`'s Version History table.

### 8. Tests — `Tests/VoiceTranscribeTests/VoiceTranscribeTests.swift`

Single flat file, Swift Testing (`@Test func ...`), no `XCTest`. Add tests mirroring the existing `factCheck*`/`llmEndpointConfiguration*` tests (lines 570+, 117+):
- `JevQueryConfiguration.sanitized` dedupes/fills blanks (mirrors `promptTemplateSanitizerPreservesEditableSpaces`, line 99).
- Request-body encoding for each primitive type produces the right `criteria` shape (noul optional dict / choice dict / score array).
- Response decoding for each answer type (`noul`/`choice`/`score` JSON fixtures → correct `JevAnswer` case).
- `JevCoordinator.enqueueTranscriptSegment` batches all enabled queries for one sentence under a shared `batchGroupID` and dedupes on resubmission (mirrors `factCheckCoordinatorQueuesOneItemPerEnabledPrompt`/`BatchesPromptQuestionsWhenEnabled`).

## Verification

- `swift test` — all existing 52 tests plus new Jev tests pass.
- `./build.sh` — clean build, no new warnings.
- Manual pass via the `run` skill (as done for the "hide empty AI Processing" feature): set a real `jevAPIKey`/`jevBaseURL` (from `~/projects/ai/jev/play1/.env`, entered directly into Settings — never write the raw key into app source, docs, or commit messages), add one query of each primitive type, run a sample transcription, confirm: Settings tab renders all three criteria editors correctly; sidebar "Jev Queries" section appears only once a query exists; transcript rows show the Jev result block under each finalized sentence with the correct type-specific summary text; disabling all queries hides both the sidebar section and the transcript block again.
