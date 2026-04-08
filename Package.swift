// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VibePet",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibePet",
            path: "Sources/VibePet",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "VibePetBridge",
            path: "Sources/VibePetBridge"
        ),
    ]
)
