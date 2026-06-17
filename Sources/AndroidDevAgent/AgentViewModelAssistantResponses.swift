import AndroidDevAgentCore
import Foundation

@MainActor
extension AgentViewModel {
    func performAssistantActions(for lower: String) -> [String] {
        if !isProjectLoaded {
            if canScanProject {
                scanProject()
                return ["Started scanning \(candidateProjectPathDisplay) so the response can use real project context."]
            }
            return ["No project is loaded yet; choose or paste an Android project before I can act on files or commands."]
        }

        var actions: [String] = []
        if shouldRefreshDevices(for: lower), canRefreshDevices {
            refreshDevices()
            actions.append("Started device refresh.")
            return actions
        }

        if shouldRunUnitTests(for: lower) {
            runCommand(.unitTests)
            actions.append("Started unit tests for \(selectedModule) \(selectedVariant).")
            return actions
        }

        if shouldRunBuild(for: lower) {
            runCommand(.assembleDebug)
            actions.append("Started assemble for \(selectedModule) \(selectedVariant).")
            return actions
        }

        if shouldCaptureLogcat(for: lower) {
            if selectedDeviceID.isEmpty {
                refreshDevices()
                actions.append("Started device refresh before Logcat because no device is selected.")
            } else {
                runCommand(.logcat)
                actions.append("Started Logcat capture for \(selectedDeviceID).")
            }
            return actions
        }

        if asksForCodeChange(lower) {
            let openedFiles = openRepresentativeFilesForPrompt(lower)
            if openedFiles.isEmpty {
                actions.append("Prepared a project-specific implementation response; no editable source file matched the request closely enough to open automatically.")
            } else {
                actions.append("Opened likely edit targets in the editor: \(openedFiles.joined(separator: ", ")).")
            }
        }
        return actions
    }

    func makeAssistantResponse(for lower: String, actionMessages: [String]) -> String {
        let response: String
        if !isProjectLoaded {
            response = """
            I need project context before I can give a useful project-specific answer. I found this candidate path: \(candidateProjectPathDisplay).

            \(actionMessages.first ?? "Open Workspace, choose the Android project, then ask again.")
            """
        } else if asksForOverview(lower) {
            response = projectOverviewResponse()
        } else if asksForLudo(lower) {
            response = ludoImplementationResponse()
        } else if plan.intent == "Crash and Logcat triage" {
            response = crashResponse()
        } else if plan.intent == "Build and dependency repair" {
            response = buildRepairResponse()
        } else if plan.intent == "Android UI implementation" {
            response = uiImplementationResponse()
        } else if plan.intent == "Test automation" {
            response = testAutomationResponse()
        } else {
            response = featureImplementationResponse()
        }

        return response
    }

    func projectOverviewResponse() -> String {
        let name = projectDisplayName
        let ui = snapshot.usesCompose ? "Jetpack Compose" : snapshot.usesXMLLayouts ? "XML layouts" : "mixed Android UI"
        let tests = snapshot.testFileCount == 1 ? "1 test file" : "\(snapshot.testFileCount) test files"
        let readme = readmeExcerpt()
        return """
        \(name) is an Android game project using \(ui) with Kotlin under package \(profile.packageName). I scanned \(snapshot.fileCount) files and found \(tests), a valid AndroidManifest, and \(snapshot.hasGradleWrapper ? "a Gradle wrapper for reproducible builds" : "system Gradle usage"). The app appears structured as a compact board-game codebase, with source, resources, and tests concentrated around the main app module. \(readme) For user-facing work, the safest path is to inspect the current game state model, board rendering, dice flow, win-condition logic, and tests before adding new mechanics.
        """
    }

    func ludoImplementationResponse() -> String {
        """
        I scanned \(profile.packageName) and it looks like a \(snapshot.usesCompose ? "Compose/Kotlin" : "Kotlin/XML") board-game app with \(snapshot.fileCount) indexed files and \(snapshot.testFileCount) test files. To incorporate Ludo cleanly, I would add it as a separate game mode rather than mixing it into the existing Snake Ladder rules. The implementation should introduce Ludo domain models for players, colors, tokens, dice, home paths, safe squares, captures, and win state; a ViewModel/reducer for turn sequencing; a Compose board renderer; and unit tests for dice entry, captures, extra turns, and finish rules. Files to inspect first: \(representativeFileList()). Verification should start with unit tests, then assemble, then device UI inspection.
        """
    }

