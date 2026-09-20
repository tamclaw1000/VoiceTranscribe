# VoiceTranscribe Functional Requirements

## 1. Purpose and Scope

VoiceTranscribe is an application for recording audio input, transcribing live speech and existing audio files, distinguishing speakers when diarization is available, reading transcripts, generating summaries, and applying configurable AI prompts to finalized sentences.

This document specifies user-visible behavior, output, and settings for implementations in different environments, programming languages, and operating systems. It incorporates this repository's source, tests, Git history, implementation checklist, and existing product decisions. Explicit product decisions take precedence over historical behavior. It describes the target product, not a claim that every requirement is already implemented. Appendix A records the review evidence and significant differences from the current application.

Internal architecture, programming languages, frameworks, processing algorithms, buffer sizes, worker counts, scheduling, and other implementation constraints are outside this document. Product-facing formats, placeholder syntax, and naming rules remain part of the functional contract. Final acceptance criteria will be provided by the user.

## 2. Supported Environment and Sources

- Preserve the workflows in this document on each supported deployment. No particular operating system, minimum OS version, language, or UI framework is required by this specification.
- Identify supported environments and any unavailable device, transcription, storage, or permission capabilities. Explain a missing capability before the user attempts an affected action; retain unaffected workflows.
- List available audio input devices exposed to the application by its host environment, including built-in microphones, USB microphones, Bluetooth microphones and headsets, audio interfaces, aggregate devices, and virtual input devices where available.
- Keep each device associated with a stable identity when the environment supplies one; distinguish devices with identical names and preserve the selected source across list refreshes. A change in the default input must not silently switch an active source.
- Show each device's name, availability, default-input status, and available device information such as manufacturer, transport, channel count, and sample rate.
- Update the list when devices connect, disconnect, change availability, or are renamed. Provide manual refresh.
- Show a clear empty state when no input devices are available.
- Allow one live input source at a time. Recording and live transcription may operate together on that source.
- Allow one file transcription at a time. Starting another source must not silently interrupt an active recording or abandon processing. Explain any conflicting activity and require it to end before switching.
- Background completion of an earlier session must not contaminate the content or output of a later session.
- Device enumeration does not imply direct capture of arbitrary applications or system output; those signals must be available through a selectable input device.

## 3. Main Window

- Provide source lists for audio devices and loaded audio files, with a Load File action.
- Give each device a Transcribe/Stop button and an independent Record checkbox. There is no Listen action or listen-only mode.
- Clearly identify the active source and distinguish starting, recording, live transcription, background processing, completed, and failed states.
- Show live input levels, recent activity, peak level, and clipping while a device is capturing audio. Allow visualization sensitivity to be adjusted.
- Provide a combined Live Transcript and AI Processing view, a Transcript Paragraphs view, an AI Summary view, speaker diarization annotations, and Recent Recordings.
- Show each configured sentence prompt's enabled state and effective model in the main window; allow prompts to be enabled or disabled there.
- Provide access to Settings and indicate when required permissions are missing.
- Display the application version.

### 3.1 Workspace Organization and Controls

- Separate source and prompt controls from the content workspace. A wide display should support viewing both together; narrower displays may use equivalent navigation that keeps all actions reachable.
- The default main-window size should be wide enough to show source controls, live levels, and the selected content tab without immediate horizontal crowding.
- Split the sidebar into two top-level sections: Microphones (live devices, plus loaded audio under File Sources) and AI Selection (prompt toggles under AI Prompts and Jev query toggles). Either section must be reachable without scrolling past the other. Include a manual device refresh and an always-available Load File action.
- Provide distinct Live Transcript, Transcript Paragraphs, AI Summary, and Recent Recordings views. Tabs are suitable, but a particular widget or window arrangement is not required.
- Keep source identity, capture/recording status, live input levels, and access to Settings discoverable while navigating content views. Show application version and build when available, or explain when version information is unavailable.
- Use clear text for states and errors; icons and colors may supplement the text. Native icon names, fixed dimensions, control order, and platform-specific dialog types are not requirements.
- Keep long content and settings lists navigable. Transcript text, paragraph text, and AI results must be readable and selectable.
- Reflect source, model, and prompt changes immediately wherever those settings appear, without reopening Settings or restarting the application.

### 3.2 Source and Processing Status

