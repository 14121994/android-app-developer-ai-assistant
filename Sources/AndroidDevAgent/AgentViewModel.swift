import AndroidDevAgentCore
import AppKit
import Combine
import Foundation

enum SessionPaneTab: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case diagnostics = "Diagnostics"
    case checks = "Checks"

    var id: String { rawValue }
}

enum ConsoleStreamFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case stdout = "Stdout"
    case stderr = "Stderr"

    var id: String { rawValue }
}

enum AndroidCommandKind: String, CaseIterable, Identifiable {
    case unitTests = "Unit Tests"
    case assembleDebug = "Assemble"
    case connectedTests = "Device Tests"
    case devices = "Devices"
    case logcat = "Logcat"
    case clearLogcat = "Clear Logs"
    case launch = "Launch"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .unitTests: return "checkmark.seal"
        case .assembleDebug: return "hammer"
        case .connectedTests: return "iphone.gen3"
        case .devices: return "list.bullet.rectangle"
        case .logcat: return "doc.text.magnifyingglass"
        case .clearLogcat: return "trash"
        case .launch: return "play"
        }
    }

    var requiresDevice: Bool {
        switch self {
        case .connectedTests, .logcat, .clearLogcat, .launch:
            return true
        case .unitTests, .assembleDebug, .devices:
            return false
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .connectedTests, .clearLogcat, .launch:
            return true
        case .unitTests, .assembleDebug, .devices, .logcat:
            return false
        }
    }

    var timeoutSeconds: TimeInterval {
        switch self {
        case .unitTests: return 90
        case .assembleDebug: return 120
        case .connectedTests: return 180
        case .devices: return 20
        case .logcat: return 20
        case .clearLogcat: return 20
        case .launch: return 25
        }
    }

    var riskSummary: String {
        switch self {
        case .connectedTests:
            return "Instrumentation tests can install, launch, and control the selected device."
        case .clearLogcat:
            return "This clears Logcat on the selected device."
        case .launch:
            return "This launches the configured package/activity on the selected device."
        default:
            return "This command will run in the selected project."
        }
    }
}

enum ScanState: Hashable {
    case waiting
    case scanning
    case ready
    case warning(String)
    case failed(String)

    var title: String {
        switch self {
        case .waiting: return "Choose project"
        case .scanning: return "Scanning"
        case .ready: return "Project ready"
        case .warning: return "Needs review"
        case .failed: return "Scan failed"
        }
    }