    func crashResponse() -> String {
        """
        I treated this as crash triage for \(profile.packageName). The useful path is to capture Logcat, isolate the first app-owned stack frame, map it to the affected Kotlin/Java file, and add the smallest null/state guard with a regression test. I found \(snapshot.fileCount) scanned files and \(snapshot.testFileCount) tests, so I would start by searching likely ViewModel/state/game-loop files, then run the targeted unit test task. If no device is selected, refresh devices before Logcat.
        """
    }

    func buildRepairResponse() -> String {
        """
        I treated this as build/dependency repair for \(profile.packageName). The project has \(snapshot.hasGradleWrapper ? "a Gradle wrapper" : "no wrapper detected"), modules \(modules.joined(separator: ", ")), and variants \(buildVariants.joined(separator: ", ")). I would inspect settings/build files, version catalog entries, plugin versions, manifest changes, and package/activity configuration before editing. Because dependency and manifest edits can affect release behavior, the app should show a scoped diff before applying them, then run assemble and unit tests.
        """
    }

    func uiImplementationResponse() -> String {
        """
        I treated this as Android UI work for \(profile.packageName). The scan shows \(snapshot.usesCompose ? "Compose" : "XML/mixed") UI, Kotlin \(snapshot.usesKotlin ? "present" : "not detected"), and \(snapshot.testFileCount) test files. I would place the new screen near the existing app UI structure, keep state in a ViewModel or reducer, add accessibility labels/content descriptions, and add tests around state transitions. Relevant files to inspect first: \(representativeFileList()). Verification should run unit tests, assemble, and then device/UI checks if an emulator is selected.
        """
    }

    func testAutomationResponse() -> String {
        """
        I treated this as test automation for \(profile.packageName). I found \(snapshot.testFileCount) existing test files and \(snapshot.fileCount) indexed project files. The safest next step is to add focused unit tests around the changed game or UI state, then run \(gradleTaskName(prefix: "test", suffix: "UnitTest")). Device or screenshot tests should run only after selecting an emulator because they can install and control the app.
        """
    }

    func featureImplementationResponse() -> String {
        """
        I prepared a project-specific implementation response for \(profile.packageName). The workspace has \(snapshot.fileCount) scanned files, \(snapshot.testFileCount) tests, modules \(modules.joined(separator: ", ")), variants \(buildVariants.joined(separator: ", ")), and \(snapshot.hasAndroidManifest ? "a detected manifest" : "no detected manifest"). My recommended path is: inspect the closest existing game/UI state files, add the smallest isolated domain model or screen change, update tests, then run unit tests and assemble. Candidate files to inspect first: \(representativeFileList()).
        """
    }

    func asksForOverview(_ lower: String) -> Bool {
        containsAny(lower, "overview", "summarize", "summary", "explain this project", "what is this project", "around 100 words")
    }

    func asksForLudo(_ lower: String) -> Bool {
        containsAny(lower, "ludo", "board game developer")
    }

    func asksForCodeChange(_ lower: String) -> Bool {
        containsAny(lower, "add ", "create ", "build ", "implement", "fix ", "repair", "refactor", "incorporate", "update ")
    }

    func shouldRunUnitTests(for lower: String) -> Bool {
        containsAny(lower, "run tests", "run unit", "execute tests", "verify tests", "test coverage", "run targeted tests")
    }

    func shouldRunBuild(for lower: String) -> Bool {
        containsAny(lower, "run build", "build apk", "assemble", "compile", "verify build")
    }

    func shouldRefreshDevices(for lower: String) -> Bool {
        containsAny(lower, "refresh devices", "list devices", "detect emulator", "detect device")
    }

    func shouldCaptureLogcat(for lower: String) -> Bool {
        containsAny(lower, "capture logcat", "run logcat", "inspect logcat", "device logs")
    }

    func containsAny(_ value: String, _ needles: String...) -> Bool {
        needles.contains { value.contains($0) }
    }

