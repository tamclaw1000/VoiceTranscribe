import Foundation

enum SummaryPrompt {
    static let defaultTemplate = """
        Summarize the recording so far by accruing finalized transcript sentences into concise paragraphs. Preserve the user's wording where possible, keep related sentences together, and do not invent details.
        """
}

@MainActor
final class SummaryCoordinator: ObservableObject {
    @Published private(set) var paragraphs: [String] = []
    @Published private(set) var sentenceCount = 0

    private var sentences: [String] = []
    private var seenSentences = Set<String>()

    func reset() {
        paragraphs = []
        sentenceCount = 0
        sentences = []
        seenSentences = []
    }

    func enqueueTranscriptSegment(_ segment: TranscriptSegment, prompt: String) {
        guard segment.isFinal else {
            return
        }

        let completeSentences = FactCheckCoordinator.completeSentences(in: segment.text)
        let candidates = completeSentences.isEmpty ? [segment.text] : completeSentences
        var didChange = false

        for sentence in candidates {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = FactCheckCoordinator.normalizedSentence(trimmed)
            guard !trimmed.isEmpty, !normalized.isEmpty, !seenSentences.contains(normalized) else {
                continue
            }

            sentences.append(trimmed)
            seenSentences.insert(normalized)
            didChange = true
        }

        guard didChange else {
            return
        }

        sentenceCount = sentences.count
        paragraphs = Self.organizeIntoParagraphs(sentences: sentences, prompt: prompt)
        Trace.event("summary.local.updated", [
            "sentences": sentenceCount,
            "paragraphs": paragraphs.count
        ])
    }

    nonisolated static func organizeIntoParagraphs(sentences: [String], prompt: String) -> [String] {
        let sentencesPerParagraph = paragraphSize(from: prompt)
        return stride(from: 0, to: sentences.count, by: sentencesPerParagraph).map { start in
            let end = min(start + sentencesPerParagraph, sentences.count)
            return sentences[start..<end].joined(separator: " ")
        }
    }

    nonisolated private static func paragraphSize(from prompt: String) -> Int {
        let lowercased = prompt.lowercased()
        if lowercased.contains("short") || lowercased.contains("concise") {
            return 3
        }
        if lowercased.contains("detailed") || lowercased.contains("long") {
            return 5
        }
        return 4
    }
}
