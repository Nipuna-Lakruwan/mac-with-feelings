// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWithFeelings",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacWithFeelings", targets: ["MacWithFeelings"]),
    ],
    targets: [
        // Pure logic: vitals, moods, events, prompts, fallback lines, the Ollama client.
        .target(name: "FeelingsCore"),
        // The menu-bar app: sensors, speech, face, popover.
        .executableTarget(name: "MacWithFeelings", dependencies: ["FeelingsCore"]),
        .testTarget(name: "FeelingsCoreTests", dependencies: ["FeelingsCore"]),
    ]
)
