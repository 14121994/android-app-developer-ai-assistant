import Foundation

public struct AgentArchitecture: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let purpose: String
    public let implementation: String
    public let readinessPercent: Int

    public init(name: String, purpose: String, implementation: String, readinessPercent: Int) {
        self.name = name
        self.purpose = purpose
        self.implementation = implementation
        self.readinessPercent = readinessPercent
    }
}

public struct AgentFeature: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let maturity: String

    public init(name: String, description: String, maturity: String) {
        self.name = name
        self.description = description
        self.maturity = maturity
    }
}

public enum ToolCategory: String, CaseIterable, Sendable {
    case context = "Context"
    case code = "Code"
    case build = "Build"
    case test = "Test"
    case device = "Device"
    case safety = "Safety"
    case memory = "Memory"
    case summary = "Summary"
}

public struct ToolCapability: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let category: ToolCategory
    public let description: String
    public let requiresConfirmation: Bool
    public let isMVP: Bool

    public init(
        name: String,
        category: ToolCategory,
        description: String,
        requiresConfirmation: Bool,
        isMVP: Bool
    ) {
        self.name = name
        self.category = category
        self.description = description
        self.requiresConfirmation = requiresConfirmation
        self.isMVP = isMVP
    }
}

public enum SignalStrength: String, Sendable {
    case weak = "Weak"
    case medium = "Medium"
    case strong = "Strong"
}

public struct ProjectSignal: Identifiable, Hashable, Sendable {
    public var id: String { "\(label)-\(value)" }
    public let label: String
    public let value: String
    public let strength: SignalStrength

    public init(label: String, value: String, strength: SignalStrength) {
        self.label = label
        self.value = value
        self.strength = strength
    }
}

public enum StepState: String, Sendable {
    case queued = "Queued"
    case running = "Running"
    case blocked = "Blocked"
    case done = "Done"
}

public struct AgentPlanStep: Identifiable, Hashable, Sendable {
    public var id: Int { order }
    public let order: Int
    public let title: String
    public let detail: String
    public let state: StepState
    public let toolNames: [String]

    public init(order: Int, title: String, detail: String, state: StepState, toolNames: [String]) {
        self.order = order
        self.title = title
        self.detail = detail
        self.state = state
        self.toolNames = toolNames
    }
}

public struct ProjectProfile: Hashable, Sendable {
    public let rootPath: String
    public let packageName: String
    public let architecturePreference: String
    public let uiSystem: String
    public let minSDK: Int
    public let memoryNotes: String

    public init(
        rootPath: String,
        packageName: String,
        architecturePreference: String,
        uiSystem: String,
        minSDK: Int,
        memoryNotes: String
    ) {
        self.rootPath = rootPath
        self.packageName = packageName
        self.architecturePreference = architecturePreference
        self.uiSystem = uiSystem
        self.minSDK = minSDK
        self.memoryNotes = memoryNotes
    }

    public static func defaultProfile(rootPath: String = FileManager.default.currentDirectoryPath) -> ProjectProfile {
        ProjectProfile(
            rootPath: rootPath,
            packageName: "unknown.android.app",
            architecturePreference: "MVVM with repository boundaries",
            uiSystem: "Compose or XML based on the selected Android project",
            minSDK: 26,
            memoryNotes: "Prefer scoped changes, concise summaries, and Gradle verification after edits."
        )
    }

    public static func from(snapshot: WorkspaceSnapshot) -> ProjectProfile {
        ProjectProfile(
            rootPath: snapshot.rootPath,
            packageName: snapshot.packageName ?? "unknown.android.app",
            architecturePreference: "MVVM with repository boundaries",
            uiSystem: snapshot.usesCompose ? "Jetpack Compose detected" : "XML/native views or mixed UI detected",
            minSDK: snapshot.minSDK ?? 26,
            memoryNotes: "Use the selected macOS folder as the Android workspace and preserve unrelated files."
        )
    }
}

public struct WorkspaceSnapshot: Hashable, Sendable {
    public let rootPath: String
    public let fileCount: Int
    public let testFileCount: Int
    public let hasGradleWrapper: Bool
    public let hasSettingsGradle: Bool
    public let hasAndroidManifest: Bool
    public let usesCompose: Bool
    public let usesKotlin: Bool
    public let usesJava: Bool
    public let usesXMLLayouts: Bool
    public let packageName: String?
    public let minSDK: Int?
    public let targetSDK: Int?

    public init(
        rootPath: String,
        fileCount: Int,
        testFileCount: Int,
        hasGradleWrapper: Bool,
        hasSettingsGradle: Bool,
        hasAndroidManifest: Bool,
        usesCompose: Bool,
        usesKotlin: Bool,
        usesJava: Bool,
        usesXMLLayouts: Bool,
        packageName: String?,
        minSDK: Int?,
        targetSDK: Int?
    ) {
        self.rootPath = rootPath
        self.fileCount = fileCount
        self.testFileCount = testFileCount
        self.hasGradleWrapper = hasGradleWrapper
        self.hasSettingsGradle = hasSettingsGradle
        self.hasAndroidManifest = hasAndroidManifest
        self.usesCompose = usesCompose
        self.usesKotlin = usesKotlin
        self.usesJava = usesJava
        self.usesXMLLayouts = usesXMLLayouts
        self.packageName = packageName
        self.minSDK = minSDK
        self.targetSDK = targetSDK
    }

    public static func empty(rootPath: String) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            rootPath: rootPath,
            fileCount: 0,
            testFileCount: 0,
            hasGradleWrapper: false,
            hasSettingsGradle: false,
            hasAndroidManifest: false,
            usesCompose: false,
            usesKotlin: false,
            usesJava: false,
            usesXMLLayouts: false,
            packageName: nil,
            minSDK: nil,
            targetSDK: nil
        )
    }
}

public struct AgentPlan: Hashable, Sendable {
    public let originalRequest: String
    public let intent: String
    public let confidencePercent: Int
    public let contextSignals: [ProjectSignal]
    public let steps: [AgentPlanStep]
    public let tools: [ToolCapability]
    public let safetyChecks: [String]
    public let finalSummary: [String]

    public init(
        originalRequest: String,
        intent: String,
        confidencePercent: Int,
        contextSignals: [ProjectSignal],
        steps: [AgentPlanStep],
        tools: [ToolCapability],
        safetyChecks: [String],
        finalSummary: [String]
    ) {
        self.originalRequest = originalRequest
        self.intent = intent
        self.confidencePercent = confidencePercent
        self.contextSignals = contextSignals
        self.steps = steps
        self.tools = tools
        self.safetyChecks = safetyChecks
        self.finalSummary = finalSummary
    }
}

public struct ToolCommand: Identifiable, Hashable, Sendable {
    public var id: String { title + preview }
    public let title: String
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String

    public init(title: String, executable: String, arguments: [String], workingDirectory: String) {
        self.title = title
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    public var preview: String {
        ([executable] + arguments).map { value in
            value.contains(" ") ? "'\(value)'" : value
        }.joined(separator: " ")
    }
}

public struct CommandResult: Hashable, Sendable {
    public let command: ToolCommand
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(command: ToolCommand, exitCode: Int32, standardOutput: String, standardError: String) {
        self.command = command
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        exitCode == 0
    }
}