- Each device exposes its name, available details, default-input indicator, availability, Transcribe/Stop action, Record control, and recording filename when available.
- For the active source, expose capture state, active modes, current RMS and peak levels, whether audio is arriving, transcription state, and estimated outstanding audio duration when measurable.
- Show recent audio activity, make quiet input visible, and indicate clipping. Visualization sensitivity changes the display without altering recorded audio or recognition input.
- Each loaded file exposes its name, available metadata, remove action, Transcribe/Stop action, and progress. Recording is not applicable to file sources.
- Prevent conflicting or duplicate start actions while an operation is starting. Keep applicable stop actions available during processing.
- Distinguish waiting for audio, receiving audio, processing retained audio, and idle states. If progress or remaining audio duration is unknown, show activity without inventing a percentage or duration.
- Reaching the end of file reading is not equivalent to completing transcription or AI work. Show those completion states separately.
- Disable unavailable actions with an explanation tied to the action's actual requirements; missing microphone access must not block reading, copying, or exporting existing results.
- Indicate missing permissions near Settings and provide the relevant recovery action.

### 3.3 Content Views

- Live Transcript presents timestamp, speaker label when available, and text for each entry, with interim text visually distinct. The transcript row should prioritize speaker identity over repeating the audio source. Show a prominent current-speaker status while diarization is active, and use stable distinct colors to help differentiate speaker labels. Treat every observed `Speaker N / Voice M` pair as a user-editable voice candidate, with `Speaker N / no voice` available for segments that do not have an embedding identity. The collapsible right-hand Voice Identification pane must let the user name a voice candidate and reset it to the generated label without reducing transcript vertical space; renamed voices must update transcript display and exports. Clicking a transcript row's speaker label must let the user correct the row to any observed voice candidate, cycle candidates, or force a new `Voice N` for that row so under-counted speakers can be represented manually. Automatic voice identity labels may distinguish same-session voices and are overridden by manual voice names. Associate prompt results beneath the relevant entry and label each by prompt name.
- Provide Auto-scroll, Copy Text, Save to File, and Export Markdown actions alongside transcription and AI processing status.
- Show whether sentence-level AI processing is disabled, ready, or processing. Per-result states distinguish queued, running, failed, and completed work. Interim text is awaiting finalization and is not an accepted AI job.
- Disabling prompts governs new work; continue to show the actual status and results of earlier accepted work.
- Transcript Paragraphs provides paragraph text, a finalized-sentence count, Copy Text, and Save to File. An included trailing fragment must not be falsely counted as a complete sentence.
- AI Summary provides its current text, effective model, processing state, Copy Text, Save to File, and a retry action after failure when input remains available.
- Recent Recordings lists completed recordings from the current application run, with filename, location, and elapsed duration.
- Each view has an informative empty state. Disable content actions or explain why they cannot run when their required content is absent. Export behavior for unfinished sessions follows section 13.

### 3.4 Settings and File Interaction

- Organize Settings into General, LLM Models, and Prompt Templates, using tabs or equivalent navigation.
- General includes output destination, recording format, transcription option, automatic transcript saving, visualization sensitivity, applicable permissions, paragraph-formatting instruction, and the separate AI Summary prompt and model.
- LLM Models includes configuration editing, diagnostic model selection, model test actions, and the global model override.
- Prompt Templates includes enabled state, name, prompt text, supported-placeholder help, effective model, add/remove actions, and reset to the default template text.
- Retain each prompt's individual model assignment while the global override is enabled; make clear that it is temporarily overridden and restore its use when the override is disabled. Disable individual model editing while the override is active.
- Persist valid settings changes and make them consistent across every Settings entry point. The main-window Settings control and platform menu Settings command must open the same Settings experience at the same usable size. Closing Settings does not itself grant permissions.
- Allow output destination selection, audio-file import, text saving, and Markdown export using the environment's file picker, storage picker, or equivalent interaction. Cancellation leaves existing content and settings intact.
- Mask API keys during ordinary editing. Show model-test and save/export outcomes within the active interaction so they are not hidden behind another window.

## 4. Recording

