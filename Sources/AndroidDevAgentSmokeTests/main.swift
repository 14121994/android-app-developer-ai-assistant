import AndroidDevAgentCore
import AndroidDevAgentUI
import Foundation

enum SmokeTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): return message
        }
    }
}

struct SmokeTestRunner {
    private(set) var passed = 0
    private(set) var failed = 0

    mutating func run(_ name: String, _ test: () throws -> Void) {
        do {
            try test()
            passed += 1
            print("PASS \(name)")
        } catch {
            failed += 1
            print("FAIL \(name): \(error)")
        }
    }

    mutating func runAsync(_ name: String, _ test: () async throws -> Void) async {
        do {
            try await test()
            passed += 1
            print("PASS \(name)")
        } catch {
            failed += 1
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        print("AndroidDevAgentSmokeTests: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SmokeTestFailure.failed(message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw SmokeTestFailure.failed("\(message) Expected \(expected), got \(actual).")
    }
}

func expectContains(_ values: [String], _ expected: String, _ message: String) throws {
    try expect(values.contains(expected), message)
}

func sampleSnapshot(
    rootPath: String = "/tmp/android-project",
    fileCount: Int = 120,
    testFileCount: Int = 18,
    hasGradleWrapper: Bool = true,
    hasAndroidManifest: Bool = true,
    usesCompose: Bool = false,
    packageName: String? = "com.example.sample",
    minSDK: Int? = 26,
    targetSDK: Int? = 34
) -> WorkspaceSnapshot {
    WorkspaceSnapshot(
        rootPath: rootPath,
        fileCount: fileCount,
        testFileCount: testFileCount,
        hasGradleWrapper: hasGradleWrapper,
        hasSettingsGradle: true,
        hasAndroidManifest: hasAndroidManifest,
        usesCompose: usesCompose,
        usesKotlin: true,
        usesJava: false,
        usesXMLLayouts: !usesCompose,
        packageName: packageName,
        minSDK: minSDK,
        targetSDK: targetSDK
    )
}

func makeTempDirectory(_ name: String) throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("AndroidDevAgent-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func toolNames(_ plan: AgentPlan) -> [String] {
    plan.tools.map(\.name)
}

func firstArguments(_ arguments: [String], _ count: Int) -> [String] {
    Array(arguments[0..<Swift.min(arguments.count, count)])
}

func runPlannerTests(runner: inout SmokeTestRunner) {
    runner.run("planner routes UI request to screen, screenshot, and tests") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Create a settings XML screen, add tests, and inspect the screenshot on an emulator.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expectEqual(plan.intent, "Android UI implementation", "UI request intent should be Android UI implementation.")
        try expectContains(toolNames(plan), "Screen generator", "UI plan should include Screen generator.")
        try expectContains(toolNames(plan), "Screenshot inspector", "UI plan should include Screenshot inspector.")
        try expectContains(toolNames(plan), "Unit test runner", "UI plan should include Unit test runner.")
        try expect(plan.steps.contains { $0.title == "Design Android UI change" }, "UI plan should include a UI design step.")
    }

    runner.run("planner routes crash request to logcat and redaction safety") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Analyze this NullPointerException crash from Logcat and propose a safe patch.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expectEqual(plan.intent, "Crash and Logcat triage", "Crash request intent should be Logcat triage.")
        try expectContains(toolNames(plan), "Logcat analyzer", "Crash plan should include Logcat analyzer.")
        try expectContains(toolNames(plan), "Emulator driver", "Crash plan should include Emulator driver.")
        try expect(plan.safetyChecks.contains { $0.contains("Redact personal data") }, "Crash plan should include log redaction safety.")
    }

