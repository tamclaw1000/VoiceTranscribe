import AppKit
import AVFoundation
import Foundation
import Speech

protocol MicrophonePermissionProvider {
    func currentStatus() -> AVAuthorizationStatus
    func requestAccess() async -> AVAuthorizationStatus
}

struct SystemMicrophonePermissionProvider: MicrophonePermissionProvider {
    func currentStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestAccess() async -> AVAuthorizationStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .audio)
    }
}

@MainActor
final class PermissionService: ObservableObject {
    @Published private(set) var microphoneStatus: AVAuthorizationStatus
    @Published private(set) var speechStatus: SFSpeechRecognizerAuthorizationStatus
    @Published private(set) var hasTouchedRecordingDevice = false

    private let microphoneProvider: MicrophonePermissionProvider

    init(microphoneProvider: MicrophonePermissionProvider = SystemMicrophonePermissionProvider()) {
        self.microphoneProvider = microphoneProvider
        microphoneStatus = microphoneProvider.currentStatus()
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    var canCaptureAudio: Bool {
        microphoneStatus == .authorized
    }

    var canTranscribe: Bool {
        speechStatus == .authorized
    }

    func refresh() {
        microphoneStatus = microphoneProvider.currentStatus()
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestMicrophonePermission() async {
        hasTouchedRecordingDevice = true
        if microphoneStatus == .notDetermined {
            microphoneStatus = await microphoneProvider.requestAccess()
        } else {
            microphoneStatus = microphoneProvider.currentStatus()
        }
    }

    func authorizeFirstRecordingDeviceTouch() async -> Bool {
        hasTouchedRecordingDevice = true

        switch microphoneStatus {
        case .authorized:
            return true
        case .notDetermined:
            microphoneStatus = await microphoneProvider.requestAccess()
            return microphoneStatus == .authorized
        case .denied, .restricted:
            return false
        @unknown default:
            microphoneStatus = microphoneProvider.currentStatus()
            return microphoneStatus == .authorized
        }
    }

    func requestSpeechPermission() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.speechStatus = status
                    continuation.resume()
                }
            }
        }
    }

    func openSystemPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
