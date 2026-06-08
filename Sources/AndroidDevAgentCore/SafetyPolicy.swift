public final class SafetyPolicy {
    public init() {}

    public func checks(for request: String, tools: [ToolCapability]) -> [String] {
        let lower = request.lowercased()
        var checks = [
            "Keep every file operation inside the selected Android workspace.",
            "Show a scoped diff before applying code, Gradle, manifest, or resource edits.",
            "Preserve unrelated user changes and create an undo checkpoint before patching.",
            "Scan prompts, files, and logs for API keys, signing data, tokens, and private paths."
        ]

        if tools.contains(where: { $0.requiresConfirmation }) {
            checks.append("Ask for confirmation before emulator control, dependency changes, manifest edits, or destructive file operations.")
        }
        if DevelopmentAgent.containsAny(lower, "permission", "manifest", "service", "receiver", "release", "signing") {
            checks.append("Flag privacy, exported component, signing, and Play release implications before changing configuration.")
        }
        if DevelopmentAgent.containsAny(lower, "crash", "logcat", "exception") {
            checks.append("Redact personal data and secrets from device logs before sending them to any model provider.")
        }

        checks.append("Run the narrowest useful Gradle and ADB commands, then summarize failures with file-level next actions.")
        return checks
    }
}