    runner.run("planner routes Gradle manifest request to configuration repair") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Fix a Gradle sync issue, update dependencies, and add a manifest permission.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expectEqual(plan.intent, "Build and dependency repair", "Gradle request should choose build/dependency intent.")
        try expectContains(toolNames(plan), "Dependency editor", "Gradle repair should include Dependency editor.")
        try expectContains(toolNames(plan), "Manifest editor", "Manifest repair should include Manifest editor.")
        try expect(plan.steps.contains { $0.title == "Repair project configuration" }, "Gradle repair should include configuration step.")
    }

    runner.run("planner normalizes empty request into useful default") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "   \n  ",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expect(plan.originalRequest.contains("dashboard screen"), "Empty request should produce the default dashboard request.")
        try expectEqual(plan.intent, "Android UI implementation", "Default request should be UI implementation.")
        try expectContains(toolNames(plan), "Screen generator", "Default request should include Screen generator.")
        try expectContains(toolNames(plan), "Unit test runner", "Default request should include Unit test runner.")
        try expectContains(toolNames(plan), "Emulator driver", "Default request should include Emulator driver.")
    }

    runner.run("planner keeps release readiness separate from build repair") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Prepare release signing, R8, and Play Store readiness checklist.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expectEqual(plan.intent, "Release readiness", "Release request should choose release readiness intent.")
        try expect(plan.safetyChecks.contains { $0.contains("Play release implications") }, "Release plan should include Play release safety.")
    }

    runner.run("tool router does not duplicate tools") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Build a Compose screen, run emulator screenshot checks, and inspect device logs.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )
        let names = toolNames(plan)
        try expectEqual(Set(names).count, names.count, "Tool names should be unique.")
    }

    runner.run("catalog keeps expected architecture and feature coverage") {
        let catalog = AgentCatalog()
        try expectEqual(catalog.architectures.count, 5, "Catalog should expose five architectures.")
        try expectEqual(catalog.features.count, 10, "Catalog should expose ten feature areas.")
        try expect(catalog.tools.count >= 15, "Catalog should expose the MVP tool set.")
        try expect(catalog.tools.allSatisfy(\.isMVP), "All current tools should be part of the MVP.")
    }

    runner.run("assistant TaskDroid config targets local planner model") {
        let config = AssistantOrchestrationConfig(mode: .deep, openAIAPIKey: nil)
        try expectEqual(
            config.taskDroidBaseURL?.absoluteString,
            "http://127.0.0.1:8000",
            "TaskDroid should default to the local planner API."
        )
        try expectEqual(
            Int(config.taskDroidTimeoutSeconds),
            360,
            "TaskDroid timeout should allow local vLLM-backed planner responses."
        )
        try expect(config.preferTaskDroid, "TaskDroid should be preferred for bound Android planner modes.")
    }

    runner.run("assistant modes expose read-only bound model metadata") {
        try expectEqual(
            AssistantModelMode.automatic.boundModels.map(\.modelID),
            ["taskdroid-android-planner-v1", "taskdroid-android-planner-v1"],
            "Auto mode should describe both conditional model routes."
        )
        try expectEqual(
            AssistantModelMode.fast.boundModels.map(\.modelID),
            ["taskdroid-android-planner-v1"],
            "Fast mode should describe the fast model route."
        )
        try expectEqual(
            AssistantModelMode.deep.boundModels.map(\.modelID),
            ["taskdroid-android-planner-v1"],
            "Deep mode should describe the deep model route."
        )
        try expectEqual(
            AssistantModelMode.privateLocal.boundModels.map(\.modelID),
            ["taskdroid-android-planner-v1"],
            "Private mode should describe the local fallback route."
        )
        try expect(
            AssistantModelMode.automatic.boundModelSummary.contains("TaskDroid Android Planner"),
            "Auto mode summary should render both bound models."
        )
    }
}

