# VoiceTranscribe

VoiceTranscribe is a native macOS SwiftUI application for enumerating sound-input sources, monitoring live input levels, recording audio, transcribing speech with speaker diarization, summarizing recordings, and running configurable AI processing prompts over finalized transcript text.

The app is built for macOS 26+ and uses FluidAudio by default for streaming ASR, with Apple SpeechTranscriber available as an alternate transcription engine.

## Features

- Lists microphone, audio interface, aggregate, Bluetooth, and virtual input sources.
- Shows a live input-level graph for the active source.
- Records audio to a configurable output folder.
- Displays finalized and interim transcript text while audio is processed.
- Annotates transcript rows with live FluidAudio speaker labels when diarization output is available, and shows the current anonymous speaker in the Live Transcript toolbar.
- Saves transcript text beside recordings and supports manual transcript export.
- Organizes finalized transcript sentences into a running recording summary.
- Supports audio file sources that can be loaded and transcribed.
- Exports transcript sessions to Markdown with details, recording rows, summary, AI output, and file references.
- Provides copy/save buttons for transcript text and recording summaries.
- Uses a tabbed main detail area for Live Transcript, Recording Summary, and Recent Recordings.
- Provides a transcript auto-scroll toggle for following live speech.

## AI Processing

VoiceTranscribe can run one or more named prompt templates against finalized transcript sentences. AI processing is configured from Settings:

- `General`: output folder, audio format, transcription engine, permissions, summary prompt, and visualization settings.
- `LLM Models`: configured model endpoints, diagnostic test buttons, and the global prompt-model option.
- `Prompt Templates`: named AI prompts, enable toggles, prompt editor, reset action, and per-prompt model selection.

Each enabled prompt creates an AI result for each finalized complete sentence. Disabling all prompts disables AI processing.

### LLM Endpoints

Configured LLM models include:

- Display name.
- API type.
- Base endpoint URL.
- Model name.
- Optional API key.

Supported API types:

- Ollama `/api/generate`
- OpenAI-compatible chat completions
- OpenRouter
- Anthropic Messages
- Gemini `generateContent`

OpenAI-compatible requests intentionally use a minimal `model` plus `messages` body for broad compatibility with proxies and routers.

### Global Prompt Model

The `Use one model for all prompts` option routes every enabled prompt through the selected global prompt model. When this option is on:

- Per-prompt model pickers remain visible but are disabled.
- The left prompt list shows that prompts are using the global model.
- Multiple prompts for the same sentence can be batched into one LLM request.

### Prompt Placeholders

Prompt templates support these substitutions:

| Placeholder | Meaning |
|-------------|---------|
| `{{sentence}}` | The current finalized sentence being processed. |
| `{{conversation}}` | The full finalized transcript context, timestamped line by line. |
| `{{last-3}}` | The last three timestamped transcript entries. |
| `{{last-5}}` | The last five timestamped transcript entries. |
| `{{last-10}}` | The last ten timestamped transcript entries. |
| `{{prompt-state}}` | The previous successful output for this prompt template. |

Conversation entries are formatted like:

```text
[10:46:12] Some finalized sentence.
```

If a prompt does not include any supported placeholder, VoiceTranscribe appends the current sentence automatically before sending the request.

### Prompt State

`{{prompt-state}}` is maintained independently per prompt template. It is useful for rolling state such as an action item list:

```text
You're maintaining a list of action items.
Update prompt-state="{{prompt-state}}" with new items from "{{sentence}}" if it is an action item.
```

After a successful AI response, that response becomes the next prompt state for the same template. Prompt state resets when a new AI processing session starts.

Prompts using `{{prompt-state}}` are serialized per template so successive calls do not race against stale state. Other prompt work can still use batching and queue concurrency.

### Queueing and Batching

AI processing uses a queue with up to three simultaneous calls. When the global prompt model is enabled and several enabled prompts apply to the same sentence, VoiceTranscribe sends those prompt questions in one combined request and maps the batch response back to the individual prompt rows.

## Exports

The Live Transcript tab includes:

- `CopyText`
- `SaveToFile`
- `ExportMarkdown`
- `Auto-scroll`

The Recording Summary tab includes:

- `CopyText`
- `SaveToFile`

Markdown exports include:

- `# DETAILS`
- `# RECORDING` with one row per finalized transcript segment, speaker labels, and an `AI result` column.
- `# SPEAKERS` with the diarized speaker timeline when speaker segments are available.
- `# SUMMARY` when summary content exists.
- `# AI RESULTS` with model metadata, non-empty prompt states, and prompts.
- `# FILES` when related output files exist.

API keys are never included in Markdown exports.

## Build

```sh
./build.sh
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

## Launch

```sh
./run.sh
```

To relaunch an existing packaged app without rebuilding:

```sh
./run.sh --no-build
```

## Logs

Trace logs are always written as JSON lines to:

```sh
tail -f /tmp/VoiceTranscribe.log
```
