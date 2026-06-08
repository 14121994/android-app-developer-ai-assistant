import Foundation

public enum AssistantModelMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case fast
    case deep
    case privateLocal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Auto"
        case .fast: return "Fast"
        case .deep: return "Deep"
        case .privateLocal: return "Private"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            return "Routes simple prompts to a fast model and complex Android work to a deep model."
        case .fast:
            return "Uses the fast model route for quick Android guidance and triage."
        case .deep:
            return "Uses the strongest model route for complex Android architecture, code, and debugging."
        case .privateLocal:
            return "Keeps the request on the local fallback route."
        }
    }
}

public enum AssistantModelProvider: String, Sendable {
    case openAI = "OpenAI"
    case taskDroid = "TaskDroid"
    case local = "Local"
}

public struct AssistantBoundModelInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let provider: AssistantModelProvider
    public let modelID: String
    public let displayName: String
    public let route: String
    public let purpose: String

    public init(
        provider: AssistantModelProvider,
        modelID: String,
        displayName: String,
        route: String,
        purpose: String
    ) {
        self.id = "\(provider.rawValue)-\(modelID)-\(route)"
        self.provider = provider
        self.modelID = modelID
        self.displayName = displayName
        self.route = route
        self.purpose = purpose
    }
}

public extension AssistantModelMode {
    var boundModels: [AssistantBoundModelInfo] {
        switch self {
        case .automatic:
            return [
                AssistantBoundModelInfo(
                    provider: .taskDroid,
                    modelID: "taskdroid-android-planner-v1",
                    displayName: "TaskDroid Android Planner",
                    route: "Complex Android work",
                    purpose: "xhigh Android implementation task planning for architecture, debugging, Gradle, tests, Compose/XML, state, and ViewModel prompts"
                ),
                AssistantBoundModelInfo(
                    provider: .taskDroid,
                    modelID: "taskdroid-android-planner-v1",
                    displayName: "TaskDroid Android Planner",
                    route: "Simple Android guidance",
                    purpose: "medium Android implementation task planning for quick routing, triage, summaries, and focused Android advice"
                )
            ]
        case .fast:
            return [
                AssistantBoundModelInfo(
                    provider: .taskDroid,
                    modelID: "taskdroid-android-planner-v1",
                    displayName: "TaskDroid Android Planner",
                    route: "All Fast prompts",
                    purpose: "low-latency Android implementation task planning"
                )
            ]
        case .deep:
            return [
                AssistantBoundModelInfo(
                    provider: .taskDroid,
                    modelID: "taskdroid-android-planner-v1",
                    displayName: "TaskDroid Android Planner",
                    route: "All Deep prompts",
                    purpose: "xhigh Android architecture, code reasoning, debugging, and agentic development planning"
                )
            ]
        case .privateLocal:
            return [
                AssistantBoundModelInfo(
                    provider: .taskDroid,
                    modelID: "taskdroid-android-planner-v1",
                    displayName: "TaskDroid Android Planner",
                    route: "All Private prompts",
                    purpose: "high local Android implementation task planning through the private TaskDroid route"
                )
            ]
        }
    }

    var boundModelSummary: String {
        let names = boundModels.map(\.displayName)
        guard !names.isEmpty else { return "No model binding" }
        return names.joined(separator: " / ")
    }
}

public struct AssistantModelSpec: Hashable, Sendable {
    public let provider: AssistantModelProvider
    public let id: String
    public let displayName: String
    public let purpose: String
    public let taskDroidIntelligenceLevel: String?

    public init(
        provider: AssistantModelProvider,
        id: String,
        displayName: String,
        purpose: String,
        taskDroidIntelligenceLevel: String? = nil
    ) {
        self.provider = provider
        self.id = id
        self.displayName = displayName
        self.purpose = purpose
        self.taskDroidIntelligenceLevel = taskDroidIntelligenceLevel
    }
}