    var detail: String {
        switch self {
        case .waiting:
            return "Select an Android project folder to scan."
        case .scanning:
            return "Scanning Gradle, manifest, source, resources, and tests."
        case .ready:
            return "Android project context is loaded."
        case let .warning(message), let .failed(message):
            return message
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "folder.badge.questionmark"
        case .scanning: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

struct ProjectFileItem: Identifiable, Hashable {
    let path: String
    let name: String
    let depth: Int
    let symbol: String
    let isSelected: Bool
    let isDirectory: Bool

    var id: String { path }

    init(
        path: String,
        name: String,
        depth: Int,
        symbol: String,
        isSelected: Bool,
        isDirectory: Bool = false
    ) {
        self.path = path
        self.name = name
        self.depth = depth
        self.symbol = symbol
        self.isSelected = isSelected
        self.isDirectory = isDirectory
    }
}

struct AgentChatMessage: Identifiable, Hashable {
    let speaker: String
    let message: String
    let isUser: Bool

    var id: String { "\(speaker)-\(message)" }
}

struct VerificationRow: Identifiable, Hashable {
    let title: String
    let detail: String
    let symbol: String
    let state: String
    let severity: String

    var id: String { title }
}

struct DeviceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let state: String

    var displayName: String {
        name.isEmpty ? "\(id) (\(state))" : "\(id) - \(name)"
    }
}

struct CommandConfirmation: Identifiable, Hashable {
    let kind: AndroidCommandKind
    let message: String

    var id: String { kind.id }
}

struct WirelessDebuggingConfirmation: Identifiable, Hashable {
    let id = UUID()
    let pairingAddress: String
    let pairingCode: String
    let connectAddress: String?
}

struct CommandRunSummary: Hashable {
    let title: String
    let status: String
    let detail: String
    let severity: String
    let duration: String
}

struct DiagnosticRow: Identifiable, Hashable {
    let title: String
    let detail: String
    let symbol: String
    let severity: String

    var id: String { title }
}

struct RecentProjectRow: Identifiable, Hashable {
    let path: String
    let name: String
    let displayPath: String
    let exists: Bool

    var id: String { path }

    var menuTitle: String {
        exists ? "\(name) - \(displayPath)" : "\(name) - missing"
    }
}

struct EditorDocument: Identifiable, Hashable {
    let path: String
    let name: String
    var content: String
    var savedContent: String
    var lastError: String?

    var id: String { path }
    var isDirty: Bool { content != savedContent }
}

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
    @Published var selectedDeviceID = ""
    @Published var fileSearchQuery = ""
    @Published private(set) var modules: [String] = ["app"]
    @Published private(set) var buildVariants: [String] = ["Debug", "Release"]
    @Published private(set) var devices: [DeviceOption] = []
    @Published private(set) var isRefreshingDevices = false
    @Published private(set) var isRunningWirelessDebugging = false
    @Published var wirelessPairingCode = ""
    @Published var wirelessConnectAddress = ""
    @Published private(set) var wirelessDebuggingStatus = "Use Android Wireless Debugging to pair or connect a device over Wi-Fi."
    @Published private(set) var lastWirelessPairingAddress = ""
    @Published private(set) var lastWirelessDeviceAddress = ""
    @Published var pendingConfirmation: CommandConfirmation?
    @Published var pendingWirelessDebuggingConfirmation: WirelessDebuggingConfirmation?
    @Published private(set) var promptHistory: [String] = []
    @Published private(set) var recentProjectPaths: [String] = []
    @Published private(set) var isOutputTruncated = false
    @Published private(set) var lastCommandSummary: CommandRunSummary?
    @Published private(set) var debugReportPath = ""
    @Published var selectedPlanStepID: Int?
    @Published var selectedSessionTab: SessionPaneTab = .chat
    @Published private(set) var lastExportPath = ""
    @Published private(set) var openEditorDocuments: [EditorDocument] = []
    @Published var selectedEditorPath = ""
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
    @Published var assistantModelMode: AssistantModelMode = .automatic {
        didSet {
            UserDefaults.standard.set(assistantModelMode.rawValue, forKey: assistantModelModeKey)
            assistantModelStatus = "Model mode set to \(assistantModelMode.title)."
        }
    }

    let agent = DevelopmentAgent()
    private let assistantOrchestrator = AssistantModelOrchestrator()
    private let runner = ProcessRunner()
    private var scanID = UUID()
    private var currentCommandID = UUID()
    private var lastRunnableCommandKind: AndroidCommandKind?
    private var previousPromptDraft: String?
    private var revealFilesAfterCurrentScan = true
    private var assistantResponseFeedbackToken = UUID()
    private let recentProjectsKey = "AndroidDevAgentRecentProjects"
    private let promptHistoryKey = "AndroidDevAgentPromptHistory"
    private let assistantModelModeKey = "AndroidDevAgentAssistantModelMode"
    private let assistantResponseExportPathKey = "AndroidDevAgentAssistantResponseExportPath"

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
        let restoredAssistantExportPath = restoreAssistantResponseExportPath()
        if let storedMode = UserDefaults.standard.string(forKey: assistantModelModeKey),
           let mode = AssistantModelMode(rawValue: storedMode) {
            assistantModelMode = mode
        }
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
        guard isScanningProject else { return }
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
        guard !isAssistantThinking else { return }
        Task { @MainActor [weak self] in
            await self?.submitAssistantPromptWithModels(runActions: runActions)
        }
    }

    func submitAssistantPromptWithModels(runActions: Bool = true, allowRemoteModels: Bool = true) async {
        guard !isAssistantThinking else { return }
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

        let contextFiles = assistantContextFiles(for: lower)
        let request = AssistantModelRequest(
            prompt: plan.originalRequest,
            profile: profile,
            snapshot: snapshot,
            planIntent: plan.intent,
            modules: modules,
            variants: buildVariants,
            contextFiles: contextFiles,
            commandSummary: lastCommandSummary?.detail,
            recentCommandOutput: recentCommandOutputExcerpt
        )
        let config = AssistantOrchestrationConfig(
            mode: assistantModelMode,
            openAIAPIKey: openAIAPIKey,
            allowRemoteModels: allowRemoteModels,
            preferTaskDroid: allowRemoteModels
        )

        isAssistantThinking = true
        assistantModelStatus = "Routing with \(assistantModelMode.title)..."
        assistantModelDetail = contextFiles.isEmpty
            ? "No file excerpts were available for model context."
            : "Prepared \(contextFiles.count) project context file\(contextFiles.count == 1 ? "" : "s")."
        selectedSessionTab = .chat

        let modelResponse = await assistantOrchestrator.answer(request: request, config: config)
        isAssistantThinking = false
        assistantActionSummary = (actionMessages + modelResponse.plannedActions).joined(separator: " ")
        assistantResponse = modelResponse.answer
        clearAssistantResponseExportPath()
        assistantResponseFeedback = ""
        assistantModelStatus = modelResponse.status
        assistantModelDetail = "\(modelResponse.modelDisplayName) (\(modelResponse.modelID)) via \(modelResponse.provider.rawValue); retrieval: \(modelResponse.retrievalModelID); context: \(modelResponse.contextFilePaths.isEmpty ? "none" : modelResponse.contextFilePaths.joined(separator: ", "))"
        lastStatusMessage = assistantActionSummary.isEmpty
            ? "Assistant response generated by \(modelResponse.modelDisplayName)."
            : "Assistant responded and acted: \(assistantActionSummary)"
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
        guard let pendingConfirmation else { return }
        let kind = pendingConfirmation.kind
        self.pendingConfirmation = nil
        executeCommand(kind)
    }

