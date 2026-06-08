public struct AgentCatalog: Sendable {
    public let architectures: [AgentArchitecture]
    public let features: [AgentFeature]
    public let tools: [ToolCapability]

    public init() {
        architectures = [
            AgentArchitecture(
                name: "macOS Workbench Interface",
                purpose: "Give the developer a native desktop console for prompts, project selection, command output, and plan review.",
                implementation: "SwiftUI app with project picker, prompt editor, tabs, Android tool buttons, and structured plan panels.",
                readinessPercent: 90
            ),
            AgentArchitecture(
                name: "Android Workspace Context Engine",
                purpose: "Understand the selected Android project before suggesting edits or commands.",
                implementation: "AndroidWorkspaceScanner and LocalProjectContextEngine inspect Gradle, Manifest, source, resources, and tests.",
                readinessPercent: 82
            ),
            AgentArchitecture(
                name: "Local Tool Executor",
                purpose: "Use macOS to run Android development tools against the chosen workspace.",
                implementation: "ProcessRunner and AndroidToolCommandFactory prepare Gradle and ADB commands with captured output.",
                readinessPercent: 80
            ),
            AgentArchitecture(
                name: "Planning + Verification Loop",
                purpose: "Convert a request into inspect, patch, build, test, device, and report stages.",
                implementation: "DevelopmentAgent creates ordered plans with selected tools, context signals, and verification steps.",
                readinessPercent: 86
            ),
            AgentArchitecture(
                name: "Safety + Permission Layer",
                purpose: "Keep user files, secrets, logs, and device actions controlled from the desktop host.",
                implementation: "SafetyPolicy adds diff gates, undo checkpoints, secret redaction, workspace boundaries, and confirmation rules.",
                readinessPercent: 84
            )
        ]

        features = [
            AgentFeature(name: "Code Generation", description: "Plan Activities, screens, ViewModels, repositories, Room, Retrofit, and tests.", maturity: "MVP"),
            AgentFeature(name: "Error Fixing", description: "Triage compiler errors, Gradle failures, runtime crashes, and stack traces.", maturity: "MVP"),
            AgentFeature(name: "Android-Aware Knowledge", description: "Reason about lifecycle, permissions, storage, coroutines, layouts, and release concerns.", maturity: "Core"),
            AgentFeature(name: "UI Builder Assistance", description: "Generate Compose or XML UI plans, preview states, themes, and accessibility checks.", maturity: "MVP"),
            AgentFeature(name: "Test Automation", description: "Create and run unit, integration, and UI test plans with failure explanations.", maturity: "MVP"),
            AgentFeature(name: "Device / Emulator Control", description: "Install, launch, tap, type, screenshot, and inspect Logcat through ADB.", maturity: "MVP"),
            AgentFeature(name: "Dependency Management", description: "Add libraries, edit manifests, detect version conflicts, and explain tradeoffs.", maturity: "MVP"),
            AgentFeature(name: "Memory and Preferences", description: "Persist package, architecture, UI stack, naming, SDK, and library preferences.", maturity: "Core"),
            AgentFeature(name: "Security and Privacy", description: "Detect secrets, avoid unsafe uploads, and confirm destructive or sensitive operations.", maturity: "Core"),
            AgentFeature(name: "Developer Experience", description: "Return concise summaries, changed files, verification status, and next actions.", maturity: "MVP")
        ]

        tools = [
            ToolCapability(name: "Project indexer", category: .context, description: "Scan Gradle, manifest, source, resources, and tests.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Semantic file retriever", category: .context, description: "Load only files that match the task and local symbols.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Patch editor", category: .code, description: "Create scoped file diffs and preserve unrelated edits.", requiresConfirmation: true, isMVP: true),
            ToolCapability(name: "Undo journal", category: .safety, description: "Track checkpoints and rollback candidates for every edit session.", requiresConfirmation: true, isMVP: true),
            ToolCapability(name: "Gradle build runner", category: .build, description: "Run assemble, lint, and compile tasks with parsed failure output.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Unit test runner", category: .test, description: "Run local JVM tests and summarize failing assertions.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Instrumentation test runner", category: .test, description: "Run device tests and connect failures to UI or lifecycle changes.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Logcat analyzer", category: .device, description: "Read crashes, ANRs, permission denials, and stack traces.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Emulator driver", category: .device, description: "Install, launch, tap, type, swipe, and capture screenshots.", requiresConfirmation: true, isMVP: true),
            ToolCapability(name: "Screenshot inspector", category: .device, description: "Review layout, clipping, contrast, and navigation state.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Screen generator", category: .code, description: "Draft Compose or XML screens with state and accessibility hooks.", requiresConfirmation: true, isMVP: true),
            ToolCapability(name: "Dependency editor", category: .code, description: "Update Gradle dependencies and detect version conflicts.", requiresConfirmation: true, isMVP: true),
            ToolCapability(name: "Manifest editor", category: .code, description: "Add permissions, services, activities, and deep links with review gates.", requiresConfirmation: true, isMVP: true),
            ToolCapability(name: "Secret scanner", category: .safety, description: "Redact API keys, signing data, and private configuration from prompts.", requiresConfirmation: false, isMVP: true),
            ToolCapability(name: "Summary reporter", category: .summary, description: "Explain changed files, verification, risks, and useful next steps.", requiresConfirmation: false, isMVP: true)
        ]
    }

    public func tool(named name: String) -> ToolCapability? {
        tools.first { $0.name == name }
    }
}