public struct AssistantContextFile: Hashable, Sendable {
    public let path: String
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct AssistantModelRequest: Sendable {
    public let prompt: String
    public let profile: ProjectProfile
    public let snapshot: WorkspaceSnapshot
    public let planIntent: String
    public let modules: [String]
    public let variants: [String]
    public let contextFiles: [AssistantContextFile]
    public let commandSummary: String?
    public let recentCommandOutput: String?

    public init(
        prompt: String,
        profile: ProjectProfile,
        snapshot: WorkspaceSnapshot,
        planIntent: String,
        modules: [String],
        variants: [String],
        contextFiles: [AssistantContextFile],
        commandSummary: String?,
        recentCommandOutput: String?
    ) {
        self.prompt = prompt
        self.profile = profile
        self.snapshot = snapshot
        self.planIntent = planIntent
        self.modules = modules
        self.variants = variants
        self.contextFiles = contextFiles
        self.commandSummary = commandSummary
        self.recentCommandOutput = recentCommandOutput
    }
}

public struct AssistantOrchestrationConfig: Sendable {
    public let mode: AssistantModelMode
    public let openAIAPIKey: String?
    public let allowRemoteModels: Bool
    public let timeoutSeconds: TimeInterval
    public let taskDroidBaseURL: URL?
    public let preferTaskDroid: Bool
    public let taskDroidTimeoutSeconds: TimeInterval

    public init(
        mode: AssistantModelMode,
        openAIAPIKey: String?,
        allowRemoteModels: Bool = true,
        timeoutSeconds: TimeInterval = 90,
        taskDroidBaseURL: URL? = nil,
        preferTaskDroid: Bool = true,
        taskDroidTimeoutSeconds: TimeInterval? = nil
    ) {
        self.mode = mode
        self.openAIAPIKey = openAIAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.allowRemoteModels = allowRemoteModels
        self.timeoutSeconds = timeoutSeconds
        self.taskDroidBaseURL = taskDroidBaseURL ?? Self.defaultTaskDroidBaseURL
        self.preferTaskDroid = preferTaskDroid
        self.taskDroidTimeoutSeconds = taskDroidTimeoutSeconds ?? Self.defaultTaskDroidTimeoutSeconds
    }

    public var embeddingModelID: String {
        mode == .fast ? "text-embedding-3-small" : "text-embedding-3-large"
    }

    private static var defaultTaskDroidBaseURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["TASKDROID_API_BASE_URL"] ?? environment["TASKDROID_URL"]
        let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "http://127.0.0.1:8000"
        return URL(string: value)
    }

    private static var defaultTaskDroidTimeoutSeconds: TimeInterval {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["TASKDROID_API_TIMEOUT_SECONDS"] ?? environment["TASKDROID_TIMEOUT_SECONDS"]
        guard let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let parsed = TimeInterval(value),
              parsed > 0 else {
            return 360
        }
        return parsed
    }
}

public struct AssistantModelResponse: Sendable {
    public let answer: String
    public let plannedActions: [String]
    public let provider: AssistantModelProvider
    public let modelID: String
    public let modelDisplayName: String
    public let retrievalModelID: String
    public let contextFilePaths: [String]
    public let status: String

    public init(
        answer: String,
        plannedActions: [String],
        provider: AssistantModelProvider,
        modelID: String,
        modelDisplayName: String,
        retrievalModelID: String,
        contextFilePaths: [String],
        status: String
    ) {
        self.answer = answer
        self.plannedActions = plannedActions
        self.provider = provider
        self.modelID = modelID
        self.modelDisplayName = modelDisplayName
        self.retrievalModelID = retrievalModelID
        self.contextFilePaths = contextFilePaths
        self.status = status
    }
}

public final class AssistantModelOrchestrator: Sendable {
    private let openAIClient: OpenAIModelClient
    private let taskDroidClient: TaskDroidPlannerClient

    public init(
        openAIClient: OpenAIModelClient = OpenAIModelClient(),
        taskDroidClient: TaskDroidPlannerClient = TaskDroidPlannerClient()
    ) {
        self.openAIClient = openAIClient
        self.taskDroidClient = taskDroidClient
    }

