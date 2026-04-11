// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VibePet",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "VibePet",
            dependencies: ["TOMLKit"],
            path: "Sources/VibePet",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "VibePetBridge",
            path: "Sources/VibePetBridge"
        ),
    ]
)
