import AndroidDevAgentCore
import Foundation

enum LaunchTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): return message
        }
    }
}

struct LaunchTestRunner {
    private(set) var passed = 0
    private(set) var failed = 0
    private var lines: [String] = []

    mutating func run(_ name: String, _ test: () throws -> Void) {
        do {
            try test()
            passed += 1
            lines.append("PASS \(name)")
        } catch {
            failed += 1
            lines.append("FAIL \(name): \(error)")
        }
    }

    mutating func runAsync(_ name: String, _ test: () async throws -> Void) async {
        do {
            try await test()
            passed += 1
            lines.append("PASS \(name)")
        } catch {
            failed += 1
            lines.append("FAIL \(name): \(error)")
        }
    }

    func report() -> String {
        (lines + ["AndroidDevAgentCoreLaunchTests: \(passed) passed, \(failed) failed"]).joined(separator: "\n")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw LaunchTestFailure.failed(message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw LaunchTestFailure.failed("\(message) Expected \(expected), got \(actual).")
    }
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

func toolNames(_ plan: AgentPlan) -> [String] {
    plan.tools.map(\.name)
}

func makeTemporaryDirectory(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AndroidDevAgentCoreLaunchTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func runPlannerTests(runner: inout LaunchTestRunner) {
    runner.run("planner routes UI request to screen, screenshot, and tests") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Create a settings XML screen, add tests, and inspect the screenshot on an emulator.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expectEqual(plan.intent, "Android UI implementation", "UI request intent should be Android UI implementation.")
        try expect(toolNames(plan).contains("Screen generator"), "UI plan should include Screen generator.")
        try expect(toolNames(plan).contains("Screenshot inspector"), "UI plan should include Screenshot inspector.")
        try expect(toolNames(plan).contains("Unit test runner"), "UI plan should include Unit test runner.")
        try expect(plan.steps.contains { $0.title == "Design Android UI change" }, "UI plan should include design step.")
        try expect(plan.confidencePercent >= 90, "UI plan should produce high confidence for a well-scanned project.")
    }

    runner.run("planner routes crash request to logcat and safety checks") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "Analyze this NullPointerException crash from Logcat and propose a safe patch.",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expectEqual(plan.intent, "Crash and Logcat triage", "Crash request intent should be Logcat triage.")
        try expect(toolNames(plan).contains("Logcat analyzer"), "Crash plan should include Logcat analyzer.")
        try expect(toolNames(plan).contains("Emulator driver"), "Crash plan should include Emulator driver.")
        try expect(plan.safetyChecks.contains { $0.contains("Redact personal data") }, "Crash plan should include log redaction safety.")
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
        try expect(plan.safetyChecks.contains { $0.contains("Play release implications") }, "Release plan should include release safety.")
        try expect(!toolNames(plan).contains("Dependency editor"), "Pure release readiness should not be treated as dependency repair.")
    }

    runner.run("planner normalizes empty request into useful default") {
        let agent = DevelopmentAgent()
        let snapshot = sampleSnapshot()
        let plan = agent.createPlan(
            request: "   \n  ",
            profile: ProjectProfile.from(snapshot: snapshot),
            snapshot: snapshot
        )

        try expect(plan.originalRequest.contains("dashboard screen"), "Empty request should produce a default dashboard request.")
        try expectEqual(plan.intent, "Android UI implementation", "Default request should be UI implementation.")
        try expect(toolNames(plan).contains("Screen generator"), "Default request should include Screen generator.")
        try expect(toolNames(plan).contains("Unit test runner"), "Default request should include Unit test runner.")
        try expect(toolNames(plan).contains("Emulator driver"), "Default request should include Emulator driver.")
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
}

func runScannerTests(runner: inout LaunchTestRunner) {
    runner.run("scanner reads Groovy Gradle and Manifest signals") {
        let root = try makeTemporaryDirectory("groovy")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("app")

        try write("pluginManagement {}\ninclude ':app'", to: root.appendingPathComponent("settings.gradle"))
        try write(
            """
            plugins { id 'com.android.application' }
            android {
                namespace 'com.example.sample'
                defaultConfig {
                    applicationId 'com.example.sample'
                    minSdk 26
                    targetSdk 35
                }
            }
            """,
            to: app.appendingPathComponent("build.gradle")
        )
        try write(
            #"<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.manifest" />"#,
            to: app.appendingPathComponent("src/main/AndroidManifest.xml")
        )
        try write("package com.example.sample\nclass MainActivity", to: app.appendingPathComponent("src/main/java/com/example/sample/MainActivity.kt"))
        try write("<LinearLayout />", to: app.appendingPathComponent("src/main/res/layout/activity_main.xml"))
        try write("class MainActivityTest", to: app.appendingPathComponent("src/test/java/com/example/sample/MainActivityTest.kt"))
        try write("", to: root.appendingPathComponent("gradlew"))

        let snapshot = AndroidWorkspaceScanner().scan(rootPath: root.path)

        try expectEqual(snapshot.packageName, "com.example.sample", "Scanner should prefer Gradle applicationId.")
        try expectEqual(snapshot.minSDK, 26, "Scanner should read minSdk.")
        try expectEqual(snapshot.targetSDK, 35, "Scanner should read targetSdk.")
        try expect(snapshot.hasGradleWrapper, "Scanner should detect Gradle wrapper.")
        try expect(snapshot.hasSettingsGradle, "Scanner should detect settings.gradle.")
        try expect(snapshot.hasAndroidManifest, "Scanner should detect AndroidManifest.")
        try expect(snapshot.usesKotlin, "Scanner should detect Kotlin files.")
        try expect(snapshot.usesXMLLayouts, "Scanner should detect XML layouts.")
        try expectEqual(snapshot.testFileCount, 1, "Scanner should count test files.")
    }

    runner.run("scanner reads Kotlin DSL and Compose signals") {
        let root = try makeTemporaryDirectory("compose")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("app")

        try write("pluginManagement {}\ninclude(\":app\")", to: root.appendingPathComponent("settings.gradle.kts"))
        try write(
            """
            plugins { id("com.android.application") }
            android {
                namespace = "com.example.compose"
                defaultConfig {
                    applicationId = "com.example.compose"
                    minSdk = 28
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
            @Composable fun Dashboard() {}
            """,
            to: app.appendingPathComponent("src/main/java/com/example/compose/Dashboard.kt")
        )
        try write(#"<manifest xmlns:android="http://schemas.android.com/apk/res/android" />"#, to: app.appendingPathComponent("src/main/AndroidManifest.xml"))

        let snapshot = AndroidWorkspaceScanner().scan(rootPath: root.path)

        try expectEqual(snapshot.packageName, "com.example.compose", "Scanner should read Kotlin DSL applicationId.")
        try expectEqual(snapshot.minSDK, 28, "Scanner should read Kotlin DSL minSdk.")
        try expectEqual(snapshot.targetSDK, 35, "Scanner should read Kotlin DSL targetSdk.")
        try expect(snapshot.usesCompose, "Scanner should detect Compose.")
        try expect(snapshot.usesKotlin, "Scanner should detect Kotlin.")
    }

    runner.run("scanner skips generated build and distribution outputs") {
        let root = try makeTemporaryDirectory("skip")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("app")

        try write("include ':app'", to: root.appendingPathComponent("settings.gradle"))
        try write("android { namespace 'com.example.clean' }", to: app.appendingPathComponent("build.gradle"))
        try write("<manifest />", to: app.appendingPathComponent("src/main/AndroidManifest.xml"))
        try write("class RealSource", to: app.appendingPathComponent("src/main/java/RealSource.kt"))
        try write("class Generated", to: app.appendingPathComponent("build/generated/Generated.kt"))
        try write("not counted", to: root.appendingPathComponent("dist/Android Dev Agent.app/Contents/Info.plist"))

        let snapshot = AndroidWorkspaceScanner().scan(rootPath: root.path)

        try expectEqual(snapshot.fileCount, 4, "Scanner should skip build and dist outputs.")
        try expect(snapshot.hasAndroidManifest, "Scanner should still detect the real manifest.")
        try expectEqual(snapshot.packageName, "com.example.clean", "Scanner should read namespace.")
    }
}

func runCommandFactoryTests(runner: inout LaunchTestRunner) {
    runner.run("Gradle command uses executable wrapper when available") {
        let root = try makeTemporaryDirectory("gradle-exec")
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appendingPathComponent("gradlew")
        try write("#!/bin/sh\n", to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

        let command = AndroidToolCommandFactory.gradleTest(rootPath: root.path)

        try expectEqual(command.executable, wrapper.path, "Executable wrapper should be used directly.")
        try expectEqual(command.arguments, ["testDebugUnitTest", "--no-daemon", "--console=plain"], "Gradle test arguments should be deterministic.")
        try expectEqual(command.workingDirectory, root.path, "Command should run in workspace root.")
    }

    runner.run("Gradle command uses shell for non-executable wrapper") {
        let root = try makeTemporaryDirectory("gradle-shell")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("#!/bin/sh\n", to: root.appendingPathComponent("gradlew"))

        let command = AndroidToolCommandFactory.assembleDebug(rootPath: root.path)

        try expectEqual(command.executable, "/bin/sh", "Non-executable wrapper should run through sh.")
        try expectEqual(command.arguments, ["./gradlew", "assembleDebug", "--no-daemon", "--console=plain"], "Assemble arguments should be deterministic.")
    }

    runner.run("device commands preserve selected serial and clamp tap coordinates") {
        let tap = AndroidToolCommandFactory.tapDeviceScreen(rootPath: "/tmp/project", deviceSerial: "emulator-5554", x: -20, y: 640)
        let launch = AndroidToolCommandFactory.launchApp(rootPath: "/tmp/project", packageName: "com.example.sample", activityName: ".MainActivity", deviceSerial: "emulator-5554")

        try expectEqual(tap.arguments, ["-s", "emulator-5554", "shell", "input", "tap", "0", "640"], "Tap command should clamp negative coordinates.")
        try expectEqual(launch.arguments, ["-s", "emulator-5554", "shell", "am", "start", "-n", "com.example.sample/.MainActivity"], "Launch command should preserve selected device.")
    }

    runner.run("ToolCommand preview quotes arguments with spaces") {
        let command = ToolCommand(title: "Preview", executable: "/usr/bin/env", arguments: ["bash", "-lc", "echo hello world"], workingDirectory: "/tmp/project")
        try expectEqual(command.preview, "/usr/bin/env bash -lc 'echo hello world'", "Preview should quote arguments with spaces.")
    }
}

func runAssistantConfigurationTests(runner: inout LaunchTestRunner) {
    runner.run("assistant config does not assume local TaskDroid planner") {
        let config = AssistantOrchestrationConfig(mode: .deep, openAIAPIKey: nil)

        try expectEqual(config.taskDroidBaseURL?.absoluteString, nil, "TaskDroid base URL should be unset until configured.")
        try expectEqual(Int(config.taskDroidTimeoutSeconds), 360, "TaskDroid timeout should support local vLLM planner latency.")
        try expect(config.preferTaskDroid, "Explicit callers can still prefer TaskDroid after configuring a URL.")
        try expectEqual(config.embeddingModelID, "text-embedding-3-large", "Deep mode should use the large embedding model.")
    }

    runner.run("assistant config accepts explicit TaskDroid planner URL") {
        let url = URL(string: "https://planner.example.com")!
        let config = AssistantOrchestrationConfig(mode: .deep, openAIAPIKey: nil, taskDroidBaseURL: url, taskDroidTimeoutSeconds: 42)

        try expectEqual(config.taskDroidBaseURL?.absoluteString, "https://planner.example.com", "TaskDroid URL should come from explicit setup.")
        try expectEqual(Int(config.taskDroidTimeoutSeconds), 42, "TaskDroid timeout should honor explicit setup.")
    }

    runner.run("assistant modes expose bound TaskDroid models") {
        try expectEqual(
            AssistantModelMode.automatic.boundModels.map(\.modelID),
            ["taskdroid-android-planner-v1", "taskdroid-android-planner-v1"],
            "Auto mode should describe both TaskDroid routes."
        )
        try expectEqual(AssistantModelMode.fast.boundModels.map(\.modelID), ["taskdroid-android-planner-v1"], "Fast mode should describe TaskDroid route.")
        try expectEqual(AssistantModelMode.privateLocal.boundModels.map(\.modelID), ["gpt-oss-20b-local-fallback"], "Private mode should describe local fallback route.")
        try expect(AssistantModelMode.automatic.boundModelSummary.contains("TaskDroid Android Planner"), "Auto summary should name TaskDroid.")
    }

    runner.run("fast mode is the only mode using small embeddings") {
        try expectEqual(AssistantOrchestrationConfig(mode: .fast, openAIAPIKey: nil).embeddingModelID, "text-embedding-3-small", "Fast mode should use small embeddings.")
        try expectEqual(AssistantOrchestrationConfig(mode: .privateLocal, openAIAPIKey: nil).embeddingModelID, "text-embedding-3-large", "Private mode should use large embeddings.")
    }
}

func runProcessRunnerTests(runner: inout LaunchTestRunner) async {
    await runner.runAsync("ProcessRunner captures stdout for successful command") {
        let command = ToolCommand(title: "Echo", executable: "/bin/echo", arguments: ["hello"], workingDirectory: "/tmp")
        let result = await ProcessRunner().run(command, timeoutSeconds: 5)

        try expect(result.succeeded, "Echo command should succeed.")
        try expectEqual(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "hello", "ProcessRunner should capture stdout.")
        try expectEqual(result.standardError, "", "Echo command should not write stderr.")
    }

    await runner.runAsync("ProcessRunner returns structured failure for missing executable") {
        let command = ToolCommand(title: "Missing", executable: "/definitely/not/a/tool", arguments: [], workingDirectory: "/tmp")
        let result = await ProcessRunner().run(command, timeoutSeconds: 1)

        try expectEqual(result.exitCode, -1, "Missing executable should return structured failure.")
        try expect(!result.standardError.isEmpty, "Missing executable should include an error message.")
    }

    await runner.runAsync("ProcessRunner times out long-running commands") {
        let command = ToolCommand(title: "Sleep", executable: "/bin/sleep", arguments: ["5"], workingDirectory: "/tmp")
        let result = await ProcessRunner().run(command, timeoutSeconds: 0.1)

        try expectEqual(result.exitCode, -2, "Timeout should return the timeout exit code.")
        try expect(result.standardError.contains("timed out"), "Timeout should include timeout details.")
    }
}

func writeReport(_ report: String, outputDirectory: String?) {
    guard let outputDirectory else {
        print(report)
        return
    }
    let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let reportURL = directory.appendingPathComponent("core-launch-tests.txt")
    try? report.write(to: reportURL, atomically: true, encoding: .utf8)
}

@main
enum AndroidDevAgentCoreLaunchTests {
    static func main() async {
        var runner = LaunchTestRunner()
        runPlannerTests(runner: &runner)
        runScannerTests(runner: &runner)
        runCommandFactoryTests(runner: &runner)
        runAssistantConfigurationTests(runner: &runner)
        await runProcessRunnerTests(runner: &runner)

        let report = runner.report()
        writeReport(report, outputDirectory: CommandLine.arguments.dropFirst().first)
        if runner.failed > 0 {
            print(report)
            exit(1)
        }
    }
}