    public func answer(request: AssistantModelRequest, config: AssistantOrchestrationConfig) async -> AssistantModelResponse {
        let spec = routeModel(for: request.prompt, mode: config.mode)
        let localRankedFiles = LocalContextRanker.rank(prompt: request.prompt, files: request.contextFiles)
        var rankedFiles = Array(localRankedFiles.prefix(8))
        var retrievalModelID = "local lexical ranker"

        if config.preferTaskDroid,
           spec.provider == .taskDroid,
           let baseURL = config.taskDroidBaseURL,
           let intelligenceLevel = spec.taskDroidIntelligenceLevel {
            do {
                let taskDroidResponse = try await taskDroidClient.createPlan(
                    request: request,
                    model: spec,
                    intelligenceLevel: intelligenceLevel,
                    baseURL: baseURL,
                    timeoutSeconds: config.taskDroidTimeoutSeconds
                )
                return taskDroidResponse.toAssistantResponse(
                    model: spec,
                    retrievalModelID: retrievalModelID,
                    contextFilePaths: rankedFiles.map(\.path)
                )
            } catch {
                return Self.taskDroidErrorResponse(
                    error: error,
                    model: spec,
                    retrievalModelID: retrievalModelID,
                    contextFilePaths: rankedFiles.map(\.path)
                )
            }
        }

        let openAIFallbackSpec = openAIFallbackModel(for: request.prompt, mode: config.mode)

        if config.allowRemoteModels, let apiKey = config.openAIAPIKey {
            if let embeddedFiles = try? await openAIClient.rankContext(
                prompt: request.prompt,
                files: request.contextFiles,
                embeddingModelID: config.embeddingModelID,
                apiKey: apiKey,
                timeoutSeconds: config.timeoutSeconds
            ), !embeddedFiles.isEmpty {
                rankedFiles = Array(embeddedFiles.prefix(8))
                retrievalModelID = config.embeddingModelID
            }

            do {
                let remote = try await openAIClient.generateResponse(
                    request: request,
                    model: openAIFallbackSpec,
                    contextFiles: rankedFiles,
                    apiKey: apiKey,
                    timeoutSeconds: config.timeoutSeconds
                )
                return AssistantModelResponse(
                    answer: remote.answer,
                    plannedActions: remote.plannedActions,
                    provider: openAIFallbackSpec.provider,
                    modelID: openAIFallbackSpec.id,
                    modelDisplayName: openAIFallbackSpec.displayName,
                    retrievalModelID: retrievalModelID,
                    contextFilePaths: rankedFiles.map(\.path),
                    status: "Answered by \(openAIFallbackSpec.displayName)."
                )
            } catch {
                let fallback = LocalAndroidAssistantResponder.answer(request: request, contextFiles: rankedFiles, routedModel: spec)
                return fallback.withStatus("Remote model unavailable: \(error.localizedDescription). Local fallback answered.")
            }
        }

        let fallbackSpec = config.mode == .privateLocal
            ? Self.privateLocalSpec
            : spec
        let response = LocalAndroidAssistantResponder.answer(request: request, contextFiles: rankedFiles, routedModel: fallbackSpec)
        return response
    }

    private static func taskDroidErrorResponse(
        error: Error,
        model: AssistantModelSpec,
        retrievalModelID: String,
        contextFilePaths: [String]
    ) -> AssistantModelResponse {
        let reason = error.localizedDescription.nilIfEmpty ?? String(describing: error)
        let message = "TaskDroid Android Planner could not generate a response from taskdroid-android-planner-v1. Reason: \(reason). No OpenAI, local, or deterministic rule fallback response was used. Verify the TaskDroid API and vLLM server, then retry."
        return AssistantModelResponse(
            answer: message,
            plannedActions: [],
            provider: model.provider,
            modelID: model.id,
            modelDisplayName: model.displayName,
            retrievalModelID: retrievalModelID,
            contextFilePaths: contextFilePaths,
            status: message
        )
    }

    public func routeModel(for prompt: String, mode: AssistantModelMode) -> AssistantModelSpec {
        switch mode {
        case .fast:
            return Self.taskDroidLowSpec
        case .deep:
            return Self.taskDroidXHighSpec
        case .privateLocal:
            return Self.taskDroidHighSpec
        case .automatic:
            let lower = prompt.lowercased()
            if DevelopmentAgent.containsAny(lower, "architecture", "refactor", "implement", "fix", "crash", "gradle", "dependency", "compose", "xml", "test", "coverage", "ludo", "state", "viewmodel") {
                return Self.taskDroidXHighSpec
            }
            return Self.taskDroidMediumSpec
        }
    }

    private func openAIFallbackModel(for prompt: String, mode: AssistantModelMode) -> AssistantModelSpec {
        switch mode {
        case .fast:
            return Self.fastSpec
        case .deep, .privateLocal:
            return Self.deepSpec
        case .automatic:
            let lower = prompt.lowercased()
            if DevelopmentAgent.containsAny(lower, "architecture", "refactor", "implement", "fix", "crash", "gradle", "dependency", "compose", "xml", "test", "coverage", "ludo", "state", "viewmodel") {
                return Self.deepSpec
            }
            return Self.fastSpec
        }
    }