func runScannerTests(runner: inout SmokeTestRunner) {
    runner.run("scanner reads Groovy Gradle and Manifest signals") {
        let root = try makeTempDirectory("groovy-scan")
        let app = root.appendingPathComponent("app")
        let manifest = app.appendingPathComponent("src/main/AndroidManifest.xml")

        try write("pluginManagement {}\ninclude ':app'", to: root.appendingPathComponent("settings.gradle"))
        try write(
            """
            plugins { id 'com.android.application' }
            android {
                namespace 'com.example.sample'
                defaultConfig {
                    applicationId 'com.example.sample'
                    minSdk 26
                    targetSdk 34
                }
            }
            """,
            to: app.appendingPathComponent("build.gradle")
        )
        try write("<manifest package=\"com.example.sample\" />", to: manifest)

        let snapshot = AndroidWorkspaceScanner().scan(rootPath: root.path)
        try expect(snapshot.hasSettingsGradle, "Scanner should detect settings.gradle.")
        try expect(snapshot.hasAndroidManifest, "Scanner should detect AndroidManifest.xml.")
        try expectEqual(snapshot.packageName, "com.example.sample", "Scanner should detect package/applicationId.")
        try expectEqual(snapshot.minSDK, 26, "Scanner should detect minSdk.")
        try expectEqual(snapshot.targetSDK, 34, "Scanner should detect targetSdk.")
    }

    runner.run("scanner reads Kotlin DSL and Compose signals") {
        let root = try makeTempDirectory("kts-compose-scan")
        let app = root.appendingPathComponent("app")

        try write("pluginManagement {}\ninclude(\":app\")", to: root.appendingPathComponent("settings.gradle.kts"))
        try write(
            """
            plugins { id("com.android.application") }
            android {
                namespace = "com.example.compose"
                defaultConfig {
                    applicationId = "com.example.compose"
                    minSdk = 24
                    targetSdk = 35
                }
                buildFeatures { compose = true }
            }
            """,
            to: app.appendingPathComponent("build.gradle.kts")
        )
        try write(
            """
            package com.example.compose
            import androidx.compose.runtime.Composable
            @Composable fun Greeting() {}
            """,
            to: app.appendingPathComponent("src/main/java/com/example/compose/Greeting.kt")
        )
        try write("<manifest />", to: app.appendingPathComponent("src/main/AndroidManifest.xml"))

        let snapshot = AndroidWorkspaceScanner().scan(rootPath: root.path)
        try expect(snapshot.usesCompose, "Scanner should detect Compose from Gradle or source.")
        try expect(snapshot.usesKotlin, "Scanner should detect Kotlin source.")
        try expectEqual(snapshot.packageName, "com.example.compose", "Scanner should read KTS applicationId.")
        try expectEqual(snapshot.minSDK, 24, "Scanner should read KTS minSdk.")
        try expectEqual(snapshot.targetSDK, 35, "Scanner should read KTS targetSdk.")
    }

    runner.run("scanner counts test files and skips generated build outputs") {
        let root = try makeTempDirectory("skip-build-scan")
        let app = root.appendingPathComponent("app")

        try write("include ':app'", to: root.appendingPathComponent("settings.gradle"))
        try write("android { namespace 'com.example.skip' }", to: app.appendingPathComponent("build.gradle"))
        try write("<manifest />", to: app.appendingPathComponent("src/main/AndroidManifest.xml"))
        try write("class MainActivity", to: app.appendingPathComponent("src/main/java/com/example/skip/MainActivity.kt"))
        try write("class MainActivityTest", to: app.appendingPathComponent("src/test/java/com/example/skip/MainActivityTest.kt"))
        try write("class MainActivityDeviceTest", to: app.appendingPathComponent("src/androidTest/java/com/example/skip/MainActivityDeviceTest.kt"))
        try write("class Generated", to: app.appendingPathComponent("build/generated/source/Generated.kt"))

        let snapshot = AndroidWorkspaceScanner().scan(rootPath: root.path)
        try expectEqual(snapshot.testFileCount, 2, "Scanner should count unit and Android test files.")
        try expect(snapshot.fileCount < 7, "Scanner should skip build/generated output.")
        try expect(snapshot.usesKotlin, "Scanner should detect Kotlin source outside build output.")
    }

    runner.run("profile falls back cleanly for sparse workspace") {
        let snapshot = WorkspaceSnapshot.empty(rootPath: "/tmp/empty-android-project")
        let profile = ProjectProfile.from(snapshot: snapshot)

        try expectEqual(profile.packageName, "unknown.android.app", "Sparse profile should use unknown package fallback.")
        try expectEqual(profile.minSDK, 26, "Sparse profile should use minSdk fallback.")
        try expect(profile.uiSystem.contains("XML/native views"), "Sparse profile should use mixed UI fallback.")
    }
}

