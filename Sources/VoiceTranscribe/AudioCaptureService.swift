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
            guard let copiedBuffer = Self.copyBuffer(buffer) else {
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.process(buffer: copiedBuffer, time: time)
                }
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
        let displayLevel = Self.displayLevel(forRMS: metrics.rms, peak: metrics.peak)
        levelHistory.append(displayLevel)
        if levelHistory.droppedCount > 0 {
            overflowWarning = "Visualization buffer dropped stale frames."
        }

        let now = Date()
        if now.timeIntervalSince(lastVisualizationUpdate) >= visualizationInterval {
            visualization = VisualizationSnapshot(
                rmsLevel: displayLevel,
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
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else {
            return (0, 0)
        }

        var sumSquares: Float = 0
        var peak: Float = 0
        let sampleCount = channelCount * frameLength

        if let channelData = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    let value = min(abs(samples[frame]), 1.0)
                    peak = max(peak, value)
                    sumSquares += value * value
                }
            }
        } else if let channelData = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    let value = min(abs(Float(samples[frame]) / Float(Int16.max)), 1.0)
                    peak = max(peak, value)
                    sumSquares += value * value
                }
            }
        } else if let channelData = buffer.int32ChannelData {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    let value = min(abs(Float(samples[frame]) / Float(Int32.max)), 1.0)
                    peak = max(peak, value)
                    sumSquares += value * value
                }
            }
        } else {
            return (0, 0)
        }

        return (sqrt(sumSquares / Float(sampleCount)), min(peak, 1.0))
    }

    static func displayLevel(forRMS rms: Float, peak: Float) -> Float {
        let blended = max(rms, peak * 0.35)
        guard blended > 0 else {
            return 0
        }
        return min(pow(blended, 0.35), 1.0)
    }

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Float>.size)
            }
            return copy
        }

        if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Int16>.size)
            }
            return copy
        }

        if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Int32>.size)
            }
            return copy
        }

        return nil
    }
}
