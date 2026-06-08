import Foundation

public final class DevelopmentAgent {
    public let catalog: AgentCatalog
    private let contextEngine: LocalProjectContextEngine
    private let toolRouter: ToolRouter
    private let safetyPolicy: SafetyPolicy

    public init(
        catalog: AgentCatalog = AgentCatalog(),
        contextEngine: LocalProjectContextEngine = LocalProjectContextEngine(),
        safetyPolicy: SafetyPolicy = SafetyPolicy()
    ) {
        self.catalog = catalog
        self.contextEngine = contextEngine
        self.toolRouter = ToolRouter(catalog: catalog)
        self.safetyPolicy = safetyPolicy
    }

    public func createPlan(request: String, profile: ProjectProfile, snapshot: WorkspaceSnapshot) -> AgentPlan {
        let normalized = normalize(request)
        let lower = normalized.lowercased()
        let intent = inferIntent(lower)
        let signals = contextEngine.inspect(profile: profile, snapshot: snapshot, request: normalized)
        let tools = toolRouter.route(request: normalized)
        let steps = buildSteps(lower: lower)
        let safety = safetyPolicy.checks(for: normalized, tools: tools)
        let summary = buildSummary(intent: intent, profile: profile, snapshot: snapshot, tools: tools, steps: steps)
        let confidence = confidence(for: lower, tools: tools, signals: signals, snapshot: snapshot)

        return AgentPlan(
            originalRequest: normalized,
            intent: intent,
            confidencePercent: confidence,
            contextSignals: signals,
            steps: steps,
            tools: tools,
            safetyChecks: safety,
            finalSummary: summary
        )
    }

    public static func containsAny(_ value: String, _ needles: String...) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func normalize(_ request: String) -> String {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Create a dashboard screen, wire it to a ViewModel, add tests, and verify it on an emulator."
        }
        return trimmed
    }

    private func inferIntent(_ lower: String) -> String {
        if Self.containsAny(lower, "crash", "exception", "stack trace", "logcat", "anr") {
            return "Crash and Logcat triage"
        }
        if Self.containsAny(lower, "gradle", "dependency", "manifest", "compile", "build failed", "sync") {
            return "Build and dependency repair"
        }
        if Self.containsAny(lower, "screen", "ui", "compose", "xml", "layout", "theme") {
            return "Android UI implementation"
        }
        if Self.containsAny(lower, "test", "coverage", "junit", "espresso", "instrumentation") {
            return "Test automation"
        }
        if Self.containsAny(lower, "release", "signing", "proguard", "r8", "play store") {
            return "Release readiness"
        }
        return "Feature implementation"
    }

    private func buildSteps(lower: String) -> [AgentPlanStep] {
        var steps = [
            step(1, "Clarify task contract", "Extract target behavior, affected modules, acceptance checks, and unknowns.", .done, ["Summary reporter"]),
            step(2, "Scan Android workspace", "Read Gradle files, AndroidManifest, source packages, resources, and tests before editing.", .queued, ["Project indexer", "Semantic file retriever"])
        ]

        var order = 3
        if Self.containsAny(lower, "crash", "exception", "stack trace", "logcat", "anr") {
            steps.append(step(order, "Reproduce failure path", "Collect Logcat, launch state, last user actions, and failing stack frames.", .queued, ["Logcat analyzer", "Emulator driver"]))
            order += 1
        }
        if Self.containsAny(lower, "screen", "ui", "compose", "xml", "layout", "theme") {
            steps.append(step(order, "Design Android UI change", "Choose Compose or XML, state holders, accessibility labels, and preview or screenshot checks.", .queued, ["Screen generator", "Screenshot inspector"]))
            order += 1
        }
        if Self.containsAny(lower, "gradle", "dependency", "manifest", "compile", "sync", "permission") {
            steps.append(step(order, "Repair project configuration", "Update dependencies, plugin versions, manifest declarations, and permission gates only where needed.", .queued, ["Dependency editor", "Manifest editor"]))
            order += 1
        }

        steps.append(step(order, "Propose scoped patch", "Create a diff that touches only the files required by the task and records rollback points.", .queued, ["Patch editor", "Undo journal", "Secret scanner"]))
        order += 1
        steps.append(step(order, "Run verification", "Compile, run targeted tests, inspect device behavior, and loop on failures.", .queued, ["Gradle build runner", "Unit test runner", "Instrumentation test runner"]))
        order += 1
        steps.append(step(order, "Report result", "Return changed files, verification status, residual risks, and a concise task summary.", .queued, ["Summary reporter"]))
        return steps
    }

    private func step(_ order: Int, _ title: String, _ detail: String, _ state: StepState, _ tools: [String]) -> AgentPlanStep {
        AgentPlanStep(order: order, title: title, detail: detail, state: state, toolNames: tools)
    }

    private func buildSummary(
        intent: String,
        profile: ProjectProfile,
        snapshot: WorkspaceSnapshot,
        tools: [ToolCapability],
        steps: [AgentPlanStep]
    ) -> [String] {
        [
            "Intent: \(intent) for package \(profile.packageName).",
            "Workspace: \(snapshot.fileCount) files, Gradle wrapper \(snapshot.hasGradleWrapper ? "available" : "not found"), Manifest \(snapshot.hasAndroidManifest ? "found" : "not found").",
            "Tool coverage: \(tools.count) MVP tools selected across context, code, build, test, device, safety, and reporting.",
            "Execution loop: \(steps.count) ordered stages from workspace scanning through verification and summary.",
            "Safety: workspace boundaries, diffs, undo checkpoints, secret scanning, and confirmation gates remain active."
        ]
    }

    private func confidence(
        for lower: String,
        tools: [ToolCapability],
        signals: [ProjectSignal],
        snapshot: WorkspaceSnapshot
    ) -> Int {
        var score = 50
        if lower.count > 40 { score += 10 }
        if snapshot.hasGradleWrapper { score += 8 }
        if snapshot.hasAndroidManifest { score += 8 }
        if snapshot.fileCount > 0 { score += 8 }
        if Self.containsAny(lower, "screen", "crash", "gradle", "test", "dependency", "manifest", "logcat") {
            score += 12
        }
        score += min(10, tools.count)
        score += min(8, signals.count)
        return min(96, score)
    }
}