    private static let taskDroidLowSpec = AssistantModelSpec(
        provider: .taskDroid,
        id: "taskdroid-android-planner-v1",
        displayName: "TaskDroid Android Planner (Low)",
        purpose: "low-latency Android implementation task planning",
        taskDroidIntelligenceLevel: "low"
    )

    private static let taskDroidMediumSpec = AssistantModelSpec(
        provider: .taskDroid,
        id: "taskdroid-android-planner-v1",
        displayName: "TaskDroid Android Planner (Medium)",
        purpose: "balanced Android implementation task planning",
        taskDroidIntelligenceLevel: "medium"
    )

    private static let taskDroidHighSpec = AssistantModelSpec(
        provider: .taskDroid,
        id: "taskdroid-android-planner-v1",
        displayName: "TaskDroid Android Planner (High)",
        purpose: "high-confidence local Android implementation task planning",
        taskDroidIntelligenceLevel: "high"
    )

    private static let taskDroidXHighSpec = AssistantModelSpec(
        provider: .taskDroid,
        id: "taskdroid-android-planner-v1",
        displayName: "TaskDroid Android Planner (xHigh)",
        purpose: "xhigh Android architecture, code reasoning, debugging, and agentic development planning",
        taskDroidIntelligenceLevel: "xhigh"
    )

    private static let fastSpec = AssistantModelSpec(
        provider: .openAI,
        id: "gpt-5.4-mini",
        displayName: "GPT-5.4 Mini",
        purpose: "fast routing, triage, summaries, and focused Android guidance"
    )

    private static let deepSpec = AssistantModelSpec(
        provider: .openAI,
        id: "gpt-5.5",
        displayName: "GPT-5.5",
        purpose: "deep Android architecture, code reasoning, debugging, and agentic development"
    )

    private static let privateLocalSpec = AssistantModelSpec(
        provider: .local,
        id: "gpt-oss-20b-local-fallback",
        displayName: "Private Local Fallback",
        purpose: "offline/private Android guidance using local project signals"
    )
}

