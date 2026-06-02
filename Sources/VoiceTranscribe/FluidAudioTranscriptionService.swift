import AVFoundation
import FluidAudio
import Foundation

/// FluidAudio streaming transcription service using Parakeet EOU (End-of-Utterance).
///
/// `StreamingEouAsrManager` handles format conversion, chunking, and EOU detection.
/// Model download and loading is handled explicitly here (the manager's built-in
/// `loadModels()` has a path bug that misses the chunk‑size subdirectory).
final class FluidAudioTranscriptionService: TranscriptionService {
    let engineName = "FluidAudio (Parakeet EOU)"

    private let chunkSize: StreamingChunkSize = .ms320
    private var manager: StreamingEouAsrManager?
    private var onSegment: ((TranscriptSegment) -> Void)?

    /// Tracks the end index (in the accumulated transcript) of text already
    /// committed as finalized segments.  Used to avoid re-emitting duplicate
    /// text when the partial callback delivers growing accumulated text.
    private var committedEndIndex: String.Index?

    /// Minimum new-character count before committing a live sentence.
    private static let minSentenceChars = 50

    // MARK: - TranscriptionService

    func start(onSegment: @escaping (TranscriptSegment) -> Void) async throws {
        self.onSegment = onSegment
        self.committedEndIndex = nil

        let mgr = StreamingEouAsrManager(
            chunkSize: chunkSize,
            eouDebounceMs: 1280
        )

        // Register callbacks *before* loading so nothing is missed.
        await mgr.setEouCallback { [weak self] text in
            Trace.event("fluidAudio.eou.raw", ["text": text.prefix(80)])
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let self else {
                Trace.event("fluidAudio.eou.skip", ["reason": text.isEmpty ? "empty" : "selfNil"])
                return
            }
            let punctuated = Self.addSentencePunctuation(trimmed)
            Trace.event("fluidAudio.eou.punctuated", ["text": punctuated])
            Task { @MainActor in
                self.onSegment?(TranscriptSegment(text: punctuated, isFinal: true))
            }
        }

        await mgr.setPartialCallback { [weak self] text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let self else { return }
            Trace.event("fluidAudio.partial", ["text": trimmed.prefix(80)])

            // Split accumulated text at NaturalLanguage sentence boundaries
            // so the user sees punctuated sentences in real time, even when
            // the Parakeet EOU model never fires.
            let (finals, interim) = self.splitSentences(trimmed)
            for sentence in finals {
                Trace.event("fluidAudio.sentence", ["text": sentence])
                Task { @MainActor in
                    self.onSegment?(TranscriptSegment(text: sentence, isFinal: true))
                }
            }
            Task { @MainActor in
                self.onSegment?(TranscriptSegment(text: interim, isFinal: false))
            }
        }

        // Load models from the correct path (same logic as the CLI).
        let modelsURL = Self.modelsDirectory(chunkSize: chunkSize)
        try await ensureModelsDownloaded(to: modelsURL)
        try await mgr.loadModels(from: modelsURL)

        self.manager = mgr
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let mgr = manager else { return }
        // Fire-and-forget; the actor serializes concurrent process() calls.
        Task {
            _ = try? await mgr.process(audioBuffer: buffer)
        }
    }

    func stop() {
        Trace.event("fluidAudio.stop.enter", [
            "managerNil": manager == nil
        ])

        let mgr = manager
        manager = nil

        guard let mgr else {
            Trace.event("fluidAudio.stop", ["reason": "managerNil"])
            return
        }

        Task { [weak self] in
            // Drain the final utterance.
            Trace.event("fluidAudio.stop.draining")
            let text = (try? await mgr.finish()) ?? ""
            Trace.event("fluidAudio.stop.drained", ["rawText": text.prefix(80), "rawLength": text.count])
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Trace.event("fluidAudio.stop.trimmed", ["text": trimmed.prefix(80), "length": trimmed.count])
            if !trimmed.isEmpty {
                let punctuated = Self.addSentencePunctuation(trimmed)
                Trace.event("fluidAudio.stop.punctuated", ["text": punctuated])
                let segment = TranscriptSegment(text: punctuated, isFinal: true)
                await MainActor.run {
                    self?.onSegment?(segment)
                }
            } else {
                Trace.event("fluidAudio.stop.empty")
            }
        }
    }

    // MARK: - Model Paths

    /// The cache root all FluidAudio models live under.
    private static var fluidAudioModelsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    /// Directory the CLI expects for a given chunk size, e.g.
    ///   …/FluidAudio/Models/parakeet-eou-streaming/320ms/
    private static func modelsDirectory(chunkSize: StreamingChunkSize) -> URL {
        fluidAudioModelsRoot
            .appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
            .appendingPathComponent(chunkSize.modelSubdirectory, isDirectory: true)
    }