func runCommandFactoryTests(runner: inout SmokeTestRunner) {
    runner.run("Gradle command uses executable wrapper when available") {
        let root = try makeTempDirectory("executable-wrapper")
        let wrapper = root.appendingPathComponent("gradlew")
        try write("#!/bin/sh\necho wrapper\n", to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

        let command = AndroidToolCommandFactory.assembleDebug(rootPath: root.path)
        try expectEqual(command.executable, wrapper.path, "Executable wrapper should be invoked directly.")
        try expectEqual(command.arguments.first, "assembleDebug", "assemble command should pass assembleDebug task.")
    }

    runner.run("Gradle command uses shell for non-executable wrapper") {
        let root = try makeTempDirectory("non-executable-wrapper")
        let wrapper = root.appendingPathComponent("gradlew")
        try write("#!/bin/sh\necho wrapper\n", to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: wrapper.path)

        let command = AndroidToolCommandFactory.gradleTest(rootPath: root.path)
        try expectEqual(command.executable, "/bin/sh", "Non-executable wrapper should be invoked through sh.")
        try expectEqual(firstArguments(command.arguments, 2), ["./gradlew", "testDebugUnitTest"], "Shell wrapper command should include Gradle task.")
    }

    runner.run("Gradle command falls back to env gradle when wrapper is missing") {
        let root = try makeTempDirectory("missing-wrapper")
        let command = AndroidToolCommandFactory.connectedAndroidTest(rootPath: root.path)

        try expectEqual(command.executable, "/usr/bin/env", "Missing wrapper should use env fallback.")
        try expectEqual(firstArguments(command.arguments, 2), ["gradle", "connectedDebugAndroidTest"], "Gradle fallback should invoke gradle task.")
    }

    runner.run("ADB command includes adb executable or env adb fallback") {
        let root = try makeTempDirectory("adb-command")
        let command = AndroidToolCommandFactory.listDevices(rootPath: root.path)

        if command.executable == "/usr/bin/env" {
            try expectEqual(firstArguments(command.arguments, 2), ["adb", "devices"], "env fallback should invoke adb devices.")
        } else {
            try expect(command.executable.hasSuffix("/adb"), "Direct ADB command should point to adb executable.")
            try expectEqual(firstArguments(command.arguments, 2), ["devices", "-l"], "Direct ADB command should pass devices arguments.")
        }
    }

    runner.run("Wireless debugging commands use adb pair connect and disconnect") {
        let root = try makeTempDirectory("wireless-adb-command")
        let mdns = AndroidToolCommandFactory.mdnsServices(rootPath: root.path)
        let pair = AndroidToolCommandFactory.pairWirelessDevice(rootPath: root.path, hostPort: "192.168.1.10:37099", pairingCode: "123456")
        let connect = AndroidToolCommandFactory.connectWirelessDevice(rootPath: root.path, hostPort: "192.168.1.10:42177")
        let disconnect = AndroidToolCommandFactory.disconnectWirelessDevice(rootPath: root.path, hostPort: "192.168.1.10:42177")

        let mdnsArguments = mdns.executable == "/usr/bin/env" ? Array(mdns.arguments.dropFirst()) : mdns.arguments
        let pairArguments = pair.executable == "/usr/bin/env" ? Array(pair.arguments.dropFirst()) : pair.arguments
        let connectArguments = connect.executable == "/usr/bin/env" ? Array(connect.arguments.dropFirst()) : connect.arguments
        let disconnectArguments = disconnect.executable == "/usr/bin/env" ? Array(disconnect.arguments.dropFirst()) : disconnect.arguments

        try expectEqual(mdnsArguments, ["mdns", "services"], "Discovery command should pass adb mdns services.")
        try expectEqual(pairArguments, ["pair", "192.168.1.10:37099", "123456"], "Pair command should pass adb pair host:port code.")
        try expectEqual(connectArguments, ["connect", "192.168.1.10:42177"], "Connect command should pass adb connect host:port.")
        try expectEqual(disconnectArguments, ["disconnect", "192.168.1.10:42177"], "Disconnect command should pass adb disconnect host:port.")
    }

    runner.run("ToolCommand preview quotes arguments with spaces") {
        let command = ToolCommand(
            title: "Preview",
            executable: "/bin/echo",
            arguments: ["hello world", "again"],
            workingDirectory: "/tmp"
        )

        try expect(command.preview.contains("'hello world'"), "Preview should quote arguments containing spaces.")
    }
}

func runProcessRunnerTests(runner: inout SmokeTestRunner) async {
    await runner.runAsync("ProcessRunner captures stdout for successful command") {
        let command = ToolCommand(
            title: "Echo",
            executable: "/bin/echo",
            arguments: ["agent-ok"],
            workingDirectory: "/tmp"
        )
        let result = await ProcessRunner().run(command)

        try expect(result.succeeded, "Echo command should succeed.")
        try expect(result.standardOutput.contains("agent-ok"), "Echo output should be captured.")
    }

    await runner.runAsync("ProcessRunner returns structured failure for missing executable") {
        let command = ToolCommand(
            title: "Missing",
            executable: "/path/that/does/not/exist",
            arguments: [],
            workingDirectory: "/tmp"
        )
        let result = await ProcessRunner().run(command)

        try expectEqual(result.exitCode, -1, "Missing executable should return -1.")
        try expect(!result.standardError.isEmpty, "Missing executable should capture an error message.")
    }
}

func runUICoverageTests(runner: inout SmokeTestRunner) async {
    await runner.runAsync("assistant surfaces TaskDroid errors without fallback") {
        let orchestrator = AssistantModelOrchestrator()
        let snapshot = sampleSnapshot()
        let request = AssistantModelRequest(
            prompt: "Build an Android Compose login screen.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot,
            planIntent: "Android UI implementation",
            modules: ["app"],
            variants: ["debug"],
            contextFiles: [],
            commandSummary: nil,
            recentCommandOutput: nil
        )
        let response = await orchestrator.answer(
            request: request,
            config: AssistantOrchestrationConfig(
                mode: .deep,
                openAIAPIKey: "unused",
                allowRemoteModels: true,
                taskDroidBaseURL: URL(string: "http://127.0.0.1:1")!,
                preferTaskDroid: true,
                taskDroidTimeoutSeconds: 0.5
            )
        )

        try expectEqual(response.provider, .taskDroid, "TaskDroid failure should stay attributed to TaskDroid.")
        try expectEqual(response.modelID, "taskdroid-android-planner-v1", "TaskDroid failure should keep the bound model ID.")
        try expect(response.answer.contains("could not generate a response"), "TaskDroid failure should render an error response.")
        try expect(response.answer.contains("No OpenAI, local, or deterministic rule fallback"), "TaskDroid failure should not be replaced by fallback output.")
        try expect(response.plannedActions.isEmpty, "TaskDroid failure should not invent planned actions.")
    }

    await runner.runAsync("SwiftUI workbench coverage harness exercises app UI states") {
        let touched = await MainActor.run {
            AndroidDevAgentUICoverageHarness.exercise()
        }

        try expect(touched > 150, "UI coverage harness should exercise many visible app states.")
    }

    await runner.runAsync("Ask Assistant returns project-specific answers") {
        let diagnostics = await AndroidDevAgentUICoverageHarness.askAssistantDiagnostics()
        let overview = diagnostics["overview"] ?? ""
        let overviewChat = diagnostics["overviewChat"] ?? ""
        let ludo = diagnostics["ludo"] ?? ""
        let actionSummary = diagnostics["actionSummary"] ?? ""
        let modelStatus = diagnostics["modelStatus"] ?? ""
        let modelDetail = diagnostics["modelDetail"] ?? ""

        try expect(overview.contains("Coverage") || overview.contains("coverage"), "Overview response should use the loaded project identity.")
        try expect(overview.contains("48 files"), "Overview response should include scanned file context.")
        try expect(overviewChat.contains(overview), "Chat transcript should display the generated assistant response.")
        try expect(ludo.contains("com.example.coverage"), "Ludo prompt should use the loaded project context.")
        try expect(actionSummary.contains("Opened likely edit targets"), "Code-change prompts should perform a concrete safe assistant action.")
        try expect(modelStatus.contains("fallback") || modelStatus.contains("answered"), "Ask should report the model orchestration status.")
        try expect(modelDetail.contains("retrieval"), "Ask should report retrieval/model context details.")
        try expect(!ludo.contains("Clarify task contract"), "Ask response should not be a raw plan step list.")
    }
}

@main
struct AndroidDevAgentSmokeTests {
    static func main() async {
        var runner = SmokeTestRunner()
        runPlannerTests(runner: &runner)
        runScannerTests(runner: &runner)
        runCommandFactoryTests(runner: &runner)
        await runProcessRunnerTests(runner: &runner)
        await runUICoverageTests(runner: &runner)
        runner.finish()
    }
}