public struct OpenAIModelClient: Sendable {
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.baseURL = baseURL
    }

    func generateResponse(
        request: AssistantModelRequest,
        model: AssistantModelSpec,
        contextFiles: [AssistantContextFile],
        apiKey: String,
        timeoutSeconds: TimeInterval
    ) async throws -> StructuredAssistantOutput {
        let endpoint = baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: responseBody(request: request, model: model, contextFiles: contextFiles))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)

        let envelope = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        if let error = envelope.error?.message {
            throw AssistantModelError.remote(error)
        }
        guard let outputText: String = envelope.outputText?.nilIfEmpty ?? envelope.outputContentText.nilIfEmpty else {
            throw AssistantModelError.remote("The model response did not include text output.")
        }
        if let structuredData = outputText.data(using: .utf8),
           let structured = try? JSONDecoder().decode(StructuredAssistantOutput.self, from: structuredData) {
            return structured
        }
        return StructuredAssistantOutput(answer: outputText, plannedActions: [])
    }

    func rankContext(
        prompt: String,
        files: [AssistantContextFile],
        embeddingModelID: String,
        apiKey: String,
        timeoutSeconds: TimeInterval
    ) async throws -> [AssistantContextFile] {
        guard !files.isEmpty else { return [] }
        let endpoint = baseURL.appendingPathComponent("embeddings")
        let inputs = [prompt] + files.map { "\($0.path)\n\($0.content.prefix(2_000))" }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": embeddingModelID,
            "input": inputs
        ])

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        let envelope = try JSONDecoder().decode(OpenAIEmbeddingEnvelope.self, from: data)
        let vectors = envelope.data.sorted { $0.index < $1.index }.map(\.embedding)
        guard let promptVector = vectors.first, vectors.count == inputs.count else {
            throw AssistantModelError.remote("Embedding response was incomplete.")
        }
        let scored = zip(files, vectors.dropFirst()).map { file, vector in
            (file, cosineSimilarity(promptVector, vector))
        }
        return scored.sorted { left, right in
            if left.1 == right.1 { return left.0.path < right.0.path }
            return left.1 > right.1
        }.map(\.0)
    }

    private func responseBody(
        request: AssistantModelRequest,
        model: AssistantModelSpec,
        contextFiles: [AssistantContextFile]
    ) -> [String: Any] {
        [
            "model": model.id,
            "instructions": instructions,
            "input": inputPayload(request: request, contextFiles: contextFiles),
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "android_assistant_response",
                    "strict": true,
                    "schema": structuredOutputSchema
                ]
            ]
        ]
    }

    private var instructions: String {
        """
        You are Ask the Assistant inside a native macOS Android development workbench.
        Answer as a professional Android app developer using AI.
        Use the supplied project scan, files, command output, and Gradle/ADB context.
        Be project-specific. Do not return a generic implementation plan unless the user explicitly asks for a plan.
        If the prompt asks for safe automatic work, describe the exact local actions the app should perform through its tools.
        Do not claim that files were edited unless the provided context proves it.
        Return only JSON matching the schema.
        """
    }

    private func inputPayload(request: AssistantModelRequest, contextFiles: [AssistantContextFile]) -> String {
        var sections = [
            "User prompt:\n\(request.prompt)",
            """
            Project:
            package=\(request.profile.packageName)
            root=\(request.profile.rootPath)
            intent=\(request.planIntent)
            files=\(request.snapshot.fileCount)
            tests=\(request.snapshot.testFileCount)
            gradleWrapper=\(request.snapshot.hasGradleWrapper)
            manifest=\(request.snapshot.hasAndroidManifest)
            compose=\(request.snapshot.usesCompose)
            kotlin=\(request.snapshot.usesKotlin)
            java=\(request.snapshot.usesJava)
            xml=\(request.snapshot.usesXMLLayouts)
            minSdk=\(request.profile.minSDK)
            modules=\(request.modules.joined(separator: ", "))
            variants=\(request.variants.joined(separator: ", "))
            """
        ]
        if let commandSummary = request.commandSummary?.nilIfEmpty {
            sections.append("Last command summary:\n\(commandSummary)")
        }
        if let recentOutput = request.recentCommandOutput?.nilIfEmpty {
            sections.append("Recent command output excerpt:\n\(recentOutput)")
        }
        if contextFiles.isEmpty {
            sections.append("Relevant project files:\nNo file excerpts were available.")
        } else {
            let fileSection = contextFiles.map { file in
                """
                --- \(file.path) ---
                \(file.content.prefix(6_000))
                """
            }.joined(separator: "\n\n")
            sections.append("Relevant project files:\n\(fileSection)")
        }
        return sections.joined(separator: "\n\n")
    }

    private var structuredOutputSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["answer", "plannedActions"],
            "properties": [
                "answer": [
                    "type": "string",
                    "description": "The project-specific Android development answer for the user."
                ],
                "plannedActions": [
                    "type": "array",
                    "description": "Safe local tool actions the workbench should perform or has enough context to prepare.",
                    "items": ["type": "string"]
                ]
            ]
        ]
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw AssistantModelError.remote("HTTP \(http.statusCode): \(body.prefix(300))")
        }
    }

    private func cosineSimilarity(_ left: [Double], _ right: [Double]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 0 }
        var dot = 0.0
        var leftMagnitude = 0.0
        var rightMagnitude = 0.0
        for index in left.indices {
            dot += left[index] * right[index]
            leftMagnitude += left[index] * left[index]
            rightMagnitude += right[index] * right[index]
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return 0 }
        return dot / (sqrt(leftMagnitude) * sqrt(rightMagnitude))
    }
}

public struct TaskDroidPlannerClient: Sendable {
    public init() {}

