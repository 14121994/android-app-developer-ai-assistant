import Foundation

public final class LocalProjectContextEngine {
    public init() {}

    public func inspect(profile: ProjectProfile, snapshot: WorkspaceSnapshot, request: String) -> [ProjectSignal] {
        let lower = request.lowercased()
        var signals: [ProjectSignal] = [
            ProjectSignal(label: "Workspace", value: snapshot.rootPath, strength: .strong),
            ProjectSignal(label: "Package", value: profile.packageName, strength: snapshot.packageName == nil ? .weak : .strong),
            ProjectSignal(label: "Files", value: "\(snapshot.fileCount) project files, \(snapshot.testFileCount) test files", strength: snapshot.fileCount > 0 ? .medium : .weak),
            ProjectSignal(label: "Gradle", value: snapshot.hasGradleWrapper ? "Wrapper available" : "System Gradle fallback", strength: snapshot.hasGradleWrapper ? .strong : .medium),
            ProjectSignal(label: "Manifest", value: snapshot.hasAndroidManifest ? "AndroidManifest.xml found" : "Manifest not found", strength: snapshot.hasAndroidManifest ? .strong : .weak),
            ProjectSignal(label: "UI", value: profile.uiSystem, strength: .medium),
            ProjectSignal(label: "Minimum SDK", value: "API \(profile.minSDK)", strength: .medium)
        ]

        if DevelopmentAgent.containsAny(lower, "screen", "ui", "compose", "xml", "layout") {
            signals.append(ProjectSignal(label: "UI surface", value: "Screen, resources, preview state, accessibility, screenshot review", strength: .strong))
        }
        if DevelopmentAgent.containsAny(lower, "gradle", "dependency", "compile", "sync") {
            signals.append(ProjectSignal(label: "Build surface", value: "Settings, app Gradle file, dependency graph, plugin compatibility", strength: .strong))
        }
        if DevelopmentAgent.containsAny(lower, "crash", "exception", "stack trace", "logcat", "anr") {
            signals.append(ProjectSignal(label: "Runtime evidence", value: "Logcat, activity launch path, device state, stack frames", strength: .strong))
        }
        if DevelopmentAgent.containsAny(lower, "test", "coverage", "junit", "espresso", "instrumentation") {
            signals.append(ProjectSignal(label: "Test surface", value: "Unit tests, Android tests, fixtures, Gradle verification", strength: .strong))
        }
        if DevelopmentAgent.containsAny(lower, "permission", "manifest", "service", "receiver") {
            signals.append(ProjectSignal(label: "Manifest surface", value: "Permissions, exported components, services, receivers, intent filters", strength: .medium))
        }
        if !profile.memoryNotes.isEmpty {
            signals.append(ProjectSignal(label: "Memory", value: profile.memoryNotes, strength: .medium))
        }

        return signals
    }
}
