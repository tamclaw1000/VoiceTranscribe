import AudioToolbox
import CoreAudio
import Foundation

@MainActor
final class AudioDeviceService: ObservableObject {
    @Published private(set) var sources: [SoundInputSource] = []
    @Published private(set) var lastError: String?

    private var refreshTimer: Timer?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        do {
            let devices = try Self.allAudioDevices()
            let defaultInput = try? Self.defaultInputDeviceID()
            let mapped = devices.compactMap { deviceID -> SoundInputSource? in
                guard let channelCount = try? Self.inputChannelCount(for: deviceID), channelCount > 0 else {
                    return nil
                }

                let uid = (try? Self.stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID)) ?? "\(deviceID)"
                let name = (try? Self.stringProperty(kAudioObjectPropertyName, deviceID: deviceID)) ?? "Input \(deviceID)"
                let manufacturer = try? Self.stringProperty(kAudioObjectPropertyManufacturer, deviceID: deviceID)
                let sampleRate = try? Self.doubleProperty(kAudioDevicePropertyNominalSampleRate, deviceID: deviceID)
                let transport = try? Self.transportType(for: deviceID)

                return SoundInputSource(
                    id: uid,
                    audioDeviceID: deviceID,
                    name: name,
                    manufacturer: manufacturer,
                    channelCount: channelCount,
                    sampleRate: sampleRate,
                    transportType: transport,
                    isDefaultInput: deviceID == defaultInput,
                    isAvailable: true
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefaultInput != rhs.isDefaultInput {
                    return lhs.isDefaultInput
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            if mapped != sources {
                Trace.event("devices.changed", [
                    "previousCount": sources.count,
                    "newCount": mapped.count,
                    "devices": mapped.map { $0.name }.joined(separator: ", ")
                ])
                sources = mapped
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func allAudioDevices() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        )
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }
        return devices
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }
        return deviceID
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }
        return (value?.takeUnretainedValue() as String?) ?? ""
    }

    private static func doubleProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) throws -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64()
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }
        return value
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }
        let bufferListPointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transportType(for deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32()
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            throw AudioDeviceError.coreAudioStatus(status)
        }

        switch value {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-in"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        case kAudioDeviceTransportTypeAggregate:
            return "Aggregate"
        case kAudioDeviceTransportTypePCI:
            return "PCI"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        default:
            return "Other"
        }
    }
}

enum AudioDeviceError: LocalizedError {
    case coreAudioStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .coreAudioStatus(let status):
            return "Core Audio returned status \(status)."
        }
    }
}