    func createPlan(
        request: AssistantModelRequest,
        model: AssistantModelSpec,
        intelligenceLevel: String,
        baseURL: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> TaskDroidPlanResponse {
        let endpoint = baseURL.appendingPathComponent("plan")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(TaskDroidPlanRequest(
            prompt: taskPrompt(from: request),
            intelligenceLevel: intelligenceLevel
        ))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(TaskDroidPlanResponse.self, from: data)
    }

    private func taskPrompt(from request: AssistantModelRequest) -> String {
        """
        User request:
        \(request.prompt)

        Android project context:
        package=\(request.profile.packageName)
        root=\(request.profile.rootPath)
        current_intent=\(request.planIntent)
        files=\(request.snapshot.fileCount)
        tests=\(request.snapshot.testFileCount)
        gradle_wrapper=\(request.snapshot.hasGradleWrapper)
        manifest=\(request.snapshot.hasAndroidManifest)
        compose=\(request.snapshot.usesCompose)
        kotlin=\(request.snapshot.usesKotlin)
        java=\(request.snapshot.usesJava)
        xml=\(request.snapshot.usesXMLLayouts)
        min_sdk=\(request.profile.minSDK)
        modules=\(request.modules.joined(separator: ", "))
        variants=\(request.variants.joined(separator: ", "))
        """
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw AssistantModelError.remote("HTTP \(http.statusCode): \(body.prefix(300))")
        }
    }
}

public struct StructuredAssistantOutput: Codable, Hashable, Sendable {
    public let answer: String
    public let plannedActions: [String]

    public init(answer: String, plannedActions: [String]) {
        self.answer = answer
        self.plannedActions = plannedActions
    }
}

struct TaskDroidPlanRequest: Encodable, Sendable {
    let prompt: String
    let intelligenceLevel: String

    enum CodingKeys: String, CodingKey {
        case prompt
        case intelligenceLevel = "intelligence_level"
    }
}

struct TaskDroidPlanResponse: Decodable, Sendable {
    let plan: TaskDroidPlan
    let intelligenceLevel: String
    let backend: String
    let requestedBackend: String?
    let fallbackUsed: Bool?
    let fallbackReason: String?
    let attemptedBackends: [String]?
    let latencyMs: Int?
    let plannerMetadata: TaskDroidPlannerMetadata?

    enum CodingKeys: String, CodingKey {
        case plan
        case intelligenceLevel = "intelligence_level"
        case backend
        case requestedBackend = "requested_backend"
        case fallbackUsed = "fallback_used"
        case fallbackReason = "fallback_reason"
        case attemptedBackends = "attempted_backends"
        case latencyMs = "latency_ms"
        case plannerMetadata = "planner_metadata"
    }

    func toAssistantResponse(
        model: AssistantModelSpec,
        retrievalModelID: String,
        contextFilePaths: [String]
    ) -> AssistantModelResponse {
        let taskLines = plan.implementationTasks.enumerated().map { index, task in
            let dependencies = task.dependencies.isEmpty ? "none" : task.dependencies.joined(separator: ", ")
            return "\(index + 1). \(task.title) [\(task.layer), effort \(task.estimatedEffort), depends on \(dependencies)] - \(task.description)"
        }
        let files = plan.filesOrModules.isEmpty
            ? "No specific files/modules were returned."
            : plan.filesOrModules.joined(separator: ", ")
        let checks = plan.acceptanceChecks.isEmpty
            ? "No acceptance checks were returned."
            : plan.acceptanceChecks.joined(separator: ", ")
        let risks = plan.risks.isEmpty
            ? "No specific risks were returned."
            : plan.risks.joined(separator: " ")
        let questions = plan.questionsForUser.isEmpty
            ? "No clarification questions."
            : plan.questionsForUser.joined(separator: " ")
        let relevance = plan.isAndroidRelated ? "Android-related" : "Not Android-related"
        let answer = """
        \(model.displayName) produced an implementation task plan.

        Summary: \(plan.featureSummary)
        Classification: \(relevance), confidence \(Int((plan.confidence * 100).rounded()))%.
        Suggested files/modules: \(files)

        Implementation tasks:
        \(taskLines.joined(separator: "\n"))

        Acceptance checks: \(checks)
        Risks: \(risks)
        Questions: \(questions)
        """

        return AssistantModelResponse(
            answer: answer,
            plannedActions: plan.implementationTasks.map { "TaskDroid: \($0.title)" },
            provider: model.provider,
            modelID: model.id,
            modelDisplayName: model.displayName,
            retrievalModelID: retrievalModelID,
            contextFilePaths: contextFilePaths,
            status: "Answered by \(model.displayName) using \(routingStatus)."
        )
    }

