// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceTranscribe",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceTranscribe",
            path: "Sources/VoiceTranscribe"
        ),
        .testTarget(
            name: "VoiceTranscribeTests",
            dependencies: ["VoiceTranscribe"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
