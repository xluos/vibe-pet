// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VibePet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VibePet",
            path: "Sources/VibePet",
            resources: [.copy("Resources/Sounds")]
        ),
        .executableTarget(
            name: "VibePetBridge",
            path: "Sources/VibePetBridge"
        ),
    ]
)
