@preconcurrency import AVFoundation
import Foundation

@MainActor
final class RecordingService: ObservableObject {
    @Published private(set) var activeSession: RecordingSession?
    @Published private(set) var lastError: String?

    private var writer: AsyncAudioFileWriter?
    private var currentFormat: AudioOutputFormat = .m4a

    var isRecording: Bool {
        activeSession != nil
    }

    func start(
        source: SoundInputSource,
        inputFormat: AVAudioFormat,
        outputFolder: URL,
        outputFormat: AudioOutputFormat
    ) throws {
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let startDate = Date()
        let basename = FileNamer.inProgressBasename(sourceName: source.name, startDate: startDate)
        let audioURL = outputFolder.appendingPathComponent("\(basename).\(outputFormat.rawValue)")
        let transcriptURL = outputFolder.appendingPathComponent("\(basename).txt")
        let metadataURL = outputFolder.appendingPathComponent("\(basename).json")
        let settings = Self.audioSettings(for: outputFormat, inputFormat: inputFormat)
        let file = try AVAudioFile(forWriting: audioURL, settings: settings)

        writer = AsyncAudioFileWriter(file: file) { [weak self] error in
            Task { @MainActor in
                Trace.event("recording.writeError", ["error": error.localizedDescription])
                self?.lastError = error.localizedDescription
            }
        }
        currentFormat = outputFormat
        activeSession = RecordingSession(
            id: UUID(),
            source: source,
            startDate: startDate,
            endDate: nil,
            basename: basename,
            audioURL: audioURL,
            transcriptURL: transcriptURL,
            metadataURL: metadataURL
        )
        Trace.file("recording.started", path: audioURL.path, extra: [
            "source": source.name,
            "format": outputFormat.rawValue,
            "sampleRate": Int(inputFormat.sampleRate)
        ])
        lastError = nil
    }

    func consume(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let writer, let copiedBuffer = buffer.deepCopy() else {
            return
        }

        writer.write(copiedBuffer)
    }

    func stop(transcriptText: String, saveTranscript: Bool, transcriptionEngine: String) throws -> RecordingSession? {
        guard var session = activeSession else {
            return nil
        }

        writer?.finish()
        writer = nil

        let endDate = Date()
        session.endDate = endDate
        let finalBasename = FileNamer.recordingBasename(
            sourceName: session.source.name,
            startDate: session.startDate,
            endDate: endDate
        )
        let finalAudioURL = session.audioURL.deletingLastPathComponent()
            .appendingPathComponent("\(finalBasename).\(currentFormat.rawValue)")
        let finalTranscriptURL = session.transcriptURL.deletingLastPathComponent()
            .appendingPathComponent("\(finalBasename).txt")
        let finalMetadataURL = session.metadataURL.deletingLastPathComponent()
            .appendingPathComponent("\(finalBasename).json")

        try moveReplacingExisting(from: session.audioURL, to: finalAudioURL)
        Trace.file("recording.finalized", path: finalAudioURL.path, extra: [
            "format": currentFormat.rawValue,
            "durationSeconds": String(format: "%.2f", endDate.timeIntervalSince(session.startDate))
        ])

        if saveTranscript {
            try transcriptText.write(to: finalTranscriptURL, atomically: true, encoding: .utf8)
            Trace.file("transcript.saved", path: finalTranscriptURL.path, extra: ["chars": transcriptText.count])
        }

        let metadata = RecordingMetadata(
            sourceID: session.source.id,
            sourceName: session.source.name,
            startedAt: session.startDate,
            endedAt: endDate,
            duration: endDate.timeIntervalSince(session.startDate),
            audioFormat: currentFormat.rawValue,
            transcriptionEngine: transcriptionEngine
        )
        let data = try JSONEncoder.voiceTranscribe.encode(metadata)
        try data.write(to: finalMetadataURL, options: .atomic)
        Trace.file("metadata.saved", path: finalMetadataURL.path)

        let finalized = RecordingSession(
            id: session.id,
            source: session.source,
            startDate: session.startDate,
            endDate: endDate,
            basename: finalBasename,
            audioURL: finalAudioURL,
            transcriptURL: finalTranscriptURL,
            metadataURL: finalMetadataURL
        )
        activeSession = nil
        return finalized
    }

    private func moveReplacingExisting(from source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private static func audioSettings(for outputFormat: AudioOutputFormat, inputFormat: AVAudioFormat) -> [String: Any] {
        let sampleRate = inputFormat.sampleRate
        let channels = Int(inputFormat.channelCount)

        switch outputFormat {
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128_000
            ]
        case .caf, .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        }
    }
}

private final class AsyncAudioFileWriter {
    private let queue = DispatchQueue(label: "VoiceTranscribe.RecordingWriter", qos: .utility)
    private let file: AVAudioFile
    private let onError: (Error) -> Void

    init(file: AVAudioFile, onError: @escaping (Error) -> Void) {
        self.file = file
        self.onError = onError
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        queue.async { [file, onError] in
            do {
                try file.write(from: buffer)
            } catch {
                onError(error)
            }
        }
    }

    func finish() {
        queue.sync {}
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength

        if let source = floatChannelData, let destination = copy.floatChannelData {
            let channelCount = Int(format.channelCount)
            let frameLength = Int(frameLength)
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copy
        }

        if let source = int16ChannelData, let destination = copy.int16ChannelData {
            let channelCount = Int(format.channelCount)
            let frameLength = Int(frameLength)
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copy
        }

        if let source = int32ChannelData, let destination = copy.int32ChannelData {
            let channelCount = Int(format.channelCount)
            let frameLength = Int(frameLength)
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copy
        }

        return nil
    }
}

private extension JSONEncoder {
    static var voiceTranscribe: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