- Checking Record starts recording the selected source, whether or not live transcription is active.
- Record alone does not automatically start transcription or AI processing.
- Unchecking Record stops that recording without stopping independently active live transcription or pending processing.
- Show the in-progress recording filename. Allow the user to reveal the recording in the environment's file manager or equivalent storage interface when its file is available.
- After recording stops, show the final filename for five seconds. Keep the completed recording accessible in Recent Recordings.
- Record source identity, start time, end time, and elapsed duration.
- Save recordings in the configured output destination; default to a VoiceTranscribe folder in the user's documents area where available, or an equivalent user-accessible storage location. Clearly show the chosen destination.
- Before recording, create the output folder when needed and validate that the destination can accept output. Report unavailable or unwritable storage and let the user choose another destination. Do not silently redirect output.
- Changes to output destination or format apply to subsequent recordings; an active recording retains its original settings.
- Default to AAC audio in `.m4a`. Offer lossless PCM recording in `.wav` and `.caf`. Produce valid files playable by compatible external audio applications, with channel and sample-rate information consistent with the saved audio.
- Recording must continue through temporary transcription or AI delays. If audio cannot be retained, report the failure and preserve the usable recording as incomplete rather than claiming success.
- Add completed recordings to the loaded file sources so the user can transcribe the saved audio, including its full duration, later.
- Recent Recordings lists completed recordings from the current application session, their filenames, paths, and durations. A persistent searchable library is not required.

## 5. Transcription and Coverage

### 5.1 Live Transcription

- Transcribe starts speech-to-text processing for the selected source without requiring a saved audio recording.
- Provide local speech recognition as the default and allow selection among transcription options available in the deployment. Show the selected option and its availability. Equivalent recognition engines may satisfy this requirement on different platforms.
- The current macOS reference implementation uses Apple Speech for finalized transcript boundaries.
- Show preparation or model-download activity before transcription is ready. Identify the language or locale being used and report unsupported language or locale and preparation failures. A multilingual picker and automatic language detection are not required.
- Reuse valid installed models. Detect missing or incomplete model assets, obtain required assets when permitted, and provide a retry path after failed preparation or download. A failed model setup must not leave a source falsely marked as transcribing.
- Once required local models are installed, local transcription must work without an external recognition service. Distinguish model installation that needs network access from local speech processing.
- Accept supported device and imported-file audio formats without requiring the user to manually resample or convert them for the recognition engine. Report an unsupported format before claiming transcription is running.
- Show interim text as speech is processed and clearly distinguish it from finalized text.
- Run speaker diarization as part of the live and file transcription pipeline when the selected implementation supports it. Show preparation, unavailable, and failure states without mixing diarization errors into spoken transcript text.
- The current macOS reference implementation uses SpeechVAD Sortformer streaming diarization alongside Apple Speech transcription, with always-on session-only SpeechVAD WeSpeaker voice identity matching. Voice identity labels are not persisted across sessions and must not be treated as real-world identity. The UI treats Sortformer speaker slots and WeSpeaker identities as observed voice tuples that the user can name, correct, merge by assigning the same display name, or extend by forcing a new voice on a transcript row.
- Preserve finalized transcript content and its source association. Interim revisions replace the corresponding provisional text; finalization must not append duplicate copies of that same occurrence.
- Keep recognition errors separate from spoken transcript text so errors are not processed as speech by summaries or AI prompts.
- Display confidence when supplied by the recognizer without inventing scores when unavailable.
- Show whether audio is being received, transcription is waiting for audio, or processing remains outstanding.
- Let the user pause and resume live transcription on the active source. Pausing withholds newly captured audio from recognition without ending the session, stopping recording, or discarding transcript text already produced, and the paused state must be distinguishable from recording and from stopped transcription.
- Paused audio is not transcribed. When recording is active it keeps running so the saved audio retains its full duration, which means the transcript has an interval with no entries; resuming continues the session without reordering, duplicating, or retroactively filling that interval, and the transcript must indicate where the pause occurred.
- Changing the preferred transcription option applies to subsequent sessions; it must not silently discard an active session's work.

### 5.2 Which Audio Is Transcribed

- Live transcription begins when Transcribe is enabled and ready. Starting it after a recording has begun does not automatically transcribe earlier recorded audio. This preserves the existing application's coverage behavior.
- Example: recording starts at 10:00 and transcription starts at 10:03. The live session's transcript starts at 10:03; the user can transcribe the saved recording separately to obtain the earlier three minutes.
- If Transcribe is never enabled, a recording produces audio and recording details, without a transcript or AI outputs.
- Once transcription has been enabled for a recording, stopping live transcription does not cancel the requirement to finish processing its covered audio through the recording's eventual end. Earlier audio before transcription was enabled remains outside that coverage.
- Example: recording runs from 10:00 to 10:10, transcription starts at 10:03, and the user selects Stop at 10:05. Recording continues, and background transcription and applicable AI processing complete coverage from 10:03 through 10:10.
- Re-enabling live transcription during the same recording resumes the live view without duplicating already processed content or abandoning pending work.
- If live transcription started before recording, the recording's associated transcript contains only covered speech within that recording's time interval. The live session may retain additional speech outside that interval.