    /// Ensure the required `.mlmodelc` bundles and `vocab.json` exist and are
    /// complete (not partial downloads).  If any file is missing or corrupted,
    /// remove the cache and download fresh from HuggingFace.
    private func ensureModelsDownloaded(to modelsURL: URL) async throws {
        // Files that prove each .mlmodelc bundle is complete (coremldata.bin is
        // written last by CoreML compilation, so its presence signals a finished
        // download + compile).
        let verificationFiles = [
            "streaming_encoder.mlmodelc/coremldata.bin",
            "decoder.mlmodelc/coremldata.bin",
            "joint_decision.mlmodelc/coremldata.bin",
            "vocab.json",
        ]

        let allExist = verificationFiles.allSatisfy {
            FileManager.default.fileExists(atPath: modelsURL.appendingPathComponent($0).path)
        }

        guard !allExist else { return }

        // Nuke any partial download so we get a clean slate.
        try? FileManager.default.removeItem(at: modelsURL)
        try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)

        // Download to the FluidAudio models root so the repo's internal
        // directory layout (chunk‑size subfolder) lands in the right place.
        let downloadRoot = modelsURL
            .deletingLastPathComponent()  // 320ms
            .deletingLastPathComponent()  // parakeet-eou-streaming
        // downloadRoot = …/FluidAudio/Models/

        let repo: Repo = switch chunkSize {
        case .ms160:  .parakeetEou160
        case .ms320:  .parakeetEou320
        case .ms1280: .parakeetEou1280
        }

        try await DownloadUtils.downloadRepo(repo, to: downloadRoot)
    }

    // MARK: - Post-processing

    /// Commit accumulated transcript in sentence-sized chunks during live
    /// transcription.  Unlike `NLTokenizer` (which needs punctuation to find
    /// boundaries), this simply commits new text once enough has accumulated.
    ///
    /// Returns one finalized sentence when the new uncommitted portion exceeds
    /// `minSentenceChars`, plus a trailing interim fragment with the remainder.
    private func splitSentences(_ text: String) -> (finals: [String], interim: String) {
        let startIndex = committedEndIndex ?? text.startIndex

        // Nothing new to commit.
        guard startIndex < text.endIndex else {
            return ([], text)
        }

        let newText = String(text[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't commit tiny fragments — wait until we have a meaningful chunk.
        guard newText.count >= Self.minSentenceChars else {
            return ([], text)
        }

        // Find a good split point: prefer the last whitespace after minSentenceChars
        // so we don't split mid-word.
        var splitIndex = newText.index(newText.startIndex, offsetBy: min(newText.count, Self.minSentenceChars))
        if let space = newText[splitIndex...].firstIndex(of: " ") {
            splitIndex = space
        } else if splitIndex < newText.endIndex {
            // No space found — split at the exact boundary.
            splitIndex = newText.index(newText.startIndex, offsetBy: Self.minSentenceChars)
        }

        let committed = String(newText[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = String(newText[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !committed.isEmpty else {
            return ([], text)
        }

        // Advance the committed index past what we just emitted.
        let committedRange = text.range(of: committed, range: startIndex..<text.endIndex)
        committedEndIndex = committedRange?.upperBound ?? text.index(startIndex, offsetBy: committed.count)

        let punctuated = Self.addSentencePunctuation(committed)
        Trace.event("fluidAudio.sentence", ["text": punctuated])

        let interim = remainder.isEmpty ? "" : remainder
        return ([punctuated], interim)
    }

    /// Add basic sentence punctuation to raw ASR output.
    ///
    /// The Parakeet EOU model does not emit punctuation tokens (`.`, `?`, `!`).
    /// Since each EOU boundary is a natural sentence/utterance end, we:
    /// - Capitalize the first letter.
    /// - Append a period if the text doesn't already end with sentence punctuation.
    private static func addSentencePunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Capitalize first letter (preserving leading whitespace if any).
        if let firstChar = result.first, firstChar.isLetter {
            result.replaceSubrange(result.startIndex...result.startIndex,
                                    with: String(firstChar).uppercased())
        }

        // Append a period if the last character is not already sentence punctuation.
        if let lastChar = result.last,
           lastChar != "." && lastChar != "?" && lastChar != "!" {
            result += "."
        }

        Trace.event("fluidAudio.punctuation", ["input": text.prefix(60), "output": result.prefix(60)])
        return result
    }
}
