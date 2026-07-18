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

    runner.run("assistant TaskDroid config is optional for customers") {
        let config = AssistantOrchestrationConfig(mode: .deep, openAIAPIKey: nil)
        let configured = AssistantOrchestrationConfig(
            mode: .deep,
            openAIAPIKey: nil,
            taskDroidBaseURL: URL(string: "https://planner.example.com")!,
            taskDroidTimeoutSeconds: 42
        )

        try expectEqual(config.taskDroidBaseURL?.absoluteString, nil, "TaskDroid should not default to localhost.")
        try expectEqual(
            Int(config.taskDroidTimeoutSeconds),
            360,
            "TaskDroid timeout should allow local vLLM-backed planner responses."
        )
        try expectEqual(configured.taskDroidBaseURL?.absoluteString, "https://planner.example.com", "TaskDroid should use the configured planner API.")
        try expectEqual(Int(configured.taskDroidTimeoutSeconds), 42, "TaskDroid timeout should use configured value.")
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
            ["gpt-oss-20b-local-fallback"],
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

    runner.run("Device screen capture command targets selected serial") {
        let root = try makeTempDirectory("screen-capture-adb-command")
        let capture = AndroidToolCommandFactory.deviceScreenCapture(rootPath: root.path, deviceSerial: "192.168.1.10:42177")
        let arguments = capture.executable == "/usr/bin/env" ? Array(capture.arguments.dropFirst()) : capture.arguments

        try expectEqual(arguments, ["-s", "192.168.1.10:42177", "exec-out", "screencap", "-p"], "Screen capture should target the selected serial and stream a PNG frame.")
    }

    runner.run("Device screen tap command targets selected serial and coordinates") {
        let root = try makeTempDirectory("screen-tap-adb-command")
        let tap = AndroidToolCommandFactory.tapDeviceScreen(rootPath: root.path, deviceSerial: "192.168.1.10:42177", x: 123, y: 456)
        let arguments = tap.executable == "/usr/bin/env" ? Array(tap.arguments.dropFirst()) : tap.arguments

        try expectEqual(arguments, ["-s", "192.168.1.10:42177", "shell", "input", "tap", "123", "456"], "Screen tap should target the selected serial and send adb input tap coordinates.")
    }

    runner.run("Device test cleanup commands target selected serial and package") {
        let root = try makeTempDirectory("device-test-cleanup-adb-command")
        let list = AndroidToolCommandFactory.listInstrumentation(rootPath: root.path, deviceSerial: "emulator-5554")
        let forceStop = AndroidToolCommandFactory.forceStopPackage(rootPath: root.path, packageName: "com.example.sample", deviceSerial: "emulator-5554")
        let listArguments = list.executable == "/usr/bin/env" ? Array(list.arguments.dropFirst()) : list.arguments
        let forceStopArguments = forceStop.executable == "/usr/bin/env" ? Array(forceStop.arguments.dropFirst()) : forceStop.arguments

        try expectEqual(listArguments, ["-s", "emulator-5554", "shell", "pm", "list", "instrumentation"], "Instrumentation lookup should target the selected device.")
        try expectEqual(forceStopArguments, ["-s", "emulator-5554", "shell", "am", "force-stop", "com.example.sample"], "Force-stop should target the selected device and package.")
    }

    runner.run("Launch installation binds the selected device and replacement mode") {
        let root = try makeTempDirectory("launch-install-command")
        let wrapper = root.appendingPathComponent("gradlew")
        try write("#!/bin/sh\necho wrapper\n", to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

        let installVariant = AndroidToolCommandFactory.installVariant(
            rootPath: root.path,
            task: ":app:installDebug",
            deviceSerial: "192.168.1.10:42177"
        )
        let installAPK = AndroidToolCommandFactory.installApp(
            rootPath: root.path,
            apkPath: "/tmp/app-debug.apk",
            deviceSerial: "192.168.1.10:42177"
        )
        let installAPKArguments = installAPK.executable == "/usr/bin/env" ? Array(installAPK.arguments.dropFirst()) : installAPK.arguments

        try expectEqual(
            firstArguments(installVariant.arguments, 3),
            ["ANDROID_SERIAL=192.168.1.10:42177", wrapper.path, ":app:installDebug"],
            "Launch installation should bind Gradle's install task to the selected ADB serial."
        )
        try expectEqual(
            installAPKArguments,
            ["-s", "192.168.1.10:42177", "install", "-r", "/tmp/app-debug.apk"],
            "APK install should use replacement mode for both absent and installed apps."
        )
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

    await runner.runAsync("ProcessRunner can terminate a running command") {
        let processRunner = ProcessRunner()
        let command = ToolCommand(
            title: "Sleep",
            executable: "/bin/sleep",
            arguments: ["5"],
            workingDirectory: "/tmp"
        )
        let task = Task {
            await processRunner.run(command, timeoutSeconds: 10)
        }

        var sawRunningProcess = false
        for _ in 0..<20 {
            if processRunner.hasRunningProcess {
                sawRunningProcess = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        try expect(sawRunningProcess, "Sleep command should expose an active process before cancellation.")
        try expect(processRunner.terminateRunningProcess(), "Active process should accept termination.")
        let result = await task.value

        try expect(!result.succeeded, "Terminated command should not report success.")
        try expect(result.exitCode != -2, "Manual termination should not be reported as a timeout.")
    }

    await runner.runAsync("ProcessRunner drains large binary stdout while command runs") {
        let root = try makeTempDirectory("large-binary-output")
        let payload = Data(repeating: 0x41, count: 512 * 1024)
        let payloadURL = root.appendingPathComponent("payload.bin")
        try payload.write(to: payloadURL)
        let command = ToolCommand(
            title: "Large Binary Output",
            executable: "/bin/cat",
            arguments: [payloadURL.path],
            workingDirectory: root.path
        )
        let result = await ProcessRunner().runBinary(command, timeoutSeconds: 2)

        try expect(result.succeeded, "Large binary command should finish without pipe-buffer timeout.")
        try expectEqual(result.standardOutput.count, payload.count, "Large binary stdout should be captured completely.")
        try expectEqual(result.standardOutput, payload, "Large binary stdout should match the emitted payload.")
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

    await runner.runAsync("Target disconnect prefers selected discovered wireless device") {
        let diagnostics = await MainActor.run {
            AndroidDevAgentUICoverageHarness.wirelessDisconnectDiagnostics()
        }

        try expectEqual(diagnostics["canDisconnect"], "true", "Wireless disconnect should be available for the discovered selected target.")
        try expectEqual(diagnostics["canDisconnectSelected"], "true", "Target-card disconnect should be available for selected wireless devices.")
        try expect(diagnostics["disconnectHelp"]?.contains("192.168.225.46:42783") == true, "Disconnect should target the discovered selected device address.")
        try expect(diagnostics["disconnectHelp"]?.contains("192.168.1.99:49999") == false, "Disconnect should not prefer stale manual address over selected target.")
        try expect(diagnostics["disconnectHelp"]?.contains("192.168.1.98:48888") == false, "Disconnect should not prefer stale last wireless address over selected target.")
    }

    await runner.runAsync("Device Tests stop includes target and instrumentation packages") {
        let diagnostics = await MainActor.run {
            AndroidDevAgentUICoverageHarness.deviceTestStopDiagnostics()
        }
        let packages = diagnostics["packages"] ?? ""

        try expect(packages.contains("com.example.coverage"), "Cleanup should include the target application package.")
        try expect(packages.contains("com.example.coverage.test"), "Cleanup should include the default Android test package.")
        try expect(packages.contains("com.example.coverage.debug"), "Cleanup should include discovered debug target packages.")
        try expect(packages.contains("com.example.coverage.debug.test"), "Cleanup should include discovered instrumentation packages.")
        try expect(!packages.contains("com.other.app"), "Cleanup should not include unrelated instrumentation packages.")
    }

    await runner.runAsync("Editor save uses scoped diff checkpoint and secret gate") {
        let diagnostics = await MainActor.run {
            AndroidDevAgentUICoverageHarness.editorSaveSafetyDiagnostics()
        }

        try expectEqual(diagnostics["safeFileUpdated"], "true", "Safe editor save should update the workspace file.")
        try expectEqual(diagnostics["pendingDiffWasScoped"], "true", "Pending editor diff should be scoped to the edited file.")
        try expectEqual(diagnostics["checkpointExists"], "true", "Safe editor save should create an undo checkpoint.")
        try expectEqual(diagnostics["checkpointMatchesOriginal"], "true", "Undo checkpoint should preserve the pre-save file content.")
        try expect(diagnostics["safeStatus"]?.contains("scoped diff") == true, "Safe editor save should report scoped diff review.")
        try expect(diagnostics["safeRows"]?.contains("Undo checkpoint") == true, "Safety rows should expose undo checkpoint status.")
        try expectEqual(diagnostics["secretBlocked"], "true", "Secret-like editor changes should be blocked before disk write.")
        try expectEqual(diagnostics["secretFileUnchanged"], "true", "Blocked secret save should leave the backing file unchanged.")
        try expect(diagnostics["secretSummary"]?.contains("Blocked") == true, "Secret scanner should report the blocked save.")
        try expectEqual(diagnostics["secretDiffRedacted"], "true", "Secret-bearing diff preview should be redacted.")
    }

    await runner.runAsync("Ask Assistant gates provider context behind consent") {
        let diagnostics = await MainActor.run {
            AndroidDevAgentUICoverageHarness.assistantPrivacyDiagnostics()
        }
        let sharedContextCount = Int(diagnostics["sharedContextCount"] ?? "0") ?? 0

        try expectEqual(diagnostics["defaultSharingAllowed"], "false", "Provider sharing should be off by default.")
        try expectEqual(diagnostics["defaultContextCount"], "0", "Default Ask payload should not include project file excerpts.")
        try expectEqual(diagnostics["defaultCommandOutputNil"], "true", "Default Ask payload should not include command output.")
        try expect(diagnostics["defaultDisclosure"]?.contains("will not send") == true, "Default privacy disclosure should state that provider payload is blocked.")
        try expect(diagnostics["defaultPayloadSummary"]?.contains("file excerpts blocked") == true, "Payload summary should show blocked file excerpts.")
        try expectEqual(diagnostics["sharedSharingAllowed"], "true", "Explicit consent should allow provider payload sharing.")
        try expect(sharedContextCount > 0, "Explicit consent should allow redacted project context excerpts.")
        try expectEqual(diagnostics["sharedCommandOutputPresent"], "true", "Explicit consent should allow recent command output.")
        try expect(diagnostics["sharedDisclosure"]?.contains("may send") == true, "Enabled disclosure should describe provider sharing.")
        try expect(diagnostics["accountSummary"]?.contains("OpenAI") == true, "Privacy flow should surface account/provider status.")
        try expectEqual(diagnostics["privateModeOverridesSharing"], "true", "Private mode should block provider payload sharing even after consent.")
    }

    await runner.runAsync("Ask Assistant uses customer model setup") {
        let diagnostics = await MainActor.run {
            AndroidDevAgentUICoverageHarness.assistantModelSetupDiagnostics()
        }

        try expectEqual(diagnostics["defaultURL"], "nil", "TaskDroid should be unset by default.")
        try expectEqual(diagnostics["defaultEnabled"], "false", "TaskDroid should not be enabled until configured.")
        try expect(diagnostics["defaultSummary"]?.contains("No customer model endpoint") == true, "Default setup summary should guide customers to configure models.")
        try expectEqual(diagnostics["configuredURL"], "https://planner.example.com", "TaskDroid setup should accept a customer URL.")
        try expectEqual(diagnostics["configuredEnabled"], "true", "Configured TaskDroid should become active when enabled.")
        try expectEqual(diagnostics["configuredTimeout"], "42", "Configured TaskDroid timeout should be used.")
        try expect(diagnostics["accountSummary"]?.contains("planner.example.com") == true, "Account summary should surface the configured customer endpoint.")
    }

    await runner.runAsync("Launch readiness exposes support controls") {
        let diagnostics = await AndroidDevAgentUICoverageHarness.launchReadinessDiagnostics()
        let rows = diagnostics["rows"] ?? ""

        try expect(rows.contains("Crash Reporting"), "Launch readiness should expose crash reporting status.")
        try expect(rows.contains("Crash Symbolication"), "Launch readiness should expose crash symbolication status.")
        try expect(rows.contains("Telemetry"), "Launch readiness should expose telemetry controls.")
        try expect(rows.contains("License Activation"), "Launch readiness should expose license activation status.")
        try expect(rows.contains("Privacy Audit"), "Launch readiness should expose privacy audit status.")
        try expect(rows.contains("Support Redaction"), "Launch readiness should expose support redaction status.")
        try expect(rows.contains("Support Upload"), "Launch readiness should expose support upload status.")
        try expect(rows.contains("Diagnostic Version"), "Launch readiness should expose diagnostic version stamps.")
        try expect(rows.contains("Onboarding"), "Launch readiness should expose onboarding status.")
        try expect(rows.contains("Release Notes"), "Launch readiness should expose release notes status.")
        try expect(diagnostics["defaultTelemetry"]?.contains("No telemetry") == true, "Telemetry should default to off.")
        try expect(diagnostics["defaultLicenseSummary"]?.contains("Trial active") == true, "Commercial licensing should start with a bounded trial.")
        try expect(diagnostics["defaultLicenseSummary"]?.contains("not configured") == true, "Default license state should not imply a configured backend.")
        try expect(diagnostics["invalidLicense"]?.contains("ADA-XXXX") == true, "Invalid license keys should be rejected with the expected format.")
        try expect(diagnostics["missingAccount"]?.contains("Account email") == true, "License activation should require account email for recovery.")
        try expectEqual(diagnostics["validLicense"], "Subscription active for Android Dev Agent Pro.", "Valid license keys should activate through the backend.")
        try expect(diagnostics["activeLicenseSummary"]?.contains("ADA-****") == true, "Activated license status should be masked.")
        try expect(diagnostics["activeLicenseSummary"]?.contains("Backend endpoints") == true, "Activated license status should reflect configured backend endpoints.")
        try expect(diagnostics["refreshedLicense"]?.contains("Subscription active") == true, "License refresh should verify the active entitlement.")
        try expect(diagnostics["offlineGrace"]?.contains("Offline grace active") == true, "License refresh failures should enter offline grace when allowed.")
        try expectEqual(diagnostics["recoveredAccount"], "Recovery email sent.", "Account recovery should call the backend contract.")
        try expect(diagnostics["transferredLicense"]?.contains("License transfer pending") == true, "License transfer should call the backend contract.")
        try expect(diagnostics["transferSummary"]?.contains("transfer pending") == true, "Transferred licenses should no longer be treated as active.")
        try expect(diagnostics["onboardingSummary"]?.contains("complete") == true, "Onboarding completion should be persisted.")
        try expect(diagnostics["releaseNotesSummary"]?.contains("available") == true, "Generated release notes should be detected.")
        try expectEqual(diagnostics["supportReportExists"], "true", "Support bundle should include support-report.txt.")
        try expectEqual(diagnostics["supportReportRedacted"], "true", "Support bundle should redact common secret-shaped values.")
        try expectEqual(diagnostics["privacyAuditCopied"], "true", "Support bundle should include privacy audit history.")
        try expectEqual(diagnostics["launchManifestExists"], "true", "Support bundle should include launch-readiness.txt.")
        try expectEqual(diagnostics["releaseNotesCopied"], "true", "Support bundle should include release notes when available.")
        try expectEqual(diagnostics["issueIDExists"], "true", "Support bundle should include a support issue id artifact.")
        try expectEqual(diagnostics["issueIDStamped"], "true", "Support issue id should use the launch support prefix.")
        try expectEqual(diagnostics["diagnosticVersionExists"], "true", "Support bundle should include diagnostic version stamps.")
        try expectEqual(diagnostics["diagnosticVersionStamped"], "true", "Diagnostic version stamps should include schema and app version.")
        try expectEqual(diagnostics["redactionSummaryExists"], "true", "Support bundle should include a redaction summary.")
        try expectEqual(diagnostics["symbolicationExists"], "true", "Support bundle should include crash symbolication metadata.")
        try expectEqual(diagnostics["symbolicationStamped"], "true", "Crash symbolication metadata should include symbol routing fields.")
        try expect(diagnostics["supportUploadStatus"]?.contains("Support bundle uploaded") == true, "Support bundle upload should run through the configured backend.")
        try expect(diagnostics["supportStatus"]?.contains("Support bundle exported") == true, "Support bundle export should update status.")
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