### 5.3 Stop and Completion

- Stop ends live transcription mode; it does not stop recording, pending saves, Transcript Paragraphs updates, AI sentence processing, or AI Summary generation.
- When no recording remains active, Stop ends the intake of new live audio and finishes processing audio already received. Release live input access once no active recording or covered transcription needs it.
- For a recording with transcription enabled, continue the covered transcription and related processing until that recording ends and all outstanding work has finished.
- Distinguish audio-file completion from transcript completion and AI completion. A recording may be saved while its transcript or AI results are still processing.
- Preserve a final incomplete sentence as transcript text. Include it in Transcript Paragraphs and AI Summary input, but do not invent punctuation solely to make it eligible for sentence-only AI prompts.
- Keep results from each session associated with that session, including results arriving after a new session starts.
- Report permanent failures as completion with errors, retaining successful results and providing a retry action for failed processing where source material remains available.
- On application quit with unfinished work, let the user wait or explicitly abandon that work; do not silently discard it.

## 6. Audio File Sources

- Allow the user to select one or more existing `.wav`, `.mp3`, `.m4a`, `.caf`, or `.flac` audio files.
- Show each loaded file's name, format, duration, channel count, and sample rate when available.
- Do not add duplicate entries for the same loaded file. Report unreadable or unsupported files individually without discarding successfully loaded files.
- Allow transcription of a loaded file from its beginning through its end, with progress and completion status. File processing need not run at playback speed and does not require audible playback or microphone capture.
- Apply the same transcript display, speaker diarization, paragraph organization, enabled AI prompts, summary generation, and export capabilities to file transcription as to live transcription.
- File processing must not modify or delete the original audio file.
- Stop during file transcription must leave already accepted work to finish and retain the obligation to complete the full selected file in the background. Show that background processing remains active.
- Allow removal of a file from the source list without deleting the original. Removal must not silently abandon unfinished processing; require an explicit decision to abandon it or keep it until completion.
- Loading a file or automatically adding a completed recording does not itself start transcription.

## 7. Transcript Display and Text Actions

- Display transcript entries in chronological order with timestamp, speaker label when available, and text. Use audio-relative timing for imported files when the original recording date is unknown; processing time is not the original speech time.
- Retain available segment timing and duration for display and export. Identify estimates or unavailable timing rather than presenting them as measured values.
- Retain available diarized speaker time ranges and export them separately from transcript rows when the diarizer provides segment timing.
- Display associated AI results directly beneath the relevant transcript entry, labeled by prompt name, in the same combined view.
- Support an auto-scroll toggle. Preserve the user's reading position when auto-scroll is off or the user is reviewing earlier content.
- Provide clear empty, starting, receiving, processing, and error states.
- Provide Copy Text and Save to File actions for the current transcript. Show a helpful message or disable the action when there is no content.
- Manual text saving allows the user to choose a destination and filename and reports success or failure. Use UTF-8 text so non-English speech and punctuation survive export. Replacing a user-selected existing file requires an explicit overwrite decision.
- Offer automatic transcript saving, enabled by default. When enabled, save a recording's associated transcript after its covered processing finishes; include late results. When disabled, retain manual saving and export.
- Do not save unrelated text from an earlier session or speech outside the associated recording interval into a recording's transcript.
- Plain-text exports must distinguish any included interim text from finalized text; completed saved transcripts contain finalized content. Include speaker labels in plain text when known.

## 8. Transcript Paragraphs

- Use the name **Transcript Paragraphs** for the readable, paragraph-form accumulation of finalized transcript text. Do not label it AI Summary.
- Preserve the speaker's words and chronological order without summarizing, inventing, or removing legitimate repeated speech.
- Update as finalized text arrives, including the final trailing fragment.
- Allow paragraph presentation to favor shorter or longer paragraphs through an editable formatting instruction, with a reset action. The default favors concise paragraphs.
- This feature works without an LLM or enabled AI prompts.
- Provide Copy Text and Save to File actions for the paragraph text.
- A new session displays its own paragraphs while older background results remain associated with their original session.

## 9. AI Summary

