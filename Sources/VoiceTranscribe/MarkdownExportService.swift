import Foundation

struct MarkdownExportContext {
    var sourceName: String
    var location: String
    var startDate: Date?
    var endDate: Date?
    var exportedAt: Date
    var transcriptionEngine: String
    var aiPromptEnabled: Bool
    var llmName: String
    var llmProvider: String
    var llmEndpoint: String
    var llmModel: String
    var promptStates: [MarkdownExportPromptState] = []
    var aiPromptPrompt: String
    var summaryPrompt: String
    var jevEnabled: Bool = false
    var jevBaseURL: String = ""
    var jevModel: String = ""
    var jevQueryDetails: String = ""
    var audioURL: URL?
    var transcriptURL: URL?
    var metadataURL: URL?
}

struct MarkdownExportPromptState: Equatable {
    var promptName: String
    var state: String
}

enum MarkdownExportService {
    static func makeDocument(
        context: MarkdownExportContext,
        finalizedSegments: [TranscriptSegment],
        speakerSegments: [SpeakerDiarizationSegment] = [],
        pauseSpans: [TranscriptionPauseSpan] = [],
        aiPrompts: [AIPromptItem],
        jevResults: [JevResultItem] = [],
        summaryParagraphs: [String],
        calendar: Calendar = .current
    ) -> String {
        var lines: [String] = []

        lines.append("# DETAILS")
        lines.append("")
        lines.append("- Time of recording: \(recordingTimeText(start: context.startDate, end: context.endDate, calendar: calendar))")
        lines.append("- Location of recording: \(context.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not specified" : context.location)")
        lines.append("- Audio source: \(context.sourceName)")
        lines.append("- Duration: \(durationText(start: context.startDate, end: context.endDate))")
        if let pauseSummary = pauseSummaryText(pauseSpans) {
            lines.append("- Paused: \(pauseSummary)")
        }
        lines.append("- Transcription engine: \(context.transcriptionEngine)")
        lines.append("- Exported: \(dateTimeText(context.exportedAt, calendar: calendar))")
        lines.append("")

        lines.append("# RECORDING")
        lines.append("")
        lines.append("| date time | length | speaker | text | AI result | Jev result |")
        lines.append("| --- | ---: | --- | --- | --- | --- |")
        for (index, segment) in finalizedSegments.enumerated() {
            let end = nextTimestamp(after: index, in: finalizedSegments) ?? context.endDate
            let length = segmentLengthText(start: segment.timestamp, end: end)
            let aiResult = aiPromptText(for: segment, aiPrompts: aiPrompts)
            let jevResult = jevText(for: segment, jevResults: jevResults)
            lines.append("| \(tableCell(dateTimeText(segment.timestamp, calendar: calendar))) | \(tableCell(length)) | \(tableCell(speakerText(segment))) | \(tableCell(segment.text)) | \(tableCell(aiResult)) | \(tableCell(jevResult)) |")
        }
        if finalizedSegments.isEmpty {
            lines.append("| | | | No finalized transcript text. | | |")
        }

        appendPauseSpans(
            to: &lines,
            pauseSpans: pauseSpans,
            calendar: calendar
        )

        appendSpeakerTimeline(
            to: &lines,
            speakerSegments: speakerSegments
        )

        let summary = summaryParagraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !summary.isEmpty {
            lines.append("")
            lines.append("# SUMMARY")
            lines.append("")
            lines.append(contentsOf: summary)
        }

        appendAIResults(
            to: &lines,
            context: context,
            summary: summary
        )

        appendJevResults(
            to: &lines,
            context: context
        )

        let fileLines = fileReferenceLines(context: context)
        if !fileLines.isEmpty {
            lines.append("")
            lines.append("# FILES")
            lines.append("")
            lines.append(contentsOf: fileLines)
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func appendAIResults(
        to lines: inout [String],
        context: MarkdownExportContext,
        summary: [String]
    ) {
        lines.append("")
        lines.append("# AI RESULTS")
        lines.append("")
        lines.append("- AI processing enabled: \(context.aiPromptEnabled ? "Yes" : "No")")
        lines.append("- LLM endpoint: \(context.llmName)")
        lines.append("- LLM provider: \(context.llmProvider)")
        lines.append("- LLM base URL: \(context.llmEndpoint)")
        lines.append("- LLM model: \(context.llmModel)")

        if !summary.isEmpty {
            lines.append("")
            lines.append("## Summary Result")
            lines.append("")
            lines.append(contentsOf: summary)
        }

        appendPromptStates(context.promptStates, to: &lines)
        appendPromptSection(title: "AI Processing Prompts", prompt: context.aiPromptPrompt, to: &lines)
        appendPromptSection(title: "Summary Prompt", prompt: context.summaryPrompt, to: &lines)
    }

    private static func appendJevResults(
        to lines: inout [String],
        context: MarkdownExportContext
    ) {
        lines.append("")
        lines.append("# JEV RESULTS")
        lines.append("")
        lines.append("- Jev enabled: \(context.jevEnabled ? "Yes" : "No")")
        lines.append("- Jev base URL: \(context.jevBaseURL)")
        lines.append("- Jev model: \(context.jevModel)")

        appendPromptSection(title: "Jev Queries", prompt: context.jevQueryDetails, to: &lines)
    }

    /// One-line summary of paused spans for the DETAILS block, or nil when the session
    /// was never paused.
    private static func pauseSummaryText(_ pauseSpans: [TranscriptionPauseSpan]) -> String? {
        guard !pauseSpans.isEmpty else {
            return nil
        }
        let completed = pauseSpans.compactMap(\.duration)
        let total = durationText(completed.reduce(0, +))
        let isPausedNow = pauseSpans.contains { $0.endedAt == nil }
        if completed.isEmpty {
            return "currently paused"
        }
        let spanText = "\(completed.count) span\(completed.count == 1 ? "" : "s") totaling \(total)"
        return isPausedNow ? "\(spanText), plus one still in progress" : spanText
    }

    /// Lists paused spans so a reader can tell why the transcript table skips time.
    private static func appendPauseSpans(
        to lines: inout [String],
        pauseSpans: [TranscriptionPauseSpan],
        calendar: Calendar
    ) {
        guard !pauseSpans.isEmpty else {
            return
        }
        lines.append("")
        lines.append("# PAUSES")
        lines.append("")
        lines.append("| started | duration |")
        lines.append("| --- | ---: |")
        for span in pauseSpans {
            let duration = span.duration.map(durationText) ?? "in progress"
            lines.append("| \(tableCell(dateTimeText(span.startedAt, calendar: calendar))) | \(tableCell(duration)) |")
        }
    }

    private static func appendSpeakerTimeline(
        to lines: inout [String],
        speakerSegments: [SpeakerDiarizationSegment]
    ) {
        guard !speakerSegments.isEmpty else {
            return
        }

        lines.append("")
        lines.append("# SPEAKERS")
        lines.append("")
        lines.append("| start | end | speaker | confidence |")
        lines.append("| ---: | ---: | --- | ---: |")
        for segment in speakerSegments.sorted(by: { $0.startTime < $1.startTime }) {
            lines.append("| \(tableCell(timeOffsetText(segment.startTime))) | \(tableCell(timeOffsetText(segment.endTime))) | \(tableCell(speakerText(segment))) | \(tableCell(segment.confidence.map { String(format: "%.2f", $0) } ?? "")) |")
        }
    }

    private static func speakerText(_ segment: TranscriptSegment) -> String {
        if let manualName = trimmedNonEmpty(segment.speakerName) {
            return manualName
        }
        if let voiceName = trimmedNonEmpty(segment.voiceName) {
            if let speakerID = trimmedNonEmpty(segment.speakerID), speakerID != voiceName {
                return "\(voiceName) (\(speakerID))"
            }
            return voiceName
        }
        if let voiceID = trimmedNonEmpty(segment.voiceID) {
            if let speakerID = trimmedNonEmpty(segment.speakerID), speakerID != voiceID {
                return "\(voiceID) (\(speakerID))"
            }
            return voiceID
        }
        return trimmedNonEmpty(segment.speakerID) ?? ""
    }

    private static func speakerText(_ segment: SpeakerDiarizationSegment) -> String {
        if let manualName = trimmedNonEmpty(segment.speakerName) {
            return manualName
        }
        if let voiceName = trimmedNonEmpty(segment.voiceName), segment.speakerID != voiceName {
            return "\(voiceName) (\(segment.speakerID))"
        }
        if let voiceID = trimmedNonEmpty(segment.voiceID), segment.speakerID != voiceID {
            return "\(voiceID) (\(segment.speakerID))"
        }
        return segment.speakerLabel
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func appendPromptStates(_ promptStates: [MarkdownExportPromptState], to lines: inout [String]) {
        let states = promptStates.compactMap { promptState -> MarkdownExportPromptState? in
            let state = promptState.state.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !state.isEmpty else {
                return nil
            }
            let name = promptState.promptName.trimmingCharacters(in: .whitespacesAndNewlines)
            return MarkdownExportPromptState(
                promptName: name.isEmpty ? "Unnamed Prompt" : name,
                state: state
            )
        }

        guard !states.isEmpty else {
            return
        }

        lines.append("")
        lines.append("## Prompt States")
        for promptState in states {
            lines.append("")
            lines.append("### \(promptState.promptName)")
            lines.append("")
            lines.append("```text")
            lines.append(promptState.state)
            lines.append("```")
        }
    }

    private static func appendPromptSection(title: String, prompt: String, to lines: inout [String]) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        lines.append("")
        lines.append("## \(title)")
        lines.append("")
        lines.append("```text")
        lines.append(trimmed)
        lines.append("```")
    }

    private static func nextTimestamp(after index: Int, in segments: [TranscriptSegment]) -> Date? {
        let nextIndex = index + 1
        guard segments.indices.contains(nextIndex) else {
            return nil
        }
        return segments[nextIndex].timestamp
    }

    private static func recordingTimeText(start: Date?, end: Date?, calendar: Calendar) -> String {
        guard let start else {
            return "Not recorded"
        }
        guard let end else {
            return "\(dateTimeText(start, calendar: calendar)) - in progress"
        }
        return "\(dateTimeText(start, calendar: calendar)) - \(dateTimeText(end, calendar: calendar))"
    }

    private static func durationText(start: Date?, end: Date?) -> String {
        guard let start else {
            return "Not recorded"
        }
        return durationText((end ?? Date()).timeIntervalSince(start))
    }

    private static func segmentLengthText(start: Date, end: Date?) -> String {
        guard let end else {
            return ""
        }
        return durationText(max(0, end.timeIntervalSince(start)))
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration >= 0 else {
            return ""
        }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func timeOffsetText(_ offset: TimeInterval) -> String {
        durationText(max(0, offset))
    }

    private static func dateTimeText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func aiPromptText(for item: AIPromptItem) -> String {
        let prefix = item.promptTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\(item.promptTemplateName): "
        switch item.state {
        case .queued:
            return "\(prefix)Queued"
        case .checking:
            return "\(prefix)Checking"
        case .failed(let message):
            return "\(prefix)Failed: \(message)"
        case .completed(let result):
            return "\(prefix)\(result.displayText)"
        }
    }

    private static func aiPromptText(for segment: TranscriptSegment, aiPrompts: [AIPromptItem]) -> String {
        let matches = aiPromptsForSegment(segment, aiPrompts: aiPrompts)
        guard !matches.isEmpty else {
            return ""
        }
        return matches.map { aiPromptText(for: $0) }.joined(separator: "\n\n")
    }

    private static func aiPromptsForSegment(_ segment: TranscriptSegment, aiPrompts: [AIPromptItem]) -> [AIPromptItem] {
        let segmentText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSegment = AIPromptCoordinator.normalizedSentence(segmentText)
        let normalizedSentences = Set(AIPromptCoordinator.completeSentences(in: segmentText).map {
            AIPromptCoordinator.normalizedSentence($0)
        })

        return aiPrompts.filter { item in
            if let segmentID = item.segmentID {
                return segmentID == segment.id
            }
            let normalizedItem = AIPromptCoordinator.normalizedSentence(item.sentence)
            return normalizedItem == normalizedSegment
                || normalizedSentences.contains(normalizedItem)
                || segmentText.localizedCaseInsensitiveContains(item.sentence)
        }
    }

    private static func jevText(for item: JevResultItem) -> String {
        let prefix = item.queryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\(item.queryName): "
        switch item.state {
        case .queued:
            return "\(prefix)Queued"
        case .checking:
            return "\(prefix)Checking"
        case .failed(let message):
            return "\(prefix)Failed: \(message)"
        case .completed(let answer):
            return "\(prefix)\(answer.displayText)"
        }
    }

    private static func jevText(for segment: TranscriptSegment, jevResults: [JevResultItem]) -> String {
        let matches = jevResultsForSegment(segment, jevResults: jevResults)
        guard !matches.isEmpty else {
            return ""
        }
        return matches.map { jevText(for: $0) }.joined(separator: "\n\n")
    }

    private static func jevResultsForSegment(_ segment: TranscriptSegment, jevResults: [JevResultItem]) -> [JevResultItem] {
        let segmentText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSegment = AIPromptCoordinator.normalizedSentence(segmentText)
        let normalizedSentences = Set(AIPromptCoordinator.completeSentences(in: segmentText).map {
            AIPromptCoordinator.normalizedSentence($0)
        })

        return jevResults.filter { item in
            if let segmentID = item.segmentID {
                return segmentID == segment.id
            }
            let normalizedItem = AIPromptCoordinator.normalizedSentence(item.sentence)
            return normalizedItem == normalizedSegment
                || normalizedSentences.contains(normalizedItem)
                || segmentText.localizedCaseInsensitiveContains(item.sentence)
        }
    }

    private static func fileReferenceLines(context: MarkdownExportContext) -> [String] {
        [
            ("Audio file", context.audioURL),
            ("Transcript file", context.transcriptURL),
            ("Metadata file", context.metadataURL)
        ].compactMap { label, url in
            guard let url else {
                return nil
            }
            return "- \(label): `\(url.path)`"
        }
    }

    private static func tableCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
