import AVFoundation
import AudioToolbox
import Foundation

typealias AudioConsumer = (AVAudioPCMBuffer, AVAudioTime) -> Void

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published private(set) var status: CaptureStatus = .idle
    @Published private(set) var activeSource: SoundInputSource?
    @Published private(set) var visualization = VisualizationSnapshot()
    @Published private(set) var overflowWarning: String?
    @Published private(set) var activeConsumerIDs: Set<String> = []

    private let engine = AVAudioEngine()
    private var consumers: [String: AudioConsumer] = [:]
    private var levelHistory = BoundedBuffer<Float>(capacity: 180)
    private var lastVisualizationUpdate = Date.distantPast
    private let visualizationInterval: TimeInterval = 1.0 / 30.0

    var isRunning: Bool {
        engine.isRunning
    }

    var currentInputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start(source: SoundInputSource) throws {
        if case .active(let sourceID) = status, sourceID == source.id {
            return
        }

        stop()
        status = .starting
        activeSource = source

        let inputNode = engine.inputNode
        if let audioUnit = inputNode.audioUnit {
            var deviceID = source.audioDeviceID
            let result = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard result == noErr else {
                status = .failed("Could not select input device \(source.name). Core Audio status \(result).")
                throw AudioDeviceError.coreAudioStatus(result)
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            Task { @MainActor in
                self?.process(buffer: buffer, time: time)
            }
        }

        do {
            try engine.start()
            status = .active(sourceID: source.id)
        } catch {
            inputNode.removeTap(onBus: 0)
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    func stopIfUnused() {
        if consumers.isEmpty {
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        status = .idle
        activeSource = nil
        visualization = VisualizationSnapshot()
        levelHistory = BoundedBuffer<Float>(capacity: 180)
        overflowWarning = nil
        activeConsumerIDs = []
    }

    func addConsumer(id: String, consumer: @escaping AudioConsumer) {
        consumers[id] = consumer
        activeConsumerIDs.insert(id)
    }

    func removeConsumer(id: String) {
        consumers[id] = nil
        activeConsumerIDs.remove(id)
    }

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let metrics = Self.metrics(for: buffer)
        levelHistory.append(metrics.rms)
        if levelHistory.droppedCount > 0 {
            overflowWarning = "Visualization buffer dropped stale frames."
        }

        let now = Date()
        if now.timeIntervalSince(lastVisualizationUpdate) >= visualizationInterval {
            visualization = VisualizationSnapshot(
                rmsLevel: metrics.rms,
                peakLevel: metrics.peak,
                isClipping: metrics.peak >= 0.98,
                history: levelHistory.elements
            )
            lastVisualizationUpdate = now
        }

        for consumer in consumers.values {
            consumer(buffer, time)
        }
    }

    static func metrics(for buffer: AVAudioPCMBuffer) -> (rms: Float, peak: Float) {
        guard let channelData = buffer.floatChannelData else {
            return (0, 0)
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            return (0, 0)
        }

        var sumSquares: Float = 0
        var peak: Float = 0
        let sampleCount = channelCount * frameLength

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let value = abs(samples[frame])
                peak = max(peak, value)
                sumSquares += value * value
            }
        }

        return (sqrt(sumSquares / Float(sampleCount)), min(peak, 1.0))
    }
}