- Use the separate name **AI Summary** for an AI-generated condensation of the finalized transcript.
- Provide an editable AI summary prompt, persist it across launches, and offer reset to its default.
- Allow selection of the summary model. When a global model override is enabled, it also applies to the AI Summary.
- Produce a running summary as finalized content accumulates and a final summary after all covered transcription completes.
- Base summaries on available finalized content, including a trailing fragment; do not present missing or failed transcription as complete input.
- Show pending, running, completed, and failed states. Older summary results must not replace a summary generated from newer content.
- Keep summary generation independent of the enabled state of sentence-level prompt templates.
- Provide Copy Text and Save to File actions and include available summary output in Markdown export.

## 10. Sentence-Level AI Processing

### 10.1 Prompts and Results

- Apply every enabled prompt template to each eligible finalized complete sentence.
- Do not process interim fragments or synthesize punctuation on a partial fragment solely to trigger AI processing.
- Support multiple named prompts with editable text, individual enabled states, model assignments, add/remove actions, and reset to defaults.
- New prompts are enabled by default. Keep at least one editable prompt template; disabling all templates disables new sentence-level AI processing.
- Disabling or changing a prompt affects new work. It does not erase existing results or abandon work already accepted for processing.
- Show one result per sentence occurrence and enabled prompt, preserving transcript order regardless of result arrival order.
- Repeated delivery of the same transcript occurrence must not create duplicate results. Separate occurrences of identical spoken words remain separate entries.
- Show pending, running, completed, and failed status for each result. Retain valid results if another prompt fails and allow retry of failed work without duplicate visible entries.
- Support arbitrary prompt output, including prose, summaries, action items, topic extraction, and fact-check results.
- Preserve the prompt and model used for each result so later settings changes do not mislabel earlier output.

### 10.2 Prompt Placeholders and State

Support the following user-facing placeholders:

| Placeholder | Meaning |
| --- | --- |
| `{{sentence}}` | The current finalized sentence. |
| `{{conversation}}` | Finalized transcript context through the current sentence, annotated with timestamps. |
| `{{last-3}}` | The last three available timestamped context entries, including the current entry. |
| `{{last-5}}` | The last five available timestamped context entries, including the current entry. |
| `{{last-10}}` | The last ten available timestamped context entries, including the current entry. |
| `{{prompt-state}}` | The previous successful output of this prompt in the current session. |

- If a template contains no supported placeholder, append the current sentence automatically.
- Define context entries consistently as timestamped sentence occurrences extracted from finalized segments; retain final trailing fragments as context where applicable. If several sentences share only segment-level timing, preserve that timing without inventing precise sentence offsets.
- For compatibility with existing saved templates, accept `{{last-3}`, `{{last-5}`, and `{{last-10}` as aliases of their double-closing-brace forms. Document the canonical forms in the editor.
- Use the available context if fewer than the requested number of entries exist. Do not include future speech or another session's transcript.
- Maintain independent prompt state for each template. Start with empty state in each new session.
- Stateful prompts use preceding successful output in sentence order. Failed attempts do not erase successful state or allow an old result to overwrite newer state.
- Editing the template or changing its effective model starts fresh state for subsequent work; existing results retain their original meaning.
- If a model cannot accept the requested context, explain the failure rather than silently omitting requested text.

### 10.3 Combined Requests and Response Handling

- Support combining independent prompt questions for one sentence into a single request when the global model override routes them to the same model. Retain separate prompt identities, statuses, and results in the interface and exports.
- Combined responses must map answers to their corresponding prompts, regardless of answer order. A missing answer fails only the affected result; retain correctly mapped answers.
- Prompts using `{{prompt-state}}` must preserve their sequential dependency and must not be combined in a way that uses stale state. Independent prompts may continue while another prompt is waiting or has failed.
- Control outstanding AI work so capture and user interaction remain usable and provider capacity failures are reported. Exact concurrency limits and scheduling are implementation choices.
- Accept useful plain-text responses as well as structured results, including structured content wrapped in Markdown code fences. Missing optional confidence or notes must not invalidate an otherwise usable result.
- Do not invent a fact-check verdict for arbitrary prose or claim success for an empty or unusable response. Preserve useful returned text and distinguish response-format problems from provider or connectivity errors.

### 10.4 Default Fact-Check Prompt

- Provide a default fact-check-style prompt that treats transcription as potentially imperfect and evaluates only claims actually present.
- Distinguish supported, questionable, false, unverifiable, and not-factual results, with a short explanation, confidence when provided, and optional notes.
- Treat opinions, commands, filler, and other non-factual text as not factual rather than false.
- Use unverifiable when the model cannot establish a claim from its available knowledge. Do not imply external verification was performed when it was not.
- Allow other templates to return ordinary text without requiring the fact-check categories.

