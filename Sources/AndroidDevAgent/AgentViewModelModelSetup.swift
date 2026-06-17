import Foundation

extension AgentViewModel {
    var assistantPrivacyDisclosure: String {
        if assistantAllowsProviderSharing && assistantModelMode == .privateLocal {
            return "Provider sharing consent is saved, but Private mode keeps Ask local and blocks project file excerpts plus command output."
        }
        if assistantAllowsProviderSharing {
            return "Ask may send the prompt, project scan metadata, redacted file excerpts, and recent command output to TaskDroid or OpenAI for this Mac account. Turn this off to keep Ask local."
        }
        return "Ask will not send project file excerpts or command output to model providers. Responses use local project signals only until sharing is enabled."
    }

    var assistantProviderAccountSummary: String {
        "\(assistantTaskDroidAccountSummary); \(assistantOpenAIAccountSummary)"
    }

    var assistantTaskDroidAccountSummary: String {
        guard let url = assistantTaskDroidBaseURL else {
            return "TaskDroid optional, not configured"
        }
        let source = assistantTaskDroidBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "environment" : "Settings"
        let enabled = assistantPrefersTaskDroid ? "enabled" : "disabled"
        return "TaskDroid \(enabled) via \(source): \(url.absoluteString)"
    }

    var assistantOpenAIAccountSummary: String {
        if AssistantModelCredentialStore.openAIAPIKey() != nil {
            return "OpenAI key saved in Keychain"
        }
        return openAIAPIKeyFromEnvironment == nil ? "OpenAI key not configured" : "OpenAI key configured by environment"
    }

    var assistantModelSetupSummary: String {
        if assistantTaskDroidEnabled {
            return "TaskDroid is configured for provider-sharing requests. OpenAI is used only for non-TaskDroid fallback paths."
        }
        if openAIAPIKey != nil {
            return "TaskDroid is optional and not active. Provider-sharing requests can use OpenAI."
        }
        return "No customer model endpoint is configured. Ask stays on the private local route unless provider settings are completed."
    }

    var assistantTaskDroidURLHelpText: String {
        "Optional TaskDroid base URL, for example https://planner.example.com. Leave empty to avoid TaskDroid routing."
    }

    var assistantTaskDroidTimeoutHelpText: String {
        "TaskDroid timeout in seconds. Use a higher value for local vLLM planners."
    }

    var assistantTaskDroidValidationMessage: String {
        let trimmed = assistantTaskDroidBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.environmentTaskDroidBaseURLText == nil
                ? "TaskDroid URL is optional and currently not configured."
                : "Using TaskDroid URL from environment: \(Self.environmentTaskDroidBaseURLText ?? "")."
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            return "Enter a valid http or https TaskDroid base URL."
        }
        return "TaskDroid URL saved."
    }

    var assistantTaskDroidTimeoutValidationMessage: String {
        guard let timeout = assistantTaskDroidTimeoutSeconds else {
            return "Enter a timeout greater than 0 seconds."
        }
        return "TaskDroid timeout: \(Int(timeout)) seconds."
    }

    var assistantTaskDroidEnabled: Bool {
        assistantPrefersTaskDroid && assistantTaskDroidBaseURL != nil
    }

    var assistantTaskDroidBaseURL: URL? {
        let configured = assistantTaskDroidBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? Self.environmentTaskDroidBaseURLText
        guard let configured else { return nil }
        return URL(string: configured)
    }

    var assistantTaskDroidTimeoutSeconds: TimeInterval? {
        let trimmed = assistantTaskDroidTimeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = TimeInterval(trimmed), value > 0 else { return nil }
        return value
    }

    var assistantPayloadPrivacySummary: String {
        let sharingAllowed = assistantAllowsProviderSharing && assistantModelMode != .privateLocal
        let context = sharingAllowed ? "redacted file excerpts allowed" : "file excerpts blocked"
        let output = sharingAllowed ? "command output allowed" : "command output blocked"
        return "\(context); \(output)"
    }

    var openAIAPIKey: String? {
        AssistantModelCredentialStore.openAIAPIKey() ?? openAIAPIKeyFromEnvironment
    }

    private var openAIAPIKeyFromEnvironment: String? {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static var environmentTaskDroidBaseURLText: String? {
        let environment = ProcessInfo.processInfo.environment
        return (environment["TASKDROID_API_BASE_URL"] ?? environment["TASKDROID_URL"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static var environmentTaskDroidTimeoutText: String? {
        let environment = ProcessInfo.processInfo.environment
        return (environment["TASKDROID_API_TIMEOUT_SECONDS"] ?? environment["TASKDROID_TIMEOUT_SECONDS"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}