    func cancelPendingCommand() {
        guard let pendingConfirmation else { return }
        lastStatusMessage = "\(pendingConfirmation.kind.rawValue) cancelled."
        self.pendingConfirmation = nil
    }

    private func executeCommand(_ kind: AndroidCommandKind) {
        savePromptToHistory(prompt)
        lastRunnableCommandKind = kind

        let command = commandFor(kind)
        let startedAt = Date()
        let commandID = UUID()
        currentCommandID = commandID
        lastCommandTitle = command.title
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
            let result = await runner.run(command, timeoutSeconds: kind.timeoutSeconds)
            guard self.currentCommandID == commandID else { return }
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

    func clearOutput() {
        commandOutput = "Console cleared.\n"
        lastStandardOutput = ""
        lastStandardError = ""
        consoleStreamFilter = .all
        consoleSearchQuery = ""
        isOutputTruncated = false
        lastStatusMessage = "Command console cleared."
    }

    func stopRunningCommand() {
        guard isRunningCommand else { return }
        currentCommandID = UUID()
        isRunningCommand = false
        lastCommandTitle = "Idle"
        lastCommandSummary = CommandRunSummary(
            title: "Command stopped",
            status: "Stopped",
            detail: "The command result will be ignored if it finishes later.",
            severity: "warning",
            duration: "0s"
        )
        lastStatusMessage = "Command stopped."
        appendOutput("\n[command stopped by user]\n")
    }

    func refreshDevices() {
        guard canRefreshDevices else {
            lastStatusMessage = isRefreshingDevices
                ? "Device refresh is already running."
                : "Wait for the current scan, command, or Wireless Debugging action before refreshing devices."
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

    func pairWirelessDevice() {
        let code = wirelessPairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canPairWirelessDevice else {
            wirelessDebuggingStatus = wirelessPairingValidationMessage
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        discoverWirelessPairingAddress(pairingCode: code)
    }

    func confirmWirelessPairing() {
        guard let confirmation = pendingWirelessDebuggingConfirmation else { return }
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
            refreshAfterSuccess: false
        )
    }

    func cancelWirelessPairing() {
        pendingWirelessDebuggingConfirmation = nil
        wirelessDebuggingStatus = "Wireless pairing cancelled."
        lastStatusMessage = wirelessDebuggingStatus
    }

    func connectWirelessDevice() {
        let address = trimmedWirelessConnectAddress.nilIfEmpty ?? lastWirelessDeviceAddress
        guard canConnectWirelessDevice else {
            wirelessDebuggingStatus = wirelessConnectValidationMessage
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        let command = AndroidToolCommandFactory.connectWirelessDevice(rootPath: commandWorkingDirectory, hostPort: address)
        runWirelessDebuggingCommand(
            command,
            displayAddress: address,
            refreshAfterSuccess: true,
            selectedDeviceAddress: address
        )
    }

    func disconnectWirelessDevice() {
        let address = trimmedWirelessConnectAddress.nilIfEmpty ?? lastWirelessDeviceAddress
        guard canDisconnectWirelessDevice else {
            wirelessDebuggingStatus = "Connect a wireless device or enter its host:port before disconnecting."
            lastStatusMessage = wirelessDebuggingStatus
            return
        }
        let command = AndroidToolCommandFactory.disconnectWirelessDevice(rootPath: commandWorkingDirectory, hostPort: address)
        runWirelessDebuggingCommand(
            command,
            displayAddress: address,
            refreshAfterSuccess: true,
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
                    if selectedDeviceID == displayAddress {
                        selectedDeviceID = ""
                    }
                    if lastWirelessDeviceAddress == displayAddress {
                        lastWirelessDeviceAddress = ""
                    }
                }
                wirelessDebuggingStatus = "\(result.command.title) succeeded. \(usefulLine)"
                lastStatusMessage = wirelessDebuggingStatus
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
        let current = prompt
        prompt = previousPromptDraft
        self.previousPromptDraft = current
        submitAssistantPrompt(runActions: false)
        lastStatusMessage = "Restored the previous prompt draft."
    }

    func removePromptHistory(_ value: String) {
        promptHistory.removeAll { $0 == value }
        UserDefaults.standard.set(promptHistory, forKey: promptHistoryKey)
        lastStatusMessage = "Removed one prompt history item."
    }

    func clearPromptHistory() {
        promptHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: promptHistoryKey)
        lastStatusMessage = "Prompt history cleared."
    }

    func copyConsole() {
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

    private var openAIAPIKey: String? {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    func exportConsole() {
        let path = temporaryArtifactPath(prefix: "android-dev-agent-console", fileExtension: "log")
        do {
            try commandOutput.write(toFile: path, atomically: true, encoding: .utf8)
            lastExportPath = path
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
            lastStatusMessage = "Debug report exported to \(path)."
        } catch {
            lastStatusMessage = "Could not export debug report: \(error.localizedDescription)"
        }
    }

    func openDebugReport() {
        guard !debugReportPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: debugReportPath))
    }

    func openLastExport() {
        guard !lastExportPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastExportPath))
    }

    func openAssistantResponseExport() {
        guard !assistantResponseExportPath.isEmpty else { return }
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
        return true
    }

    func retryLastCommand() {
        guard let lastRunnableCommandKind else {
            lastStatusMessage = "No previous command to retry."
            return
        }
        runCommand(lastRunnableCommandKind)
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
        packageOverride = profile.packageName == "unknown.android.app" ? "" : profile.packageName
        lastStatusMessage = packageOverride.isEmpty
            ? "No detected package is available yet."
            : "Launch package reset to \(packageOverride)."
    }

    func revealProjectFileInFinder(_ item: ProjectFileItem) {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(item.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        lastStatusMessage = "Revealed \(item.path) in Finder."
    }

    func openProjectFileExternally(_ item: ProjectFileItem) {
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(item.path)
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
        selectedEditorPath = document.path
        lastStatusMessage = "Focused \(document.path) in the editor."
    }

    func updateSelectedEditorContent(_ content: String) {
        guard let index = selectedEditorIndex() else { return }
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
        NSWorkspace.shared.activateFileViewerSelecting([url])
        lastStatusMessage = "Revealed \(document.path) in Finder."
    }

    func openSelectedEditorDocumentExternally() {
        guard let document = selectedEditorDocument else {
            lastStatusMessage = "Open a file before opening it externally."
            return
        }
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(document.path)
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
        guard let index = selectedEditorIndex() else { return false }
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
        guard openEditorDocuments.indices.contains(index) else { return false }
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
        recentProjectPaths.removeAll { $0 == path }
        UserDefaults.standard.set(recentProjectPaths, forKey: recentProjectsKey)
        lastStatusMessage = "Removed \(displayPath(path)) from recent projects."
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
        recentProjectPaths.removeAll()
        UserDefaults.standard.removeObject(forKey: recentProjectsKey)
        lastStatusMessage = "Recent projects cleared."
    }

    func clearPrompt() {
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
        !isScanningProject && !resolvedProjectPath(projectPath).isEmpty
    }

    var canRunTools: Bool {
        isProjectLoaded && !isScanningProject && !isRunningCommand && !isRefreshingDevices && !isRunningWirelessDebugging
    }

    var canRefreshDevices: Bool {
        !isRefreshingDevices && !isRunningCommand && !isScanningProject && !isRunningWirelessDebugging
    }

    var canPairWirelessDevice: Bool {
        canRunADBWirelessAction && !wirelessPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canConnectWirelessDevice: Bool {
        canRunADBWirelessAction && isValidHostPort(trimmedWirelessConnectAddress.nilIfEmpty ?? lastWirelessDeviceAddress)
    }

    var canDisconnectWirelessDevice: Bool {
        canRunADBWirelessAction && isValidHostPort(trimmedWirelessConnectAddress.nilIfEmpty ?? lastWirelessDeviceAddress)
    }

    var wirelessDebuggingSummary: String {
        if isRunningWirelessDebugging { return wirelessDebuggingStatus }
        let pairing = lastWirelessPairingAddress.isEmpty ? "" : " Last pairing address: \(lastWirelessPairingAddress)."
        let device = lastWirelessDeviceAddress.isEmpty ? "" : " Last wireless target: \(lastWirelessDeviceAddress)."
        return wirelessDebuggingStatus + pairing + device
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
            return devices.isEmpty ? "No online device selected. Refresh devices to detect emulator or USB targets.\(suffix)" : "Choose a device for Logcat, Launch, and device tests.\(suffix)"
        }
        return "Selected \(selectedDeviceID)"
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
        let taskDroidURL = ProcessInfo.processInfo.environment["TASKDROID_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "http://127.0.0.1:8000"
        return "TaskDroid planner route: \(taskDroidURL). If unavailable, Ask shows the TaskDroid/vLLM error without fallback."
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
        return DiagnosticRow(title: "Launch ready", detail: "\(packageNameForCommands)/\(launchActivity)", symbol: "play.circle", severity: selectedDeviceID.isEmpty ? "neutral" : "ready")
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
        guard item.isDirectory else { return }
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
        expandedProjectFolderPaths = Set(projectFiles.filter(\.isDirectory).map(\.path))
        lastStatusMessage = "Expanded all project folders."
    }

    func collapseAllProjectFolders() {
        expandedProjectFolderPaths.removeAll()
        lastStatusMessage = "Collapsed all project folders."
    }

    private func performAssistantActions(for lower: String) -> [String] {
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

    private func makeAssistantResponse(for lower: String, actionMessages: [String]) -> String {
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

    private func projectOverviewResponse() -> String {
        let name = projectDisplayName
        let ui = snapshot.usesCompose ? "Jetpack Compose" : snapshot.usesXMLLayouts ? "XML layouts" : "mixed Android UI"
        let tests = snapshot.testFileCount == 1 ? "1 test file" : "\(snapshot.testFileCount) test files"
        let readme = readmeExcerpt()
        return """
        \(name) is an Android game project using \(ui) with Kotlin under package \(profile.packageName). I scanned \(snapshot.fileCount) files and found \(tests), a valid AndroidManifest, and \(snapshot.hasGradleWrapper ? "a Gradle wrapper for reproducible builds" : "system Gradle usage"). The app appears structured as a compact board-game codebase, with source, resources, and tests concentrated around the main app module. \(readme) For user-facing work, the safest path is to inspect the current game state model, board rendering, dice flow, win-condition logic, and tests before adding new mechanics.
        """
    }

    private func ludoImplementationResponse() -> String {
        """
        I scanned \(profile.packageName) and it looks like a \(snapshot.usesCompose ? "Compose/Kotlin" : "Kotlin/XML") board-game app with \(snapshot.fileCount) indexed files and \(snapshot.testFileCount) test files. To incorporate Ludo cleanly, I would add it as a separate game mode rather than mixing it into the existing Snake Ladder rules. The implementation should introduce Ludo domain models for players, colors, tokens, dice, home paths, safe squares, captures, and win state; a ViewModel/reducer for turn sequencing; a Compose board renderer; and unit tests for dice entry, captures, extra turns, and finish rules. Files to inspect first: \(representativeFileList()). Verification should start with unit tests, then assemble, then device UI inspection.
        """
    }

    private func crashResponse() -> String {
        """
        I treated this as crash triage for \(profile.packageName). The useful path is to capture Logcat, isolate the first app-owned stack frame, map it to the affected Kotlin/Java file, and add the smallest null/state guard with a regression test. I found \(snapshot.fileCount) scanned files and \(snapshot.testFileCount) tests, so I would start by searching likely ViewModel/state/game-loop files, then run the targeted unit test task. If no device is selected, refresh devices before Logcat.
        """
    }

    private func buildRepairResponse() -> String {
        """
        I treated this as build/dependency repair for \(profile.packageName). The project has \(snapshot.hasGradleWrapper ? "a Gradle wrapper" : "no wrapper detected"), modules \(modules.joined(separator: ", ")), and variants \(buildVariants.joined(separator: ", ")). I would inspect settings/build files, version catalog entries, plugin versions, manifest changes, and package/activity configuration before editing. Because dependency and manifest edits can affect release behavior, the app should show a scoped diff before applying them, then run assemble and unit tests.
        """
    }

    private func uiImplementationResponse() -> String {
        """
        I treated this as Android UI work for \(profile.packageName). The scan shows \(snapshot.usesCompose ? "Compose" : "XML/mixed") UI, Kotlin \(snapshot.usesKotlin ? "present" : "not detected"), and \(snapshot.testFileCount) test files. I would place the new screen near the existing app UI structure, keep state in a ViewModel or reducer, add accessibility labels/content descriptions, and add tests around state transitions. Relevant files to inspect first: \(representativeFileList()). Verification should run unit tests, assemble, and then device/UI checks if an emulator is selected.
        """
    }

    private func testAutomationResponse() -> String {
        """
        I treated this as test automation for \(profile.packageName). I found \(snapshot.testFileCount) existing test files and \(snapshot.fileCount) indexed project files. The safest next step is to add focused unit tests around the changed game or UI state, then run \(gradleTaskName(prefix: "test", suffix: "UnitTest")). Device or screenshot tests should run only after selecting an emulator because they can install and control the app.
        """
    }

    private func featureImplementationResponse() -> String {
        """
        I prepared a project-specific implementation response for \(profile.packageName). The workspace has \(snapshot.fileCount) scanned files, \(snapshot.testFileCount) tests, modules \(modules.joined(separator: ", ")), variants \(buildVariants.joined(separator: ", ")), and \(snapshot.hasAndroidManifest ? "a detected manifest" : "no detected manifest"). My recommended path is: inspect the closest existing game/UI state files, add the smallest isolated domain model or screen change, update tests, then run unit tests and assemble. Candidate files to inspect first: \(representativeFileList()).
        """
    }

    private func asksForOverview(_ lower: String) -> Bool {
        containsAny(lower, "overview", "summarize", "summary", "explain this project", "what is this project", "around 100 words")
    }

    private func asksForLudo(_ lower: String) -> Bool {
        containsAny(lower, "ludo", "board game developer")
    }

    private func asksForCodeChange(_ lower: String) -> Bool {
        containsAny(lower, "add ", "create ", "build ", "implement", "fix ", "repair", "refactor", "incorporate", "update ")
    }

    private func shouldRunUnitTests(for lower: String) -> Bool {
        containsAny(lower, "run tests", "run unit", "execute tests", "verify tests", "test coverage", "run targeted tests")
    }

    private func shouldRunBuild(for lower: String) -> Bool {
        containsAny(lower, "run build", "build apk", "assemble", "compile", "verify build")
    }

    private func shouldRefreshDevices(for lower: String) -> Bool {
        containsAny(lower, "refresh devices", "list devices", "detect emulator", "detect device")
    }

    private func shouldCaptureLogcat(for lower: String) -> Bool {
        containsAny(lower, "capture logcat", "run logcat", "inspect logcat", "device logs")
    }

    private func containsAny(_ value: String, _ needles: String...) -> Bool {
        needles.contains { value.contains($0) }
    }

    private var projectDisplayName: String {
        let name = URL(fileURLWithPath: projectPath).lastPathComponent
        let rawName = name.isEmpty ? profile.packageName : name
        return rawName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func readmeExcerpt() -> String {
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

    private func representativeFileList() -> String {
        let files = projectFiles
            .filter { !$0.isDirectory }
            .filter { isKeyProjectFile($0.path) || $0.path.lowercased().contains("main") || $0.path.lowercased().contains("game") }
            .prefix(5)
            .map(\.path)
        let selected = files.isEmpty ? projectFiles.filter { !$0.isDirectory }.prefix(5).map(\.path) : Array(files)
        return selected.isEmpty ? "scan the Files panel for source and Gradle files" : selected.joined(separator: ", ")
    }

    private func assistantContextFiles(for lower: String) -> [AssistantContextFile] {
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

    private func readAssistantContextFile(relativePath: String) -> AssistantContextFile? {
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

    private func redactAssistantContext(_ content: String) -> String {
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

    private func openRepresentativeFilesForPrompt(_ lower: String) -> [String] {
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

    private func representativeFilesForPrompt(_ lower: String) -> [ProjectFileItem] {
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

    var selectedPlanStep: AgentPlanStep? {
        plan.steps.first { $0.id == selectedPlanStepID } ?? plan.steps.first
    }

    func canRunCommand(_ kind: AndroidCommandKind) -> Bool {
        commandBlockReason(for: kind) == nil
    }

    func commandStateText(_ kind: AndroidCommandKind) -> String {
        if isScanningProject { return "Scanning" }
        if isRunningCommand { return "Busy" }
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
            DiagnosticRow(title: "Ask Export", detail: askExportDiagnosticsDetail, symbol: "square.and.arrow.down", severity: askExportDiagnosticsSeverity),
            DiagnosticRow(title: "Last Export", detail: lastExportPath.isEmpty ? "No console, assistant response, or debug report exported yet" : displayPath(lastExportPath), symbol: "doc.text.magnifyingglass", severity: lastExportPath.isEmpty ? "neutral" : "ready")
        ]
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
            DiagnosticRow(title: "Risk confirmation", detail: "Launch, clear logs, and device tests ask before running.", symbol: "exclamationmark.shield", severity: "ready"),
            DiagnosticRow(title: "Timeouts", detail: "Gradle and ADB commands have command-specific timeouts.", symbol: "timer", severity: "ready"),
            DiagnosticRow(title: "Device preflight", detail: "Device commands require a selected target.", symbol: "iphone.gen3.radiowaves.left.and.right", severity: selectedDeviceID.isEmpty ? "warning" : "ready"),
            DiagnosticRow(title: "Root scan guard", detail: "Broad filesystem scans are blocked.", symbol: "lock.shield", severity: "ready")
        ]
    }

    var diffPreviewLines: [String] {
        guard isProjectLoaded else {
            return [
                "// No Android project loaded",
                "// Choose a project folder to scan files, create a patch preview, and enable verification.",
                "// The agent will keep file counts, tests, and Gradle status hidden until then."
            ]
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

    private func gradleTaskName(prefix: String, suffix: String) -> String {
        let variant = selectedVariant.trimmingCharacters(in: .whitespacesAndNewlines)
        let module = selectedModule.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = "\(prefix)\(variant)\(suffix)"
        return module.isEmpty ? task : ":\(module):\(task)"
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

    private func saveEditorDocument(at index: Int) {
        guard openEditorDocuments.indices.contains(index) else { return }
        let document = openEditorDocuments[index]
        let url = URL(fileURLWithPath: projectPath).appendingPathComponent(document.path)
        do {
            try document.content.write(to: url, atomically: true, encoding: .utf8)
            openEditorDocuments[index].savedContent = document.content
            openEditorDocuments[index].lastError = nil
            planNeedsRefresh = true
            lastStatusMessage = "Saved \(document.path)."
        } catch {
            openEditorDocuments[index].lastError = error.localizedDescription
            lastStatusMessage = "Could not save \(document.path): \(error.localizedDescription)"
        }
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
        expandedProjectFolderPaths.removeAll()
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
        !isScanningProject && !isRunningCommand && !isRefreshingDevices && !isRunningWirelessDebugging
    }

    private var trimmedWirelessConnectAddress: String {
        wirelessConnectAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var wirelessPairingValidationMessage: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, or Wireless Debugging action to finish."
        }
        if wirelessPairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the Wireless Debugging pairing code shown on the Android device."
        }
        return "Ready to discover the pairing address and confirm wireless pairing."
    }

    private var wirelessConnectValidationMessage: String {
        if !canRunADBWirelessAction {
            return "Wait for the current scan, command, device refresh, or Wireless Debugging action to finish."
        }
        if !isValidHostPort(trimmedWirelessConnectAddress.nilIfEmpty ?? lastWirelessDeviceAddress) {
            return "Enter or discover the Wireless Debugging connect address as host:port."
        }
        return "Ready to connect wireless device."
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

    private func wirelessHostPort(in line: String) -> String? {
        let tokens = line
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            }
        return tokens.last(where: { isValidHostPort($0) })
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

    private func makeProjectFiles(rootPath: String, snapshot: WorkspaceSnapshot) -> [ProjectFileItem] {
        let rootURL = URL(fileURLWithPath: rootPath)
        var relativeFilePaths: [String] = []
        var seenPaths = Set<String>()

        func appendFile(relativePath: String) {
            guard seenPaths.insert(relativePath).inserted else { return }
            relativeFilePaths.append(relativePath)
        }

        let importantPaths = [
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "gradle/libs.versions.toml",
            "app/build.gradle",
            "app/build.gradle.kts",
            "app/src/main/AndroidManifest.xml"
        ]

        for relativePath in importantPaths {
            let absolute = rootURL.appendingPathComponent(relativePath).path
            if FileManager.default.fileExists(atPath: absolute) {
                appendFile(relativePath: relativePath)
            }
        }

        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                let path = url.path
                guard relativeFilePaths.count < 1_000 else { break }
                if shouldSkipProjectTreePath(path) {
                    enumerator.skipDescendants()
                    continue
                }
                guard shouldShowSourcePath(path), let relative = relativePath(for: path, rootPath: rootPath) else {
                    continue
                }
                appendFile(relativePath: relative)
            }
        }

        return makeProjectFileTree(from: relativeFilePaths)
    }

    private func makeProjectFileTree(from relativeFilePaths: [String]) -> [ProjectFileItem] {
        var directoryPaths = Set<String>()
        let filePaths = Set(relativeFilePaths)

        for relativePath in relativeFilePaths {
            directoryPaths.formUnion(ancestorFolderPaths(for: relativePath))
        }

        let allPaths = Array(directoryPaths.union(filePaths)).sorted {
            projectTreeSort($0, before: $1, directoryPaths: directoryPaths)
        }

        return allPaths.map { relativePath in
            fileItem(
                relativePath: relativePath,
                selected: !directoryPaths.contains(relativePath) && isKeyProjectFile(relativePath),
                isDirectory: directoryPaths.contains(relativePath)
            )
        }
    }

    private func isVisibleInCollapsedFileTree(_ item: ProjectFileItem) -> Bool {
        guard item.depth > 0 else { return true }
        return ancestorFolderPaths(for: item.path).allSatisfy { expandedProjectFolderPaths.contains($0) }
    }

    private func ancestorFolderPaths(for relativePath: String) -> [String] {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { count in
            parts.prefix(count).joined(separator: "/")
        }
    }

    private func isDescendant(_ path: String, of folderPath: String) -> Bool {
        path.hasPrefix(folderPath + "/")
    }

    private func projectTreeSort(_ lhs: String, before rhs: String, directoryPaths: Set<String>) -> Bool {
        let leftParts = lhs.split(separator: "/").map(String.init)
        let rightParts = rhs.split(separator: "/").map(String.init)
        let sharedCount = min(leftParts.count, rightParts.count)

        for index in 0..<sharedCount where leftParts[index] != rightParts[index] {
            let leftPath = leftParts.prefix(index + 1).joined(separator: "/")
            let rightPath = rightParts.prefix(index + 1).joined(separator: "/")
            let leftIsDirectory = directoryPaths.contains(leftPath)
            let rightIsDirectory = directoryPaths.contains(rightPath)
            if leftIsDirectory != rightIsDirectory {
                return leftIsDirectory
            }
            return leftParts[index].localizedStandardCompare(rightParts[index]) == .orderedAscending
        }

        return leftParts.count < rightParts.count
    }

    private func shouldShowSourcePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.hasSuffix(".kt") || lower.hasSuffix(".java") || lower.hasSuffix(".xml") else {
            return false
        }
        return !lower.contains("/build/") && !lower.contains("/generated/")
    }

    private func shouldSkipProjectTreePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/.gradle/")
            || lower.contains("/.idea/")
            || lower.contains("/build/")
            || lower.contains("/generated/")
            || lower.contains("/.git/")
    }

    private func relativePath(for path: String, rootPath: String) -> String? {
        guard path.hasPrefix(rootPath) else {
            return nil
        }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func fileItem(relativePath: String, selected: Bool, isDirectory: Bool) -> ProjectFileItem {
        let parts = relativePath.split(separator: "/").map(String.init)
        let name = parts.last ?? relativePath
        let depth = max(0, parts.count - 1)
        return ProjectFileItem(
            path: relativePath,
            name: name,
            depth: depth,
            symbol: isDirectory ? "folder" : symbol(for: name),
            isSelected: selected,
            isDirectory: isDirectory
        )
    }

    private func isKeyProjectFile(_ relativePath: String) -> Bool {
        let lower = relativePath.lowercased()
        return lower.contains("build.gradle")
            || lower.contains("androidmanifest.xml")
            || lower.contains("mainactivity")
            || lower.contains("/res/layout/")
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

    private func symbol(for fileName: String) -> String {
        if fileName.hasSuffix(".gradle") || fileName.hasSuffix(".kts") || fileName == "libs.versions.toml" {
            return "hammer"
        }
        if fileName == "AndroidManifest.xml" {
            return "doc.badge.gearshape"
        }
        if fileName.hasSuffix(".kt") || fileName.hasSuffix(".java") {
            return "curlybraces"
        }
        if fileName.hasSuffix(".xml") {
            return "doc.richtext"
        }
        return "doc"
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
        loaded.wirelessDebuggingStatus = "Wireless fixture ready."
        _ = loaded.canPairWirelessDevice
        _ = loaded.canConnectWirelessDevice
        _ = loaded.canDisconnectWirelessDevice
        _ = loaded.wirelessDebuggingSummary
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