## 11. AI Models and Settings

- Support multiple named model configurations with provider type, endpoint address, model name, and optional API key.
- Support Ollama-compatible services, OpenAI-compatible services, OpenRouter, Anthropic, and Gemini.
- Default to Local Ollama at `http://localhost:11434`, model `igorls/gemma-4-12B-it-heretic-GGUF`.
- Allow adding, editing, selecting, and removing configurations; keep at least one configuration available.
- Allow a model per sentence prompt and a global override that routes all enabled prompts and the AI Summary to the selected global model.
- Show the effective model and whether it is globally overridden. When removing an assigned model, reassign affected prompts to the remaining selected model and show the new assignment.
- Provide a plain-prompt connectivity test for a selected model and a test of configured AI processing, showing returned output or a useful error. Identify the model and prompt being tested. Tests must be usable without starting audio capture or enabling live sentence processing and must not change session results or prompt state.
- Test the active AI route at launch when sentence-level AI processing is enabled. Show whether the active AI route is untested, testing, reachable, failed, or disabled, and identify the active model choice or mixed-model configuration currently in use.
- Keep the diagnostic model selection distinct from per-prompt assignments and the global override; selecting a diagnostic model alone does not reroute accepted processing.
- Accept provider-appropriate base URLs and, for OpenAI-compatible configurations, versioned or full chat-completions URLs without duplicating route components. Support compatible proxies and routers without requiring optional provider features such as structured-response controls.
- Validate required configuration fields and report invalid addresses before sending requests. Normalize harmless surrounding whitespace and legacy escaped slashes in stored endpoint/model strings. Do not silently send text to another destination on validation failure.
- Report unreachable services, missing models, authentication failures, unsupported responses, context-limit failures, and timeouts clearly.
- Persist model configurations, prompt templates, enabled states, model assignments, global override, summary settings, output location, audio format, transcription preference, automatic-save preference, auto-scroll, and visualization sensitivity across launches.
- Organize Settings into General, LLM Models, and Prompt Templates. Expose auto-scroll in the Live Transcript view.

### 11.1 Settings Defaults and Upgrade Compatibility

- Start with a preconfigured local model entry and an editable default AI Processing prompt. If its service or model is not installed, explain the setup needed without blocking recording or local transcription. Automatic transcript saving and transcript auto-scroll default to enabled; global model override defaults to disabled.
- Preserve saved preferences, named models, custom prompt text, enabled states, and model assignments across application upgrades.
- Migrate legacy single-endpoint and single-prompt settings into the corresponding named configurations, preserving the user's previous enabled/disabled choice. Superseded global AI toggles must not invisibly disable the new per-prompt controls.
- Recover from missing, invalid, or obsolete saved settings with valid defaults or an explicit correction path. Keep at least one model configuration and prompt template, repair dangling model assignments visibly, and avoid discarding unrelated valid settings.
- Resetting a prompt restores its default text without removing other templates, changing their states, or erasing past processing results.

## 12. Files, Names, and Recording Details

### 12.1 Output Files

- Each completed recording produces its audio file and a recording-details `.json` file.
- Produce a matching `.txt` transcript when transcription was enabled and automatic saving is enabled. Do not imply a transcript exists for record-only sessions.
- Recording details include source identifier and name, full start and end dates/times, duration, audio format, and transcription option or an explicit indication that transcription was not used.
- Preserve full dates and elapsed duration for recordings crossing midnight or a local clock change, even though the filename's end segment contains only a time.
- AI outputs are available through Markdown export; storing them in the recording-details file is not required for this version.

### 12.2 Filename Convention

Use local timestamps and a filesystem-safe, lowercase source name with separators normalized to hyphens.

- In progress: `YYYYMMDDHHMMSS-recording-audiosource.ext`.
- Completed: `YYYYMMDDHHMMSS-HHMMSSm-audiosource.ext`.
- `m` is one fractional-second digit, so the end segment has seven characters.
- Example: `20260530142317-1439052-built-in-microphone.m4a`.
- Related audio, transcript, and recording-details files share the same basename.
- If a name already exists, append a random number before the extension and use the same number for the related files. Never overwrite an existing recording or its related files to resolve a collision.
- Apply collision protection to both in-progress and completed names, checking all related file extensions.
- Use `audio-source` when a source name yields an empty safe name. Respect the destination filesystem's reserved characters and names while retaining the timestamp and source naming convention.

## 13. Markdown Export