    var projectDisplayName: String {
        let name = URL(fileURLWithPath: projectPath).lastPathComponent
        let rawName = name.isEmpty ? profile.packageName : name
        return rawName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func readmeExcerpt() -> String {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent("README.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let cleaned = text
            .replacingOccurrences(of: "#", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return "" }
        return "README notes: \(String(cleaned.prefix(180)))."
    }

    func representativeFileList() -> String {
        let files = projectFiles
            .filter { !$0.isDirectory }
            .filter { isKeyProjectFile($0.path) || $0.path.lowercased().contains("main") || $0.path.lowercased().contains("game") }
            .prefix(5)
            .map(\.path)
        let selected = files.isEmpty ? projectFiles.filter { !$0.isDirectory }.prefix(5).map(\.path) : Array(files)
        return selected.isEmpty ? "scan the Files panel for source and Gradle files" : selected.joined(separator: ", ")
    }

    func assistantContextFiles(for lower: String) -> [AssistantContextFile] {
        guard isProjectLoaded else { return [] }

        var paths: [String] = []
        var seen = Set<String>()
        func appendPath(_ path: String) {
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            paths.append(path)
        }

        [
            "README.md",
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "gradle/libs.versions.toml",
            "\(selectedModule)/build.gradle",
            "\(selectedModule)/build.gradle.kts",
            "\(selectedModule)/src/main/AndroidManifest.xml",
            "app/build.gradle",
            "app/build.gradle.kts",
            "app/src/main/AndroidManifest.xml"
        ].forEach(appendPath)

        openEditorDocuments.map(\.path).forEach(appendPath)
        representativeFilesForPrompt(lower).prefix(12).map(\.path).forEach(appendPath)

        return Array(paths.compactMap(readAssistantContextFile(relativePath:)).prefix(12))
    }

    func readAssistantContextFile(relativePath: String) -> AssistantContextFile? {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        guard shouldShowSourcePath(url.path) || relativePath == "README.md" else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 500_000 else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let redacted = redactAssistantContext(content)
        return AssistantContextFile(path: relativePath, content: String(redacted.prefix(14_000)))
    }

    func redactAssistantContext(_ content: String) -> String {
        let sensitiveTerms = ["api_key", "apikey", "token", "secret", "password", "signing", "keystore", "storepassword", "keypassword"]
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let value = String(line)
                let lower = value.lowercased()
                guard sensitiveTerms.contains(where: { lower.contains($0) }),
                      let delimiterIndex = value.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                    return value
                }
                return String(value[...delimiterIndex]) + " [REDACTED]"
            }
            .joined(separator: "\n")
    }

    func openRepresentativeFilesForPrompt(_ lower: String) -> [String] {
        let candidates = representativeFilesForPrompt(lower).prefix(3)
        var opened: [String] = []
        for item in candidates {
            openFile(item)
            if openEditorDocuments.contains(where: { $0.path == item.path }) {
                opened.append(item.path)
            }
        }
        return opened
    }

    func representativeFilesForPrompt(_ lower: String) -> [ProjectFileItem] {
        let files = projectFiles.filter { !$0.isDirectory }
        let scored = files.compactMap { item -> (ProjectFileItem, Int)? in
            let path = item.path.lowercased()
            let name = item.name.lowercased()
            var score = 0

            if isKeyProjectFile(item.path) { score += 2 }
            if path.hasSuffix(".kt") || path.hasSuffix(".java") { score += 2 }
            if path.hasSuffix(".xml") { score += 1 }
            if path.contains("/src/main/") { score += 2 }
            if path.contains("/src/test/") || path.contains("/src/androidtest/") { score += shouldRunUnitTests(for: lower) ? 4 : 1 }
            if containsAny(lower, "gradle", "dependency", "build", "compile", "sync"), path.contains("gradle") || path.contains("libs.versions.toml") {
                score += 8
            }
            if containsAny(lower, "manifest", "permission", "activity"), name == "androidmanifest.xml" {
                score += 8
            }
            if containsAny(lower, "screen", "ui", "compose", "layout", "theme"), containsAny(path, "mainactivity", "screen", "theme", "layout", "ui") {
                score += 7
            }
            if containsAny(lower, "ludo", "snake", "ladder", "game", "board", "dice"), containsAny(path, "game", "board", "dice", "snake", "ladder", "mainactivity") {
                score += 9
            }
            if containsAny(lower, "test", "coverage", "junit"), path.contains("test") {
                score += 6
            }

            return score > 0 ? (item, score) : nil
        }
        let sorted = scored.sorted { left, right in
            if left.1 == right.1 { return left.0.path < right.0.path }
            return left.1 > right.1
        }
        return sorted.map(\.0)
    }
}
