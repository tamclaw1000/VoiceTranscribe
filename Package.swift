// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceTranscribe",
    platforms: [
        .macOS("26.0")
    ],
    dependencies: [
        .package(path: "external/FluidAudio"),
        .package(path: "external/speech-swift-worktree"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceTranscribe",
            dependencies: [
                "FluidAudio",
                .product(name: "AudioCommon", package: "speech-swift-worktree"),
                .product(name: "SpeechVAD", package: "speech-swift-worktree"),
            ],
            path: "Sources/VoiceTranscribe"
        ),
        .testTarget(
            name: "VoiceTranscribeTests",
            dependencies: ["VoiceTranscribe"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