- Allow export of the current session to a user-selected `.md` file, including sessions without a saved audio recording.
- Export a consistent snapshot of available results. Identify pending or failed work when exporting before all processing finishes.
- Include recording start/end date and time when known, duration, source, transcription option, export time, and location. Use `Not specified` for an unknown location; automatic location collection is not required.
- When the session was paused, report it rather than leaving an unexplained gap: a paused summary in `# DETAILS` and a `# PAUSES` table listing each paused span's start time and duration, marking a span that is still open as in progress.
- For imported audio with no known recording date, mark it unknown rather than using the transcription date as if it were the recording date.
- Use one recording table with one row per finalized transcript segment and these columns:

```markdown
# DETAILS

- Time of recording: start and end time, in progress, or unknown
- Location of recording: location or Not specified
- Paused: paused summary when the session was paused, omitted otherwise

# RECORDING

| date time | length | speaker | text | AI result |
| --- | ---: | --- | --- | --- |
```

- Include each segment's available timestamp, length, and speaker label when available. Distinguish estimated timing from known timing; leave unavailable values blank or explicitly unknown.
- Put all associated sentence-level AI results in the segment's AI result cell, labeled by prompt. Do not create a second AI result table.
- Include a separate speaker timeline section with diarized speaker start/end offsets and confidence when diarization segments are available.
- Add separate Transcript Paragraphs and AI Summary sections when those outputs exist.
- Include an AI Results section describing enabled prompts at export time, effective provider/model information, global override, non-empty prompt states, and the actual processing and summary prompts used. Preserve distinctions between historical result settings and current settings.
- Include paths to related audio, transcript, and recording-details files when available, without claiming files exist before they have been saved.
- Preserve readable tables and prompt text when content contains pipes, line breaks, or Markdown delimiters.
- Do not include API keys as export fields. Automatic redaction of transcript content or other exported content is not required for this version.

## 14. Permissions and Privacy

- Explain microphone, speech-recognition, and storage access where the environment requires them; show whether each applicable permission is allowed, denied/restricted, not yet requested, or not applicable.
- During initial setup, request undetermined permissions needed for the selected workflows, observing host requirements such as a user gesture. Refresh authorization after the user changes it.
- Restart after permission changes only when the environment requires it. Explain why and restart safely, or give manual restart instructions when automatic restart is unavailable.
- If authorization resets or is revoked, re-evaluate the relevant permissions regardless of prior setup completion. Do not repeatedly prompt for a denied permission on every action.
- Disable only actions lacking a required permission and provide access or instructions for the host's relevant permission controls. Record-only operation requires no recognition authorization unless the environment actually mandates it; local file transcription requires no microphone permission. Permission denial must not crash the app or discard existing results.
- Keep AI processing local by default. Selecting and enabling a remote model sends the text required by its prompts, potentially including the full finalized transcript; make that destination clear.
- Do not transmit audio to an external transcription service without user opt-in.
- File import and processing must not modify original audio files.

## 15. Delays, Temporary Storage, and Errors

- Keep controls, source status, transcript reading, and recording usable while transcription, summarization, or AI processing takes longer than incoming speech.
- Preserve audio needed to finish processing. Temporary disk storage is allowed as needed, including when no permanent audio recording was requested.
- Retain temporary material while unfinished work needs it. Remove it after successful completion or explicit abandonment.
- After an interruption, offer recovery or cleanup of recoverable unfinished work. Do not silently delete material needed for pending processing.
- If storage becomes unavailable or audio can no longer be retained, stop the affected input, preserve usable material, identify the incomplete interval or failure point, and continue unaffected work.
- Handle no devices, disconnected devices, permission denial, unavailable transcription or diarization options, missing models, unsupported or corrupt audio, failed writes, low disk space, and AI-service failures with plain-language messages and a practical next action.
- Warn when available storage threatens ongoing capture and finalize the usable recording when continued saving is impossible. A transcript or metadata save failure must not delete an otherwise valid audio recording. Report which outputs succeeded and allow failed saves to be retried when content remains available.
- On active-device loss or an incompatible format change, end the affected capture, clear stale active indicators, preserve accepted audio and results, and identify the affected source. Reconnection does not silently resume capture.
- Never label incomplete recordings, transcripts, or AI output as fully processed. Do not silently substitute another source when the selected source disappears.
- Report copying, saving, exporting, and model-test outcomes clearly.

### 15.1 Diagnostic Information

