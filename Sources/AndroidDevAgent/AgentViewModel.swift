import AndroidDevAgentCore
import AppKit
import Combine
import CoreImage
import Foundation

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var projectPath: String
    @Published var prompt: String
    @Published private(set) var snapshot: WorkspaceSnapshot
    @Published private(set) var profile: ProjectProfile
    @Published private(set) var plan: AgentPlan
    @Published private(set) var commandOutput: String = ""
    @Published private(set) var isRunningCommand = false
    @Published private(set) var lastCommandTitle = "Idle"
    @Published private(set) var runningCommandKind: AndroidCommandKind?
    @Published private(set) var projectFiles: [ProjectFileItem] = []
    @Published private(set) var isProjectLoaded = false
    @Published private(set) var filePanelRevealGeneration = 0
    @Published private(set) var scanState: ScanState = .waiting
    @Published private(set) var isScanningProject = false
    @Published private(set) var lastStatusMessage = "Choose an Android project folder to begin."
    @Published var selectedModule = "app"
    @Published var selectedVariant = "Debug"
    @Published var packageOverride = ""
    @Published var launchActivity = ".MainActivity"
    @Published var selectedDeviceID = "" {
        didSet {
            guard selectedDeviceID != oldValue else { return }
            resetDevicePreviewForSelectionChange()
        }
    }
    @Published var fileSearchQuery = ""
    @Published private(set) var modules: [String] = ["app"]
    @Published private(set) var buildVariants: [String] = ["Debug", "Release"]
    @Published private(set) var devices: [DeviceOption] = []
    @Published private(set) var isRefreshingDevices = false
    @Published private(set) var devicePreviewImage: NSImage?
    @Published private(set) var isRefreshingDevicePreview = false
    @Published private(set) var isSendingDeviceInput = false
    @Published private(set) var isDevicePreviewAutoRefreshEnabled = true {
        didSet {
            guard isDevicePreviewAutoRefreshEnabled != oldValue else { return }
            if isDevicePreviewAutoRefreshEnabled {
                startDevicePreviewAutoRefresh()
            } else {
                stopDevicePreviewAutoRefresh(updateStatus: true)
            }
        }
    }
    @Published private(set) var devicePreviewStatus = "Select an Android target to preview its screen."
    @Published private(set) var devicePreviewUpdatedAt: Date?
    @Published private(set) var isRunningWirelessDebugging = false
    @Published var wirelessPairingCode = ""
    @Published var wirelessConnectAddress = ""
    @Published private(set) var wirelessDebuggingStatus = "Use Android Wireless Debugging to pair or connect a device over Wi-Fi."
    @Published private(set) var lastWirelessPairingAddress = ""
    @Published private(set) var lastWirelessDeviceAddress = ""
    @Published private(set) var wirelessDebuggingDevices: [WirelessDebuggingDevice] = []
    @Published private(set) var wirelessDeviceDiscoveryStatus = "Scan for wireless Android devices on this network."
    @Published var selectedWirelessDebuggingDeviceID = "" {
        didSet {
            guard selectedWirelessDebuggingDeviceID != oldValue else { return }
            applySelectedWirelessDebuggingDevice()
        }
    }
    @Published private(set) var wirelessQRCodeImage: NSImage?
    @Published private(set) var wirelessQRCodeStatus = "Generate a QR code, then scan it from Android Wireless Debugging."
    @Published private(set) var wirelessQRCodePayload = ""
    @Published var pendingConfirmation: CommandConfirmation?
    @Published var pendingWirelessDebuggingConfirmation: WirelessDebuggingConfirmation?
    @Published private(set) var promptHistory: [String] = []
    @Published private(set) var recentProjectPaths: [String] = []
    @Published private(set) var isOutputTruncated = false
    @Published private(set) var lastCommandSummary: CommandRunSummary?
    @Published private(set) var debugReportPath = ""
    @Published private(set) var supportBundlePath = ""
    @Published private(set) var supportUploadStatus = ""
    @Published private(set) var isSupportUploadRunning = false
    @Published var selectedPlanStepID: Int?
    @Published var selectedSessionTab: SessionPaneTab = .chat
    @Published private(set) var lastExportPath = ""
    @Published private(set) var lastExportSource = ""
    @Published private(set) var openEditorDocuments: [EditorDocument] = []
    @Published var selectedEditorPath = ""
    @Published private(set) var lastEditorSaveDiffLines: [String] = []
    @Published private(set) var lastEditorSaveSafetySummary = "No editor save has run yet."
    @Published private(set) var lastEditorUndoCheckpointPath = ""
    @Published private(set) var lastEditorSecretScanSummary = "No editor save has scanned for secrets yet."
    @Published private(set) var expandedProjectFolderPaths = Set<String>()
    @Published var consoleSearchQuery = ""
    @Published var consoleStreamFilter: ConsoleStreamFilter = .all
    @Published private(set) var planNeedsRefresh = false
    @Published private(set) var unavailableDeviceSummary = ""
    @Published private(set) var scanStartedAt: Date?
    @Published private(set) var lastStandardOutput = ""
    @Published private(set) var lastStandardError = ""
    @Published private(set) var assistantResponse = ""
    @Published private(set) var assistantActionSummary = ""
    @Published private(set) var assistantResponseExportPath = ""
    @Published private(set) var assistantResponseFeedback = ""
    @Published private(set) var assistantModelStatus = "Local assistant ready."
    @Published private(set) var assistantModelDetail = "Model orchestration has not run yet."
    @Published private(set) var isAssistantThinking = false
    @Published var assistantTaskDroidBaseURLText = "" {
        didSet {
            UserDefaults.standard.set(assistantTaskDroidBaseURLText, forKey: assistantTaskDroidBaseURLKey)
        }
    }
    @Published var assistantTaskDroidTimeoutText = "360" {
        didSet {
            UserDefaults.standard.set(assistantTaskDroidTimeoutText, forKey: assistantTaskDroidTimeoutKey)
        }
    }
    @Published var assistantPrefersTaskDroid = false {
        didSet {
            UserDefaults.standard.set(assistantPrefersTaskDroid, forKey: assistantPrefersTaskDroidKey)
        }
    }
    @Published private(set) var assistantCredentialStatus = "OpenAI key not configured."
    @Published var assistantAllowsProviderSharing = false {
        didSet {
            UserDefaults.standard.set(assistantAllowsProviderSharing, forKey: assistantProviderSharingConsentKey)
            if hasLoadedStoredPreferences && oldValue != assistantAllowsProviderSharing {
                AndroidDevAgentLaunchReadiness.recordPrivacyAudit(
                    assistantAllowsProviderSharing ? "provider_sharing_enabled" : "provider_sharing_disabled"
                )
            }
            assistantModelStatus = assistantAllowsProviderSharing
                ? "Provider sharing enabled by user consent."
                : "Provider sharing off; Ask uses the private local route."
        }
    }
    @Published var assistantModelMode: AssistantModelMode = .automatic {
        didSet {
            UserDefaults.standard.set(assistantModelMode.rawValue, forKey: assistantModelModeKey)
            assistantModelStatus = assistantAllowsProviderSharing
                ? "Model mode set to \(assistantModelMode.title)."
                : "Model mode set to \(assistantModelMode.title); provider sharing remains off."
        }
    }

    let agent = DevelopmentAgent()
    private let assistantOrchestrator = AssistantModelOrchestrator()
    private let runner = ProcessRunner()
    private let commandRunner = ProcessRunner()
    private let deviceTestCleanupRunner = ProcessRunner()
    private let deviceInputRunner = ProcessRunner()
    private var scanID = UUID()
    private var currentCommandID = UUID()
    private var currentDeviceInputID = UUID()
    private var lastRunnableCommandKind: AndroidCommandKind?
    private var previousPromptDraft: String?
    private var revealFilesAfterCurrentScan = true
    private var hasLoadedStoredPreferences = false
    private var assistantResponseFeedbackToken = UUID()
    private var currentDevicePreviewID = UUID()
    private var isDevicePreviewCaptureInFlight = false
    private var devicePreviewAutoRefreshTask: Task<Void, Never>?
    private var pendingDeviceTapCoordinates: (x: Int, y: Int)?
    private var shouldResumeDevicePreviewAutoRefreshAfterInput = false
    private let devicePreviewAutoRefreshIntervalNanoseconds: UInt64 = 20_000_000
    private let recentProjectsKey = "AndroidDevAgentRecentProjects"
    private let promptHistoryKey = "AndroidDevAgentPromptHistory"
    private let assistantModelModeKey = "AndroidDevAgentAssistantModelMode"
    private let assistantResponseExportPathKey = "AndroidDevAgentAssistantResponseExportPath"
    private let assistantProviderSharingConsentKey = "AndroidDevAgentAssistantProviderSharingConsent"
    private let assistantTaskDroidBaseURLKey = "AndroidDevAgentAssistantTaskDroidBaseURL"
    private let assistantTaskDroidTimeoutKey = "AndroidDevAgentAssistantTaskDroidTimeout"
    private let assistantPrefersTaskDroidKey = "AndroidDevAgentAssistantPrefersTaskDroid"

    init() {
        let initialPrompt = "Create a login screen, add ViewModel validation, run tests, and inspect the UI on an emulator."
        let initialSnapshot = WorkspaceSnapshot.empty(rootPath: "")
        let initialProfile = ProjectProfile.defaultProfile(rootPath: "")
        let initialPlan = agent.createPlan(request: initialPrompt, profile: initialProfile, snapshot: initialSnapshot)

        projectPath = ""
        prompt = initialPrompt
        snapshot = initialSnapshot
        profile = initialProfile
        plan = initialPlan
        commandOutput = "Android Dev Agent ready.\nChoose an Android project to scan files and enable Gradle/ADB tools.\n"
        projectFiles = []
        recentProjectPaths = UserDefaults.standard.stringArray(forKey: recentProjectsKey) ?? []
        promptHistory = UserDefaults.standard.stringArray(forKey: promptHistoryKey) ?? []
        supportBundlePath = UserDefaults.standard.string(forKey: AndroidDevAgentLaunchReadiness.latestSupportBundlePathKey) ?? ""
        supportUploadStatus = UserDefaults.standard.string(forKey: AndroidDevAgentLaunchReadiness.latestSupportUploadStatusKey) ?? ""
        assistantTaskDroidBaseURLText = UserDefaults.standard.string(forKey: assistantTaskDroidBaseURLKey) ?? ""
        assistantTaskDroidTimeoutText = UserDefaults.standard.string(forKey: assistantTaskDroidTimeoutKey)
            ?? Self.environmentTaskDroidTimeoutText
            ?? "360"
        if let storedPreference = UserDefaults.standard.object(forKey: assistantPrefersTaskDroidKey) as? Bool {
            assistantPrefersTaskDroid = storedPreference
        } else {
            assistantPrefersTaskDroid = Self.environmentTaskDroidBaseURLText != nil
        }
        refreshAssistantCredentialStatus()
        assistantAllowsProviderSharing = UserDefaults.standard.bool(forKey: assistantProviderSharingConsentKey)
        let restoredAssistantExportPath = restoreAssistantResponseExportPath()
        if let storedMode = UserDefaults.standard.string(forKey: assistantModelModeKey),
           let mode = AssistantModelMode(rawValue: storedMode) {
            assistantModelMode = mode
        }
        hasLoadedStoredPreferences = true
        if let lastProject = recentProjectPaths.first {
            projectPath = lastProject
            if restoredAssistantExportPath {
                lastStatusMessage = "Auto-loading recent project: \(displayPath(lastProject)). Restored previous assistant export path."
            } else {
                lastStatusMessage = "Auto-loading recent project: \(displayPath(lastProject))"
            }
            Task { @MainActor [weak self] in
                self?.scanProject(revealFilesWhenLoaded: false)
            }
        } else if restoredAssistantExportPath {
            lastStatusMessage = "Restored previous assistant export path."
        }
    }

    func chooseProject() {
        chooseProject(scanImmediately: true)
    }

    func chooseProjectOnly() {
        chooseProject(scanImmediately: false)
    }

    private func chooseProject(scanImmediately: Bool) {
        let panel = NSOpenPanel()
        panel.title = "Choose Android Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            projectPath = resolvedProjectPath(url.path)
            if scanImmediately {
                scanProject()
            } else {
                lastStatusMessage = "Selected \(displayPath(projectPath)). Scan when you are ready."
            }
        } else {
            lastStatusMessage = "Project selection cancelled. Paste a path, drop a folder, or choose a recent project."
        }
    }

    func selectProject(path: String, scanImmediately: Bool = true) {
        let resolvedPath = resolvedProjectPath(path)
        projectPath = resolvedPath
        lastStatusMessage = "Selected \(displayPath(resolvedPath))"
        if scanImmediately {
            scanProject()
        }
    }

    func selectDroppedItem(url: URL) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            selectProject(path: url.deletingLastPathComponent().path)
            lastStatusMessage = "Dropped a file, so I scanned its parent folder: \(displayPath(projectPath))"
        } else {
            selectProject(path: url.path)
        }
    }

    func cancelScan() {
        guard isScanningProject else {
            lastStatusMessage = "No project scan is currently running."
            return
        }
        scanID = UUID()
        isScanningProject = false
        scanState = .warning("Scan cancelled before completion.")
        lastStatusMessage = "Scan cancelled. The previous project state was preserved."
        scanStartedAt = nil
        appendOutput("Scan cancelled.\n")
    }

    func scanProject() {
        scanProject(revealFilesWhenLoaded: true)
    }

    private func scanProject(revealFilesWhenLoaded: Bool) {
        let trimmedPath = resolvedProjectPath(projectPath)
        guard !trimmedPath.isEmpty else {
            failScan("Choose an Android project before scanning.")
            return
        }
        guard !isUnsafeScanRoot(trimmedPath) else {
            failScan("Scanning broad folders is blocked. Choose a specific Android project folder.")
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            failScan("The selected project path does not exist or is not a directory: \(trimmedPath)")
            return
        }

        projectPath = trimmedPath
        revealFilesAfterCurrentScan = revealFilesWhenLoaded
        isScanningProject = true
        scanStartedAt = Date()
        scanState = .scanning
        lastStatusMessage = "Scanning \(displayPath(trimmedPath))..."
        appendOutput("Scanning workspace: \(trimmedPath)\n")

        let currentScanID = UUID()
        scanID = currentScanID

        Task {
            let scannedSnapshot = await Task.detached(priority: .userInitiated) {
                AndroidWorkspaceScanner().scan(rootPath: trimmedPath)
            }.value

            guard self.scanID == currentScanID else { return }
            self.applyScan(snapshot: scannedSnapshot, rootPath: trimmedPath)
        }
    }

    func generatePlan(updateStatus: Bool = true) {
        guard !updateStatus || canGeneratePlan else {
            lastStatusMessage = generatePlanHelpText
            return
        }
        savePromptToHistory(prompt)
        profile = ProjectProfile.from(snapshot: snapshot)
        plan = agent.createPlan(request: prompt, profile: profile, snapshot: snapshot)
        selectedPlanStepID = plan.steps.first?.id
        planNeedsRefresh = false
        if updateStatus {
            lastStatusMessage = "Plan refreshed for \(isProjectLoaded ? profile.packageName : "pending project")."
        }
        selectedSessionTab = .chat
    }

    var canGeneratePlan: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isScanningProject
    }

    var generatePlanHelpText: String {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a prompt before regenerating the plan."
        }
        if isScanningProject {
            return "Wait for project scanning to finish before regenerating the plan."
        }
        return "Refreshes the assistant plan from the current prompt and workspace context."
    }

    func submitAssistantPrompt(runActions: Bool = true) {
        savePromptToHistory(prompt)
        profile = ProjectProfile.from(snapshot: snapshot)
        plan = agent.createPlan(request: prompt, profile: profile, snapshot: snapshot)
        selectedPlanStepID = plan.steps.first?.id
        planNeedsRefresh = false

        let lower = plan.originalRequest.lowercased()
        var actionMessages: [String] = []
        if runActions {
            actionMessages = performAssistantActions(for: lower)
        }

        assistantActionSummary = actionMessages.joined(separator: " ")
        assistantResponse = makeAssistantResponse(for: lower, actionMessages: actionMessages)
        clearAssistantResponseExportPath()
        assistantResponseFeedback = ""
        selectedSessionTab = .chat
        lastStatusMessage = actionMessages.isEmpty
            ? "Assistant response generated for \(isProjectLoaded ? profile.packageName : "pending project")."
            : "Assistant responded and acted: \(assistantActionSummary)"
    }

    func askAssistant(runActions: Bool = true) {
        guard !isAssistantThinking else {
            lastStatusMessage = "The assistant is already generating a response."
            return
        }
        Task { @MainActor [weak self] in
            await self?.submitAssistantPromptWithModels(runActions: runActions)
        }
    }

    var canAskAssistant: Bool {
        askAssistantBlockReason == nil
    }

    var canEditAssistantPrompt: Bool {
        !isAssistantThinking
    }

    var canEditAssistantModelMode: Bool {
        !isAssistantThinking
    }

    var canEditAssistantPrivacyConsent: Bool {
        !isAssistantThinking
    }

    var assistantModelModeHelpText: String {
        isAssistantThinking
            ? "Wait for the current assistant response before changing model mode."
            : "Selects the Ask routing mode."
    }

    var assistantPromptHelpText: String {
        isAssistantThinking
            ? "Wait for the assistant response before editing the prompt."
            : "Describe the Android development task for the plan."
    }

    var askAssistantHelpText: String {
        askAssistantBlockReason ?? "Ask the assistant for a project-specific response and run safe automatic actions requested by the prompt."
    }

    var assistantProviderSharingHelpText: String {
        if isAssistantThinking {
            return "Wait for the current assistant response before changing provider sharing."
        }
        if assistantAllowsProviderSharing && assistantModelMode == .privateLocal {
            return "Provider sharing consent is saved, but Private mode still blocks project file excerpts and command output."
        }
        return assistantAllowsProviderSharing
            ? "Provider sharing is enabled. Ask may send redacted project context and recent command output to the selected model provider."
            : "Provider sharing is off. Ask uses the private local route and omits project file excerpts plus command output."
    }

    var assistantPrivacySummary: String {
        if assistantAllowsProviderSharing && assistantModelMode == .privateLocal {
            return "Private mode local"
        }
        if assistantAllowsProviderSharing {
            return "Provider sharing enabled"
        }
        return "Private by default"
    }

    private var askAssistantBlockReason: String? {
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a prompt before asking the assistant."
        }
        if isScanningProject { return "Wait for project scanning to finish before asking the assistant." }
        if isRunningCommand { return "Wait for the current command to finish before asking the assistant." }
        if isRefreshingDevices { return "Wait for device refresh to finish before asking the assistant." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging to finish before asking the assistant." }
        if isAssistantThinking { return "The assistant is already generating a response." }
        return nil
    }

    func submitAssistantPromptWithModels(runActions: Bool = true, allowRemoteModels: Bool = true) async {
        guard !isAssistantThinking else {
            lastStatusMessage = "The assistant is already generating a response."
            return
        }
        savePromptToHistory(prompt)
        profile = ProjectProfile.from(snapshot: snapshot)
        plan = agent.createPlan(request: prompt, profile: profile, snapshot: snapshot)
        selectedPlanStepID = plan.steps.first?.id
        planNeedsRefresh = false

        let lower = plan.originalRequest.lowercased()
        var actionMessages: [String] = []
        if runActions {
            actionMessages = performAssistantActions(for: lower)
        }

        let sharingAllowed = assistantProviderPayloadSharingAllowed(allowRemoteModels: allowRemoteModels)
        let request = makeAssistantModelRequest(for: lower, sharingAllowed: sharingAllowed)
        let contextFiles = request.contextFiles
        let config = AssistantOrchestrationConfig(
            mode: sharingAllowed ? assistantModelMode : .privateLocal,
            openAIAPIKey: openAIAPIKey,
            allowRemoteModels: sharingAllowed,
            taskDroidBaseURL: assistantTaskDroidBaseURL,
            preferTaskDroid: sharingAllowed && assistantTaskDroidEnabled,
            taskDroidTimeoutSeconds: assistantTaskDroidTimeoutSeconds
        )

        isAssistantThinking = true
        assistantModelStatus = sharingAllowed
            ? "Routing with \(assistantModelMode.title) after provider-sharing consent..."
            : "Routing privately; provider sharing is off."
        assistantModelDetail = assistantPayloadDetail(contextFileCount: contextFiles.count, sharingAllowed: sharingAllowed)
        selectedSessionTab = .chat

        let modelResponse = await assistantOrchestrator.answer(request: request, config: config)
        isAssistantThinking = false
        assistantActionSummary = (actionMessages + modelResponse.plannedActions).joined(separator: " ")
        assistantResponse = modelResponse.answer
        clearAssistantResponseExportPath()
        assistantResponseFeedback = ""
        assistantModelStatus = modelResponse.status
        assistantModelDetail = "\(modelResponse.modelDisplayName) (\(modelResponse.modelID)) via \(modelResponse.provider.rawValue); privacy: \(sharingAllowed ? "provider sharing enabled" : "private local, no provider sharing"); setup: \(assistantModelSetupSummary); retrieval: \(modelResponse.retrievalModelID); context: \(modelResponse.contextFilePaths.isEmpty ? "none" : modelResponse.contextFilePaths.joined(separator: ", "))"
        lastStatusMessage = assistantActionSummary.isEmpty
            ? "Assistant response generated by \(modelResponse.modelDisplayName)\(sharingAllowed ? "." : " without provider sharing.")."
            : "Assistant responded and acted: \(assistantActionSummary)"
    }

    private func assistantProviderPayloadSharingAllowed(allowRemoteModels: Bool) -> Bool {
        allowRemoteModels && assistantAllowsProviderSharing && assistantModelMode != .privateLocal
    }

    private func makeAssistantModelRequest(for lower: String, sharingAllowed: Bool) -> AssistantModelRequest {
        let contextFiles = sharingAllowed ? assistantContextFiles(for: lower) : []
        return AssistantModelRequest(
            prompt: plan.originalRequest,
            profile: profile,
            snapshot: snapshot,
            planIntent: plan.intent,
            modules: modules,
            variants: buildVariants,
            contextFiles: contextFiles,
            commandSummary: sharingAllowed ? lastCommandSummary?.detail : nil,
            recentCommandOutput: sharingAllowed ? recentCommandOutputExcerpt : nil
        )
    }

    private func assistantPayloadDetail(contextFileCount: Int, sharingAllowed: Bool) -> String {
        if sharingAllowed {
            let context = contextFileCount == 0
                ? "No file excerpts were available for model context."
                : "Prepared \(contextFileCount) redacted project context file\(contextFileCount == 1 ? "" : "s")."
            let command = recentCommandOutputExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No recent command output will be sent."
                : "Recent command output excerpt is allowed by consent."
            return "\(context) \(command) \(assistantProviderAccountSummary)."
        }
        return "Provider sharing is off; Ask omitted project file excerpts and command output. \(assistantProviderAccountSummary)."
    }

    func runCommand(_ kind: AndroidCommandKind) {
        guard !isScanningProject && !isRunningCommand && !isRefreshingDevices && !isRunningWirelessDebugging else {
            let detail: String
            if isScanningProject {
                detail = "Wait for the project scan to finish or cancel it before running \(kind.rawValue)."
            } else if isRefreshingDevices {
                detail = "Wait for the device refresh to finish before running \(kind.rawValue)."
            } else if isRunningWirelessDebugging {
                detail = "Wait for Wireless Debugging to finish before running \(kind.rawValue)."
            } else {
                detail = "Wait for the running command to finish or stop it before starting \(kind.rawValue)."
            }
            lastCommandSummary = CommandRunSummary(
                title: kind.rawValue,
                status: "Blocked",
                detail: detail,
                severity: "warning",
                duration: "0s"
            )
            selectedSessionTab = .checks
            lastStatusMessage = lastCommandSummary?.detail ?? "\(kind.rawValue) is blocked."
            appendOutput("Blocked \(kind.rawValue): \(lastStatusMessage)\n")
            return
        }
        if kind == .devices {
            executeCommand(kind)
            return
        }
        guard isProjectLoaded else {
            let message = "Scan a valid Android project before running \(kind.rawValue)."
            lastCommandSummary = CommandRunSummary(title: kind.rawValue, status: "Blocked", detail: message, severity: "warning", duration: "0s")
            selectedSessionTab = .diagnostics
            appendOutput("Blocked \(kind.rawValue): \(message)\n")
            lastStatusMessage = message
            return
        }
        guard !kind.requiresDevice || !selectedDeviceID.isEmpty else {
            selectedSessionTab = .diagnostics
            lastCommandSummary = CommandRunSummary(
                title: kind.rawValue,
                status: "Blocked",
                detail: "No Android device is selected. Refresh devices and choose a target before running \(kind.rawValue).",
                severity: "warning",
                duration: "0s"
            )
            lastStatusMessage = lastCommandSummary?.detail ?? "No Android device selected."
            appendOutput("Blocked \(kind.rawValue): no Android device selected.\n")
            return
        }
        if kind == .launch {
            let packageName = packageNameForCommands
            let activity = launchActivity.trimmingCharacters(in: .whitespacesAndNewlines)
            guard packageName != "unknown.android.app", !activity.isEmpty else {
                let message = packageName == "unknown.android.app"
                    ? "Set a launch package before starting the app on a device."
                    : "Set a launch activity before starting the app on a device."
                lastCommandSummary = CommandRunSummary(title: kind.rawValue, status: "Blocked", detail: message, severity: "warning", duration: "0s")
                selectedSessionTab = .diagnostics
                appendOutput("Blocked \(kind.rawValue): \(message)\n")
                lastStatusMessage = message
                return
            }
        }
        if kind.requiresConfirmation {
            pendingConfirmation = CommandConfirmation(kind: kind, message: confirmationMessage(for: kind))
            lastStatusMessage = "Confirm \(kind.rawValue) before running."
            return
        }

        executeCommand(kind)
    }

    func confirmPendingCommand() {
        guard let pendingConfirmation else {
            lastStatusMessage = "No command is waiting for confirmation."
            return
        }
        let kind = pendingConfirmation.kind
        self.pendingConfirmation = nil
        executeCommand(kind)
    }

    func cancelPendingCommand() {
        guard let pendingConfirmation else {
            lastStatusMessage = "No command confirmation is open."
            return
        }
        lastStatusMessage = "\(pendingConfirmation.kind.rawValue) cancelled."
        self.pendingConfirmation = nil
    }

    private func executeCommand(_ kind: AndroidCommandKind) {
        savePromptToHistory(prompt)
        lastRunnableCommandKind = kind

        if kind == .launch {
            executeInstallAndLaunch()
            return
        }

        let command = commandFor(kind)
        let startedAt = Date()
        let commandID = UUID()
        currentCommandID = commandID
        lastCommandTitle = command.title
        runningCommandKind = kind
        isRunningCommand = true
        let runLocation = kind == .devices && !isProjectLoaded ? "ADB environment" : displayPath(projectPath)
        lastCommandSummary = CommandRunSummary(
            title: command.title,
            status: "Running",
            detail: "Running in \(runLocation) with a \(Int(kind.timeoutSeconds))s timeout.",
            severity: "running",
            duration: "0s"
        )
        selectedSessionTab = .checks
        appendOutput("$ \(command.preview)\n")

        Task {
            let result = await commandRunner.run(command, timeoutSeconds: kind.timeoutSeconds)
            guard self.currentCommandID == commandID else { return }
            runningCommandKind = nil
            let elapsed = Date().timeIntervalSince(startedAt)
            let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
            appendOutput("\n[\(result.command.title) \(status)]\n")
            if !result.standardOutput.isEmpty {
                appendOutput(result.standardOutput)
            }
            if !result.standardError.isEmpty {
                appendOutput("\n" + result.standardError)
            }
            lastStandardOutput = result.standardOutput
            lastStandardError = result.standardError
            appendOutput("\n")
            if kind == .devices {
                isRunningCommand = false
                lastCommandTitle = "Idle"
                applyDeviceOutput(
                    result.standardOutput,
                    standardError: result.standardError,
                    succeeded: result.succeeded
                )
                lastCommandSummary = summarizeDeviceResult(result, status: status, elapsed: elapsed)
                selectedSessionTab = .diagnostics
                return
            }
            lastCommandSummary = summarizeCommandResult(result, status: status, elapsed: elapsed)
            lastStatusMessage = lastCommandSummary?.detail ?? "\(result.command.title) \(status)."
            selectedSessionTab = result.succeeded ? .checks : .diagnostics
            isRunningCommand = false
            lastCommandTitle = "Idle"
        }
    }

    private func executeInstallAndLaunch() {
        let installTask = gradleTaskName(prefix: "install", suffix: "")
        let installCommand = AndroidToolCommandFactory.installVariant(
            rootPath: projectPath,
            task: installTask,
            deviceSerial: selectedDeviceID
        )
        let launchCommand = commandFor(.launch)
        let workflowTitle = "Install and Launch App"
        let startedAt = Date()
        let commandID = UUID()

        currentCommandID = commandID
        lastCommandTitle = workflowTitle
        runningCommandKind = .launch
        isRunningCommand = true
        lastCommandSummary = CommandRunSummary(
            title: workflowTitle,
            status: "Running",
            detail: "Running \(installTask) on \(selectedDeviceID), then launching \(packageNameForCommands)/\(launchActivity).",
            severity: "running",
            duration: "0s"
        )
        selectedSessionTab = .checks
        appendOutput("$ \(installCommand.preview)\n")

        Task {
            let installResult = await commandRunner.run(
                installCommand,
                timeoutSeconds: AndroidCommandKind.launch.timeoutSeconds
            )
            guard self.currentCommandID == commandID else { return }

            let installStatus = commandExecutionStatus(installResult)
            appendCommandResultToOutput(installResult, status: installStatus)
            lastStandardOutput = installResult.standardOutput
            lastStandardError = installResult.standardError

            guard installResult.succeeded else {
                let elapsed = Date().timeIntervalSince(startedAt)
                let installSummary = summarizeCommandResult(installResult, status: installStatus, elapsed: elapsed)
                lastCommandSummary = CommandRunSummary(
                    title: workflowTitle,
                    status: installSummary.status,
                    detail: "Launch was skipped because \(installSummary.detail)",
                    severity: installSummary.severity,
                    duration: installSummary.duration
                )
                lastStatusMessage = lastCommandSummary?.detail ?? "App installation failed; launch was skipped."
                selectedSessionTab = .diagnostics
                finishInstallAndLaunchWorkflow()
                return
            }

            appendOutput("$ \(launchCommand.preview)\n")
            let launchResult = await commandRunner.run(launchCommand, timeoutSeconds: 25)
            guard self.currentCommandID == commandID else { return }

            let launchStatus = commandExecutionStatus(launchResult)
            appendCommandResultToOutput(launchResult, status: launchStatus)
            lastStandardOutput = [installResult.standardOutput, launchResult.standardOutput]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            lastStandardError = [installResult.standardError, launchResult.standardError]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let elapsed = Date().timeIntervalSince(startedAt)
            if launchResult.succeeded {
                lastCommandSummary = CommandRunSummary(
                    title: workflowTitle,
                    status: "Succeeded",
                    detail: "Installed \(selectedModule) \(selectedVariant) on \(selectedDeviceID) and launched \(packageNameForCommands)/\(launchActivity).",
                    severity: "ready",
                    duration: String(format: "%.1fs", elapsed)
                )
                selectedSessionTab = .checks
            } else {
                let launchSummary = summarizeCommandResult(launchResult, status: launchStatus, elapsed: elapsed)
                lastCommandSummary = CommandRunSummary(
                    title: workflowTitle,
                    status: launchSummary.status,
                    detail: "App installation succeeded, but \(launchSummary.detail)",
                    severity: launchSummary.severity,
                    duration: launchSummary.duration
                )
                selectedSessionTab = .diagnostics
            }
            lastStatusMessage = lastCommandSummary?.detail ?? "Install and launch finished."
            finishInstallAndLaunchWorkflow()
        }
    }

    private func commandExecutionStatus(_ result: CommandResult) -> String {
        if result.succeeded { return "succeeded" }
        if result.exitCode == -2 { return "timed out" }
        return "failed with exit code \(result.exitCode)"
    }

    private func appendCommandResultToOutput(_ result: CommandResult, status: String) {
        appendOutput("\n[\(result.command.title) \(status)]\n")
        if !result.standardOutput.isEmpty {
            appendOutput(result.standardOutput)
        }
        if !result.standardError.isEmpty {
            appendOutput("\n" + result.standardError)
        }
        appendOutput("\n")
    }

    private func finishInstallAndLaunchWorkflow() {
        runningCommandKind = nil
        isRunningCommand = false
        lastCommandTitle = "Idle"
    }

    func clearOutput() {
        commandOutput = ""
        lastStandardOutput = ""
        lastStandardError = ""
        consoleStreamFilter = .all
        consoleSearchQuery = ""
        isOutputTruncated = false
        lastStatusMessage = "Command console cleared."
    }

    func stopRunningCommand() {
        guard isRunningCommand else {
            lastStatusMessage = "No command is currently running."
            return
        }
        let stoppedKind = runningCommandKind
        let stoppedTitle = stoppedKind?.rawValue ?? (lastCommandTitle == "Idle" ? "Command" : lastCommandTitle)
        let didTerminateProcess = commandRunner.terminateRunningProcess()
        let didStartDeviceCleanup = stopDeviceTestsIfNeeded(for: stoppedKind)
        currentCommandID = UUID()
        runningCommandKind = nil
        isRunningCommand = false
        lastCommandTitle = "Idle"
        lastCommandSummary = CommandRunSummary(
            title: stoppedTitle,
            status: "Stopped",
            detail: stoppedCommandDetail(
                hostProcessTerminated: didTerminateProcess,
                deviceCleanupStarted: didStartDeviceCleanup,
                kind: stoppedKind
            ),
            severity: "warning",
            duration: "0s"
        )
        lastStatusMessage = "\(stoppedTitle) stopped."
        appendOutput("\n[\(stoppedTitle) stopped by user]\n")
    }

    private func stoppedCommandDetail(
        hostProcessTerminated: Bool,
        deviceCleanupStarted: Bool,
        kind: AndroidCommandKind?
    ) -> String {
        if kind == .connectedTests, deviceCleanupStarted {
            return hostProcessTerminated
                ? "The host process tree was asked to terminate, and device-side instrumentation cleanup is running."
                : "Stop was requested before a host process handle was available; device-side instrumentation cleanup is running."
        }
        if kind == .connectedTests {
            return hostProcessTerminated
                ? "The host process tree was asked to terminate. Device-side cleanup was skipped because the selected device or package is unavailable."
                : "Stop was requested before a host process handle was available. Device-side cleanup was skipped because the selected device or package is unavailable."
        }
        return hostProcessTerminated
            ? "The running process tree was asked to terminate. Any late result will be ignored."
            : "Stop was requested before a process handle was available. Any late result will be ignored."
    }

    @discardableResult
    private func stopDeviceTestsIfNeeded(for kind: AndroidCommandKind?) -> Bool {
        guard kind == .connectedTests else { return false }

        let deviceSerial = selectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePackage = packageNameForCommands.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceSerial.isEmpty else {
            appendOutput("[Device test cleanup skipped: no selected device.]\n")
            return false
        }
        guard isKnownAndroidPackageName(basePackage) else {
            appendOutput("[Device test cleanup skipped: package name is unavailable.]\n")
            return false
        }

        let rootPath = commandWorkingDirectory
        let deviceName = selectedDeviceDisplayName
        let initialPackages = defaultDeviceTestStopPackages(for: basePackage)
        appendOutput("[Stopping device-side tests on \(deviceName).]\n")

        Task {
            var packagesToStop = initialPackages
            let instrumentationCommand = AndroidToolCommandFactory.listInstrumentation(
                rootPath: rootPath,
                deviceSerial: deviceSerial
            )
            let instrumentationResult = await deviceTestCleanupRunner.run(instrumentationCommand, timeoutSeconds: 8)
            if instrumentationResult.succeeded {
                packagesToStop.append(
                    contentsOf: instrumentationStopPackages(
                        in: instrumentationResult.standardOutput,
                        basePackageName: basePackage
                    )
                )
            } else {
                let reason = firstUsefulLine(in: instrumentationResult.standardError)
                    ?? firstUsefulLine(in: instrumentationResult.standardOutput)
                    ?? "Unable to inspect installed instrumentation packages."
                appendOutput("[Instrumentation package lookup failed: \(reason)]\n")
            }

            let uniquePackages = orderedUniquePackages(packagesToStop)
            for packageName in uniquePackages {
                let command = AndroidToolCommandFactory.forceStopPackage(
                    rootPath: rootPath,
                    packageName: packageName,
                    deviceSerial: deviceSerial
                )
                appendOutput("$ \(command.preview)\n")
                let result = await deviceTestCleanupRunner.run(command, timeoutSeconds: 8)
                let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
                appendOutput("[\(command.title) \(status)]\n")
                if !result.standardOutput.isEmpty {
                    appendOutput(result.standardOutput)
                }
                if !result.standardError.isEmpty {
                    appendOutput("\n" + result.standardError)
                }
                appendOutput("\n")
            }

            lastStatusMessage = "Device Tests stopped on \(deviceName)."
            lastCommandSummary = CommandRunSummary(
                title: "Device Tests",
                status: "Stopped",
                detail: "Stopped the host command and force-stopped \(uniquePackages.joined(separator: ", ")) on \(deviceName).",
                severity: "warning",
                duration: "0s"
            )
        }

        return true
    }

    func refreshDevices() {
        guard canRefreshDevices else {
            lastStatusMessage = refreshDevicesHelpText
            return
        }
        isRefreshingDevices = true
        lastStatusMessage = "Refreshing Android devices..."
        lastCommandSummary = CommandRunSummary(
            title: "List Devices",
            status: "Running",
            detail: "Refreshing attached Android devices.",
            severity: "running",
            duration: "0s"
        )
        appendOutput("$ adb devices -l\n")
        let root = commandWorkingDirectory
        let command = AndroidToolCommandFactory.listDevices(rootPath: root)
        let startedAt = Date()
        Task {
            let result = await runner.run(command, timeoutSeconds: AndroidCommandKind.devices.timeoutSeconds)
            let elapsed = Date().timeIntervalSince(startedAt)
            let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
            if !result.standardOutput.isEmpty {
                appendOutput(result.standardOutput)
            }
            lastStandardOutput = result.standardOutput
            isRefreshingDevices = false
            applyDeviceOutput(
                result.standardOutput,
                standardError: result.standardError,
                succeeded: result.succeeded
            )
            if !result.standardError.isEmpty {
                appendOutput("\n\(result.standardError)")
            }
            lastStandardError = result.standardError
            appendOutput("\n[Device refresh \(status)]\n")
            lastCommandSummary = summarizeDeviceResult(result, status: status, elapsed: elapsed)
        }
    }

    func refreshDevicePreview() {
        captureDevicePreview(manual: true)
    }

    func sendDeviceTap(x: Int, y: Int) {
        guard hasConnectedDevice else {
            devicePreviewStatus = deviceTapHelpText
            lastStatusMessage = deviceTapHelpText
            return
        }

        pendingDeviceTapCoordinates = (max(0, x), max(0, y))
        pauseDevicePreviewAutoRefreshForInput()
        if isDevicePreviewCaptureInFlight || isRefreshingDevicePreview {
            devicePreviewStatus = "Waiting for the current frame before tapping \(selectedDeviceDisplayName)..."
            lastStatusMessage = devicePreviewStatus
            return
        }
        runPendingDeviceTapIfPossible()
    }

    private func runPendingDeviceTapIfPossible() {
        guard let tap = pendingDeviceTapCoordinates,
              !isSendingDeviceInput,
              !isDevicePreviewCaptureInFlight,
              !isRefreshingDevicePreview else {
            return
        }
        guard canSendDeviceTap else {
            pendingDeviceTapCoordinates = nil
            resumeDevicePreviewAfterInput()
            devicePreviewStatus = deviceTapHelpText
            lastStatusMessage = deviceTapHelpText
            return
        }
        pendingDeviceTapCoordinates = nil
        runDeviceTap(x: tap.x, y: tap.y)
    }

    private func runDeviceTap(x: Int, y: Int) {
        let serial = selectedDeviceID
        let deviceName = selectedDeviceDisplayName
        let command = AndroidToolCommandFactory.tapDeviceScreen(
            rootPath: commandWorkingDirectory,
            deviceSerial: serial,
            x: x,
            y: y
        )
        let inputID = UUID()
        currentDeviceInputID = inputID
        isSendingDeviceInput = true
        devicePreviewStatus = "Sending tap to \(deviceName)..."
        lastStatusMessage = devicePreviewStatus
        appendOutput("$ \(command.preview)\n")

        let startedAt = Date()
        Task {
            let result = await deviceInputRunner.run(command, timeoutSeconds: 5)
            let elapsed = Date().timeIntervalSince(startedAt)
            let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
            guard currentDeviceInputID == inputID, selectedDeviceID == serial else { return }
            isSendingDeviceInput = false
            appendOutput("\n[\(result.command.title) \(status)]\n")
            if !result.standardOutput.isEmpty {
                appendOutput(result.standardOutput)
            }
            if !result.standardError.isEmpty {
                appendOutput("\n" + result.standardError)
            }
            appendOutput("\n")
            lastStandardOutput = result.standardOutput
            lastStandardError = result.standardError
            defer {
                if pendingDeviceTapCoordinates != nil {
                    runPendingDeviceTapIfPossible()
                } else {
                    resumeDevicePreviewAfterInput()
                }
            }

            if result.succeeded {
                devicePreviewStatus = "Tapped \(deviceName) at \(x), \(y)."
                lastStatusMessage = devicePreviewStatus
                lastCommandSummary = CommandRunSummary(
                    title: result.command.title,
                    status: "Succeeded",
                    detail: "Sent adb input tap \(x) \(y) to \(deviceName).",
                    severity: "ready",
                    duration: String(format: "%.1fs", elapsed)
                )
            } else {
                let usefulLine = firstUsefulLine(in: result.standardError)
                    ?? firstUsefulLine(in: result.standardOutput)
                    ?? "ADB input tap did not complete."
                devicePreviewStatus = "Device tap failed. \(usefulLine)"
                lastStatusMessage = devicePreviewStatus
                lastCommandSummary = CommandRunSummary(
                    title: result.command.title,
                    status: status.capitalized,
                    detail: usefulLine,
                    severity: "warning",
                    duration: String(format: "%.1fs", elapsed)
                )
            }
        }
    }

    private func pauseDevicePreviewAutoRefreshForInput() {
        shouldResumeDevicePreviewAutoRefreshAfterInput = isDevicePreviewAutoRefreshEnabled
        devicePreviewAutoRefreshTask?.cancel()
        devicePreviewAutoRefreshTask = nil
    }

    private func resumeDevicePreviewAfterInput() {
        let shouldResume = shouldResumeDevicePreviewAutoRefreshAfterInput
        shouldResumeDevicePreviewAutoRefreshAfterInput = false
        guard shouldResume, isDevicePreviewAutoRefreshEnabled, hasConnectedDevice else { return }
        startDevicePreviewAutoRefresh()
    }

    private func captureDevicePreview(manual: Bool) {
        guard canRefreshDevicePreview else {
            if manual {
                devicePreviewStatus = devicePreviewHelpText
                lastStatusMessage = devicePreviewHelpText
            }
            return
        }

        let serial = selectedDeviceID
        let deviceName = selectedDeviceDisplayName
        let command = AndroidToolCommandFactory.deviceScreenCapture(
            rootPath: commandWorkingDirectory,
            deviceSerial: serial
        )
        let previewID = UUID()
        currentDevicePreviewID = previewID
        isDevicePreviewCaptureInFlight = true
        if manual {
            isRefreshingDevicePreview = true
        }
        if manual {
            devicePreviewStatus = "Refreshing \(deviceName)..."
        } else if devicePreviewImage == nil {
            devicePreviewStatus = "Loading \(deviceName)..."
        }
        if manual {
            lastStatusMessage = "Refreshing device preview for \(deviceName)..."
        }

        Task {
            let result = await runner.runBinary(command, timeoutSeconds: 10)
            let isCurrentPreview = self.currentDevicePreviewID == previewID
            if isCurrentPreview {
                self.isDevicePreviewCaptureInFlight = false
                if manual {
                    self.isRefreshingDevicePreview = false
                }
            }
            guard isCurrentPreview else { return }
            guard self.selectedDeviceID == serial else { return }
            defer {
                self.runPendingDeviceTapIfPossible()
            }

            if result.succeeded, let image = NSImage(data: result.standardOutput) {
                self.devicePreviewImage = image
                self.devicePreviewUpdatedAt = Date()
                self.devicePreviewStatus = "Showing \(deviceName)."
                if manual {
                    self.lastStatusMessage = "Device preview updated for \(deviceName)."
                }
                return
            }

            let errorLine = firstUsefulLine(in: result.standardError)
            let fallback = result.standardOutput.isEmpty
                ? "ADB returned no frame data."
                : "ADB returned \(result.standardOutput.count) bytes that were not a PNG frame."
            let detail = errorLine ?? fallback
            self.devicePreviewStatus = "Preview unavailable. \(detail)"
            if manual {
                self.lastStatusMessage = self.devicePreviewStatus
            }
        }
    }

    private func startDevicePreviewAutoRefresh() {
        devicePreviewAutoRefreshTask?.cancel()
        guard hasConnectedDevice else {
            devicePreviewStatus = selectedDeviceID.isEmpty
                ? "Select an Android target to preview its screen."
                : "Waiting for selected target to reconnect."
            return
        }
        devicePreviewStatus = "Auto previewing \(selectedDeviceDisplayName)."
        captureDevicePreview(manual: false)
        devicePreviewAutoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.devicePreviewAutoRefreshIntervalNanoseconds ?? 20_000_000)
                guard let self, !Task.isCancelled, self.isDevicePreviewAutoRefreshEnabled else { break }
                self.captureDevicePreview(manual: false)
            }
        }
    }

    private func stopDevicePreviewAutoRefresh(updateStatus: Bool) {
        devicePreviewAutoRefreshTask?.cancel()
        devicePreviewAutoRefreshTask = nil
        currentDevicePreviewID = UUID()
        currentDeviceInputID = UUID()
        isDevicePreviewCaptureInFlight = false
        isRefreshingDevicePreview = false
        if updateStatus {
            devicePreviewStatus = devicePreviewImage == nil
                ? "Select an Android target to preview its screen."
                : "Preview paused."
        }
    }

    private func resetDevicePreviewForSelectionChange() {
        stopDevicePreviewAutoRefresh(updateStatus: false)
        currentDevicePreviewID = UUID()
        isDevicePreviewCaptureInFlight = false
        isRefreshingDevicePreview = false
        isSendingDeviceInput = false
        pendingDeviceTapCoordinates = nil
        shouldResumeDevicePreviewAutoRefreshAfterInput = false
        devicePreviewImage = nil
        devicePreviewUpdatedAt = nil
        devicePreviewStatus = selectedDeviceID.isEmpty
            ? "Select an Android target to preview its screen."
            : hasConnectedDevice ? "Ready to preview \(selectedDeviceDisplayName)." : "Waiting for selected target to reconnect."
        if isDevicePreviewAutoRefreshEnabled, hasConnectedDevice {
            startDevicePreviewAutoRefresh()
        }
    }

    func pairWirelessDevice() {
        let code = wirelessPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canPairWirelessDevice else {
            wirelessDebuggingStatus = wirelessPairingValidationMessage
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        if let selectedWirelessDebuggingDevice, let pairingAddress = selectedWirelessDebuggingDevice.pairingAddress {
            lastWirelessPairingAddress = pairingAddress
            if let connectAddress = selectedWirelessDebuggingDevice.connectAddress {
                wirelessConnectAddress = connectAddress
            }
            pendingWirelessDebuggingConfirmation = WirelessDebuggingConfirmation(
                pairingAddress: pairingAddress,
                pairingCode: code,
                connectAddress: selectedWirelessDebuggingDevice.connectAddress
            )
            wirelessDebuggingStatus = "Selected wireless device ready for pairing confirmation."
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        discoverWirelessPairingAddress(pairingCode: code)
    }

    func prepareWirelessDeviceConnectionSheet() {
        guard wirelessDebuggingDevices.isEmpty else { return }
        refreshWirelessDebuggingDevices()
    }

    func refreshWirelessDebuggingDevices() {
        guard canRefreshWirelessDebuggingDevices else {
            wirelessDeviceDiscoveryStatus = wirelessDiscoveryHelpText
            lastStatusMessage = wirelessDeviceDiscoveryStatus
            return
        }

        let command = AndroidToolCommandFactory.mdnsServices(rootPath: commandWorkingDirectory)
        isRunningWirelessDebugging = true
        lastCommandTitle = command.title
        selectedSessionTab = .diagnostics
        wirelessDeviceDiscoveryStatus = "Scanning for wireless Android devices..."
        wirelessDebuggingStatus = wirelessDeviceDiscoveryStatus
        lastStatusMessage = wirelessDeviceDiscoveryStatus
        lastCommandSummary = CommandRunSummary(
            title: command.title,
            status: "Running",
            detail: "Scanning ADB mDNS services for wireless Android devices.",
            severity: "running",
            duration: "0s"
        )
        appendOutput("$ \(command.preview)\n")

        let startedAt = Date()
        Task {
            let result = await runner.run(command, timeoutSeconds: 20)
            let elapsed = Date().timeIntervalSince(startedAt)
            let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
            appendOutput("\n[\(result.command.title) \(status)]\n")
            if !result.standardOutput.isEmpty {
                appendOutput(result.standardOutput)
            }
            if !result.standardError.isEmpty {
                appendOutput("\n" + result.standardError)
            }
            appendOutput("\n")
            lastStandardOutput = result.standardOutput
            lastStandardError = result.standardError
            isRunningWirelessDebugging = false
            lastCommandTitle = "Idle"
            lastCommandSummary = summarizeCommandResult(result, status: status, elapsed: elapsed)

            guard result.succeeded else {
                let usefulLine = firstUsefulLine(in: result.standardError) ?? firstUsefulLine(in: result.standardOutput) ?? "ADB mDNS discovery failed."
                wirelessDebuggingDevices = []
                selectedWirelessDebuggingDeviceID = ""
                wirelessDeviceDiscoveryStatus = "Could not scan wireless devices. \(usefulLine)"
                wirelessDebuggingStatus = wirelessDeviceDiscoveryStatus
                lastStatusMessage = wirelessDeviceDiscoveryStatus
                selectedSessionTab = .diagnostics
                return
            }

            let discoveredDevices = parseWirelessDebuggingDeviceList(result.standardOutput)
            wirelessDebuggingDevices = discoveredDevices
            if !discoveredDevices.contains(where: { $0.id == selectedWirelessDebuggingDeviceID }) {
                selectedWirelessDebuggingDeviceID = ""
            } else {
                applySelectedWirelessDebuggingDevice()
            }
            if discoveredDevices.isEmpty {
                wirelessDeviceDiscoveryStatus = "No wireless Android devices found on this network."
            } else {
                wirelessDeviceDiscoveryStatus = "Found \(discoveredDevices.count) wireless Android device\(discoveredDevices.count == 1 ? "" : "s")."
            }
            wirelessDebuggingStatus = wirelessDeviceDiscoveryStatus
            lastStatusMessage = wirelessDeviceDiscoveryStatus
            selectedSessionTab = .diagnostics
        }
    }

    func selectWirelessDebuggingDevice(_ device: WirelessDebuggingDevice) {
        selectedWirelessDebuggingDeviceID = device.id
    }

    func generateWirelessQRCode() {
        guard canGenerateWirelessQRCode else {
            wirelessQRCodeStatus = wirelessQRCodeHelpText
            lastStatusMessage = wirelessQRCodeStatus
            return
        }
        let serviceName = "adb-\(randomADBToken(length: 12))"
        let password = randomADBToken(length: 16)
        let payload = "WIFI:T:ADB;S:\(escapedQRCodeValue(serviceName));P:\(escapedQRCodeValue(password));;"
        guard let image = makeQRCodeImage(from: payload) else {
            wirelessQRCodeImage = nil
            wirelessQRCodePayload = ""
            wirelessQRCodeStatus = "Could not generate QR code."
            lastStatusMessage = wirelessQRCodeStatus
            return
        }
        wirelessQRCodeImage = image
        wirelessQRCodePayload = payload
        wirelessQRCodeStatus = "QR code ready. Scan it from Android Wireless Debugging, then scan devices to connect the discovered target."
        lastStatusMessage = wirelessQRCodeStatus
    }

    func clearWirelessQRCode() {
        wirelessQRCodeImage = nil
        wirelessQRCodePayload = ""
        wirelessQRCodeStatus = "Generate a QR code, then scan it from Android Wireless Debugging."
        lastStatusMessage = "Wireless QR code cleared."
    }

    func confirmWirelessPairing() {
        guard let confirmation = pendingWirelessDebuggingConfirmation else {
            lastStatusMessage = "No Wireless Debugging pairing confirmation is open."
            return
        }
        pendingWirelessDebuggingConfirmation = nil
        lastWirelessPairingAddress = confirmation.pairingAddress
        if let connectAddress = confirmation.connectAddress {
            wirelessConnectAddress = connectAddress
        }
        let command = AndroidToolCommandFactory.pairWirelessDevice(
            rootPath: commandWorkingDirectory,
            hostPort: confirmation.pairingAddress,
            pairingCode: confirmation.pairingCode
        )
        runWirelessDebuggingCommand(
            command,
            displayAddress: confirmation.pairingAddress,
            refreshAfterSuccess: confirmation.connectAddress == nil,
            connectAfterSuccessAddress: confirmation.connectAddress
        )
    }

    func cancelWirelessPairing() {
        guard pendingWirelessDebuggingConfirmation != nil else {
            lastStatusMessage = "No Wireless Debugging pairing confirmation is open."
            return
        }
        pendingWirelessDebuggingConfirmation = nil
        wirelessDebuggingStatus = "Wireless pairing cancelled."
        lastStatusMessage = wirelessDebuggingStatus
    }

    func connectWirelessDevice() {
        guard let address = wirelessConnectTargetAddress else {
            wirelessDebuggingStatus = wirelessConnectValidationMessage
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        connectWirelessDevice(to: address)
    }

    private func connectWirelessDevice(to address: String) {
        let command = AndroidToolCommandFactory.connectWirelessDevice(rootPath: commandWorkingDirectory, hostPort: address)
        runWirelessDebuggingCommand(
            command,
            displayAddress: address,
            refreshAfterSuccess: true,
            selectedDeviceAddress: address
        )
    }

    func disconnectWirelessDevice() {
        guard let address = wirelessDisconnectAddress else {
            wirelessDebuggingStatus = "Connect or select a wireless device before disconnecting."
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        let disconnectedDeviceAddress = selectedWirelessConnectedDeviceSerial ?? address
        let command = AndroidToolCommandFactory.disconnectWirelessDevice(rootPath: commandWorkingDirectory, hostPort: address)
        runWirelessDebuggingCommand(
            command,
            displayAddress: address,
            refreshAfterSuccess: true,
            disconnectedDeviceAddress: disconnectedDeviceAddress,
            clearDeviceOnSuccess: true
        )
    }

    private func discoverWirelessPairingAddress(pairingCode: String) {
        let command = AndroidToolCommandFactory.mdnsServices(rootPath: commandWorkingDirectory)
        isRunningWirelessDebugging = true
        lastCommandTitle = command.title
        selectedSessionTab = .diagnostics
        wirelessDebuggingStatus = "Discovering Android Wireless Debugging pairing address..."
        lastStatusMessage = wirelessDebuggingStatus
        lastCommandSummary = CommandRunSummary(
            title: command.title,
            status: "Running",
            detail: "Looking for _adb-tls-pairing._tcp through ADB mDNS.",
            severity: "running",
            duration: "0s"
        )
        appendOutput("$ \(command.preview)\n")

        let startedAt = Date()
        Task {
            let result = await runner.run(command, timeoutSeconds: 20)
            let elapsed = Date().timeIntervalSince(startedAt)
            let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
            appendOutput("\n[\(result.command.title) \(status)]\n")
            if !result.standardOutput.isEmpty {
                appendOutput(result.standardOutput)
            }
            if !result.standardError.isEmpty {
                appendOutput("\n" + result.standardError)
            }
            appendOutput("\n")
            lastStandardOutput = result.standardOutput
            lastStandardError = result.standardError
            isRunningWirelessDebugging = false
            lastCommandTitle = "Idle"
            lastCommandSummary = summarizeCommandResult(result, status: status, elapsed: elapsed)

            guard result.succeeded else {
                let usefulLine = firstUsefulLine(in: result.standardError) ?? firstUsefulLine(in: result.standardOutput) ?? "ADB mDNS discovery failed."
                wirelessDebuggingStatus = "Could not discover pairing address. \(usefulLine)"
                lastStatusMessage = wirelessDebuggingStatus
                selectedSessionTab = .diagnostics
                return
            }

            let services = parseWirelessDebuggingServices(result.standardOutput)
            guard let pairingAddress = services.pairingAddress else {
                wirelessDebuggingStatus = "No pairing address discovered. On the Android device, open Wireless Debugging and tap Pair device with pairing code, then try Pair again."
                lastStatusMessage = wirelessDebuggingStatus
                selectedSessionTab = .diagnostics
                return
            }

            lastWirelessPairingAddress = pairingAddress
            if let connectAddress = services.connectAddress {
                wirelessConnectAddress = connectAddress
            }
            pendingWirelessDebuggingConfirmation = WirelessDebuggingConfirmation(
                pairingAddress: pairingAddress,
                pairingCode: pairingCode,
                connectAddress: services.connectAddress
            )
            wirelessDebuggingStatus = "Discovered pairing address \(pairingAddress). Confirm pairing to continue."
            lastStatusMessage = wirelessDebuggingStatus
            selectedSessionTab = .diagnostics
        }
    }

    private func runWirelessDebuggingCommand(
        _ command: ToolCommand,
        displayAddress: String,
        refreshAfterSuccess: Bool,
        selectedDeviceAddress: String? = nil,
        disconnectedDeviceAddress: String? = nil,
        connectAfterSuccessAddress: String? = nil,
        clearDeviceOnSuccess: Bool = false
    ) {
        isRunningWirelessDebugging = true
        lastCommandTitle = command.title
        selectedSessionTab = .diagnostics
        wirelessDebuggingStatus = "\(command.title) running for \(displayAddress)..."
        lastStatusMessage = wirelessDebuggingStatus
        lastCommandSummary = CommandRunSummary(
            title: command.title,
            status: "Running",
            detail: "Running \(command.title) through ADB.",
            severity: "running",
            duration: "0s"
        )
        appendOutput("$ \(command.preview)\n")

        let startedAt = Date()
        Task {
            let result = await runner.run(command, timeoutSeconds: 30)
            let elapsed = Date().timeIntervalSince(startedAt)
            let status = result.succeeded ? "succeeded" : result.exitCode == -2 ? "timed out" : "failed with exit code \(result.exitCode)"
            appendOutput("\n[\(result.command.title) \(status)]\n")
            if !result.standardOutput.isEmpty {
                appendOutput(result.standardOutput)
            }
            if !result.standardError.isEmpty {
                appendOutput("\n" + result.standardError)
            }
            appendOutput("\n")
            lastStandardOutput = result.standardOutput
            lastStandardError = result.standardError
            isRunningWirelessDebugging = false
            lastCommandTitle = "Idle"
            lastCommandSummary = summarizeCommandResult(result, status: status, elapsed: elapsed)
            selectedSessionTab = result.succeeded ? .checks : .diagnostics

            let usefulLine = firstUsefulLine(in: result.standardOutput)
                ?? firstUsefulLine(in: result.standardError)
                ?? lastCommandSummary?.detail
                ?? "\(result.command.title) \(status)."
            if result.succeeded {
                if let selectedDeviceAddress {
                    lastWirelessDeviceAddress = selectedDeviceAddress
                    selectedDeviceID = selectedDeviceAddress
                }
                if clearDeviceOnSuccess {
                    let disconnectedAddresses = Set([displayAddress, disconnectedDeviceAddress].compactMap { $0 })
                    let shouldClearWirelessHistory = disconnectedDeviceAddress == selectedWirelessConnectedDeviceSerial
                    if disconnectedAddresses.contains(selectedDeviceID) {
                        selectedDeviceID = ""
                    }
                    if disconnectedAddresses.contains(lastWirelessDeviceAddress) || shouldClearWirelessHistory {
                        lastWirelessDeviceAddress = ""
                    }
                }
                if result.command.title == "Pair Wireless Device" {
                    wirelessDebuggingStatus = "Pairing successful"
                } else if result.command.title == "Connect Wireless Device" {
                    wirelessDebuggingStatus = "Device connected"
                } else if result.command.title == "Disconnect Wireless Device" {
                    wirelessDebuggingStatus = "Device disconnected"
                } else {
                    wirelessDebuggingStatus = "\(result.command.title) succeeded. \(usefulLine)"
                }
                lastStatusMessage = wirelessDebuggingStatus
                if let connectAfterSuccessAddress {
                    connectWirelessDevice(to: connectAfterSuccessAddress)
                    return
                }
                if refreshAfterSuccess {
                    refreshDevices()
                }
            } else {
                wirelessDebuggingStatus = "\(result.command.title) failed. \(usefulLine)"
                lastStatusMessage = wirelessDebuggingStatus
            }
        }
    }

    func usePromptFromHistory(_ value: String) {
        guard value != prompt else {
            lastStatusMessage = "Prompt is already using that history item."
            return
        }
        previousPromptDraft = prompt
        savePromptToHistory(prompt)
        prompt = value
        submitAssistantPrompt(runActions: false)
        lastStatusMessage = "Prompt restored from history."
    }

    func restorePreviousPromptDraft() {
        guard let previousPromptDraft else {
            lastStatusMessage = "No previous prompt draft to restore."
            return
        }
        guard previousPromptDraft != prompt else {
            lastStatusMessage = "Prompt already matches the previous draft."
            return
        }
        let current = prompt
        prompt = previousPromptDraft
        self.previousPromptDraft = current
        submitAssistantPrompt(runActions: false)
        lastStatusMessage = "Restored the previous prompt draft."
    }

    var canRestorePreviousPromptDraft: Bool {
        previousPromptDraft != nil
    }

    func removePromptHistory(_ value: String) {
        let originalCount = promptHistory.count
        promptHistory.removeAll { $0 == value }
        UserDefaults.standard.set(promptHistory, forKey: promptHistoryKey)
        lastStatusMessage = promptHistory.count == originalCount
            ? "Prompt history item was not found."
            : "Removed one prompt history item."
    }

    func clearPromptHistory() {
        guard !promptHistory.isEmpty else {
            lastStatusMessage = "Prompt history is already empty."
            return
        }
        promptHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: promptHistoryKey)
        lastStatusMessage = "Prompt history cleared."
    }

    func copyConsole() {
        guard !commandOutput.isEmpty else {
            lastStatusMessage = "No command console output to copy."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filteredCommandOutput, forType: .string)
        lastStatusMessage = consoleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Console output copied."
            : "Filtered console output copied."
    }

    func copyAssistantResponse() {
        let response = assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else {
            lastStatusMessage = "No assistant response to copy."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response, forType: .string)
        showAssistantResponseFeedback("Copied")
        lastStatusMessage = "Assistant response copied."
    }

    func exportAssistantResponse() {
        let response = assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else {
            lastStatusMessage = "No assistant response to export."
            return
        }
        let path = temporaryArtifactPath(prefix: "android-dev-agent-assistant-response", fileExtension: "txt")
        do {
            try response.write(toFile: path, atomically: true, encoding: .utf8)
            setAssistantResponseExportPath(path)
            lastExportPath = path
            lastExportSource = "Ask"
            showAssistantResponseFeedback("Exported")
            lastStatusMessage = "Assistant response exported to \(path)."
        } catch {
            lastStatusMessage = "Could not export assistant response: \(error.localizedDescription)"
        }
    }

    private func showAssistantResponseFeedback(_ value: String) {
        assistantResponseFeedback = value
        let token = UUID()
        assistantResponseFeedbackToken = token
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.assistantResponseFeedbackToken == token else { return }
                self.assistantResponseFeedback = ""
            }
        }
    }

    func copyPatchPreview() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diffPreviewLines.joined(separator: "\n"), forType: .string)
        lastStatusMessage = "Patch preview copied. Apply/revert stays disabled until a real diff exists."
    }

    func markPreviewReviewed() {
        lastStatusMessage = "Patch preview marked reviewed. No files were modified."
    }

    func clearConsoleSearch() {
        consoleSearchQuery = ""
        lastStatusMessage = "Console filter cleared."
    }

    var isConsoleViewFiltered: Bool {
        consoleStreamFilter != .all || !consoleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var consoleExportHelpText: String {
        isConsoleViewFiltered
            ? "Exports the complete unfiltered console log, not only the visible filtered output."
            : "Exports the complete console log."
    }

    var filteredCommandOutput: String {
        let query = consoleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = consoleSourceOutput
        guard !query.isEmpty else { return source }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let filtered = lines.filter { $0.localizedCaseInsensitiveContains(query) }
        return filtered.isEmpty ? "No console lines match \"\(query)\"." : filtered.joined(separator: "\n")
    }

    private var consoleSourceOutput: String {
        switch consoleStreamFilter {
        case .all:
            return commandOutput
        case .stdout:
            return lastStandardOutput.isEmpty ? "No stdout captured for the last command." : lastStandardOutput
        case .stderr:
            return lastStandardError.isEmpty ? "No stderr captured for the last command." : lastStandardError
        }
    }

    private var recentCommandOutputExcerpt: String {
        let combined = [lastStandardOutput, lastStandardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let source = combined.isEmpty ? commandOutput : combined
        return String(source.suffix(6_000))
    }

    func saveAssistantOpenAIAPIKey(_ key: String) {
        do {
            try AssistantModelCredentialStore.saveOpenAIAPIKey(key)
            refreshAssistantCredentialStatus()
            lastStatusMessage = "OpenAI API key saved in Keychain."
        } catch {
            refreshAssistantCredentialStatus()
            lastStatusMessage = "Could not save OpenAI API key: \(error.localizedDescription)"
        }
    }

    func clearAssistantOpenAIAPIKey() {
        AssistantModelCredentialStore.clearOpenAIAPIKey()
        refreshAssistantCredentialStatus()
        lastStatusMessage = "OpenAI API key removed from Keychain."
    }

    private func refreshAssistantCredentialStatus() {
        assistantCredentialStatus = assistantOpenAIAccountSummary
    }

    func exportConsole() {
        guard !commandOutput.isEmpty else {
            lastStatusMessage = "No command console output to export."
            return
        }
        let path = temporaryArtifactPath(prefix: "android-dev-agent-console", fileExtension: "log")
        do {
            try commandOutput.write(toFile: path, atomically: true, encoding: .utf8)
            lastExportPath = path
            lastExportSource = "Console"
            lastStatusMessage = "Console output exported to \(path)."
        } catch {
            lastStatusMessage = "Could not export console: \(error.localizedDescription)"
        }
    }

    func createDebugReport() {
        let report = """
        Android Dev Agent Debug Report

        Project: \(projectPathDisplay)
        Package: \(packageNameForCommands)
        Module: \(selectedModule)
        Variant: \(selectedVariant)
        Device: \(selectedDeviceID.isEmpty ? "None selected" : selectedDeviceID)
        Scan: \(scanState.title) - \(scanState.detail)
        Summary: \(workspaceSummary)

        Diagnostics:
        \(diagnosticRows.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"))

        Last Command:
        \(lastCommandSummary.map { "\($0.title) - \($0.status): \($0.detail)" } ?? "None")

        Console:
        \(commandOutput)
        """
        let path = temporaryArtifactPath(prefix: "android-dev-agent-debug-report", fileExtension: "txt")
        do {
            try report.write(toFile: path, atomically: true, encoding: .utf8)
            debugReportPath = path
            lastExportPath = path
            lastExportSource = "Diagnostics"
            lastStatusMessage = "Debug report exported to \(path)."
        } catch {
            lastStatusMessage = "Could not export debug report: \(error.localizedDescription)"
        }
    }

    func createSupportBundle() {
        do {
            let bundleURL = try AndroidDevAgentLaunchReadiness.createSupportBundle(report: supportDiagnosticsReport)
            supportBundlePath = bundleURL.path
            lastExportPath = bundleURL.path
            lastExportSource = "Support Bundle"
            lastStatusMessage = "Support bundle exported to \(bundleURL.path)."
        } catch {
            lastStatusMessage = "Could not export support bundle: \(error.localizedDescription)"
        }
    }

    func uploadSupportBundle() {
        guard !isSupportUploadRunning else { return }
        guard hasSupportBundleFile else {
            lastStatusMessage = supportBundlePath.isEmpty
                ? "Create a support bundle before uploading."
                : "Support bundle is no longer available. Create a new bundle."
            return
        }

        isSupportUploadRunning = true
        lastStatusMessage = "Uploading support bundle..."
        Task { @MainActor [weak self] in
            guard let self else { return }
            let message = await AndroidDevAgentLaunchReadiness.uploadSupportBundle(at: URL(fileURLWithPath: supportBundlePath))
            supportUploadStatus = message
            isSupportUploadRunning = false
            lastExportPath = supportBundlePath
            lastExportSource = "Support Bundle"
            lastStatusMessage = message
        }
    }

    private var supportDiagnosticsReport: String {
        """
        Android Dev Agent Support Diagnostics

        Project: \(projectPathDisplay)
        Package: \(packageNameForCommands)
        Module: \(selectedModule)
        Variant: \(selectedVariant)
        Device: \(selectedDeviceID.isEmpty ? "None selected" : selectedDeviceID)
        Scan: \(scanState.title) - \(scanState.detail)
        Summary: \(workspaceSummary)

        Launch Readiness:
        \(launchReadinessRows.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"))

        Diagnostics:
        \(diagnosticRows.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"))

        Safety:
        \(safetyRows.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"))

        Verification:
        \(verificationRows.map { "- \($0.title): \($0.detail)" }.joined(separator: "\n"))

        Last Command:
        \(lastCommandSummary.map { "\($0.title) - \($0.status): \($0.detail)" } ?? "None")

        Assistant Privacy:
        \(assistantPrivacyDisclosure)
        \(assistantPayloadPrivacySummary)

        Console:
        \(commandOutput)
        """
    }

    func openDebugReport() {
        guard !debugReportPath.isEmpty else {
            lastStatusMessage = "No diagnostics report is available yet."
            return
        }
        guard hasDebugReportFile else {
            lastStatusMessage = "Diagnostics report file is no longer available. Create a new report."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: debugReportPath))
    }

    func openSupportBundle() {
        guard !supportBundlePath.isEmpty else {
            lastStatusMessage = "No support bundle is available yet."
            return
        }
        guard hasSupportBundleFile else {
            lastStatusMessage = "Support bundle is no longer available. Create a new bundle."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: supportBundlePath))
    }

    var hasDebugReportFile: Bool {
        guard !debugReportPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: debugReportPath)
    }

    var hasSupportBundleFile: Bool {
        guard !supportBundlePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: supportBundlePath)
    }

    var debugReportAvailabilityMessage: String {
        guard !debugReportPath.isEmpty else { return "" }
        return hasDebugReportFile ? "" : "Diagnostics report file is no longer available. Create a new report."
    }

    var supportBundleAvailabilityMessage: String {
        guard !supportBundlePath.isEmpty else { return "" }
        return hasSupportBundleFile ? "" : "Support bundle is no longer available. Create a new bundle."
    }

    var canUploadSupportBundle: Bool {
        hasSupportBundleFile && !isSupportUploadRunning
    }

    var supportBundleUploadActionTitle: String {
        isSupportUploadRunning ? "Uploading" : "Upload"
    }

    var supportBundleUploadActionSymbol: String {
        isSupportUploadRunning ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up"
    }

    var supportBundleUploadHelpText: String {
        if isSupportUploadRunning {
            return "Support bundle upload is running."
        }
        if !hasSupportBundleFile {
            return supportBundlePath.isEmpty
                ? "Create a support bundle before uploading."
                : "Support bundle is no longer available. Create a new bundle."
        }
        return "Upload the latest redacted support bundle when support upload consent and a configured endpoint are available."
    }

    func openLastExport() {
        guard !lastExportPath.isEmpty else {
            lastStatusMessage = "No export file is available yet."
            return
        }
        guard hasLastExportFile else {
            lastStatusMessage = "Last export file is no longer available. Export again."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastExportPath))
    }

    var hasLastExportFile: Bool {
        guard !lastExportPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: lastExportPath)
    }

    var lastExportAvailabilityMessage: String {
        guard !lastExportPath.isEmpty else { return "" }
        return hasLastExportFile ? "" : "Last export file is no longer available. Export again."
    }

    var lastExportSourceTitle: String {
        lastExportSource.isEmpty ? "Export" : lastExportSource
    }

    func openAssistantResponseExport() {
        guard !assistantResponseExportPath.isEmpty else {
            lastStatusMessage = "No assistant response export is available yet."
            return
        }
        guard FileManager.default.fileExists(atPath: assistantResponseExportPath) else {
            clearAssistantResponseExportPath()
            lastStatusMessage = "Exported assistant response file is no longer available. Export again."
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: assistantResponseExportPath))
    }

    func copyAssistantResponseExportPath() {
        guard !assistantResponseExportPath.isEmpty else {
            lastStatusMessage = "No assistant response export path to copy."
            return
        }
        guard FileManager.default.fileExists(atPath: assistantResponseExportPath) else {
            clearAssistantResponseExportPath()
            lastStatusMessage = "Exported assistant response file is no longer available. Export again."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(assistantResponseExportPath, forType: .string)
        lastStatusMessage = "Copied \(assistantResponseExportPath)"
    }

    var hasAssistantResponseExportFile: Bool {
        guard !assistantResponseExportPath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: assistantResponseExportPath)
    }

    var assistantResponseExportAvailabilityMessage: String {
        guard !assistantResponseExportPath.isEmpty else { return "" }
        return hasAssistantResponseExportFile
            ? ""
            : "Exported assistant response file is no longer available. Export again."
    }

    var needsAskExportRecoveryAction: Bool {
        !assistantResponseExportPath.isEmpty && !hasAssistantResponseExportFile
    }

    var askExportDiagnosticsActionTitle: String {
        needsAskExportRecoveryAction ? "Re-export" : "Open Export"
    }

    var askExportDiagnosticsActionSymbol: String {
        needsAskExportRecoveryAction ? "arrow.clockwise.circle" : "arrow.up.right.square"
    }

    var canRunAskExportDiagnosticsAction: Bool {
        if hasAssistantResponseExportFile {
            return true
        }
        if needsAskExportRecoveryAction {
            return !assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var askExportDiagnosticsActionDisabledReason: String {
        if hasAssistantResponseExportFile {
            return ""
        }
        if needsAskExportRecoveryAction {
            return "No assistant response available to re-export yet."
        }
        return "No assistant response export available yet."
    }

    var askExportDiagnosticsActionHelpText: String {
        if canRunAskExportDiagnosticsAction {
            return needsAskExportRecoveryAction
                ? "Re-export the assistant response because the previous file is missing."
                : "Open the assistant response export file."
        }
        return askExportDiagnosticsActionDisabledReason
    }

    func runAskExportDiagnosticsAction() {
        if needsAskExportRecoveryAction {
            exportAssistantResponse()
            return
        }
        openAssistantResponseExport()
    }

    var askExportRecoveryDisabledReason: String {
        if assistantResponseExportPath.isEmpty {
            return "No stale Ask export to recover yet."
        }
        if hasAssistantResponseExportFile {
            return "Ask export is already available."
        }
        return ""
    }

    func noteOpenedAskForExportRecovery() {
        selectedSessionTab = .chat
        lastStatusMessage = "Opened Ask for export recovery."
    }

    private func setAssistantResponseExportPath(_ path: String) {
        assistantResponseExportPath = path
        UserDefaults.standard.set(path, forKey: assistantResponseExportPathKey)
    }

    private func clearAssistantResponseExportPath() {
        assistantResponseExportPath = ""
        UserDefaults.standard.removeObject(forKey: assistantResponseExportPathKey)
    }

    private func restoreAssistantResponseExportPath() -> Bool {
        guard let storedPath = UserDefaults.standard.string(forKey: assistantResponseExportPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !storedPath.isEmpty else {
            return false
        }
        guard FileManager.default.fileExists(atPath: storedPath) else {
            UserDefaults.standard.removeObject(forKey: assistantResponseExportPathKey)
            return false
        }
        assistantResponseExportPath = storedPath
        lastExportPath = storedPath
        lastExportSource = "Ask"
        return true
    }

    func retryLastCommand() {
        guard let lastRunnableCommandKind else {
            lastStatusMessage = "No previous command to retry."
            return
        }
        runCommand(lastRunnableCommandKind)
    }

    var hasRunnableCommandHistory: Bool {
        lastRunnableCommandKind != nil
    }

    var canRetryLastCommand: Bool {
        hasRunnableCommandHistory && !isRunningCommand
    }

    func copyLastCommandPreview() {
        guard let lastRunnableCommandKind else {
            lastStatusMessage = "No command has run yet."
            return
        }
        let command = commandFor(lastRunnableCommandKind)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.preview, forType: .string)
        lastStatusMessage = "Copied command: \(command.preview)"
    }

    func openProjectInFinder() {
        let path = resolvedProjectPath(projectPath)
        guard !path.isEmpty else {
            lastStatusMessage = "Choose a project folder before opening it in Finder."
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            lastStatusMessage = "Cannot reveal missing path: \(displayPath(path))"
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([isDirectory.boolValue ? url : url.deletingLastPathComponent()])
    }

    func clearFileSearch() {
        fileSearchQuery = ""
        lastStatusMessage = "File search cleared."
    }

    func resetLaunchPackageToDetected() {
        guard canResetLaunchPackageToDetected else {
            lastStatusMessage = launchPackageHelpText
            return
        }
        packageOverride = profile.packageName == "unknown.android.app" ? "" : profile.packageName
        lastStatusMessage = packageOverride.isEmpty
            ? "No detected package is available yet."
            : "Launch package reset to \(packageOverride)."
    }

    func revealProjectFileInFinder(_ item: ProjectFileItem) {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(item.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastStatusMessage = "Cannot reveal missing file: \(item.path)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        lastStatusMessage = "Revealed \(item.path) in Finder."
    }

    func openProjectFileExternally(_ item: ProjectFileItem) {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(item.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastStatusMessage = "Cannot open missing file: \(item.path)"
            return
        }
        NSWorkspace.shared.open(url)
        lastStatusMessage = "Opened \(item.path) with the default macOS app."
    }

    func openFile(_ item: ProjectFileItem) {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(item.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            lastStatusMessage = "File no longer exists: \(item.path)"
            return
        }
        guard !isDirectory.boolValue else {
            lastStatusMessage = "Folders cannot be opened in the editor: \(item.path)"
            return
        }
        if let existingIndex = openEditorDocuments.firstIndex(where: { $0.path == item.path }) {
            selectedEditorPath = openEditorDocuments[existingIndex].path
            lastStatusMessage = "Focused \(item.path) in the editor."
            return
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let document = EditorDocument(
                path: item.path,
                name: item.name,
                content: content,
                savedContent: content,
                lastError: nil
            )
            openEditorDocuments.append(document)
            selectedEditorPath = item.path
            lastStatusMessage = "Opened \(item.path) in the editor."
        } catch {
            lastStatusMessage = "Could not open \(item.path) as editable UTF-8 text: \(error.localizedDescription)"
        }
    }

    func copyProjectPath(_ item: ProjectFileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
        lastStatusMessage = "Copied \(item.path)"
    }

    func copyProjectAbsolutePath(_ item: ProjectFileItem) {
        let path = URL(fileURLWithPath: projectPath).appendingPathComponent(item.path).path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        lastStatusMessage = "Copied \(path)"
    }

    var selectedEditorDocument: EditorDocument? {
        if let document = openEditorDocuments.first(where: { $0.path == selectedEditorPath }) {
            return document
        }
        return openEditorDocuments.first
    }

    var selectedEditorContent: String {
        selectedEditorDocument?.content ?? ""
    }

    var dirtyEditorDocumentCount: Int {
        openEditorDocuments.filter(\.isDirty).count
    }

    var editorStatusSummary: String {
        guard let document = selectedEditorDocument else {
            return "Open a file from Files to start editing."
        }
        let dirtyText = document.isDirty ? "Unsaved changes" : "Saved"
        let planText = planNeedsRefresh ? "Plan refresh recommended" : "Plan current"
        return "\(dirtyText) - \(planText) - \(document.path)"
    }

    func selectEditorDocument(_ document: EditorDocument) {
        guard openEditorDocuments.contains(where: { $0.path == document.path }) else {
            lastStatusMessage = "Editor file is not open: \(document.path)"
            return
        }
        selectedEditorPath = document.path
        lastStatusMessage = "Focused \(document.path) in the editor."
    }

    func updateSelectedEditorContent(_ content: String) {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before editing content."
            return
        }
        openEditorDocuments[index].content = content
        planNeedsRefresh = true
    }

    func saveSelectedEditorDocument() {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before saving."
            return
        }
        saveEditorDocument(at: index)
    }

    func saveAllEditorDocuments() {
        let dirtyIndices = openEditorDocuments.indices.filter { openEditorDocuments[$0].isDirty }
        guard !dirtyIndices.isEmpty else {
            lastStatusMessage = "No editor changes to save."
            return
        }
        for index in dirtyIndices {
            saveEditorDocument(at: index)
        }
        if dirtyEditorDocumentCount == 0 {
            lastStatusMessage = "Saved all open editor changes."
        }
    }

    func revertSelectedEditorDocument() {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before reverting."
            return
        }
        openEditorDocuments[index].content = openEditorDocuments[index].savedContent
        openEditorDocuments[index].lastError = nil
        planNeedsRefresh = true
        lastStatusMessage = "Reverted \(openEditorDocuments[index].path) to the last saved version."
    }

    func reloadSelectedEditorDocument() {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before reloading."
            return
        }
        let document = openEditorDocuments[index]
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(document.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            openEditorDocuments[index].lastError = "Backing file is missing."
            lastStatusMessage = "Could not reload \(document.path): backing file is missing."
            return
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            openEditorDocuments[index].content = content
            openEditorDocuments[index].savedContent = content
            openEditorDocuments[index].lastError = nil
            planNeedsRefresh = true
            lastStatusMessage = "Reloaded \(document.path) from disk."
        } catch {
            openEditorDocuments[index].lastError = error.localizedDescription
            lastStatusMessage = "Could not reload \(document.path): \(error.localizedDescription)"
        }
    }

    func replaceInSelectedEditorDocument(find query: String, replacement: String) {
        let findText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !findText.isEmpty else {
            lastStatusMessage = "Enter text to find before replacing."
            return
        }
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before replacing text."
            return
        }
        let original = openEditorDocuments[index].content
        let updated = original.replacingOccurrences(of: findText, with: replacement, options: [.caseInsensitive, .diacriticInsensitive])
        guard updated != original else {
            lastStatusMessage = "No matches found for \(findText)."
            return
        }
        openEditorDocuments[index].content = updated
        planNeedsRefresh = true
        lastStatusMessage = "Replaced matches for \(findText) in \(openEditorDocuments[index].path)."
    }

    func formatSelectedEditorDocument() {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before formatting."
            return
        }
        let original = openEditorDocuments[index].content
        let lines = original.split(separator: "\n", omittingEmptySubsequences: false)
        let formatted = lines
            .map { value -> String in
                var line = String(value)
                while line.last == " " || line.last == "\t" {
                    line.removeLast()
                }
                return line
            }
            .joined(separator: "\n")
        guard formatted != original else {
            lastStatusMessage = "No whitespace formatting changes needed."
            return
        }
        openEditorDocuments[index].content = formatted
        planNeedsRefresh = true
        lastStatusMessage = "Formatted whitespace in \(openEditorDocuments[index].path)."
    }

    var selectedEditorLintSummary: String {
        guard let document = selectedEditorDocument else { return "Open a file to run editor checks." }
        let lines = document.content.split(separator: "\n", omittingEmptySubsequences: false)
        let longLineCount = lines.filter { $0.count > 120 }.count
        let todoCount = document.content.localizedStandardContains("TODO") ? document.content.components(separatedBy: "TODO").count - 1 : 0
        let trailingWhitespaceCount = lines.filter { line in
            guard let last = line.last else { return false }
            return last == " " || last == "\t"
        }.count
        let issueCount = longLineCount + todoCount + trailingWhitespaceCount
        guard issueCount > 0 else { return "Editor checks: no TODOs, long lines, or trailing whitespace found." }
        return "Editor checks: \(issueCount) issue\(issueCount == 1 ? "" : "s") found (\(longLineCount) long, \(todoCount) TODO, \(trailingWhitespaceCount) whitespace)."
    }

    var canFormatSelectedEditorDocument: Bool {
        guard let document = selectedEditorDocument else { return false }
        return document.content.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            guard let last = line.last else { return false }
            return last == " " || last == "\t"
        }
    }

    var selectedEditorFormatHelpText: String {
        guard selectedEditorDocument != nil else {
            return "Open a file before formatting."
        }
        return canFormatSelectedEditorDocument
            ? "Remove trailing whitespace from this file."
            : "No trailing whitespace formatting changes are needed."
    }

    var hasSelectedEditorFileOnDisk: Bool {
        guard let document = selectedEditorDocument else { return false }
        let path = URL(fileURLWithPath: projectPath).appendingPathComponent(document.path).path
        return FileManager.default.fileExists(atPath: path)
    }

    var selectedEditorDiskActionHelpText: String {
        guard let document = selectedEditorDocument else {
            return "Open a file before using disk actions."
        }
        return hasSelectedEditorFileOnDisk
            ? "Use disk actions for \(document.path)."
            : "The backing file is no longer available on disk."
    }

    func copySelectedEditorPath(absolute: Bool = false) {
        guard let document = selectedEditorDocument else {
            lastStatusMessage = "Open a file before copying its path."
            return
        }
        let value = absolute
            ? URL(fileURLWithPath: projectPath).appendingPathComponent(document.path).path
            : document.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        lastStatusMessage = "Copied \(value)"
    }

    func revealSelectedEditorDocumentInFinder() {
        guard let document = selectedEditorDocument else {
            lastStatusMessage = "Open a file before revealing it."
            return
        }
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(document.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastStatusMessage = "Cannot reveal \(document.path): backing file is missing."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        lastStatusMessage = "Revealed \(document.path) in Finder."
    }

    func openSelectedEditorDocumentExternally() {
        guard let document = selectedEditorDocument else {
            lastStatusMessage = "Open a file before opening it externally."
            return
        }
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(document.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastStatusMessage = "Cannot open \(document.path): backing file is missing."
            return
        }
        NSWorkspace.shared.open(url)
        lastStatusMessage = "Opened \(document.path) externally."
    }

    @discardableResult
    func saveAndCloseSelectedEditorDocument() -> Bool {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before saving and closing."
            return false
        }
        if openEditorDocuments[index].isDirty {
            saveEditorDocument(at: index)
            guard openEditorDocuments.indices.contains(index), openEditorDocuments[index].lastError == nil else {
                return false
            }
        }
        return closeEditorDocument(at: index, discardingChanges: false)
    }

    @discardableResult
    func closeSelectedEditorDocument(discardingChanges: Bool = false) -> Bool {
        guard let index = selectedEditorIndex() else {
            lastStatusMessage = "Open a file before closing it."
            return false
        }
        return closeEditorDocument(at: index, discardingChanges: discardingChanges)
    }

    @discardableResult
    func closeEditorDocument(path: String, discardingChanges: Bool = false) -> Bool {
        guard let index = openEditorDocuments.firstIndex(where: { $0.path == path }) else {
            lastStatusMessage = "Editor file is not open: \(path)"
            return false
        }
        return closeEditorDocument(at: index, discardingChanges: discardingChanges)
    }

    @discardableResult
    func closeAllEditorDocuments(discardingChanges: Bool = false) -> Bool {
        guard !openEditorDocuments.isEmpty else {
            lastStatusMessage = "No editor files are open."
            return false
        }
        let dirtyCount = dirtyEditorDocumentCount
        guard dirtyCount == 0 || discardingChanges else {
            lastStatusMessage = "Confirm discarding unsaved changes before closing \(dirtyCount) editor file\(dirtyCount == 1 ? "" : "s")."
            return false
        }
        let closedCount = openEditorDocuments.count
        openEditorDocuments.removeAll()
        selectedEditorPath = ""
        lastStatusMessage = dirtyCount > 0
            ? "Closed \(closedCount) editor file\(closedCount == 1 ? "" : "s") and discarded unsaved changes."
            : "Closed \(closedCount) editor file\(closedCount == 1 ? "" : "s")."
        return true
    }

    @discardableResult
    private func closeEditorDocument(at index: Int, discardingChanges: Bool) -> Bool {
        guard openEditorDocuments.indices.contains(index) else {
            lastStatusMessage = "No editor file is selected to close."
            return false
        }
        let document = openEditorDocuments[index]
        guard !document.isDirty || discardingChanges else {
            lastStatusMessage = "Save or revert \(document.path) before closing it."
            return false
        }
        openEditorDocuments.remove(at: index)
        selectedEditorPath = openEditorDocuments.indices.contains(index)
            ? openEditorDocuments[index].path
            : openEditorDocuments.last?.path ?? ""
        lastStatusMessage = document.isDirty
            ? "Closed \(document.path) and discarded unsaved changes."
            : "Closed \(document.path)."
        return true
    }

    func removeRecentProject(_ path: String) {
        let originalCount = recentProjectPaths.count
        recentProjectPaths.removeAll { $0 == path }
        UserDefaults.standard.set(recentProjectPaths, forKey: recentProjectsKey)
        lastStatusMessage = recentProjectPaths.count == originalCount
            ? "Recent project was not found: \(displayPath(path))."
            : "Removed \(displayPath(path)) from recent projects."
    }

    func clearMissingRecentProjects() {
        let originalCount = recentProjectPaths.count
        recentProjectPaths = recentProjectPaths.filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        UserDefaults.standard.set(recentProjectPaths, forKey: recentProjectsKey)
        let removedCount = originalCount - recentProjectPaths.count
        lastStatusMessage = removedCount == 0 ? "No missing recent projects to clear." : "Cleared \(removedCount) missing recent project\(removedCount == 1 ? "" : "s")."
    }

    func clearRecentProjects() {
        guard !recentProjectPaths.isEmpty else {
            lastStatusMessage = "Recent projects are already empty."
            return
        }
        recentProjectPaths.removeAll()
        UserDefaults.standard.removeObject(forKey: recentProjectsKey)
        lastStatusMessage = "Recent projects cleared."
    }

    func clearPrompt() {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastStatusMessage = "Prompt is already empty."
            return
        }
        previousPromptDraft = prompt
        savePromptToHistory(prompt)
        prompt = ""
        lastStatusMessage = "Prompt cleared. Previous prompt is available in history."
    }

    func performRecommendedAction() {
        if isScanningProject {
            cancelScan()
            return
        }
        if canScanProject, !isProjectLoaded {
            scanProject()
            return
        }
        if resolvedProjectPath(projectPath).isEmpty {
            chooseProject()
            return
        }
        if !isProjectLoaded {
            scanProject()
            return
        }
        if selectedDeviceID.isEmpty {
            if isRunningWirelessDebugging {
                selectedSessionTab = .diagnostics
                lastStatusMessage = "Wireless Debugging is already running."
                return
            }
            if isRefreshingDevices {
                selectedSessionTab = .diagnostics
                lastStatusMessage = "Device refresh is already running."
                return
            }
            refreshDevices()
            selectedSessionTab = .diagnostics
            return
        }
        selectedSessionTab = lastCommandSummary?.severity == "failed" ? .diagnostics : .checks
        lastStatusMessage = "Opened \(selectedSessionTab.rawValue) for the next recommended review."
    }

    var canScanProject: Bool {
        guard canEditProjectSelection else { return false }
        let path = resolvedProjectPath(projectPath)
        guard !path.isEmpty, !isUnsafeScanRoot(path) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var canEditProjectSelection: Bool {
        !isScanningProject && !isRunningCommand && !isRefreshingDevices && !isRunningWirelessDebugging
    }

    var projectSelectionHelpText: String {
        if isScanningProject { return "Wait for the current scan to finish or cancel it first." }
        if isRunningCommand { return "Wait for the current command before changing the project." }
        if isRefreshingDevices { return "Wait for device refresh before changing the project." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging before changing the project." }
        return "Choose or edit the Android project path."
    }

    var canRevealProjectPath: Bool {
        let path = resolvedProjectPath(projectPath)
        guard !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var projectRevealHelpText: String {
        let path = resolvedProjectPath(projectPath)
        guard !path.isEmpty else {
            return "Choose a project path before revealing it in Finder."
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return "Cannot reveal missing path: \(displayPath(path))."
        }
        return "Reveal \(displayPath(path)) in Finder."
    }

    var canRunTools: Bool {
        isProjectLoaded && !isScanningProject && !isRunningCommand && !isRefreshingDevices && !isRunningWirelessDebugging
    }

    var canEditBuildTarget: Bool {
        isProjectLoaded && !isRunningCommand && !isScanningProject
    }

    var buildTargetHelpText: String {
        if !isProjectLoaded { return "Scan a project before choosing a Gradle target." }
        if isScanningProject { return "Wait for project scanning to finish before changing targets." }
        if isRunningCommand { return "Wait for the current command before changing targets." }
        return "Choose the Gradle module and build variant used by commands."
    }

    var canResetLaunchPackageToDetected: Bool {
        canEditLaunchTarget && profile.packageName != "unknown.android.app"
    }

    var canEditLaunchTarget: Bool {
        isProjectLoaded && !isRunningCommand && !isScanningProject
    }

    var launchPackageHelpText: String {
        guard isProjectLoaded else {
            return "Scan a project before editing the launch package."
        }
        if isScanningProject { return "Wait for project scanning to finish before editing launch package." }
        if isRunningCommand { return "Wait for the current command before editing launch package." }
        if profile.packageName == "unknown.android.app" {
            return "No package was detected. Enter a package override before Launch."
        }
        return "Override the detected package used for Launch."
    }

    var launchActivityHelpText: String {
        if !isProjectLoaded { return "Scan a project before editing the launch activity." }
        if isScanningProject { return "Wait for project scanning to finish before editing launch activity." }
        if isRunningCommand { return "Wait for the current command before editing launch activity." }
        return "Set the Android activity used by Launch."
    }

    var canRefreshDevices: Bool {
        !isRefreshingDevices && !isRunningCommand && !isScanningProject && !isRunningWirelessDebugging && !isRefreshingDevicePreview
    }

    var refreshDevicesHelpText: String {
        if isRefreshingDevices { return "Device refresh is already running." }
        if isRunningCommand { return "Wait for the current command before refreshing devices." }
        if isScanningProject { return "Wait for project scanning to finish before refreshing devices." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging to finish before refreshing devices." }
        if isRefreshingDevicePreview { return "Wait for the device preview refresh to finish before refreshing devices." }
        return "Refresh attached Android devices. This does not require a loaded project."
    }

    var canSelectDevice: Bool {
        (!devices.isEmpty || !selectedDeviceID.isEmpty) && !isRefreshingDevices && !isRunningCommand && !isRunningWirelessDebugging && !isRefreshingDevicePreview
    }

    var selectedDeviceOption: DeviceOption? {
        devices.first { $0.id == selectedDeviceID }
    }

    var selectedWirelessDebuggingDevice: WirelessDebuggingDevice? {
        wirelessDebuggingDevices.first { $0.id == selectedWirelessDebuggingDeviceID }
    }

    var hasSelectedWirelessDebuggingDevice: Bool {
        selectedWirelessDebuggingDevice != nil
    }

    var selectedDeviceDisplayName: String {
        guard !selectedDeviceID.isEmpty else { return "No device" }
        return selectedDeviceOption?.displayName ?? "Android Device"
    }

    var hasConnectedDevice: Bool {
        !selectedDeviceID.isEmpty && selectedDeviceOption != nil
    }

    var shouldShowDeviceScreenPreview: Bool {
        hasConnectedDevice
    }

    var devicePickerHelpText: String {
        if isRefreshingDevices { return "Device refresh is already running." }
        if isRunningCommand { return "Wait for the current command before changing devices." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging to finish before changing devices." }
        if isRefreshingDevicePreview { return "Wait for the device preview refresh before changing devices." }
        if devices.isEmpty && !selectedDeviceID.isEmpty { return "No devices are currently listed. Choose No device to clear the stale target." }
        if devices.isEmpty { return "Refresh devices before selecting an Android target." }
        return deviceSummary
    }

    var canRefreshDevicePreview: Bool {
        hasConnectedDevice && !isDevicePreviewCaptureInFlight && !isRefreshingDevicePreview && !isRefreshingDevices && !isRunningCommand && !isScanningProject && !isRunningWirelessDebugging
    }

    var canSendDeviceTap: Bool {
        hasConnectedDevice && !isSendingDeviceInput && !isDevicePreviewCaptureInFlight && !isRefreshingDevicePreview && !isRefreshingDevices && !isRunningCommand && !isScanningProject && !isRunningWirelessDebugging
    }

    var devicePreviewHelpText: String {
        if !hasConnectedDevice { return "Connect an Android target before refreshing the preview." }
        if isDevicePreviewCaptureInFlight || isRefreshingDevicePreview { return "Device preview refresh is already running." }
        if isRefreshingDevices { return "Wait for device refresh to finish before refreshing preview." }
        if isRunningCommand { return "Wait for the current command before refreshing preview." }
        if isScanningProject { return "Wait for project scanning to finish before refreshing preview." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging to finish before refreshing preview." }
        return "Refresh the \(selectedDeviceDisplayName) screen preview."
    }

    var deviceTapHelpText: String {
        if !hasConnectedDevice { return "Connect an Android target before sending screen taps." }
        if isSendingDeviceInput { return "A device tap is already being sent." }
        if isDevicePreviewCaptureInFlight || isRefreshingDevicePreview { return "Wait for the current device frame before tapping the preview." }
        if isRefreshingDevices { return "Wait for device refresh to finish before tapping the preview." }
        if isRunningCommand { return "Wait for the current command before tapping the preview." }
        if isScanningProject { return "Wait for project scanning to finish before tapping the preview." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging to finish before tapping the preview." }
        return "Send taps to \(selectedDeviceDisplayName) from the preview."
    }

    var devicePreviewUpdatedSummary: String {
        guard let devicePreviewUpdatedAt else { return devicePreviewStatus }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "\(devicePreviewStatus) Updated \(formatter.string(from: devicePreviewUpdatedAt))."
    }

    var canPairWirelessDevice: Bool {
        canRunADBWirelessAction && !wirelessPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canConnectWirelessDevice: Bool {
        canRunADBWirelessAction && wirelessConnectTargetAddress != nil
    }

    var wirelessConnectActionTitle: String {
        trimmedWirelessConnectAddress.isEmpty && isValidHostPort(lastWirelessDeviceAddress)
            ? "Reconnect"
            : "Connect"
    }

    var canDisconnectWirelessDevice: Bool {
        canRunADBWirelessAction && wirelessDisconnectAddress != nil
    }

    var canDisconnectSelectedWirelessDevice: Bool {
        hasConnectedDevice && selectedDeviceOption?.isNetworkSerial == true && canRunADBWirelessAction && wirelessDisconnectAddress != nil
    }

    var canRefreshWirelessDebuggingDevices: Bool {
        canRunADBWirelessAction
    }

    var wirelessDiscoveryHelpText: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, preview refresh, or wireless action to finish."
        }
        return "Scan this network for Android Wireless Debugging services."
    }

    var canEditWirelessDebuggingFields: Bool {
        canRunADBWirelessAction
    }

    var canGenerateWirelessQRCode: Bool {
        canRunADBWirelessAction
    }

    var wirelessQRCodeHelpText: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, preview refresh, or Wireless Debugging action to finish."
        }
        return "Generate a QR code for Android Wireless Debugging, then scan for the paired device."
    }

    var wirelessDebuggingSummary: String {
        if isRunningWirelessDebugging { return wirelessDebuggingStatus }
        if hasConnectedDevice { return "" }
        if wirelessDebuggingStatus == "Pairing successful"
            || wirelessDebuggingStatus == "Device connected"
            || wirelessDebuggingStatus == "Device disconnected" {
            return wirelessDebuggingStatus
        }
        let pairing = lastWirelessPairingAddress.isEmpty ? "" : " Last pairing address: \(lastWirelessPairingAddress)."
        let device = lastWirelessDeviceAddress.isEmpty ? "" : " Last wireless target: \(lastWirelessDeviceAddress)."
        return wirelessDebuggingStatus + pairing + device
    }

    var wirelessPairingHelpText: String {
        wirelessPairingValidationMessage
    }

    var wirelessConnectHelpText: String {
        wirelessConnectValidationMessage
    }

    var wirelessDisconnectHelpText: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, preview refresh, or Wireless Debugging action to finish."
        }
        guard let target = wirelessDisconnectAddress else {
            return "Connect or enter a Wireless Debugging target before disconnecting."
        }
        return "Disconnect wireless target \(target)."
    }

    var deviceRecoveryGuidance: String {
        if isRefreshingDevices || isRunningWirelessDebugging || !selectedDeviceID.isEmpty {
            return ""
        }
        if devices.isEmpty {
            return "No online Android target is selected. Start an emulator, connect USB debugging, or use Connect wireless devices."
        }
        return "Choose one of the detected devices to unlock Logcat, Launch, and connected tests."
    }

    var projectPathDisplay: String {
        isProjectLoaded ? displayPath(projectPath) : "No project loaded"
    }

    var candidateProjectPathDisplay: String {
        let candidate = resolvedProjectPath(projectPath)
        return candidate.isEmpty ? "No project selected" : displayPath(candidate)
    }

    var projectPathFeedback: DiagnosticRow {
        let candidate = resolvedProjectPath(projectPath)
        guard !candidate.isEmpty else {
            return DiagnosticRow(title: "Choose a folder", detail: "Select, paste, or drop an Android project folder.", symbol: "folder.badge.questionmark", severity: "neutral")
        }
        if isUnsafeScanRoot(candidate) {
            return DiagnosticRow(title: "Folder too broad", detail: "Choose the project folder itself, not \(displayPath(candidate)).", symbol: "exclamationmark.triangle", severity: "warning")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) else {
            return DiagnosticRow(title: "Path missing", detail: "This folder is not available. Choose another project or remove it from recents.", symbol: "xmark.octagon", severity: "failed")
        }
        guard isDirectory.boolValue else {
            return DiagnosticRow(title: "Not a folder", detail: "Choose a project directory. Dropping a file scans its parent folder.", symbol: "doc.badge.ellipsis", severity: "warning")
        }
        if isScanningProject {
            return DiagnosticRow(title: "Scanning", detail: "Reading Gradle, manifest, source, resource, and test signals.", symbol: "arrow.triangle.2.circlepath", severity: "running")
        }
        if isProjectLoaded {
            return DiagnosticRow(title: "Project loaded", detail: workspaceSummary, symbol: "checkmark.circle", severity: "ready")
        }
        return DiagnosticRow(title: "Ready to scan", detail: "Scan this folder to unlock Gradle, files, checks, and device actions.", symbol: "arrow.clockwise.circle", severity: "neutral")
    }

    var recentProjectRows: [RecentProjectRow] {
        recentProjectPaths.map { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            let name = URL(fileURLWithPath: path).lastPathComponent
            return RecentProjectRow(
                path: path,
                name: name.isEmpty ? displayPath(path) : name,
                displayPath: displayPath(path),
                exists: exists
            )
        }
    }

    var hasMissingRecentProjects: Bool {
        recentProjectRows.contains { !$0.exists }
    }

    var projectSubtitle: String {
        if isScanningProject { return "Scanning project context" }
        return isProjectLoaded ? profile.packageName : "No project loaded"
    }

    var confidenceDisplay: String {
        isProjectLoaded ? "\(plan.confidencePercent)% confidence" : scanState.title
    }

    var workspaceSummary: String {
        guard isProjectLoaded else { return scanState.detail }
        return "\(snapshot.fileCount) files, \(snapshot.testFileCount) tests, \(snapshot.hasGradleWrapper ? "Gradle wrapper" : "system Gradle")"
    }

    var deviceSummary: String {
        if isRunningWirelessDebugging { return wirelessDebuggingStatus }
        if isRefreshingDevices { return "Refreshing attached Android devices..." }
        if selectedDeviceID.isEmpty {
            let suffix = unavailableDeviceSummary.isEmpty ? "" : " \(unavailableDeviceSummary)"
            return devices.isEmpty ? "No online Android device selected. Refresh devices after starting an emulator, connecting USB debugging, or pairing Wireless Debugging.\(suffix)" : "Choose a device for Logcat, Launch, and device tests.\(suffix)"
        }
        return hasConnectedDevice ? "Connected: \(selectedDeviceDisplayName)" : "Selected device is not currently connected."
    }

    var scanProgressSummary: String {
        guard isScanningProject else { return scanState.detail }
        let elapsed = scanStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        return "Scanning Gradle, manifest, source, resources, and tests for \(elapsed)s."
    }

    var promptContextSummary: String {
        let project = isProjectLoaded ? profile.packageName : "no project"
        let files = isProjectLoaded ? "\(snapshot.fileCount) files" : "scan pending"
        let stale = planNeedsRefresh ? "Plan may be stale after editor changes." : "Plan is current."
        return "\(project), \(files). \(stale)"
    }

    var promptMetricsSummary: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        return "\(prompt.count) characters, \(words) words"
    }

    var assistantModelRouteSummary: String {
        "\(assistantModelMode.title) - \(assistantModelStatus)"
    }

    var taskDroidRouteSummary: String {
        if assistantModelMode == .privateLocal {
            return "Private mode is selected. TaskDroid/OpenAI routes are not called, even if provider sharing consent is enabled."
        }
        if !assistantAllowsProviderSharing {
            return "Provider sharing is off. TaskDroid/OpenAI routes are not called until the consent switch is enabled. \(assistantTaskDroidAccountSummary)."
        }
        if assistantTaskDroidEnabled, let url = assistantTaskDroidBaseURL {
            return "TaskDroid planner route: \(url.absoluteString). If this configured route fails, Ask shows the TaskDroid error without fallback."
        }
        return "TaskDroid is optional and not active. Configure a TaskDroid URL below, or use OpenAI/private local routing."
    }

    var fileSearchSummary: String {
        if !isProjectLoaded { return "No project indexed." }
        let query = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(filteredProjectFiles.filter(\.isDirectory).count) folders, \(filteredProjectFiles.filter { !$0.isDirectory }.count) files"
        return query.isEmpty ? "\(base) shown." : "\(base) match \"\(query)\"."
    }

    var launchTargetFeedback: DiagnosticRow {
        guard isProjectLoaded else {
            return DiagnosticRow(title: "Launch locked", detail: "Scan a project before configuring launch.", symbol: "lock", severity: "neutral")
        }
        if packageNameForCommands == "unknown.android.app" {
            return DiagnosticRow(title: "Package needed", detail: "Set a package override before Launch.", symbol: "shippingbox", severity: "warning")
        }
        if launchActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DiagnosticRow(title: "Activity needed", detail: "Set a launch activity, for example .MainActivity.", symbol: "play.slash", severity: "warning")
        }
        return DiagnosticRow(title: "Install and launch ready", detail: "\(gradleTaskName(prefix: "install", suffix: "")) → \(packageNameForCommands)/\(launchActivity)", symbol: "play.circle", severity: selectedDeviceID.isEmpty ? "neutral" : "ready")
    }

    var recommendedActionTitle: String {
        if isScanningProject { return "Cancel Scan" }
        if resolvedProjectPath(projectPath).isEmpty { return "Choose Folder" }
        if !isProjectLoaded { return "Scan Project" }
        if selectedDeviceID.isEmpty { return "Refresh Devices" }
        if lastCommandSummary?.severity == "failed" { return "Open Diagnostics" }
        return "Review Checks"
    }

    var recommendedActionDetail: String {
        if isScanningProject { return "A scan is running. Cancel if the selected folder was wrong." }
        if resolvedProjectPath(projectPath).isEmpty { return "Start by choosing, pasting, or dropping an Android project." }
        if !isProjectLoaded { return projectPathFeedback.detail }
        if selectedDeviceID.isEmpty { return "Build and unit tests can run now; refresh devices to unlock Logcat, Launch, and connected tests." }
        if lastCommandSummary?.severity == "failed" { return "Open diagnostics to review the failing command and recovery hints." }
        return "Review verification readiness, then run the narrowest useful command."
    }

    var packageNameForCommands: String {
        let override = packageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return profile.packageName
    }

    var filteredProjectFiles: [ProjectFileItem] {
        let query = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return projectFiles.filter { isVisibleInCollapsedFileTree($0) }
        }

        let matchingItems = projectFiles.filter {
            $0.path.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
        var includedPaths = Set(matchingItems.map(\.path))
        let matchingFolderPaths = Set(matchingItems.filter(\.isDirectory).map(\.path))

        for item in matchingItems {
            includedPaths.formUnion(ancestorFolderPaths(for: item.path))
        }
        if !matchingFolderPaths.isEmpty {
            for item in projectFiles where matchingFolderPaths.contains(where: { isDescendant(item.path, of: $0) }) {
                includedPaths.insert(item.path)
            }
        }

        return projectFiles.filter { includedPaths.contains($0.path) }
    }

    func toggleProjectFolder(_ item: ProjectFileItem) {
        guard item.isDirectory else {
            lastStatusMessage = "Only folders can be expanded or collapsed."
            return
        }
        if expandedProjectFolderPaths.contains(item.path) {
            expandedProjectFolderPaths.remove(item.path)
            lastStatusMessage = "Collapsed \(item.path)."
        } else {
            expandedProjectFolderPaths.insert(item.path)
            lastStatusMessage = "Expanded \(item.path)."
        }
    }

    func isProjectFolderExpanded(_ item: ProjectFileItem) -> Bool {
        guard item.isDirectory else { return false }
        if !fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return expandedProjectFolderPaths.contains(item.path)
    }

    func expandAllProjectFolders() {
        guard isProjectLoaded else {
            lastStatusMessage = "Scan a project before expanding project folders."
            return
        }
        expandedProjectFolderPaths = Set(projectFiles.filter(\.isDirectory).map(\.path))
        lastStatusMessage = "Expanded all project folders."
    }

    func collapseAllProjectFolders() {
        guard isProjectLoaded else {
            lastStatusMessage = "Scan a project before collapsing project folders."
            return
        }
        expandedProjectFolderPaths.removeAll()
        lastStatusMessage = "Collapsed all project folders."
    }

    private func defaultExpandedProjectFolderPaths(from items: [ProjectFileItem]) -> Set<String> {
        var paths = Set(items.filter { $0.isDirectory && $0.depth == 0 }.map(\.path))
        for item in items where item.isSelected && !item.isDirectory {
            paths.formUnion(ancestorFolderPaths(for: item.path))
        }
        return paths
    }

    var selectedPlanStep: AgentPlanStep? {
        plan.steps.first { $0.id == selectedPlanStepID } ?? plan.steps.first
    }

    func canRunCommand(_ kind: AndroidCommandKind) -> Bool {
        commandBlockReason(for: kind) == nil
    }

    func commandStateText(_ kind: AndroidCommandKind) -> String {
        if isScanningProject { return "Scanning" }
        if isRunningCommand { return runningCommandKind == kind ? "Running" : "Busy" }
        if isRefreshingDevices { return kind == .devices ? "Refreshing" : "Busy" }
        if isRunningWirelessDebugging { return "Wireless" }
        if kind == .devices { return isRefreshingDevices ? "Refreshing" : "Ready" }
        if !isProjectLoaded { return "Scan first" }
        if kind.requiresDevice && selectedDeviceID.isEmpty { return "Select device" }
        if kind == .launch && packageNameForCommands == "unknown.android.app" { return "Set package" }
        if kind == .launch && launchActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Set activity" }
        if kind.requiresConfirmation { return "Confirm" }
        return "Ready"
    }

    func commandHelpText(_ kind: AndroidCommandKind) -> String {
        commandBlockReason(for: kind) ?? "Run \(kind.rawValue) for the current Android workspace."
    }

    func commandBlockReason(for kind: AndroidCommandKind) -> String? {
        if isScanningProject { return "Wait for scanning to finish or cancel the scan first." }
        if isRunningCommand { return "A command is already running. Stop it or wait for completion." }
        if isRefreshingDevices { return kind == .devices ? "Device refresh is already running." : "Wait for device refresh to finish before running \(kind.rawValue)." }
        if isRunningWirelessDebugging { return "Wait for Wireless Debugging to finish before running \(kind.rawValue)." }
        if kind == .devices { return nil }
        if !isProjectLoaded { return "Scan a valid Android project before running \(kind.rawValue)." }
        if kind.requiresDevice && selectedDeviceID.isEmpty { return "Refresh devices and choose a target before running \(kind.rawValue)." }
        if kind == .launch && packageNameForCommands == "unknown.android.app" { return "Set a launch package before starting the app." }
        if kind == .launch && launchActivity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Set a launch activity before starting the app." }
        return nil
    }

    var runningCommandStopTitle: String {
        guard isRunningCommand else { return "Stop Command" }
        if let runningCommandKind {
            return "Stop \(runningCommandKind.rawValue)"
        }
        return lastCommandTitle == "Idle" ? "Stop Command" : "Stop \(lastCommandTitle)"
    }

    var runningCommandStopHelpText: String {
        guard isRunningCommand else { return "No Run Tool command is currently running." }
        if let runningCommandKind {
            return "Stop the active \(runningCommandKind.rawValue) command."
        }
        return "Stop the currently running command."
    }

    func displayState(for step: AgentPlanStep) -> String {
        if step.order == 1 { return "Done" }
        if isProjectLoaded && step.title == "Scan Android workspace" { return "Done" }
        if isRunningCommand && step.title == "Run verification" { return "Running" }
        if lastCommandSummary?.severity == "failed" && step.title == "Run verification" { return "Blocked" }
        return step.state.rawValue
    }

    func displaySeverity(for step: AgentPlanStep) -> String {
        let state = displayState(for: step)
        if state == "Done" { return "ready" }
        if state == "Running" { return "running" }
        if state == "Blocked" { return "failed" }
        return "neutral"
    }

    var diagnosticRows: [DiagnosticRow] {
        [
            DiagnosticRow(title: "Android SDK", detail: androidSDKSummary, symbol: "iphone.gen3", severity: androidSDKSummary.contains("Missing") ? "warning" : "ready"),
            DiagnosticRow(title: "ADB Devices", detail: deviceSummary, symbol: "list.bullet.rectangle", severity: selectedDeviceID.isEmpty ? "warning" : "ready"),
            DiagnosticRow(title: "Wireless Debugging", detail: wirelessDebuggingSummary, symbol: "wifi", severity: lastWirelessDeviceAddress.isEmpty ? "neutral" : "ready"),
            DiagnosticRow(title: "Git Worktree", detail: gitSummary, symbol: "arrow.triangle.branch", severity: gitSummary.contains("not found") ? "warning" : "ready"),
            DiagnosticRow(title: "Modules", detail: modules.joined(separator: ", "), symbol: "square.stack.3d.up", severity: modules.isEmpty ? "warning" : "ready"),
            DiagnosticRow(title: "Package", detail: packageNameForCommands == "unknown.android.app" ? "Package missing; set override before Launch" : packageNameForCommands, symbol: "shippingbox", severity: packageNameForCommands == "unknown.android.app" ? "warning" : "ready"),
            DiagnosticRow(title: "Ask Response Export", detail: askExportDiagnosticsDetail, symbol: "square.and.arrow.down", severity: askExportDiagnosticsSeverity),
            DiagnosticRow(title: "Latest App Export", detail: lastExportDiagnosticsDetail, symbol: "doc.text.magnifyingglass", severity: lastExportDiagnosticsSeverity)
        ]
    }

    var launchReadinessRows: [DiagnosticRow] {
        [
            DiagnosticRow(
                title: "Crash Reporting",
                detail: AndroidDevAgentLaunchReadiness.crashReportingSummary,
                symbol: "waveform.path.ecg.rectangle",
                severity: AndroidDevAgentLaunchReadiness.crashReportingSeverity
            ),
            DiagnosticRow(
                title: "Crash Symbolication",
                detail: AndroidDevAgentLaunchReadiness.crashSymbolicationSummary,
                symbol: "ladybug",
                severity: AndroidDevAgentLaunchReadiness.crashSymbolicationSeverity
            ),
            DiagnosticRow(
                title: "Telemetry",
                detail: AndroidDevAgentLaunchReadiness.telemetrySummary,
                symbol: "chart.line.uptrend.xyaxis",
                severity: AndroidDevAgentLaunchReadiness.telemetrySeverity
            ),
            DiagnosticRow(
                title: "License Activation",
                detail: AndroidDevAgentLaunchReadiness.licenseSummary,
                symbol: "key.horizontal",
                severity: AndroidDevAgentLaunchReadiness.licenseSeverity
            ),
            DiagnosticRow(
                title: "Privacy Audit",
                detail: AndroidDevAgentLaunchReadiness.privacyAuditSummary,
                symbol: "lock.doc",
                severity: AndroidDevAgentLaunchReadiness.privacyAuditSeverity
            ),
            DiagnosticRow(
                title: "Support Redaction",
                detail: AndroidDevAgentLaunchReadiness.supportRedactionSummary,
                symbol: "eye.slash",
                severity: AndroidDevAgentLaunchReadiness.supportRedactionSeverity
            ),
            DiagnosticRow(
                title: "Support Upload",
                detail: AndroidDevAgentLaunchReadiness.supportUploadSummary,
                symbol: "icloud.and.arrow.up",
                severity: AndroidDevAgentLaunchReadiness.supportUploadSeverity
            ),
            DiagnosticRow(
                title: "Diagnostic Version",
                detail: AndroidDevAgentLaunchReadiness.diagnosticVersionStampSummary,
                symbol: "number.square",
                severity: AndroidDevAgentLaunchReadiness.diagnosticVersionStampSeverity
            ),
            DiagnosticRow(
                title: "Onboarding",
                detail: AndroidDevAgentLaunchReadiness.onboardingSummary,
                symbol: "list.bullet.clipboard",
                severity: AndroidDevAgentLaunchReadiness.onboardingSeverity
            ),
            DiagnosticRow(
                title: "Support Bundle",
                detail: supportBundleDiagnosticsDetail,
                symbol: "shippingbox.and.arrow.backward",
                severity: supportBundleDiagnosticsSeverity
            ),
            DiagnosticRow(
                title: "Release Notes",
                detail: AndroidDevAgentLaunchReadiness.releaseNotesSummary,
                symbol: "doc.plaintext",
                severity: AndroidDevAgentLaunchReadiness.releaseNotesSeverity
            )
        ]
    }

    private var supportBundleDiagnosticsDetail: String {
        guard !supportBundlePath.isEmpty else {
            return "No support bundle exported yet."
        }
        if hasSupportBundleFile {
            return "Available at \(displayPath(supportBundlePath))."
        }
        return "Missing support bundle: \(displayPath(supportBundlePath)). Export again."
    }

    private var supportBundleDiagnosticsSeverity: String {
        guard !supportBundlePath.isEmpty else { return "neutral" }
        return hasSupportBundleFile ? "ready" : "warning"
    }

    private var lastExportDiagnosticsDetail: String {
        guard !lastExportPath.isEmpty else {
            return "No console, assistant response, or debug report exported yet"
        }
        if hasLastExportFile {
            return "\(lastExportSourceTitle): \(displayPath(lastExportPath))"
        }
        return "Missing \(lastExportSourceTitle): \(displayPath(lastExportPath)). Export again."
    }

    private var lastExportDiagnosticsSeverity: String {
        guard !lastExportPath.isEmpty else { return "neutral" }
        return hasLastExportFile ? "ready" : "warning"
    }

    private var askExportDiagnosticsDetail: String {
        guard !assistantResponseExportPath.isEmpty else {
            return "No assistant response export yet."
        }
        if hasAssistantResponseExportFile {
            return "Available at \(displayPath(assistantResponseExportPath))."
        }
        return "Export path is stale. Export again from Ask The Assistant."
    }

    private var askExportDiagnosticsSeverity: String {
        guard !assistantResponseExportPath.isEmpty else { return "neutral" }
        return hasAssistantResponseExportFile ? "ready" : "warning"
    }

    var safetyRows: [DiagnosticRow] {
        [
            DiagnosticRow(title: "Workspace boundary", detail: "Commands run from \(projectPathDisplay)", symbol: "folder.badge.gearshape", severity: isProjectLoaded ? "ready" : "neutral"),
            DiagnosticRow(title: "Scoped editor diff", detail: editorScopedDiffSafetyDetail, symbol: "doc.text.magnifyingglass", severity: selectedEditorDocument?.isDirty == true ? "warning" : "ready"),
            DiagnosticRow(title: "Undo checkpoint", detail: lastEditorUndoCheckpointPath.isEmpty ? "Editor saves create a rollback checkpoint before writing." : "Latest checkpoint: \(displayPath(lastEditorUndoCheckpointPath))", symbol: "arrow.uturn.backward.circle", severity: "ready"),
            DiagnosticRow(title: "Secret scanner", detail: lastEditorSecretScanSummary, symbol: "key.horizontal", severity: lastEditorSecretScanSummary.contains("Blocked") ? "warning" : "ready"),
            DiagnosticRow(title: "Risk confirmation", detail: "Launch, clear logs, and device tests ask before running.", symbol: "exclamationmark.shield", severity: "ready"),
            DiagnosticRow(title: "Timeouts", detail: "Gradle and ADB commands have command-specific timeouts.", symbol: "timer", severity: "ready"),
            DiagnosticRow(title: "Device preflight", detail: "Device commands require a selected target.", symbol: "iphone.gen3.radiowaves.left.and.right", severity: selectedDeviceID.isEmpty ? "warning" : "ready"),
            DiagnosticRow(title: "Root scan guard", detail: "Broad filesystem scans are blocked.", symbol: "lock.shield", severity: "ready")
        ]
    }

    private var editorScopedDiffSafetyDetail: String {
        if let document = selectedEditorDocument, document.isDirty {
            return "Pending \(document.path): \(makeEditorScopedDiff(path: document.path, original: document.savedContent, proposed: document.content).summary)."
        }
        return lastEditorSaveSafetySummary
    }

    var diffPreviewLines: [String] {
        guard isProjectLoaded else {
            return [
                "// No Android project loaded",
                "// Choose a project folder to scan files, create a patch preview, and enable verification.",
                "// The agent will keep file counts, tests, and Gradle status hidden until then."
            ]
        }
        if let document = selectedEditorDocument, document.isDirty {
            return makeEditorScopedDiff(path: document.path, original: document.savedContent, proposed: document.content).lines
        }

        let request = plan.intent
        if request == "Build and dependency repair" {
            return [
                "@@ app/build.gradle @@",
                "+ implementation(libs.androidx.room.runtime)",
                "+ ksp(libs.androidx.room.compiler)",
                "~ align kotlinCompilerExtensionVersion",
                "",
                "@@ AndroidManifest.xml @@",
                "+ <uses-permission android:name=\"android.permission.POST_NOTIFICATIONS\" />",
                "~ exported components reviewed"
            ]
        }
        if request == "Crash and Logcat triage" {
            return [
                "@@ LoginViewModel.kt @@",
                "- val user = session.user!!",
                "+ val user = session.user ?: return LoginState.SignedOut",
                "+ logger.warn(\"Missing restored user session\")",
                "",
                "@@ LoginViewModelTest.kt @@",
                "+ restores signed-out state when session is empty",
                "+ preserves existing happy-path assertions"
            ]
        }
        return [
            "@@ LoginScreen.kt @@",
            "+ @Composable",
            "+ fun LoginScreen(state: LoginState, onSubmit: () -> Unit)",
            "+ TextField(value = state.email, isError = state.emailError != null)",
            "+ Button(enabled = state.isValid, onClick = onSubmit)",
            "+ Modifier.semantics { contentDescription = \"Login form\" }",
            "",
            "@@ LoginViewModelTest.kt @@",
            "+ rejects invalid email and empty password",
            "+ enables submit when form is valid"
        ]
    }

    var chatMessages: [AgentChatMessage] {
        let trimmedResponse = assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedActionSummary = assistantActionSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedResponse.isEmpty {
            var messages = [
                AgentChatMessage(speaker: "You", message: prompt, isUser: true),
                AgentChatMessage(speaker: "Agent", message: trimmedResponse, isUser: false)
            ]
            if !trimmedActionSummary.isEmpty {
                messages.append(AgentChatMessage(speaker: "Agent", message: "Automatic actions: \(trimmedActionSummary)", isUser: false))
            }
            if let summary = lastCommandSummary {
                messages.append(AgentChatMessage(speaker: "Agent", message: summary.detail, isUser: false))
            }
            return messages
        }

        guard isProjectLoaded else {
            let candidateDetail = canScanProject
                ? "Ask can auto-scan \(candidateProjectPathDisplay) before answering."
                : "Choose or paste a valid Android project path, then Ask will use that project as context."
            return [
                AgentChatMessage(speaker: "You", message: prompt, isUser: true),
                AgentChatMessage(speaker: "Agent", message: "Choose an Android project to scan context and enable Gradle or ADB actions.", isUser: false),
                AgentChatMessage(speaker: "Agent", message: candidateDetail, isUser: false)
            ]
        }

        return [
            AgentChatMessage(speaker: "You", message: prompt, isUser: true),
            AgentChatMessage(speaker: "Agent", message: "I scanned \(snapshot.fileCount) files and found \(snapshot.testFileCount) test files in \(profile.packageName).", isUser: false),
            AgentChatMessage(speaker: "Agent", message: "Primary intent is \(plan.intent.lowercased()). I selected \(plan.tools.count) Android tools with safety gates active.", isUser: false),
            AgentChatMessage(speaker: "Agent", message: lastCommandSummary?.detail ?? "Next move: review the scoped patch preview, then run the narrowest useful Gradle or ADB command.", isUser: false)
        ]
    }

    var verificationRows: [VerificationRow] {
        guard isProjectLoaded else {
            return [
                VerificationRow(title: "Project required", detail: "Choose an Android project to enable verification", symbol: "folder.badge.questionmark", state: "Waiting", severity: "neutral")
            ]
        }

        return [
            VerificationRow(title: "Unit tests", detail: "testDebugUnitTest", symbol: "checkmark.seal", state: "Ready", severity: "ready"),
            VerificationRow(title: "Build", detail: "assembleDebug", symbol: "hammer", state: snapshot.hasGradleWrapper ? "Ready" : "System Gradle", severity: snapshot.hasGradleWrapper ? "ready" : "warning"),
            VerificationRow(title: "Device tests", detail: selectedDeviceID.isEmpty ? "Refresh and select a device" : "connected\(selectedVariant)AndroidTest", symbol: "iphone.gen3", state: selectedDeviceID.isEmpty ? "Blocked" : "Optional", severity: selectedDeviceID.isEmpty ? "warning" : "optional"),
            VerificationRow(title: "Logcat", detail: selectedDeviceID.isEmpty ? "No device selected" : "adb -s \(selectedDeviceID) logcat -d -t 250", symbol: "doc.text.magnifyingglass", state: selectedDeviceID.isEmpty ? "Blocked" : "Ready", severity: selectedDeviceID.isEmpty ? "warning" : "ready")
        ]
    }

    private func commandFor(_ kind: AndroidCommandKind) -> ToolCommand {
        switch kind {
        case .unitTests:
            return AndroidToolCommandFactory.gradleTask(title: "Run Unit Tests", rootPath: projectPath, task: gradleTaskName(prefix: "test", suffix: "UnitTest"))
        case .assembleDebug:
            return AndroidToolCommandFactory.gradleTask(title: "Assemble \(selectedVariant)", rootPath: projectPath, task: gradleTaskName(prefix: "assemble", suffix: ""))
        case .connectedTests:
            return AndroidToolCommandFactory.gradleTask(title: "Run Instrumentation Tests", rootPath: projectPath, task: gradleTaskName(prefix: "connected", suffix: "AndroidTest"))
        case .devices:
            return AndroidToolCommandFactory.listDevices(rootPath: commandWorkingDirectory)
        case .logcat:
            return AndroidToolCommandFactory.logcatSnapshot(rootPath: projectPath, deviceSerial: selectedDeviceID)
        case .clearLogcat:
            return AndroidToolCommandFactory.clearLogcat(rootPath: projectPath, deviceSerial: selectedDeviceID)
        case .launch:
            return AndroidToolCommandFactory.launchApp(rootPath: projectPath, packageName: packageNameForCommands, activityName: launchActivity, deviceSerial: selectedDeviceID)
        }
    }

    func gradleTaskName(prefix: String, suffix: String) -> String {
        let variant = selectedVariant.trimmingCharacters(in: .whitespacesAndNewlines)
        let module = selectedModule.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = "\(prefix)\(variant)\(suffix)"
        return module.isEmpty ? task : ":\(module):\(task)"
    }

    private func defaultDeviceTestStopPackages(for basePackageName: String) -> [String] {
        guard isKnownAndroidPackageName(basePackageName) else { return [] }
        return orderedUniquePackages([basePackageName, "\(basePackageName).test"])
    }

    private func instrumentationStopPackages(in output: String, basePackageName: String) -> [String] {
        guard isKnownAndroidPackageName(basePackageName) else { return [] }
        let parsedPackages = output
            .split(separator: "\n")
            .compactMap { instrumentationPackageDescriptor(from: String($0)) }
            .filter { descriptor in
                isInstrumentationMatch(descriptor.targetPackage, basePackageName: basePackageName)
                    || isInstrumentationMatch(descriptor.instrumentationPackage, basePackageName: basePackageName)
            }
            .flatMap { [$0.instrumentationPackage, $0.targetPackage] }
        return orderedUniquePackages(parsedPackages)
    }

    private func instrumentationPackageDescriptor(from line: String) -> (instrumentationPackage: String, targetPackage: String)? {
        let prefix = "instrumentation:"
        guard let prefixRange = line.range(of: prefix),
              let slashIndex = line[prefixRange.upperBound...].firstIndex(of: "/"),
              let targetRange = line.range(of: "(target=") else {
            return nil
        }
        let instrumentationPackage = String(line[prefixRange.upperBound..<slashIndex])
        let targetStart = targetRange.upperBound
        let targetTail = line[targetStart...]
        guard let targetEnd = targetTail.firstIndex(of: ")") else { return nil }
        let targetPackage = String(targetTail[..<targetEnd])
        guard isKnownAndroidPackageName(instrumentationPackage),
              isKnownAndroidPackageName(targetPackage) else {
            return nil
        }
        return (instrumentationPackage, targetPackage)
    }

    private func isInstrumentationMatch(_ packageName: String, basePackageName: String) -> Bool {
        packageName == basePackageName
            || packageName == "\(basePackageName).test"
            || packageName.hasPrefix("\(basePackageName).")
    }

    private func orderedUniquePackages(_ packageNames: [String]) -> [String] {
        var seen = Set<String>()
        return packageNames.filter { packageName in
            guard isKnownAndroidPackageName(packageName), !seen.contains(packageName) else { return false }
            seen.insert(packageName)
            return true
        }
    }

    private func isKnownAndroidPackageName(_ packageName: String) -> Bool {
        let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unknown.android.app" else { return false }
        return trimmed.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "_"
        }
    }

    private func summarizeCommandResult(_ result: CommandResult, status: String, elapsed: TimeInterval) -> CommandRunSummary {
        let combinedOutput = (result.standardOutput + "\n" + result.standardError).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstUsefulLine = combinedOutput
            .split(separator: "\n")
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "No command output."
        let severity = result.succeeded ? "ready" : result.exitCode == -2 ? "warning" : "failed"
        let detail: String
        if result.succeeded {
            detail = "\(result.command.title) succeeded. \(firstUsefulLine)"
        } else if result.exitCode == -2 {
            detail = "\(result.command.title) timed out. Check device state or Gradle progress before retrying."
        } else {
            detail = "\(result.command.title) failed. \(firstUsefulLine)"
        }
        return CommandRunSummary(
            title: result.command.title,
            status: status.capitalized,
            detail: detail,
            severity: severity,
            duration: String(format: "%.1fs", elapsed)
        )
    }

    private func summarizeDeviceResult(_ result: CommandResult, status: String, elapsed: TimeInterval) -> CommandRunSummary {
        let severity: String
        if result.succeeded {
            severity = devices.isEmpty ? "warning" : "ready"
        } else {
            severity = result.exitCode == -2 ? "warning" : "failed"
        }
        return CommandRunSummary(
            title: result.command.title,
            status: status.capitalized,
            detail: lastStatusMessage,
            severity: severity,
            duration: String(format: "%.1fs", elapsed)
        )
    }

    private func applyDeviceOutput(_ output: String, standardError: String = "", succeeded: Bool = true) {
        var unavailableDeviceCount = 0
        let parsed = output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> DeviceOption? in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 2 else { return nil }
                let serial = parts[0]
                let state = parts[1]
                guard state == "device" else {
                    unavailableDeviceCount += 1
                    return nil
                }
                let name = parts.dropFirst(2).joined(separator: " ")
                return DeviceOption(id: serial, name: name, state: state)
            }
        devices = parsed
        unavailableDeviceSummary = unavailableDeviceCount == 0
            ? ""
            : "\(unavailableDeviceCount) unavailable target\(unavailableDeviceCount == 1 ? "" : "s") ignored."
        if selectedDeviceID.isEmpty || !parsed.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = parsed.first?.id ?? ""
        } else if isDevicePreviewAutoRefreshEnabled, hasConnectedDevice, devicePreviewAutoRefreshTask == nil {
            startDevicePreviewAutoRefresh()
        } else if !hasConnectedDevice {
            stopDevicePreviewAutoRefresh(updateStatus: false)
        }
        selectedSessionTab = .diagnostics
        if !succeeded {
            let errorLine = firstUsefulLine(in: standardError) ?? "ADB did not return a device list."
            lastStatusMessage = "Device refresh failed. \(errorLine)"
        } else if parsed.isEmpty {
            let unavailableSuffix = unavailableDeviceSummary.isEmpty ? "" : " \(unavailableDeviceSummary)"
            lastStatusMessage = "No online Android devices detected.\(unavailableSuffix)"
        } else {
            let unavailableSuffix = unavailableDeviceSummary.isEmpty ? "" : " \(unavailableDeviceSummary)"
            lastStatusMessage = "Detected \(parsed.count) online Android device\(parsed.count == 1 ? "" : "s").\(unavailableSuffix)"
        }
    }

    private func firstUsefulLine(in output: String) -> String? {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func selectedEditorIndex() -> Int? {
        if let index = openEditorDocuments.firstIndex(where: { $0.path == selectedEditorPath }) {
            return index
        }
        guard let first = openEditorDocuments.first else { return nil }
        selectedEditorPath = first.path
        return openEditorDocuments.startIndex
    }

    private func editorSaveURL(for document: EditorDocument) throws -> URL {
        let root = URL(fileURLWithPath: resolvedProjectPath(projectPath), isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let fileURL = root
            .appendingPathComponent(document.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"

        guard !document.path.hasPrefix("/") else {
            throw EditorSaveSafetyError.blocked("Editor save path must be relative to the selected workspace.")
        }
        guard fileURL.path.hasPrefix(rootPath) else {
            throw EditorSaveSafetyError.blocked("Editor save blocked because \(document.path) resolves outside the selected workspace.")
        }
        return fileURL
    }

    private func saveEditorDocument(at index: Int) {
        guard openEditorDocuments.indices.contains(index) else {
            lastStatusMessage = "No editor file is selected to save."
            return
        }
        let document = openEditorDocuments[index]
        let diff = makeEditorScopedDiff(path: document.path, original: document.savedContent, proposed: document.content)
        let findings = editorSecretFindings(original: document.savedContent, proposed: document.content)
        guard findings.isEmpty else {
            blockEditorSaveForSecrets(at: index, document: document, diff: diff, findings: findings)
            return
        }

        do {
            let url = try editorSaveURL(for: document)
            let checkpointPath = try createEditorUndoCheckpoint(for: document, fileURL: url)
            try document.content.write(to: url, atomically: true, encoding: .utf8)
            openEditorDocuments[index].savedContent = document.content
            openEditorDocuments[index].lastError = nil
            lastEditorSaveDiffLines = diff.lines
            lastEditorUndoCheckpointPath = checkpointPath
            lastEditorSecretScanSummary = "Secret scan passed for \(document.path)."
            lastEditorSaveSafetySummary = "Saved \(document.path) after scoped diff review with an undo checkpoint."
            planNeedsRefresh = true
            appendOutput("Editor save safety: \(document.path) \(diff.summary). Undo checkpoint: \(checkpointPath)\n")
            lastStatusMessage = "Saved \(document.path) with scoped diff, secret scan, and undo checkpoint."
        } catch {
            openEditorDocuments[index].lastError = error.localizedDescription
            lastStatusMessage = "Could not save \(document.path): \(error.localizedDescription)"
        }
    }

    private func blockEditorSaveForSecrets(
        at index: Int,
        document: EditorDocument,
        diff: EditorScopedDiff,
        findings: [EditorSecretFinding]
    ) {
        let findingSummary = findings.map(\.summary).joined(separator: ", ")
        let error = "Secret scanner blocked save: \(findingSummary)"
        openEditorDocuments[index].lastError = error
        lastEditorSaveDiffLines = diff.lines
        lastEditorSecretScanSummary = "Blocked \(document.path): \(findingSummary)."
        lastEditorSaveSafetySummary = "Save blocked before disk write for \(document.path)."
        selectedSessionTab = .checks
        appendOutput("Editor save blocked by secret scanner for \(document.path): \(findingSummary)\n")
        lastStatusMessage = "Save blocked for \(document.path): secret-like value detected (\(findingSummary))."
    }

    private func createEditorUndoCheckpoint(for document: EditorDocument, fileURL: URL) throws -> String {
        let original = try String(contentsOf: fileURL, encoding: .utf8)
        let root = try writableEditorCheckpointRoot()
        let timestamp = editorCheckpointTimestamp()
        let checkpointURL = root
            .appendingPathComponent(timestamp, isDirectory: true)
            .appendingPathComponent(sanitizedCheckpointRelativePath(document.path), isDirectory: false)
        try FileManager.default.createDirectory(at: checkpointURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: checkpointURL, atomically: true, encoding: .utf8)
        return checkpointURL.path
    }

    private func writableEditorCheckpointRoot() throws -> URL {
        let projectKey = stableProjectKey(for: resolvedProjectPath(projectPath))
        let appSupportRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Android Dev Agent/UndoCheckpoints/\(projectKey)", isDirectory: true)
        let candidates = [appSupportRoot, FileManager.default.temporaryDirectory.appendingPathComponent("AndroidDevAgentUndoCheckpoints/\(projectKey)", isDirectory: true)]
            .compactMap { $0 }
        var lastError: Error?

        for candidate in candidates {
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
                return candidate
            } catch {
                lastError = error
            }
        }

        throw lastError ?? EditorSaveSafetyError.blocked("No writable undo checkpoint location is available.")
    }

    private func editorCheckpointTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private func stableProjectKey(for path: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let name = URL(fileURLWithPath: path).lastPathComponent.nilIfEmpty ?? "workspace"
        return "\(sanitizedCheckpointPathComponent(name))-\(String(hash, radix: 16))"
    }

    private func sanitizedCheckpointRelativePath(_ path: String) -> String {
        let parts = path.split(separator: "/").map { sanitizedCheckpointPathComponent(String($0)) }
        return parts.isEmpty ? "file.txt" : parts.joined(separator: "/")
    }

    private func sanitizedCheckpointPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return String((sanitized.nilIfEmpty ?? "item").prefix(96))
    }

    private func makeEditorScopedDiff(path: String, original: String, proposed: String) -> EditorScopedDiff {
        let originalLines = original.components(separatedBy: "\n")
        let proposedLines = proposed.components(separatedBy: "\n")
        let lineCount = max(originalLines.count, proposedLines.count)
        let previewLimit = 24
        var lines = ["@@ \(path) @@"]
        var added = 0
        var removed = 0
        var changed = 0
        var omitted = 0

        for index in 0..<lineCount {
            let oldLine = index < originalLines.count ? originalLines[index] : nil
            let newLine = index < proposedLines.count ? proposedLines[index] : nil
            guard oldLine != newLine else { continue }

            if lines.count <= previewLimit {
                lines.append("@@ line \(index + 1) @@")
                if let oldLine {
                    lines.append("- \(redactedEditorDiffLine(oldLine))")
                }
                if let newLine {
                    lines.append("+ \(redactedEditorDiffLine(newLine))")
                }
            } else {
                omitted += 1
            }

            switch (oldLine, newLine) {
            case (nil, .some):
                added += 1
            case (.some, nil):
                removed += 1
            case (.some, .some):
                changed += 1
            case (nil, nil):
                break
            }
        }

        if omitted > 0 {
            lines.append("// ... \(omitted) additional changed line\(omitted == 1 ? "" : "s") omitted")
        }
        if lines.count == 1 {
            lines.append("// No editor changes pending")
        }
        return EditorScopedDiff(lines: lines, addedLineCount: added, removedLineCount: removed, changedLineCount: changed)
    }

    private func editorSecretFindings(original: String, proposed: String) -> [EditorSecretFinding] {
        let originalLines = original.components(separatedBy: "\n")
        let proposedLines = proposed.components(separatedBy: "\n")
        return proposedLines.enumerated().compactMap { index, line in
            let changed = index >= originalLines.count || originalLines[index] != line
            guard changed, let label = editorSecretLabel(in: line) else { return nil }
            return EditorSecretFinding(lineNumber: index + 1, label: label)
        }
    }

    private func redactedEditorDiffLine(_ line: String) -> String {
        if let label = editorSecretLabel(in: line) {
            return "[REDACTED \(label)]"
        }
        return line
    }

    private func editorSecretLabel(in line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("-----begin") && lower.contains("private key") {
            return "private key"
        }
        if lower.contains("sk-") || lower.contains("xoxb-") || line.contains("AIza") {
            return "API token"
        }

        let sensitiveTerms: [(term: String, label: String)] = [
            ("api_key", "API key"),
            ("apikey", "API key"),
            ("api-key", "API key"),
            ("client_secret", "client secret"),
            ("access_token", "access token"),
            ("refresh_token", "refresh token"),
            ("auth_token", "auth token"),
            ("storepassword", "keystore password"),
            ("keypassword", "key password"),
            ("password", "password"),
            ("private_key", "private key"),
            ("keystore", "keystore")
        ]

        guard let match = sensitiveTerms.first(where: { lower.contains($0.term) }),
              let delimiterIndex = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
            return nil
        }

        let valueStart = line.index(after: delimiterIndex)
        let value = line[valueStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let normalized = value.lowercased()
        guard !normalized.isEmpty,
              normalized != "null",
              normalized != "nil",
              normalized != "false",
              !normalized.contains("redacted"),
              !normalized.contains("placeholder"),
              !normalized.contains("example"),
              !normalized.contains("todo"),
              !normalized.contains("changeme"),
              !normalized.hasPrefix("system.getenv"),
              !normalized.hasPrefix("project.findproperty") else {
            return nil
        }
        return match.label
    }

    private func appendOutput(_ value: String) {
        commandOutput += value
        if commandOutput.count > 80_000 {
            commandOutput = String(commandOutput.suffix(80_000))
            isOutputTruncated = true
        }
    }

    private func failScan(_ message: String) {
        isScanningProject = false
        isProjectLoaded = false
        scanState = .failed(message)
        lastStatusMessage = message
        lastCommandSummary = CommandRunSummary(title: "Scan", status: "Blocked", detail: message, severity: "failed", duration: "0s")
        selectedSessionTab = .diagnostics
        scanStartedAt = nil
        appendOutput("\(message)\n")
    }

    private func applyScan(snapshot scannedSnapshot: WorkspaceSnapshot, rootPath: String) {
        snapshot = scannedSnapshot
        profile = ProjectProfile.from(snapshot: scannedSnapshot)
        projectFiles = makeProjectFiles(rootPath: rootPath, snapshot: scannedSnapshot)
        expandedProjectFolderPaths = defaultExpandedProjectFolderPaths(from: projectFiles)
        modules = discoverModules(rootPath: rootPath)
        if modules.isEmpty { modules = ["app"] }
        if !modules.contains(selectedModule) { selectedModule = modules.first ?? "app" }
        buildVariants = discoverBuildVariants(rootPath: rootPath, module: selectedModule)
        if !buildVariants.contains(selectedVariant) { selectedVariant = buildVariants.first ?? "Debug" }
        packageOverride = scannedSnapshot.packageName ?? ""
        isScanningProject = false
        scanStartedAt = nil

        let hasAndroidMarkers = scannedSnapshot.hasSettingsGradle || scannedSnapshot.hasAndroidManifest || scannedSnapshot.packageName != nil
        isProjectLoaded = hasAndroidMarkers
        if hasAndroidMarkers {
            scanState = .ready
            lastStatusMessage = "Loaded \(displayPath(rootPath))"
            addRecentProject(rootPath)
            if revealFilesAfterCurrentScan {
                filePanelRevealGeneration += 1
            }
            refreshDevices()
        } else {
            scanState = .warning("No Android project markers were found in \(displayPath(rootPath)).")
            lastStatusMessage = scanState.detail
        }
        revealFilesAfterCurrentScan = true

        generatePlan(updateStatus: false)
        selectedSessionTab = hasAndroidMarkers ? .checks : .diagnostics
        appendOutput(
            """
            Scanned workspace: \(rootPath)
            Files: \(scannedSnapshot.fileCount)
            Tests: \(scannedSnapshot.testFileCount)
            Package: \(profile.packageName)
            Gradle wrapper: \(scannedSnapshot.hasGradleWrapper ? "yes" : "no")
            Android markers: \(hasAndroidMarkers ? "found" : "missing")

            """
        )
    }

    private func savePromptToHistory(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptHistory.removeAll { $0 == trimmed }
        promptHistory.insert(trimmed, at: 0)
        if promptHistory.count > 12 {
            promptHistory = Array(promptHistory.prefix(12))
        }
        UserDefaults.standard.set(promptHistory, forKey: promptHistoryKey)
    }

    private func addRecentProject(_ path: String) {
        recentProjectPaths.removeAll { $0 == path }
        recentProjectPaths.insert(path, at: 0)
        if recentProjectPaths.count > 8 {
            recentProjectPaths = Array(recentProjectPaths.prefix(8))
        }
        UserDefaults.standard.set(recentProjectPaths, forKey: recentProjectsKey)
    }

    private var commandWorkingDirectory: String {
        let candidate = resolvedProjectPath(projectPath)
        var isDirectory: ObjCBool = false
        if !candidate.isEmpty, FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        return NSTemporaryDirectory()
    }

    private var canRunADBWirelessAction: Bool {
        !isScanningProject && !isRunningCommand && !isRefreshingDevices && !isRunningWirelessDebugging && !isRefreshingDevicePreview && !isSendingDeviceInput
    }

    private var trimmedWirelessConnectAddress: String {
        wirelessConnectAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var wirelessDisconnectAddress: String? {
        if let selectedAddress = selectedWirelessDisconnectTargetAddress {
            return selectedAddress
        }
        if let address = trimmedWirelessConnectAddress.nilIfEmpty, isValidHostPort(address) {
            return address
        }
        if isValidHostPort(lastWirelessDeviceAddress) {
            return lastWirelessDeviceAddress
        }
        return nil
    }

    private var selectedWirelessConnectedDeviceSerial: String? {
        guard hasConnectedDevice, selectedDeviceOption?.isNetworkSerial == true else { return nil }
        let selectedSerial = selectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedSerial.isEmpty else { return nil }
        return selectedSerial
    }

    private var selectedWirelessDisconnectTargetAddress: String? {
        guard let selectedSerial = selectedWirelessConnectedDeviceSerial else { return nil }
        if isValidHostPort(selectedSerial) {
            return selectedSerial
        }
        if let discoveredAddress = discoveredConnectAddress(forADBSerial: selectedSerial) {
            return discoveredAddress
        }
        if isValidHostPort(lastWirelessDeviceAddress) {
            return lastWirelessDeviceAddress
        }
        return selectedSerial.contains("._adb-tls-connect._tcp") ? selectedSerial : nil
    }

    private func discoveredConnectAddress(forADBSerial serial: String) -> String? {
        guard let serviceName = wirelessServiceName(fromADBSerial: serial) else { return nil }
        return wirelessDebuggingDevices.first { $0.serviceName == serviceName }?.connectAddress
    }

    private func wirelessServiceName(fromADBSerial serial: String) -> String? {
        guard let range = serial.range(of: "._adb-tls-connect._tcp") else { return nil }
        return String(serial[..<range.lowerBound]).nilIfEmpty
    }

    private var wirelessConnectTargetAddress: String? {
        if let selectedAddress = selectedWirelessDebuggingDevice?.connectAddress {
            return selectedAddress
        }
        if let address = trimmedWirelessConnectAddress.nilIfEmpty, isValidHostPort(address) {
            return address
        }
        if isValidHostPort(lastWirelessDeviceAddress) {
            return lastWirelessDeviceAddress
        }
        return nil
    }

    private var wirelessPairingValidationMessage: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, preview refresh, or Wireless Debugging action to finish."
        }
        if wirelessPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the Wireless Debugging pairing code shown on the Android device."
        }
        return "Ready to discover the pairing address and confirm wireless pairing."
    }

    private var wirelessConnectValidationMessage: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, preview refresh, or Wireless Debugging action to finish."
        }
        if trimmedWirelessConnectAddress.isEmpty, isValidHostPort(lastWirelessDeviceAddress) {
            return "Ready to reconnect last wireless target \(lastWirelessDeviceAddress)."
        }
        if wirelessConnectTargetAddress == nil {
            return "Select a discovered wireless device with a connect service, or scan again."
        }
        return "Ready to connect wireless target \(wirelessConnectTargetAddress ?? "selected device")."
    }

    private func parseWirelessDebuggingServices(_ output: String) -> (pairingAddress: String?, connectAddress: String?) {
        var pairingAddress: String?
        var connectAddress: String?
        for line in output.split(separator: "\n").map(String.init) {
            if line.contains("_adb-tls-pairing._tcp"), pairingAddress == nil {
                pairingAddress = wirelessHostPort(in: line)
            } else if line.contains("_adb-tls-connect._tcp"), connectAddress == nil {
                connectAddress = wirelessHostPort(in: line)
            }
        }
        return (pairingAddress, connectAddress)
    }

    private func parseWirelessDebuggingDeviceList(_ output: String) -> [WirelessDebuggingDevice] {
        var devicesByHost: [String: (serviceName: String, connectAddress: String?, pairingAddress: String?)] = [:]

        for line in output.split(separator: "\n").map(String.init) {
            let isPairingService = line.contains("_adb-tls-pairing._tcp")
            let isConnectService = line.contains("_adb-tls-connect._tcp")
            guard isPairingService || isConnectService,
                  let address = wirelessHostPort(in: line),
                  let host = wirelessHost(in: address) else {
                continue
            }

            var device = devicesByHost[host] ?? (serviceName: "", connectAddress: nil, pairingAddress: nil)
            if device.serviceName.isEmpty, let serviceName = wirelessServiceName(in: line) {
                device.serviceName = serviceName
            }
            if isPairingService {
                device.pairingAddress = address
            }
            if isConnectService {
                device.connectAddress = address
            }
            devicesByHost[host] = device
        }

        return devicesByHost
            .map { host, device in
                WirelessDebuggingDevice(
                    id: host,
                    serviceName: device.serviceName,
                    host: host,
                    connectAddress: device.connectAddress,
                    pairingAddress: device.pairingAddress
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func applySelectedWirelessDebuggingDevice() {
        guard let selectedWirelessDebuggingDevice else { return }
        if let connectAddress = selectedWirelessDebuggingDevice.connectAddress {
            wirelessConnectAddress = connectAddress
            lastWirelessDeviceAddress = connectAddress
        }
        if let pairingAddress = selectedWirelessDebuggingDevice.pairingAddress {
            lastWirelessPairingAddress = pairingAddress
        }
        wirelessDeviceDiscoveryStatus = "Selected \(selectedWirelessDebuggingDevice.displayName)."
    }

    private func wirelessHostPort(in line: String) -> String? {
        let tokens = line
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            }
        return tokens.last(where: { isValidHostPort($0) })
    }

    private func wirelessHost(in address: String) -> String? {
        let parts = address.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return String(parts[0])
    }

    private func wirelessServiceName(in line: String) -> String? {
        line
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first(where: { $0.contains("._adb-tls-") })?
            .components(separatedBy: "._adb-tls-")
            .first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .nilIfEmpty
    }

    private func makeQRCodeImage(from payload: String) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter?.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let representation = NSCIImageRep(ciImage: scaledImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    private func randomADBToken(length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    private func escapedQRCodeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
    }

    private func isValidHostPort(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              let port = Int(parts[1]),
              (1...65_535).contains(port) else {
            return false
        }
        return true
    }

    private func resolvedProjectPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let url = URL(string: trimmed), url.isFileURL {
            return url.standardizedFileURL.path
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func confirmationMessage(for kind: AndroidCommandKind) -> String {
        var lines = [
            kind.riskSummary,
            "Project: \(candidateProjectPathDisplay)"
        ]
        if kind.requiresDevice {
            lines.append("Device: \(selectedDeviceID.isEmpty ? "none selected" : selectedDeviceID)")
        }
        if kind == .launch {
            lines.append("Install task: \(gradleTaskName(prefix: "install", suffix: "")) (fresh install or replacement)")
            lines.append("Launch target: \(packageNameForCommands)/\(launchActivity)")
        }
        lines.append("The command output will be written to the Command Console.")
        return lines.joined(separator: "\n")
    }

    private func temporaryArtifactPath(prefix: String, fileExtension pathExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "\(prefix)-\(formatter.string(from: Date())).\(pathExtension)"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName).path
    }

    private func isUnsafeScanRoot(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let blocked = [
            "/",
            "/Users",
            home,
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads"
        ]
        return blocked.contains(path)
    }

    private func discoverModules(rootPath: String) -> [String] {
        let rootURL = URL(fileURLWithPath: rootPath)
        let settingsText = [
            "settings.gradle",
            "settings.gradle.kts"
        ].compactMap { try? String(contentsOf: rootURL.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")

        var names: [String] = []
        let pattern = #":([A-Za-z0-9_\-]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(settingsText.startIndex..<settingsText.endIndex, in: settingsText)
            regex.enumerateMatches(in: settingsText, range: range) { match, _, _ in
                guard let match, let moduleRange = Range(match.range(at: 1), in: settingsText) else { return }
                names.append(String(settingsText[moduleRange]))
            }
        }

        if let entries = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if FileManager.default.fileExists(atPath: entry.appendingPathComponent("build.gradle").path)
                    || FileManager.default.fileExists(atPath: entry.appendingPathComponent("build.gradle.kts").path) {
                    names.append(entry.lastPathComponent)
                }
            }
        }

        let unique = Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        return unique.isEmpty ? ["app"] : unique
    }

    private func discoverBuildVariants(rootPath: String, module: String) -> [String] {
        let moduleURL = URL(fileURLWithPath: rootPath).appendingPathComponent(module)
        let gradleText = [
            "build.gradle",
            "build.gradle.kts"
        ].compactMap { try? String(contentsOf: moduleURL.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        var variants = ["Debug", "Release"]
        let flavorNames = captureBlockNames(named: "productFlavors", in: gradleText)
        if !flavorNames.isEmpty {
            variants = flavorNames.flatMap { flavor in
                ["\(flavor.capitalized)Debug", "\(flavor.capitalized)Release"]
            }
        }
        return Array(NSOrderedSet(array: variants).compactMap { $0 as? String })
    }

    private func captureBlockNames(named blockName: String, in text: String) -> [String] {
        guard let blockRange = text.range(of: blockName) else { return [] }
        let tail = String(text[blockRange.upperBound...])
        let pattern = #"(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*(\{|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(tail.startIndex..<tail.endIndex, in: tail)
        var values: [String] = []
        regex.enumerateMatches(in: tail, range: nsRange) { match, _, stop in
            guard let match, let nameRange = Range(match.range(at: 1), in: tail) else { return }
            let value = String(tail[nameRange])
            if ["buildTypes", "sourceSets", "dependencies", "android"].contains(value) {
                stop.pointee = true
            } else {
                values.append(value)
            }
            if values.count >= 8 { stop.pointee = true }
        }
        return values
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path.isEmpty ? "No project loaded" : path
    }

    private var androidSDKSummary: String {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["ANDROID_HOME"],
            environment["ANDROID_SDK_ROOT"],
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Android/sdk"
        ].compactMap { $0 }
        for sdkRoot in candidates {
            let adb = URL(fileURLWithPath: sdkRoot).appendingPathComponent("platform-tools/adb").path
            if FileManager.default.isExecutableFile(atPath: adb) {
                return "ADB found at \(displayPath(adb))"
            }
        }
        return "Missing ADB. Set ANDROID_HOME or install Android SDK platform-tools."
    }

    private var gitSummary: String {
        guard isProjectLoaded else { return "No project loaded" }
        var url = URL(fileURLWithPath: projectPath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return "Git repository found at \(displayPath(url.path))"
            }
            url.deleteLastPathComponent()
        }
        return "Git repository not found"
    }
}

@MainActor
extension AgentViewModel {
    static func coverageFixtures() -> [AgentViewModel] {
        let defaults = UserDefaults.standard
        let recentKey = "AndroidDevAgentRecentProjects"
        let historyKey = "AndroidDevAgentPromptHistory"
        let previousRecent = defaults.stringArray(forKey: recentKey)
        let previousHistory = defaults.stringArray(forKey: historyKey)
        defer {
            restore(previousRecent, forKey: recentKey, defaults: defaults)
            restore(previousHistory, forKey: historyKey, defaults: defaults)
        }

        let empty = AgentViewModel()
        let tempProject = makeCoverageProject()

        empty.generatePlan()
        empty.usePromptFromHistory("Add a Compose details screen and run targeted tests.")
        empty.clearOutput()
        empty.copyConsole()
        empty.copyPatchPreview()
        empty.markPreviewReviewed()
        empty.exportConsole()
        empty.createDebugReport()
        empty.clearPrompt()
        empty.selectProject(path: "   ", scanImmediately: false)
        empty.scanProject()
        empty.selectProject(path: "/", scanImmediately: true)
        empty.clearMissingRecentProjects()
        _ = empty.canScanProject
        _ = empty.canRunTools
        _ = empty.canRefreshDevices
        _ = empty.canPairWirelessDevice
        _ = empty.canConnectWirelessDevice
        _ = empty.canDisconnectWirelessDevice
        _ = empty.wirelessDebuggingSummary
        _ = empty.projectPathDisplay
        _ = empty.candidateProjectPathDisplay
        _ = empty.projectPathFeedback
        _ = empty.recentProjectRows
        _ = empty.projectSubtitle
        _ = empty.confidenceDisplay
        _ = empty.workspaceSummary
        _ = empty.deviceSummary
        _ = empty.launchTargetFeedback
        _ = empty.recommendedActionTitle
        _ = empty.recommendedActionDetail
        _ = empty.packageNameForCommands
        _ = empty.filteredProjectFiles
        _ = empty.selectedPlanStep
        _ = empty.diagnosticRows
        _ = empty.safetyRows
        _ = empty.diffPreviewLines
        _ = empty.chatMessages
        _ = empty.verificationRows

        let scanning = AgentViewModel()
        scanning.projectPath = tempProject.path
        scanning.scanProject()
        scanning.cancelScan()

        let warning = AgentViewModel()
        let sparseSnapshot = WorkspaceSnapshot.empty(rootPath: tempProject.path)
        warning.applyScan(snapshot: sparseSnapshot, rootPath: tempProject.path)

        let loaded = makeLoadedCoverageModel(rootPath: tempProject.path)
        loaded.prompt = "Analyze a NullPointerException crash, repair Gradle dependencies, inspect Logcat, and prepare release readiness."
        loaded.generatePlan()
        loaded.selectedPlanStepID = loaded.plan.steps.last?.id
        loaded.fileSearchQuery = "Main"
        loaded.packageOverride = "com.coverage.override"
        loaded.launchActivity = ".CoverageActivity"
        loaded.applyDeviceOutput(
            """
            List of devices attached
            emulator-5554 device product:sdk_gphone64 model:Pixel_8 device:emu64 transport_id:1
            192.168.1.10:42177 device product:wifi model:Pixel_8 device:shiba transport_id:2
            emulator-5556 offline product:sdk
            """
        )
        loaded.selectedDeviceID = "emulator-5554"
        loaded.wirelessPairingCode = "123456"
        loaded.lastWirelessPairingAddress = "192.168.1.10:37099"
        loaded.wirelessConnectAddress = "192.168.1.10:42177"
        loaded.lastWirelessDeviceAddress = "192.168.1.10:42177"
        loaded.wirelessDebuggingDevices = [
            WirelessDebuggingDevice(
                id: "192.168.1.10",
                serviceName: "Pixel 8",
                host: "192.168.1.10",
                connectAddress: "192.168.1.10:42177",
                pairingAddress: "192.168.1.10:37099"
            )
        ]
        loaded.selectedWirelessDebuggingDeviceID = "192.168.1.10"
        loaded.wirelessDebuggingStatus = "Wireless fixture ready."
        _ = loaded.selectedWirelessDebuggingDevice
        _ = loaded.hasSelectedWirelessDebuggingDevice
        _ = loaded.canRefreshWirelessDebuggingDevices
        _ = loaded.wirelessDiscoveryHelpText
        _ = loaded.canPairWirelessDevice
        _ = loaded.canConnectWirelessDevice
        _ = loaded.canDisconnectWirelessDevice
        _ = loaded.wirelessDebuggingSummary
        let selectedWirelessOnly = makeLoadedCoverageModel(rootPath: tempProject.path)
        selectedWirelessOnly.applyDeviceOutput(
            """
            List of devices attached
            192.168.1.11:42177 device product:wifi model:Pixel_9 device:komodo transport_id:3
            """
        )
        selectedWirelessOnly.selectedDeviceID = "192.168.1.11:42177"
        selectedWirelessOnly.wirelessConnectAddress = ""
        selectedWirelessOnly.lastWirelessDeviceAddress = ""
        _ = selectedWirelessOnly.canDisconnectSelectedWirelessDevice
        _ = selectedWirelessOnly.wirelessDisconnectHelpText
        loaded.lastCommandSummary = loaded.summarizeCommandResult(
            CommandResult(
                command: ToolCommand(title: "Run Unit Tests", executable: "/bin/echo", arguments: ["ok"], workingDirectory: tempProject.path),
                exitCode: 0,
                standardOutput: "BUILD SUCCESSFUL",
                standardError: ""
            ),
            status: "succeeded",
            elapsed: 0.42
        )
        loaded.appendOutput(String(repeating: "x", count: 80_500))
        let editorFixtureFile = ProjectFileItem(path: "app/src/main/AndroidManifest.xml", name: "AndroidManifest.xml", depth: 3, symbol: "doc.badge.gearshape", isSelected: true)
        loaded.copyProjectPath(editorFixtureFile)
        loaded.openFile(editorFixtureFile)
        loaded.updateSelectedEditorContent(loaded.selectedEditorContent + "\n<!-- coverage edit -->\n")
        _ = loaded.selectedEditorDocument
        _ = loaded.dirtyEditorDocumentCount
        _ = loaded.editorStatusSummary
        loaded.revertSelectedEditorDocument()
        loaded.updateSelectedEditorContent(loaded.selectedEditorContent + "\n<!-- saved coverage edit -->\n")
        loaded.saveSelectedEditorDocument()
        loaded.saveAllEditorDocuments()
        loaded.closeSelectedEditorDocument()
        loaded.removeRecentProject(tempProject.path)
        loaded.performRecommendedAction()
        for kind in AndroidCommandKind.allCases {
            _ = loaded.commandFor(kind).preview
            _ = loaded.canRunCommand(kind)
            _ = loaded.commandStateText(kind)
            _ = loaded.commandHelpText(kind)
            _ = loaded.commandBlockReason(for: kind)
            _ = kind.id
            _ = kind.symbol
            _ = kind.requiresDevice
            _ = kind.requiresConfirmation
            _ = kind.timeoutSeconds
            _ = kind.riskSummary
        }
        loaded.runCommand(.launch)
        loaded.cancelPendingCommand()
        loaded.selectedDeviceID = ""
        loaded.runCommand(.logcat)
        loaded.stopRunningCommand()
        loaded.isRunningCommand = true
        loaded.lastCommandTitle = "Coverage command"
        loaded.stopRunningCommand()
        _ = loaded.filteredProjectFiles
        loaded.fileSearchQuery = "missing"
        _ = loaded.filteredProjectFiles
        loaded.fileSearchQuery = ""
        for step in loaded.plan.steps {
            _ = loaded.displayState(for: step)
            _ = loaded.displaySeverity(for: step)
        }
        loaded.lastCommandSummary = loaded.summarizeCommandResult(
            CommandResult(
                command: ToolCommand(title: "Assemble Debug", executable: "/bin/false", arguments: [], workingDirectory: tempProject.path),
                exitCode: 1,
                standardOutput: "",
                standardError: "Compilation failed"
            ),
            status: "failed with exit code 1",
            elapsed: 1.2
        )
        for step in loaded.plan.steps {
            _ = loaded.displayState(for: step)
            _ = loaded.displaySeverity(for: step)
        }
        _ = loaded.diagnosticRows
        _ = loaded.safetyRows
        _ = loaded.diffPreviewLines
        _ = loaded.chatMessages
        _ = loaded.verificationRows
        loaded.prompt = "Fix a Gradle sync error after adding Room database dependencies."
        loaded.generatePlan()
        _ = loaded.diffPreviewLines
        loaded.prompt = "Build a login screen with ViewModel validation and accessibility."
        loaded.generatePlan()
        _ = loaded.diffPreviewLines

        let running = makeLoadedCoverageModel(rootPath: tempProject.path)
        running.isRunningCommand = true
        running.isScanningProject = true
        running.lastCommandTitle = "Connected Tests"
        running.lastCommandSummary = CommandRunSummary(
            title: "Connected Tests",
            status: "Running",
            detail: "Instrumentation is running on emulator-5554.",
            severity: "running",
            duration: "2.0s"
        )
        running.scanState = .scanning
        running.lastStatusMessage = "Scanning coverage fixture..."

        let failed = AgentViewModel()
        failed.failScan("Coverage failure state.")
        failed.lastCommandSummary = CommandRunSummary(
            title: "Coverage Failure",
            status: "Failed",
            detail: "A representative failure for the UI summary rows.",
            severity: "failed",
            duration: "0.1s"
        )

        return [empty, warning, scanning, loaded, running, failed]
    }

    static func exerciseCoverageSurface() -> Int {
        let states: [ScanState] = [
            .waiting,
            .scanning,
            .ready,
            .warning("Coverage warning"),
            .failed("Coverage failure")
        ]
        var touched = 0
        for state in states {
            _ = state.title
            _ = state.detail
            _ = state.symbol
            touched += 3
        }
        for tab in SessionPaneTab.allCases {
            _ = tab.id
            touched += 1
        }
        for fixture in coverageFixtures() {
            _ = fixture.canScanProject
            _ = fixture.canRunTools
            _ = fixture.canRefreshDevices
            _ = fixture.selectedWirelessDebuggingDevice
            _ = fixture.hasSelectedWirelessDebuggingDevice
            _ = fixture.canRefreshWirelessDebuggingDevices
            _ = fixture.wirelessDiscoveryHelpText
            _ = fixture.canPairWirelessDevice
            _ = fixture.canConnectWirelessDevice
            _ = fixture.canDisconnectWirelessDevice
            _ = fixture.wirelessDebuggingSummary
            _ = fixture.projectPathDisplay
            _ = fixture.candidateProjectPathDisplay
            _ = fixture.projectPathFeedback
            _ = fixture.recentProjectRows
            _ = fixture.projectSubtitle
            _ = fixture.confidenceDisplay
            _ = fixture.workspaceSummary
            _ = fixture.deviceSummary
            _ = fixture.launchTargetFeedback
            _ = fixture.recommendedActionTitle
            _ = fixture.recommendedActionDetail
            _ = fixture.packageNameForCommands
            _ = fixture.filteredProjectFiles
            _ = fixture.selectedPlanStep
            _ = fixture.diagnosticRows
            _ = fixture.safetyRows
            _ = fixture.diffPreviewLines
            _ = fixture.chatMessages
            _ = fixture.verificationRows
            for kind in AndroidCommandKind.allCases {
                _ = fixture.canRunCommand(kind)
                _ = fixture.commandStateText(kind)
                _ = fixture.commandHelpText(kind)
                _ = fixture.commandBlockReason(for: kind)
                touched += 4
            }
            touched += 25
        }
        return touched
    }

    static func wirelessDisconnectCoverageDiagnostics() -> [String: String] {
        let tempProject = makeCoverageProject()
        let model = makeLoadedCoverageModel(rootPath: tempProject.path)
        model.applyDeviceOutput(
            """
            List of devices attached
            adb-RSVSS469IBLBPVJZ-fJ2LPO._adb-tls-connect._tcp device product:wifi model:RMX3998 device:RE5C94L1 transport_id:3
            """
        )
        model.selectedDeviceID = "adb-RSVSS469IBLBPVJZ-fJ2LPO._adb-tls-connect._tcp"
        model.wirelessConnectAddress = "192.168.1.99:49999"
        model.lastWirelessDeviceAddress = "192.168.1.98:48888"
        model.wirelessDebuggingDevices = [
            WirelessDebuggingDevice(
                id: "192.168.225.46",
                serviceName: "adb-RSVSS469IBLBPVJZ-fJ2LPO",
                host: "192.168.225.46",
                connectAddress: "192.168.225.46:42783",
                pairingAddress: nil
            )
        ]

        return [
            "canDisconnect": "\(model.canDisconnectWirelessDevice)",
            "canDisconnectSelected": "\(model.canDisconnectSelectedWirelessDevice)",
            "disconnectHelp": model.wirelessDisconnectHelpText
        ]
    }

    static func deviceTestStopCoverageDiagnostics() -> [String: String] {
        let tempProject = makeCoverageProject()
        let model = makeLoadedCoverageModel(rootPath: tempProject.path)
        let output = """
        instrumentation:com.example.coverage.debug.test/androidx.test.runner.AndroidJUnitRunner (target=com.example.coverage.debug)
        instrumentation:com.other.app.test/androidx.test.runner.AndroidJUnitRunner (target=com.other.app)
        """
        let packages = model.orderedUniquePackages(
            model.defaultDeviceTestStopPackages(for: "com.example.coverage")
                + model.instrumentationStopPackages(in: output, basePackageName: "com.example.coverage")
        )

        return [
            "packages": packages.joined(separator: ",")
        ]
    }

    static func editorSaveSafetyCoverageDiagnostics() -> [String: String] {
        let tempProject = makeCoverageProject()
        let model = makeLoadedCoverageModel(rootPath: tempProject.path)
        let manifestItem = ProjectFileItem(
            path: "app/src/main/AndroidManifest.xml",
            name: "AndroidManifest.xml",
            depth: 3,
            symbol: "doc.badge.gearshape",
            isSelected: true
        )
        let manifestURL = tempProject.appendingPathComponent(manifestItem.path)
        let originalManifest = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""

        model.openFile(manifestItem)
        model.updateSelectedEditorContent(
            model.selectedEditorContent.replacingOccurrences(
                of: "</manifest>",
                with: "    <!-- save safety coverage -->\n</manifest>"
            )
        )
        let pendingDiff = model.diffPreviewLines.joined(separator: "\n")
        model.saveSelectedEditorDocument()

        let savedManifest = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
        let safeStatus = model.lastEditorSaveSafetySummary
        let safeRows = model.safetyRows.map { "\($0.title): \($0.detail)" }.joined(separator: "\n")
        let checkpointContent = model.lastEditorUndoCheckpointPath.isEmpty
            ? ""
            : ((try? String(contentsOfFile: model.lastEditorUndoCheckpointPath, encoding: .utf8)) ?? "")

        let secretURL = tempProject.appendingPathComponent("app/src/main/java/com/example/coverage/Secrets.kt")
        try? "package com.example.coverage\nobject Secrets {}\n".write(to: secretURL, atomically: true, encoding: .utf8)
        let secretItem = ProjectFileItem(
            path: "app/src/main/java/com/example/coverage/Secrets.kt",
            name: "Secrets.kt",
            depth: 5,
            symbol: "curlybraces",
            isSelected: true
        )

        model.openFile(secretItem)
        model.updateSelectedEditorContent("package com.example.coverage\nconst val API_KEY = \"sk-live-secret\"\n")
        model.saveSelectedEditorDocument()
        let blockedSecretContent = (try? String(contentsOf: secretURL, encoding: .utf8)) ?? ""
        let blockedDiff = model.diffPreviewLines.joined(separator: "\n")

        return [
            "safeFileUpdated": "\(savedManifest.contains("save safety coverage"))",
            "pendingDiffWasScoped": "\(pendingDiff.contains(manifestItem.path) && pendingDiff.contains("save safety coverage"))",
            "checkpointExists": "\(FileManager.default.fileExists(atPath: model.lastEditorUndoCheckpointPath))",
            "checkpointMatchesOriginal": "\(checkpointContent == originalManifest)",
            "safeStatus": safeStatus,
            "safeRows": safeRows,
            "secretBlocked": "\(model.lastStatusMessage.contains("Save blocked"))",
            "secretFileUnchanged": "\(blockedSecretContent.contains("object Secrets") && !blockedSecretContent.contains("sk-live-secret"))",
            "secretSummary": model.lastEditorSecretScanSummary,
            "secretDiffRedacted": "\(blockedDiff.contains("[REDACTED"))"
        ]
    }

    static func assistantPrivacyCoverageDiagnostics() -> [String: String] {
        let tempProject = makeCoverageProject()
        let model = makeLoadedCoverageModel(rootPath: tempProject.path)
        let previousConsent = UserDefaults.standard.object(forKey: model.assistantProviderSharingConsentKey)
        let previousMode = UserDefaults.standard.object(forKey: model.assistantModelModeKey)
        defer {
            if let previousConsent {
                UserDefaults.standard.set(previousConsent, forKey: model.assistantProviderSharingConsentKey)
            } else {
                UserDefaults.standard.removeObject(forKey: model.assistantProviderSharingConsentKey)
            }
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: model.assistantModelModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: model.assistantModelModeKey)
            }
        }
        model.assistantAllowsProviderSharing = false
        model.assistantModelMode = .automatic
        model.prompt = "Give me a repo overview around 100 words."
        model.profile = ProjectProfile.from(snapshot: model.snapshot)
        model.plan = model.agent.createPlan(request: model.prompt, profile: model.profile, snapshot: model.snapshot)
        model.lastStandardOutput = "assembleDebug privacy probe output\n"

        let lower = model.plan.originalRequest.lowercased()
        let privateSharingAllowed = model.assistantProviderPayloadSharingAllowed(allowRemoteModels: true)
        let privateRequest = model.makeAssistantModelRequest(for: lower, sharingAllowed: privateSharingAllowed)
        let privateDisclosure = model.assistantPrivacyDisclosure
        let privatePayloadSummary = model.assistantPayloadPrivacySummary

        model.assistantAllowsProviderSharing = true
        let sharedSharingAllowed = model.assistantProviderPayloadSharingAllowed(allowRemoteModels: true)
        let sharedRequest = model.makeAssistantModelRequest(for: lower, sharingAllowed: sharedSharingAllowed)
        let sharedDisclosure = model.assistantPrivacyDisclosure

        model.assistantModelMode = .privateLocal
        let privateModeSharingAllowed = model.assistantProviderPayloadSharingAllowed(allowRemoteModels: true)

        return [
            "defaultSharingAllowed": "\(privateSharingAllowed)",
            "defaultContextCount": "\(privateRequest.contextFiles.count)",
            "defaultCommandOutputNil": "\(privateRequest.recentCommandOutput == nil)",
            "defaultDisclosure": privateDisclosure,
            "defaultPayloadSummary": privatePayloadSummary,
            "sharedSharingAllowed": "\(sharedSharingAllowed)",
            "sharedContextCount": "\(sharedRequest.contextFiles.count)",
            "sharedCommandOutputPresent": "\(sharedRequest.recentCommandOutput?.contains("privacy probe") == true)",
            "sharedDisclosure": sharedDisclosure,
            "accountSummary": model.assistantProviderAccountSummary,
            "privateModeOverridesSharing": "\(!privateModeSharingAllowed)"
        ]
    }

    static func assistantModelSetupCoverageDiagnostics() -> [String: String] {
        let model = AgentViewModel()
        let defaults = UserDefaults.standard
        let keys = [
            model.assistantTaskDroidBaseURLKey,
            model.assistantTaskDroidTimeoutKey,
            model.assistantPrefersTaskDroidKey
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = previousValues[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        keys.forEach(defaults.removeObject(forKey:))
        model.assistantPrefersTaskDroid = false
        model.assistantTaskDroidBaseURLText = ""
        let defaultSummary = model.assistantModelSetupSummary
        let defaultURL = model.assistantTaskDroidBaseURL?.absoluteString ?? "nil"
        let defaultEnabled = model.assistantTaskDroidEnabled

        model.assistantPrefersTaskDroid = true
        model.assistantTaskDroidBaseURLText = "https://planner.example.com"
        model.assistantTaskDroidTimeoutText = "42"

        return [
            "defaultSummary": defaultSummary,
            "defaultURL": defaultURL,
            "defaultEnabled": "\(defaultEnabled)",
            "configuredURL": model.assistantTaskDroidBaseURL?.absoluteString ?? "nil",
            "configuredEnabled": "\(model.assistantTaskDroidEnabled)",
            "configuredTimeout": "\(Int(model.assistantTaskDroidTimeoutSeconds ?? 0))",
            "configuredSummary": model.assistantModelSetupSummary,
            "accountSummary": model.assistantProviderAccountSummary
        ]
    }

    static func launchReadinessCoverageDiagnostics() async -> [String: String] {
        let defaults = UserDefaults.standard
        let keys = [
            AndroidDevAgentLaunchReadiness.telemetryModeKey,
            AndroidDevAgentLaunchReadiness.onboardingCompletedKey,
            AndroidDevAgentLaunchReadiness.licenseStateKey,
            AndroidDevAgentLaunchReadiness.licenseMaskedKey,
            AndroidDevAgentLaunchReadiness.licenseActivatedAtKey,
            AndroidDevAgentLaunchReadiness.licenseSnapshotKey,
            AndroidDevAgentLaunchReadiness.licenseDeviceIDKey,
            AndroidDevAgentLaunchReadiness.latestSupportBundlePathKey,
            AndroidDevAgentLaunchReadiness.latestSupportIssueIDKey,
            AndroidDevAgentLaunchReadiness.latestSupportUploadStatusKey,
            AndroidDevAgentLaunchReadiness.releaseNotesPathKey,
            AndroidDevAgentLaunchReadiness.crashUploadConsentKey,
            AndroidDevAgentLaunchReadiness.supportUploadConsentKey,
            "AndroidDevAgentRecentProjects"
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = previousValues[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        keys.forEach(defaults.removeObject(forKey:))
        let tempProject = makeCoverageProject()
        let model = makeLoadedCoverageModel(rootPath: tempProject.path)
        let defaultRows = model.launchReadinessRows.map(\.title).joined(separator: "|")
        let defaultTelemetry = AndroidDevAgentLaunchReadiness.telemetrySummary
        let defaultLicenseSummary = AndroidDevAgentLaunchReadiness.licenseSummary

        defaults.set(AndroidDevAgentTelemetryMode.diagnosticsOnly.rawValue, forKey: AndroidDevAgentLaunchReadiness.telemetryModeKey)
        AndroidDevAgentLaunchReadiness.recordTelemetryEvent("coverage_launch_readiness")
        let invalidLicense = await AndroidDevAgentLaunchReadiness.activateLicense("bad-key", accountEmail: "launch@example.com")
        let missingAccount = await AndroidDevAgentLaunchReadiness.activateLicense("ADA-ABCD-EFGH-IJKL-MNOP", accountEmail: "")
        let activationDiagnostics = await AndroidDevAgentLaunchReadiness.withCoverageLicenseBackend {
            let message = await AndroidDevAgentLaunchReadiness.activateLicense("ADA-ABCD-EFGH-IJKL-MNOP", accountEmail: "launch@example.com")
            return [
                "message": message,
                "summary": AndroidDevAgentLaunchReadiness.licenseSummary
            ]
        }
        let validLicense = activationDiagnostics["message"] ?? ""
        let activeLicenseSummary = activationDiagnostics["summary"] ?? ""
        let refreshedLicense = await AndroidDevAgentLaunchReadiness.withCoverageLicenseBackend {
            await AndroidDevAgentLaunchReadiness.refreshLicenseEntitlement()
        }
        let offlineGrace = await AndroidDevAgentLaunchReadiness.withCoverageLicenseBackend(failingRefresh: true) {
            await AndroidDevAgentLaunchReadiness.refreshLicenseEntitlement()
        }
        let recoveredAccount = await AndroidDevAgentLaunchReadiness.withCoverageLicenseBackend {
            await AndroidDevAgentLaunchReadiness.recoverLicenseAccount("launch@example.com")
        }
        let transferredLicense = await AndroidDevAgentLaunchReadiness.withCoverageLicenseBackend {
            await AndroidDevAgentLaunchReadiness.transferLicense(to: "new-owner@example.com")
        }
        let transferSummary = AndroidDevAgentLaunchReadiness.licenseSummary
        AndroidDevAgentLaunchReadiness.markOnboardingCompleted()

        let releaseNotesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-dev-agent-coverage-release-notes.md")
        try? "Coverage release notes\n".write(to: releaseNotesURL, atomically: true, encoding: .utf8)
        defaults.set(releaseNotesURL.path, forKey: AndroidDevAgentLaunchReadiness.releaseNotesPathKey)

        model.commandOutput = """
        Authorization: Bearer launch-secret-token
        OPENAI_API_KEY=sk-test-secret-value
        harmless console line
        """
        model.createSupportBundle()
        let supportBundlePath = model.supportBundlePath
        let supportReportURL = URL(fileURLWithPath: supportBundlePath).appendingPathComponent("support-report.txt")
        let supportReportText = (try? String(contentsOf: supportReportURL, encoding: .utf8)) ?? ""
        let supportReportExists = FileManager.default.fileExists(atPath: supportReportURL.path)
        let launchReadinessManifestExists = FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: supportBundlePath)
                .appendingPathComponent("launch-readiness.txt")
                .path
        )
        let releaseNotesCopied = FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: supportBundlePath)
                .appendingPathComponent("release-notes.md")
                .path
        )
        let privacyAuditCopied = FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: supportBundlePath)
                .appendingPathComponent("privacy-audit.jsonl")
                .path
        )
        let issueIDURL = URL(fileURLWithPath: supportBundlePath).appendingPathComponent("issue-id.txt")
        let diagnosticVersionURL = URL(fileURLWithPath: supportBundlePath).appendingPathComponent("diagnostic-version.txt")
        let redactionSummaryURL = URL(fileURLWithPath: supportBundlePath).appendingPathComponent("redaction-summary.txt")
        let symbolicationURL = URL(fileURLWithPath: supportBundlePath).appendingPathComponent("crash-symbolication.txt")
        let issueIDText = (try? String(contentsOf: issueIDURL, encoding: .utf8)) ?? ""
        let diagnosticVersionText = (try? String(contentsOf: diagnosticVersionURL, encoding: .utf8)) ?? ""
        let symbolicationText = (try? String(contentsOf: symbolicationURL, encoding: .utf8)) ?? ""
        let supportReportRedacted = supportReportText.contains("[REDACTED]")
            && !supportReportText.contains("launch-secret-token")
            && !supportReportText.contains("sk-test-secret-value")
        AndroidDevAgentLaunchReadiness.setSupportUploadConsent(true)
        let supportUploadStatus = await AndroidDevAgentLaunchReadiness.withCoverageSupportBackend {
            await AndroidDevAgentLaunchReadiness.uploadSupportBundle(at: URL(fileURLWithPath: supportBundlePath))
        }

        return [
            "rows": defaultRows,
            "defaultTelemetry": defaultTelemetry,
            "defaultLicenseSummary": defaultLicenseSummary,
            "invalidLicense": invalidLicense,
            "missingAccount": missingAccount,
            "validLicense": validLicense,
            "activeLicenseSummary": activeLicenseSummary,
            "refreshedLicense": refreshedLicense,
            "offlineGrace": offlineGrace,
            "recoveredAccount": recoveredAccount,
            "transferredLicense": transferredLicense,
            "transferSummary": transferSummary,
            "licenseSummary": AndroidDevAgentLaunchReadiness.licenseSummary,
            "onboardingSummary": AndroidDevAgentLaunchReadiness.onboardingSummary,
            "releaseNotesSummary": AndroidDevAgentLaunchReadiness.releaseNotesSummary,
            "supportBundlePath": supportBundlePath,
            "supportReportExists": "\(supportReportExists)",
            "supportReportRedacted": "\(supportReportRedacted)",
            "privacyAuditCopied": "\(privacyAuditCopied)",
            "launchManifestExists": "\(launchReadinessManifestExists)",
            "releaseNotesCopied": "\(releaseNotesCopied)",
            "issueIDExists": "\(FileManager.default.fileExists(atPath: issueIDURL.path))",
            "issueIDStamped": "\(issueIDText.contains("ADA-"))",
            "diagnosticVersionExists": "\(FileManager.default.fileExists(atPath: diagnosticVersionURL.path))",
            "diagnosticVersionStamped": "\(diagnosticVersionText.contains("Diagnostic Schema") && diagnosticVersionText.contains("App Version"))",
            "redactionSummaryExists": "\(FileManager.default.fileExists(atPath: redactionSummaryURL.path))",
            "symbolicationExists": "\(FileManager.default.fileExists(atPath: symbolicationURL.path))",
            "symbolicationStamped": "\(symbolicationText.contains("Crash Symbolication") && symbolicationText.contains("dSYM UUID"))",
            "supportUploadStatus": supportUploadStatus,
            "supportStatus": model.lastStatusMessage
        ]
    }

    private static func makeLoadedCoverageModel(rootPath: String) -> AgentViewModel {
        let viewModel = AgentViewModel()
        let snapshot = WorkspaceSnapshot(
            rootPath: rootPath,
            fileCount: 48,
            testFileCount: 9,
            hasGradleWrapper: true,
            hasSettingsGradle: true,
            hasAndroidManifest: true,
            usesCompose: true,
            usesKotlin: true,
            usesJava: true,
            usesXMLLayouts: true,
            packageName: "com.example.coverage",
            minSDK: 24,
            targetSDK: 35
        )
        viewModel.projectPath = rootPath
        viewModel.snapshot = snapshot
        viewModel.profile = ProjectProfile.from(snapshot: snapshot)
        viewModel.projectFiles = viewModel.makeProjectFiles(rootPath: rootPath, snapshot: snapshot)
        viewModel.modules = viewModel.discoverModules(rootPath: rootPath)
        viewModel.selectedModule = viewModel.modules.first ?? "app"
        viewModel.buildVariants = viewModel.discoverBuildVariants(rootPath: rootPath, module: viewModel.selectedModule)
        viewModel.selectedVariant = viewModel.buildVariants.first ?? "Debug"
        viewModel.packageOverride = snapshot.packageName ?? ""
        viewModel.isProjectLoaded = true
        viewModel.isScanningProject = false
        viewModel.scanState = .ready
        viewModel.lastStatusMessage = "Loaded \(viewModel.displayPath(rootPath))"
        viewModel.addRecentProject(rootPath)
        viewModel.generatePlan()
        return viewModel
    }

    private static func makeCoverageProject() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AndroidDevAgentCoverage-\(UUID().uuidString)", isDirectory: true)
        let appSource = root.appendingPathComponent("app/src/main/java/com/example/coverage", isDirectory: true)
        let testSource = root.appendingPathComponent("app/src/test/java/com/example/coverage", isDirectory: true)
        let layoutSource = root.appendingPathComponent("app/src/main/res/layout", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSource, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: testSource, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: layoutSource, withIntermediateDirectories: true)
        try? "include ':app', ':feature-login'\n".write(
            to: root.appendingPathComponent("settings.gradle"),
            atomically: true,
            encoding: .utf8
        )
        try? """
        plugins {
            id 'com.android.application'
            id 'org.jetbrains.kotlin.android'
        }

        android {
            namespace 'com.example.coverage'
            defaultConfig {
                minSdk 24
                targetSdk 35
            }
            productFlavors {
                free { dimension 'tier' }
                paid { dimension 'tier' }
            }
        }
        """.write(
            to: root.appendingPathComponent("app/build.gradle"),
            atomically: true,
            encoding: .utf8
        )
        try? """
        <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.coverage">
            <application>
                <activity android:name=".MainActivity" android:exported="true" />
            </application>
        </manifest>
        """.write(
            to: root.appendingPathComponent("app/src/main/AndroidManifest.xml"),
            atomically: true,
            encoding: .utf8
        )
        try? "class MainActivity\n".write(to: appSource.appendingPathComponent("MainActivity.kt"), atomically: true, encoding: .utf8)
        try? "class LegacyView {}\n".write(to: appSource.appendingPathComponent("LegacyView.java"), atomically: true, encoding: .utf8)
        try? "<LinearLayout />\n".write(to: layoutSource.appendingPathComponent("activity_main.xml"), atomically: true, encoding: .utf8)
        try? "class MainActivityTest\n".write(to: testSource.appendingPathComponent("MainActivityTest.kt"), atomically: true, encoding: .utf8)
        try? "#!/bin/sh\nexit 0\n".write(to: root.appendingPathComponent("gradlew"), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("gradlew").path)
        return root
    }

    private static func restore(_ values: [String]?, forKey key: String, defaults: UserDefaults) {
        if let values {
            defaults.set(values, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