    private var routingStatus: String {
        var parts = [
            "intelligence_level=\(intelligenceLevel)",
            "backend=\(backend)"
        ]
        if let requestedBackend {
            parts.append("requested_backend=\(requestedBackend)")
        }
        if let fallbackUsed {
            parts.append("fallback_used=\(fallbackUsed)")
        }
        if let fallbackReason, !fallbackReason.isEmpty {
            parts.append("fallback_reason=\(fallbackReason)")
        }
        if let attemptedBackends, !attemptedBackends.isEmpty {
            parts.append("attempted_backends=\(attemptedBackends.joined(separator: ">"))")
        }
        if let latencyMs {
            parts.append("latency_ms=\(latencyMs)")
        }
        if let plannerMetadata {
            parts.append("model_alias=\(plannerMetadata.modelAlias)")
            parts.append("served_by_fallback=\(plannerMetadata.servedByFallback)")
        }
        return parts.joined(separator: ", ")
    }
}

struct TaskDroidPlannerMetadata: Decodable, Sendable {
    let plannerName: String
    let plannerVersion: String
    let behaviorVersion: String
    let modelAlias: String
    let backendKind: String
    let servedByFallback: Bool

    enum CodingKeys: String, CodingKey {
        case plannerName = "planner_name"
        case plannerVersion = "planner_version"
        case behaviorVersion = "behavior_version"
        case modelAlias = "model_alias"
        case backendKind = "backend_kind"
        case servedByFallback = "served_by_fallback"
    }
}

struct TaskDroidPlan: Decodable, Sendable {
    let isAndroidRelated: Bool
    let confidence: Double
    let featureSummary: String
    let filesOrModules: [String]
    let implementationTasks: [TaskDroidImplementationTask]
    let acceptanceChecks: [String]
    let risks: [String]
    let questionsForUser: [String]

    enum CodingKeys: String, CodingKey {
        case isAndroidRelated = "is_android_related"
        case confidence
        case featureSummary = "feature_summary"
        case filesOrModules = "files_or_modules"
        case implementationTasks = "implementation_tasks"
        case acceptanceChecks = "acceptance_checks"
        case risks
        case questionsForUser = "questions_for_user"
    }
}

struct TaskDroidImplementationTask: Decodable, Sendable {
    let id: String
    let title: String
    let description: String
    let layer: String
    let estimatedEffort: String
    let dependencies: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case layer
        case estimatedEffort = "estimated_effort"
        case dependencies
    }
}

private enum LocalContextRanker {
    static func rank(prompt: String, files: [AssistantContextFile]) -> [AssistantContextFile] {
        let promptTerms = terms(in: prompt)
        let scored = files.map { file in
            let path = file.path.lowercased()
            let contentTerms = terms(in: "\(file.path) \(file.content.prefix(2_000))")
            var score = contentTerms.intersection(promptTerms).count
            if path.contains("build.gradle") || path.contains("libs.versions.toml") { score += promptTerms.contains("gradle") || promptTerms.contains("dependency") ? 12 : 2 }
            if path.contains("androidmanifest.xml") { score += promptTerms.contains("manifest") || promptTerms.contains("permission") ? 12 : 2 }
            if path.hasSuffix(".kt") || path.hasSuffix(".java") { score += 3 }
            if path.contains("/src/test/") || path.contains("/src/androidtest/") { score += promptTerms.contains("test") ? 8 : 1 }
            if path.contains("mainactivity") || path.contains("screen") || path.contains("viewmodel") { score += 4 }
            return (file, score)
        }
        return scored.sorted { left, right in
            if left.1 == right.1 { return left.0.path < right.0.path }
            return left.1 > right.1
        }.map(\.0)
    }

    private static func terms(in value: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(
            value.lowercased()
                .components(separatedBy: separators)
                .filter { $0.count > 2 }
        )
    }
}

