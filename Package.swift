// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AndroidDevelopmentAgent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AndroidDevAgentUI", targets: ["AndroidDevAgentUI"]),
        .executable(name: "AndroidDevAgent", targets: ["AndroidDevAgent"]),
        .executable(name: "AndroidDevAgentSmokeTests", targets: ["AndroidDevAgentSmokeTests"])
    ],
    targets: [
        .target(
            name: "AndroidDevAgentCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AndroidDevAgentUI",
            dependencies: ["AndroidDevAgentCore"],
            path: "Sources/AndroidDevAgent",
            exclude: ["AndroidDevAgentApp.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AndroidDevAgent",
            dependencies: ["AndroidDevAgentUI"],
            path: "Sources/AndroidDevAgent",
            exclude: ["AgentViewModel.swift", "AgentWorkbenchView.swift"],
            sources: ["AndroidDevAgentApp.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AndroidDevAgentSmokeTests",
            dependencies: ["AndroidDevAgentCore", "AndroidDevAgentUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
