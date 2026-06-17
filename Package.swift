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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.3")
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
            dependencies: [
                "AndroidDevAgentUI",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AndroidDevAgent",
            exclude: [
                "AssistantModelSetupPanel.swift",
                "AssistantModelCredentialStore.swift",
                "AgentSettingsPopover.swift",
                "AgentViewModelAssistantResponses.swift",
                "AgentViewModelModelSetup.swift",
                "AgentViewModelProjectFiles.swift",
                "AgentViewModel.swift",
                "AgentViewModelTypes.swift",
                "AgentWorkbenchShellTypes.swift",
                "AgentWorkbenchStylePrimitives.swift",
                "AgentWorkbenchView.swift",
                "AskAssistantCard.swift",
                "LaunchReadinessControls.swift",
                "LaunchReadinessSupport.swift"
            ],
            sources: ["AndroidDevAgentApp.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(
                    ["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"],
                    .when(platforms: [.macOS])
                )
            ]
        ),
        .executableTarget(
            name: "AndroidDevAgentSmokeTests",
            dependencies: ["AndroidDevAgentCore", "AndroidDevAgentUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AndroidDevAgentCoreLaunchTests",
            dependencies: ["AndroidDevAgentCore"],
            path: "Tests/AndroidDevAgentCoreLaunchTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .plugin(
            name: "RunCoreLaunchTestsPlugin",
            capability: .buildTool(),
            dependencies: ["AndroidDevAgentCoreLaunchTests"]
        ),
        .testTarget(
            name: "AndroidDevAgentCoreTests",
            plugins: ["RunCoreLaunchTestsPlugin"]
        )
    ]
)
