// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundBlink",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SoundBlink",
            path: "Sources/SoundBlink"
        ),
    ]
)