private enum LocalAndroidAssistantResponder {
    static func answer(
        request: AssistantModelRequest,
        contextFiles: [AssistantContextFile],
        routedModel: AssistantModelSpec
    ) -> AssistantModelResponse {
        let lower = request.prompt.lowercased()
        let fileList = contextFiles.map(\.path).prefix(6).joined(separator: ", ")
        let project = request.profile.packageName
        let ui = request.snapshot.usesCompose ? "Jetpack Compose" : request.snapshot.usesXMLLayouts ? "XML layouts" : "mixed Android UI"
        let modules = request.modules.isEmpty ? "default module" : request.modules.joined(separator: ", ")
        let variants = request.variants.isEmpty ? "Debug/Release" : request.variants.joined(separator: ", ")

        let answer: String
        if DevelopmentAgent.containsAny(lower, "overview", "summary", "summarize", "what is this project") {
            answer = "\(project) is an Android project using \(ui), with \(request.snapshot.fileCount) files, \(request.snapshot.testFileCount) test files, modules \(modules), and variants \(variants). The most relevant files I found are \(fileList.nilIfEmpty ?? "not available yet"). Use this context for changes to source, Gradle, manifest, resources, and tests instead of treating the prompt as a generic plan."
        } else if DevelopmentAgent.containsAny(lower, "crash", "exception", "logcat", "anr") {
            answer = "For \(project), I would triage this as an Android runtime issue: inspect the first app-owned Logcat stack frame, open the closest Kotlin/Java state or UI file, add the smallest guard or state fix, and add a regression test. Relevant context: \(fileList.nilIfEmpty ?? "no matching files yet"). If a device is selected, capture Logcat before changing code."
        } else if DevelopmentAgent.containsAny(lower, "gradle", "dependency", "compile", "sync", "manifest") {
            answer = "For \(project), I would handle this through the build/config route: inspect settings, module Gradle files, version catalog, and AndroidManifest before editing. The project has \(request.snapshot.hasGradleWrapper ? "a Gradle wrapper" : "system Gradle only"), modules \(modules), and variants \(variants). Relevant context: \(fileList.nilIfEmpty ?? "no build files were loaded"). Run assemble and unit tests after the scoped change."
        } else if DevelopmentAgent.containsAny(lower, "screen", "ui", "compose", "xml", "layout", "theme") {
            answer = "For \(project), I would implement the UI in the detected \(ui) style, keep state in the nearest ViewModel/reducer, preserve accessibility labels, and add tests around state transitions. Relevant files: \(fileList.nilIfEmpty ?? "open the Files panel to load source context"). Verification should include unit tests, assemble, and device UI checks when a target is selected."
        } else if DevelopmentAgent.containsAny(lower, "test", "coverage", "junit", "espresso", "instrumentation") {
            answer = "For \(project), I found \(request.snapshot.testFileCount) test files. I would add focused unit tests near the changed logic first, then consider instrumentation tests only after an emulator is selected. Relevant context: \(fileList.nilIfEmpty ?? "no test files were loaded")."
        } else {
            answer = "I routed this Android development prompt for \(project) through \(routedModel.displayName). Based on \(request.snapshot.fileCount) scanned files, \(request.snapshot.testFileCount) tests, \(ui), modules \(modules), and variants \(variants), the safest next step is to inspect \(fileList.nilIfEmpty ?? "the closest source and Gradle files"), open likely edit targets, make a scoped patch, then run the narrowest useful Gradle or ADB verification."
        }

        return AssistantModelResponse(
            answer: answer,
            plannedActions: [],
            provider: routedModel.provider,
            modelID: routedModel.id,
            modelDisplayName: routedModel.displayName,
            retrievalModelID: "local lexical ranker",
            contextFilePaths: contextFiles.map(\.path),
            status: "Local fallback answered via \(routedModel.displayName)."
        )
    }
}

private enum AssistantModelError: LocalizedError {
    case remote(String)

    var errorDescription: String? {
        switch self {
        case let .remote(message): return message
        }
    }
}

private struct OpenAIResponseEnvelope: Decodable {
    let outputText: String?
    let output: [OpenAIOutputItem]?
    let error: OpenAIErrorPayload?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
        case error
    }

    var outputContentText: String {
        output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
    }
}

private struct OpenAIOutputItem: Decodable {
    let content: [OpenAIContentItem]?
}

private struct OpenAIContentItem: Decodable {
    let text: String?
}

private struct OpenAIErrorPayload: Decodable {
    let message: String
}

private struct OpenAIEmbeddingEnvelope: Decodable {
    let data: [OpenAIEmbeddingItem]
}

private struct OpenAIEmbeddingItem: Decodable {
    let index: Int
    let embedding: [Double]
}

private extension AssistantModelResponse {
    func withStatus(_ status: String) -> AssistantModelResponse {
        AssistantModelResponse(
            answer: answer,
            plannedActions: plannedActions,
            provider: provider,
            modelID: modelID,
            modelDisplayName: modelDisplayName,
            retrievalModelID: retrievalModelID,
            contextFilePaths: contextFilePaths,
            status: status
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