- Make timestamped diagnostic information available for source changes, permission decisions, capture start/stop/errors, recording and export outcomes, transcription preparation/progress/finalization, and AI request outcomes.
- Include enough source, session, model, and operation context to distinguish no incoming audio from pending recognition, failed storage, or a failed AI request.
- Explain how to locate diagnostics in the supported environment. A fixed log path, serialization format, or console application is not required.
- Exclude API keys and authorization credentials from diagnostics. Diagnostic failures must not stop recording or discard user results.

## 16. Initial-Version Exclusions and Acceptance

The initial version does not require audio editing, cloud account synchronization, multi-user collaboration, advanced transcript search, automatic meeting detection, simultaneous live input sources, automatic location collection, or AI results in recording-details files.

Final acceptance scenarios and quantitative targets will be supplied by the user. They are separate from this functional specification.

## Appendix A. Review Evidence and Implementation Status

Reviewed against the working tree on 2026-09-15, with Git HEAD `39d0640` and existing uncommitted work through the documented v2.4.7 release. This appendix explains provenance; the functional sections above govern the target product. Existing defects and unchecked implementation tasks are not evidence of completed features.

| Area | Evidence reviewed | Requirements consequence |
| --- | --- | --- |
| Source controls, capture, recording, and files | `AppModel.swift`, `AudioDeviceService.swift`, `AudioCaptureService.swift`, `RecordingService.swift`, `Models.swift`, `Utilities.swift`, `Views.swift`; file-source commit `6d81204`; implementation sections 26–33 | Preserve independent Record/Transcribe actions, live status, file import, recording formats, naming, recent recordings, and external file access using host-equivalent controls. |
| Recognition, diarization, and model preparation | `TranscriptionService.swift`, `FluidAudioTranscriptionService.swift`, `DiarizationService.swift`; commits `31bbb64`, `1937299`, `5cf4475`; working-tree v2.4.8 diarization | Require preparation feedback, reusable/recoverable models, interim/final text, speaker labels where available, and supported input conversion without requiring the original recognition libraries. |
| Paragraphs and summaries | `SummaryService.swift`, `AppModel.swift`, `Views.swift`; implementation section 42 | The current Recording Summary organizes sentences locally. Transcript Paragraphs preserves that function. The separate LLM-generated AI Summary is a retained target requirement, not an implemented feature. |
| AI models, prompts, and responses | `AppSettings.swift`, `AIPromptService.swift`, `Tests/VoiceTranscribeTests/VoiceTranscribeTests.swift`; commits `033272c`, `31811d5`, `39d0640`; implementation sections 47–68 | Capture provider configuration, independent prompt toggles, global routing, context placeholders, state, combined requests, response tolerance, diagnostics, and legacy-settings migration. The reference implementation's three concurrent calls are not a portable functional limit. |
| Provider compatibility | Commit `31a3c59`; implementation sections 52 and 61; configuration and response tests | Preserve interoperability with compatible endpoints and proxies, including stored-string normalization, without prescribing request-building code. |
| Text and Markdown output | `MarkdownExportService.swift`, related `AppModel.swift` actions and export tests; commit `d6f7bca`; working-tree v2.4.7 prompt-state export; working-tree v2.4.8 speaker export | Preserve single-table transcript/AI output with speaker labels, speaker timeline export, prompt and model information, accumulated prompt state, text actions, and related file references. |
| Permissions and diagnostics | `PermissionService.swift`, `Trace.swift`, startup actions in `AppModel.swift`; commits `978bc8e`, `db9323e` | Express authorization, recovery, and troubleshooting as host-dependent capabilities rather than requiring macOS dialogs, an unconditional relaunch, or a fixed temporary log path. |
| Known gaps and superseded behavior | `APPLICATION-REVIEW.md`, unchecked implementation section 27, current stop/finalization and reset paths, existing requirements | Retain safe collision handling, device-loss recovery, storage validation, effective sensitivity, background completion, late-result isolation, and preservation of repeated speech as target obligations. These are not all implemented. |

The current source can cancel file work on Stop, reset pending AI state on a new session, preserve repeated identical sentence occurrences for AI/Jev processing, and finalize recording files before related processing completes. Those behaviors do not override sections 5–10 and 15. Full-file background completion, covered-recording completion after Stop, quit/recovery handling, accurate timing provenance, and historical prompt/model preservation require implementation and verification against this specification.

Historical Listen-only mode, the global AI enable switch, and length-based promotion of partial text are superseded by the requirements above. The unchecked Sherpa-Onnx proposals in the implementation checklist do not make a particular engine part of the required feature set.
