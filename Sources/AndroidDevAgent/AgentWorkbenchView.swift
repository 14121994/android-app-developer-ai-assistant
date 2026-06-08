import AndroidDevAgentCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let agentWorkbenchVisiblePanelsKey = "AndroidDevAgentVisiblePanels"

private enum ToolWindowSide: Equatable {
    case left
    case right
}

private enum ToolWindowPanel: String, CaseIterable, Hashable, Identifiable {
    case workspace
    case androidTarget
    case runTools
    case files
    case projectIntelligence
    case editor
    case askAssistant
    case commandConsole
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .androidTarget: return "Android Target"
        case .runTools: return "Run Tools"
        case .files: return "Files"
        case .projectIntelligence: return "Project Intelligence"
        case .editor: return "Editor"
        case .askAssistant: return "Ask The Assistant"
        case .commandConsole: return "Command Console"
        case .session: return "Session"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: return "folder"
        case .androidTarget: return "slider.horizontal.3"
        case .runTools: return "wrench.and.screwdriver"
        case .files: return "list.bullet.rectangle"
        case .projectIntelligence: return "brain.head.profile"
        case .editor: return "curlybraces.square"
        case .askAssistant: return "text.bubble"
        case .commandConsole: return "terminal"
        case .session: return "rectangle.rightthird.inset.filled"
        }
    }

    var shortTitle: String {
        switch self {
        case .workspace: return "Workspace"
        case .androidTarget: return "Target"
        case .runTools: return "Tools"
        case .files: return "Files"
        case .projectIntelligence: return "Insights"
        case .editor: return "Editor"
        case .askAssistant: return "Ask"
        case .commandConsole: return "Console"
        case .session: return "Session"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .workspace: return "1"
        case .androidTarget: return "2"
        case .runTools: return "3"
        case .files: return "4"
        case .projectIntelligence: return "5"
        case .askAssistant: return "6"
        case .commandConsole: return "7"
        case .session: return "8"
        case .editor: return "9"
        }
    }

    var shortcutHint: String {
        switch self {
        case .workspace: return "Cmd-Option-1"
        case .androidTarget: return "Cmd-Option-2"
        case .runTools: return "Cmd-Option-3"
        case .files: return "Cmd-Option-4"
        case .projectIntelligence: return "Cmd-Option-5"
        case .askAssistant: return "Cmd-Option-6"
        case .commandConsole: return "Cmd-Option-7"
        case .session: return "Cmd-Option-8"
        case .editor: return "Cmd-Option-9"
        }
    }

    static let leftPanels: [ToolWindowPanel] = [.workspace, .androidTarget, .runTools, .files]
    static let rightPanels: [ToolWindowPanel] = [.projectIntelligence, .askAssistant, .commandConsole, .session]
    static let defaultVisible = Set<ToolWindowPanel>()
    static let starterVisible: Set<ToolWindowPanel> = [.workspace, .askAssistant, .session]
}

public struct AgentWorkbenchView: View {
    @StateObject private var viewModel = AgentViewModel()
    @State private var visiblePanels: Set<ToolWindowPanel>

    public init() {
        _visiblePanels = State(initialValue: Self.loadVisiblePanels())
    }

    public var body: some View {
        VStack(spacing: 0) {
            ShellTitleBar(viewModel: viewModel)
            Divider()
            HStack(spacing: 0) {
                ToolWindowRail(
                    side: .left,
                    panels: ToolWindowPanel.leftPanels,
                    visiblePanels: $visiblePanels
                )
                Divider()
                HSplitView {
                    if showsLeftFeaturePane {
                        WorkspaceSidebarPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 480)
                    }
                    if visiblePanels.contains(.editor) {
                        CenterEditorWorkspace(viewModel: viewModel, visiblePanels: $visiblePanels)
                            .frame(minWidth: 380, idealWidth: 760, maxWidth: .infinity)
                    } else {
                        EmptyToolWindowCanvas(viewModel: viewModel, visiblePanels: $visiblePanels)
                            .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity)
                    }
                    if showsRightFeaturePane {
                        RightToolDockPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                            .frame(minWidth: 320, idealWidth: 430, maxWidth: 560)
                    }
                }
                Divider()
                ToolWindowRail(
                    side: .right,
                    panels: ToolWindowPanel.rightPanels,
                    visiblePanels: $visiblePanels
                )
            }
        }
        .frame(minWidth: 1120, idealWidth: 1280, minHeight: 700, idealHeight: 820)
        .background(Palette.appBackground)
        .colorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Android Dev Agent workspace")
        .accessibilityIdentifier("Android Dev Agent workspace shell")
        .onChange(of: viewModel.filePanelRevealGeneration) { _, generation in
            if generation > 0 {
                visiblePanels.insert(.files)
            }
        }
        .onChange(of: visiblePanels) { _, panels in
            Self.saveVisiblePanels(panels)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let data = item as? Data
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url {
                    Task { @MainActor in
                        viewModel.selectDroppedItem(url: url)
                    }
                }
            }
            return true
        }
        .alert(item: $viewModel.pendingConfirmation) { confirmation in
            Alert(
                title: Text("Run \(confirmation.kind.rawValue)?"),
                message: Text(confirmation.message),
                primaryButton: .default(Text("Run"), action: viewModel.confirmPendingCommand),
                secondaryButton: .cancel(viewModel.cancelPendingCommand)
            )
        }
        .alert(item: $viewModel.pendingWirelessDebuggingConfirmation) { confirmation in
            let connectText = confirmation.connectAddress.map { "\nConnect address: \($0)" } ?? ""
            return Alert(
                title: Text("Pair Wireless Device?"),
                message: Text("Pairing address: \(confirmation.pairingAddress)\(connectText)"),
                primaryButton: .default(Text("Pair"), action: viewModel.confirmWirelessPairing),
                secondaryButton: .cancel(viewModel.cancelWirelessPairing)
            )
        }
    }

    private var showsLeftFeaturePane: Bool {
        ToolWindowPanel.leftPanels.contains { visiblePanels.contains($0) }
    }

    private var showsMainFeaturePane: Bool {
        visiblePanels.contains(.projectIntelligence)
            || visiblePanels.contains(.askAssistant)
            || visiblePanels.contains(.commandConsole)
    }

    private var showsRightFeaturePane: Bool {
        showsMainFeaturePane || visiblePanels.contains(.session)
    }

    private static func saveVisiblePanels(_ panels: Set<ToolWindowPanel>) {
        let values = panels.map(\.rawValue).sorted()
        UserDefaults.standard.set(values, forKey: agentWorkbenchVisiblePanelsKey)
    }

    private static func loadVisiblePanels() -> Set<ToolWindowPanel> {
        guard let values = UserDefaults.standard.stringArray(forKey: agentWorkbenchVisiblePanelsKey) else {
            return ToolWindowPanel.starterVisible
        }
        return Set(values.compactMap(ToolWindowPanel.init(rawValue:)))
    }
}

private struct ShellTitleBar: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "curlybraces.square.fill")
                .font(.title3)
                .foregroundStyle(Palette.teal)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Android Dev Agent")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(viewModel.projectSubtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            StatusPill(
                text: viewModel.isRunningCommand ? viewModel.lastCommandTitle : viewModel.confidenceDisplay,
                color: shellStatusColor(for: viewModel),
                symbol: viewModel.isRunningCommand ? "clock.arrow.circlepath" : viewModel.scanState.symbol
            )

            Text("v1.0")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.inputBackground))

            if viewModel.isRunningCommand || viewModel.isScanningProject || viewModel.isRefreshingDevices || viewModel.isRunningWirelessDebugging {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Busy")
            } else {
                Color.clear
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Palette.titleBar)
    }
}

private struct ToolWindowRail: View {
    let side: ToolWindowSide
    let panels: [ToolWindowPanel]
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        VStack(spacing: 7) {
            Text(side == .left ? "Primary" : "Assistant")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.muted)
                .padding(.top, 2)
                .accessibilityHidden(true)

            ForEach(panels) { panel in
                let actionTitle = "\(isVisible(panel) ? "Hide" : "Show") \(panel.title)"
                RailButton(
                    title: panel.shortTitle,
                    symbol: panel.symbol,
                    accessibilityTitle: "\(actionTitle) (\(panel.shortcutHint))",
                    accessibilityHelp: "\(isVisible(panel) ? "Closes" : "Opens") the \(panel.title) tool pane. Shortcut: \(panel.shortcutHint).",
                    identifier: "\(side == .left ? "Left" : "Right") tool window: \(panel.title)",
                    isSelected: isVisible(panel),
                    shortcut: panel.shortcut
                ) {
                    toggle(panel)
                }
                .frame(width: 64, height: 46)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .frame(width: 78)
        .background(Palette.titleBar)
        .accessibilityElement(children: .contain)
    }

    private func isVisible(_ panel: ToolWindowPanel) -> Bool {
        visiblePanels.contains(panel)
    }

    private func toggle(_ panel: ToolWindowPanel) {
        if visiblePanels.contains(panel) {
            visiblePanels.remove(panel)
        } else {
            visiblePanels.insert(panel)
        }
    }
}

private struct RailButton: View {
    let title: String
    let symbol: String
    let accessibilityTitle: String
    let accessibilityHelp: String
    let identifier: String
    let isSelected: Bool
    let shortcut: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 64, height: 46)
            .foregroundStyle(isSelected ? Palette.blue : Palette.railMuted)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Palette.railSelectedBackground : Palette.railBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Palette.railSelectedBorder : Palette.railBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [.command, .option])
        .help(accessibilityTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityHint(Text(accessibilityHelp))
        .accessibilityIdentifier(identifier)
    }
}

private struct EmptyToolWindowCanvas: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "curlybraces.square.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .accessibilityHidden(true)
            Text("Android Dev Agent")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(viewModel.isProjectLoaded ? "Workspace context is ready." : "Choose Workspace to scan an Android project, or Ask to draft a plan.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    visiblePanels.insert(.workspace)
                } label: {
                    Label("Workspace", systemImage: "folder")
                }
                .buttonStyle(ReadableProminentButtonStyle(color: Palette.blue))
                .namedControl("Open Workspace panel", hint: "Shows project selection and scan controls.")

                Button {
                    visiblePanels.insert(.askAssistant)
                } label: {
                    Label("Ask", systemImage: "text.bubble")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .namedControl("Open Ask The Assistant panel", hint: "Shows the prompt composer.")

                Button {
                    visiblePanels.insert(.session)
                } label: {
                    Label("Session", systemImage: "rectangle.rightthird.inset.filled")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .namedControl("Open Session panel", hint: "Shows chat, diagnostics, and checks.")
            }
            .controlSize(.small)

            if !savedPanels.isEmpty {
                Button {
                    visiblePanels = savedPanels
                } label: {
                    Label("Restore Last Layout", systemImage: "rectangle.3.group")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)
                .namedControl("Restore last panel layout", hint: "Reopens the tool panes you used previously.")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.workspace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Android Dev Agent start area")
    }

    private var savedPanels: Set<ToolWindowPanel> {
        let values = UserDefaults.standard.stringArray(forKey: agentWorkbenchVisiblePanelsKey) ?? []
        return Set(values.compactMap(ToolWindowPanel.init(rawValue:)))
    }
}

private struct WorkspaceSidebarPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if visiblePanels.contains(.workspace) {
                    HStack(spacing: 8) {
                        Button(action: viewModel.chooseProject) {
                            Label("Choose and Scan", systemImage: "folder.badge.gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ReadableProminentButtonStyle(color: Palette.blue))
                        .disabled(viewModel.isScanningProject)
                        .help("Choose an Android project and scan it immediately.")
                        .namedControl("Choose and scan Android workspace", hint: "Opens a folder picker and starts project scanning.")

                        Button(action: viewModel.chooseProjectOnly) {
                            Label("Select", systemImage: "folder")
                        }
                        .buttonStyle(ReadableBorderedButtonStyle())
                        .disabled(viewModel.isScanningProject)
                        .help("Choose a project folder without scanning yet.")
                        .namedControl("Select Android workspace without scanning", hint: "Opens a folder picker and leaves scanning under your control.")
                    }
                    .controlSize(.small)

                    ClosableSectionTitle("Workspace", symbol: "folder", panel: .workspace, visiblePanels: $visiblePanels)
                    WorkspacePathCard(viewModel: viewModel)
                }
                if visiblePanels.contains(.androidTarget) {
                    WorkspaceOptionsDisclosure(viewModel: viewModel)
                }
                if visiblePanels.contains(.runTools) {
                    SidebarToolList(viewModel: viewModel)
                }
                if visiblePanels.contains(.files) {
                    SidebarFileBrowser(viewModel: viewModel, visiblePanels: $visiblePanels)
                }
            }
            .padding(16)
        }
        .background(Palette.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary tool pane")
        .accessibilityIdentifier("Primary tool pane")
    }
}

private struct WorkspacePathCard: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.candidateProjectPathDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                DiagnosticRowView(row: viewModel.projectPathFeedback)

                TextField("Android project path", text: $viewModel.projectPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .disabled(viewModel.isScanningProject)
                    .onSubmit(viewModel.scanProject)
                    .namedControl("Android project path", hint: "Paste a project folder path, then press Return to scan.")

                HStack(spacing: 8) {
                    if viewModel.isScanningProject {
                        Button(action: viewModel.cancelScan) {
                            Label("Cancel Scan", systemImage: "xmark.circle")
                        }
                        .help("Cancel the current scan.")
                        .namedControl("Cancel project scan")
                    } else {
                        Button(action: viewModel.scanProject) {
                            Label(viewModel.isProjectLoaded ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                        }
                        .disabled(!viewModel.canScanProject)
                        .help(viewModel.projectPathFeedback.detail)
                        .namedControl(viewModel.isProjectLoaded ? "Rescan project" : "Scan project")
                    }

                    Button(action: viewModel.openProjectInFinder) {
                        Label("Reveal", systemImage: "folder")
                    }
                    .disabled(viewModel.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Reveal the selected path in Finder.")
                    .namedControl("Reveal selected project path")

                    Spacer(minLength: 0)
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                    Text("Drop a folder, paste a path, or choose a recent project.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                if !viewModel.recentProjectRows.isEmpty {
                    Menu {
                        ForEach(viewModel.recentProjectRows) { row in
                            Button(row.menuTitle) {
                                viewModel.selectProject(path: row.path, scanImmediately: row.exists)
                            }
                            Button("Remove \(row.name)") {
                                viewModel.removeRecentProject(row.path)
                            }
                        }
                        Divider()
                        Button("Clear Missing Projects") {
                            viewModel.clearMissingRecentProjects()
                        }
                        Button("Clear Recent Projects") {
                            viewModel.clearRecentProjects()
                        }
                    } label: {
                        HighContrastMenuLabel(title: "Recent Projects", symbol: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .colorScheme(.light)
                    .controlSize(.small)
                    .help("Open a recently scanned Android project.")
                    .namedControl("Recent projects")
                }
            }
        }
    }
}

private struct WorkspaceOptionsDisclosure: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ProjectMetricStrip(viewModel: viewModel)
                AndroidTargetCard(viewModel: viewModel)
            }
            .padding(.top, 8)
        } label: {
            SidebarSectionTitle("Android Target", symbol: "slider.horizontal.3")
        }
    }
}

private struct AndroidTargetCard: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Android Target", symbol: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gradle target")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        ReadableStringDropdown(
                            title: "Module",
                            selection: $viewModel.selectedModule,
                            options: viewModel.modules,
                            symbol: "square.stack.3d.up"
                        )
                        .namedControl("Gradle module")
                        ReadableStringDropdown(
                            title: "Variant",
                            selection: $viewModel.selectedVariant,
                            options: viewModel.buildVariants,
                            symbol: "tag"
                        )
                        .namedControl("Build variant")
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.isProjectLoaded)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Device")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        ReadableDeviceDropdown(viewModel: viewModel)
                        .disabled(viewModel.isRefreshingDevices || viewModel.isRunningWirelessDebugging || viewModel.devices.isEmpty)
                        .help(viewModel.deviceSummary)
                        .namedControl("Android device")

                        Button(action: viewModel.refreshDevices) {
                            Label(viewModel.isRefreshingDevices ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(ReadableBorderedButtonStyle())
                        .disabled(!viewModel.canRefreshDevices)
                        .help("Refresh attached Android devices. This does not require a loaded project.")
                        .namedControl("Refresh Android devices")
                    }
                    .controlSize(.small)
                    Text(viewModel.deviceSummary)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Wireless Debugging")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                        Spacer(minLength: 0)
                        if viewModel.isRunningWirelessDebugging {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Wireless Debugging running")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Code", text: $viewModel.wirelessPairingCode)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .namedControl("Wireless pairing code", hint: "Enter only the pairing code. The pairing address is discovered and shown in the confirmation popup.")
                            Button(action: viewModel.pairWirelessDevice) {
                                Label("Pair", systemImage: "link.badge.plus")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .disabled(!viewModel.canPairWirelessDevice)
                            .namedControl("Pair wireless Android device")
                        }

                        HStack(spacing: 8) {
                            TextField("Connect address 192.168.1.10:42177", text: $viewModel.wirelessConnectAddress)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .namedControl("Wireless connect address", hint: "Enter the host and connect port shown in Android Wireless Debugging.")
                            Button(action: viewModel.connectWirelessDevice) {
                                Label("Connect", systemImage: "wifi")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .disabled(!viewModel.canConnectWirelessDevice)
                            .namedControl("Connect wireless Android device")
                            Button(action: viewModel.disconnectWirelessDevice) {
                                Label("Disconnect", systemImage: "wifi.slash")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .disabled(!viewModel.canDisconnectWirelessDevice)
                            .namedControl("Disconnect wireless Android device")
                        }
                    }
                    .controlSize(.small)

                    Text(viewModel.wirelessDebuggingSummary)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Launch package")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    TextField("Package override for Launch", text: $viewModel.packageOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .disabled(!viewModel.isProjectLoaded)
                        .namedControl("Launch package override", hint: "Overrides the detected package used for Launch.")
                    if viewModel.isProjectLoaded {
                        HStack(spacing: 6) {
                            Text("Detected: \(viewModel.profile.packageName)")
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button(action: viewModel.resetLaunchPackageToDetected) {
                                Label("Use Detected", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .controlSize(.small)
                            .namedControl("Use detected launch package", hint: "Copies the detected package into the launch package field.")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Launch activity")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    TextField("Launch activity, for example .MainActivity", text: $viewModel.launchActivity)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .disabled(!viewModel.isProjectLoaded)
                        .namedControl("Launch activity")
                }

                DiagnosticRowView(row: viewModel.launchTargetFeedback)
            }
        }
    }
}

private struct ReadableStringDropdown: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    let symbol: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Label(option, systemImage: option == selection ? "checkmark" : "circle")
                }
            }
        } label: {
            DropdownLabel(
                title: title,
                value: selection.isEmpty ? "None" : selection,
                symbol: symbol,
                isEnabled: !options.isEmpty
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .colorScheme(.light)
        .disabled(options.isEmpty)
    }
}

private struct ReadableDeviceDropdown: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Menu {
            Button("Refresh Devices") {
                viewModel.refreshDevices()
            }
            .disabled(!viewModel.canRefreshDevices)
            Divider()
            Button {
                viewModel.selectedDeviceID = ""
            } label: {
                Label("No device", systemImage: viewModel.selectedDeviceID.isEmpty ? "checkmark" : "circle")
            }
            ForEach(viewModel.devices) { device in
                Button {
                    viewModel.selectedDeviceID = device.id
                } label: {
                    Label(device.displayName, systemImage: viewModel.selectedDeviceID == device.id ? "checkmark" : "circle")
                }
            }
        } label: {
            DropdownLabel(
                title: "Device",
                value: selectedDeviceTitle,
                symbol: "iphone.gen3",
                isEnabled: !viewModel.isRefreshingDevices && !viewModel.isRunningWirelessDebugging
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .colorScheme(.light)
    }

    private var selectedDeviceTitle: String {
        guard !viewModel.selectedDeviceID.isEmpty else { return "No device" }
        return viewModel.devices.first(where: { $0.id == viewModel.selectedDeviceID })?.displayName ?? viewModel.selectedDeviceID
    }
}

private struct DropdownLabel: View {
    let title: String
    let value: String
    let symbol: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? Palette.blue : Palette.muted)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Palette.muted)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minWidth: 118, maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(isEnabled ? Palette.surface : Palette.inputBackground))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
        .opacity(isEnabled ? 1 : 0.72)
    }
}

private struct AssistantModelBindingDropdown: View {
    let mode: AssistantModelMode
    @State private var showsModels = false

    var body: some View {
        Button {
            showsModels.toggle()
        } label: {
            DropdownLabel(
                title: "Models bound to \(mode.title)",
                value: mode.boundModelSummary,
                symbol: "cpu",
                isEnabled: true
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsModels, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "cpu")
                        .foregroundStyle(Palette.blue)
                        .accessibilityHidden(true)
                    Text("\(mode.title) mode bindings")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                }

                Text(mode.detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                ForEach(mode.boundModels) { model in
                    AssistantModelBindingRow(model: model)
                }

                Text("Read-only model bindings. Change the mode above to change routing.")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 340)
            .background(Palette.surface)
        }
        .help("Show the models bound to \(mode.title). Model rows are informational only.")
        .accessibilityLabel("Models bound to \(mode.title)")
        .accessibilityHint("Opens a read-only list of models used by this Ask mode.")
    }
}

private struct AssistantModelBindingRow: View {
    let model: AssistantBoundModelInfo

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: model.provider == .openAI ? "sparkles" : "lock.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.provider == .openAI ? Palette.blue : Palette.teal)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text(model.provider.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.inputBackground))
                }

                Text(model.modelID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Palette.muted)

                Text(model.route)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)

                Text(model.purpose)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.noticeBackground))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName), \(model.modelID), \(model.provider.rawValue), \(model.route)")
    }
}

private struct SidebarFileBrowser: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Search files", text: $viewModel.fileSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .disabled(!viewModel.isProjectLoaded)
                        .namedControl("Search project files", hint: "Filters indexed project files by name or path.")
                    if !viewModel.fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: viewModel.clearFileSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.muted)
                        .help("Clear file search.")
                        .namedControl("Clear file search", hint: "Clears the current file filter.")
                    }
                }

                HStack(spacing: 6) {
                    Button(action: viewModel.expandAllProjectFolders) {
                        Label("Expand", systemImage: "plus.square.on.square")
                    }
                    .disabled(!viewModel.isProjectLoaded)
                    .help("Expand all folders.")
                    .namedControl("Expand all project folders")

                    Button(action: viewModel.collapseAllProjectFolders) {
                        Label("Collapse", systemImage: "minus.square")
                    }
                    .disabled(!viewModel.isProjectLoaded)
                    .help("Collapse all folders.")
                    .namedControl("Collapse all project folders")

                    Spacer(minLength: 0)

                    Button(action: viewModel.scanProject) {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(!viewModel.canScanProject)
                    .help("Rescan the workspace and refresh the file tree.")
                    .namedControl("Rescan project files", hint: "Refreshes project analysis and indexed files.")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)

                if viewModel.isProjectLoaded {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.projectPathDisplay)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text(viewModel.fileSearchSummary)
                            .font(.caption2)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.inputBackground))

                    if viewModel.filteredProjectFiles.isEmpty {
                        EmptyProjectPlaceholder(
                            symbol: "doc.text.magnifyingglass",
                            title: "No key files found",
                            message: viewModel.fileSearchQuery.isEmpty ? "The scan found Android markers but no common Gradle, manifest, Kotlin, Java, or XML files." : "No scanned file matches the current search."
                        )
                    } else {
                        VStack(spacing: 4) {
                            ForEach(viewModel.filteredProjectFiles) { item in
                                ProjectFileRow(item: item, viewModel: viewModel, visiblePanels: $visiblePanels)
                            }
                        }
                    }
                } else {
                    EmptyProjectPlaceholder(
                        symbol: viewModel.isScanningProject ? "arrow.triangle.2.circlepath" : "folder.badge.plus",
                        title: viewModel.isScanningProject ? "Scanning project" : "No project selected",
                        message: viewModel.isScanningProject ? "Files will appear after the scan completes." : "Choose an Android project to scan files."
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            SidebarSectionTitle("Files", symbol: "list.bullet.rectangle")
        }
    }

}

private struct SidebarToolList: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                ForEach(AndroidCommandKind.allCases) { command in
                    SidebarToolRow(command: command, viewModel: viewModel)
                }
                if !viewModel.canRunTools {
                    Text(viewModel.isScanningProject ? "Tools unlock after scanning finishes. You can cancel the scan from Workspace." : "Click a tool to see exactly what is needed before it can run.")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        } label: {
            SidebarSectionTitle("Run Tools", symbol: "wrench.and.screwdriver")
        }
    }
}

private struct SidebarToolRow: View {
    let command: AndroidCommandKind
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Button {
            viewModel.runCommand(command)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: command.symbol)
                    .foregroundStyle(Palette.blue)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(command.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(command.requiresDevice ? "Device Tool" : "Android Tool")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                    Text(command.shellDescription)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ToolStateBadge(text: stateText, color: stateColor)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
        }
        .buttonStyle(.plain)
        .opacity(viewModel.canRunCommand(command) ? 1 : 0.72)
        .help(helpText)
        .namedControl("\(command.rawValue), \(stateText)")
    }

    private var stateText: String {
        viewModel.commandStateText(command)
    }

    private var stateColor: Color {
        switch stateText {
        case "Ready": return Palette.teal
        case "Confirm": return Palette.amber
        case "Scan first", "Select device", "Set package", "Set activity": return Palette.amber
        default: return Palette.muted
        }
    }

    private var helpText: String {
        viewModel.commandHelpText(command)
    }
}

private struct ToolStateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.11)))
            .lineLimit(1)
    }
}

private struct MainWorkspaceContentPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatusInfoBar(viewModel: viewModel)

                if visiblePanels.contains(.projectIntelligence) {
                    ClosableSectionTitle("Project Intelligence", symbol: "brain.head.profile", panel: .projectIntelligence, visiblePanels: $visiblePanels)
                    ProjectIntelligenceCard(viewModel: viewModel)
                }

                if visiblePanels.contains(.askAssistant) {
                    ClosableSectionTitle("Ask The Assistant", symbol: "text.bubble", panel: .askAssistant, visiblePanels: $visiblePanels)
                    AskAssistantCard(viewModel: viewModel)
                }

                if visiblePanels.contains(.commandConsole) {
                    ClosableSectionTitle("Command Console", symbol: "terminal", panel: .commandConsole, visiblePanels: $visiblePanels)
                    BuildLogCard(viewModel: viewModel)
                }
            }
            .padding(22)
        }
        .background(Palette.workspace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant feature pane")
        .accessibilityIdentifier("Assistant feature pane")
    }
}

private struct RightToolDockPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        Group {
            if showsMainFeatures && visiblePanels.contains(.session) {
                VSplitView {
                    MainWorkspaceContentPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                        .frame(minHeight: 300, idealHeight: 430, maxHeight: .infinity)
                    SessionPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                        .frame(minHeight: 280, idealHeight: 360, maxHeight: .infinity)
                }
            } else {
                singlePaneContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.inspector)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right assistant dock")
        .accessibilityIdentifier("Right assistant dock")
    }

    @ViewBuilder
    private var singlePaneContent: some View {
        VStack(spacing: 0) {
            if showsMainFeatures {
                MainWorkspaceContentPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if visiblePanels.contains(.session) {
                SessionPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var showsMainFeatures: Bool {
        visiblePanels.contains(.projectIntelligence)
            || visiblePanels.contains(.askAssistant)
            || visiblePanels.contains(.commandConsole)
    }
}

private struct CenterEditorWorkspace: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        FileEditorPane(viewModel: viewModel, visiblePanels: $visiblePanels)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.workspace)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Editor workspace")
            .accessibilityIdentifier("Editor workspace")
    }
}

private enum EditorCloseTarget: Identifiable {
    case document(path: String, name: String)
    case all(count: Int, dirtyCount: Int)

    var id: String {
        switch self {
        case let .document(path, _): return "document-\(path)"
        case .all: return "all-editor-documents"
        }
    }

    var alertTitle: String {
        switch self {
        case let .document(_, name): return "Close \(name)?"
        case let .all(count, _): return "Close \(count) editor file\(count == 1 ? "" : "s")?"
        }
    }

    var alertMessage: String {
        switch self {
        case .document:
            return "This file has unsaved changes. Closing it will discard those changes."
        case let .all(_, dirtyCount):
            return "\(dirtyCount) open editor file\(dirtyCount == 1 ? " has" : "s have") unsaved changes. Closing all files will discard those changes."
        }
    }

    var confirmTitle: String {
        switch self {
        case .document: return "Discard and Close"
        case .all: return "Discard and Close All"
        }
    }
}

private struct StatusInfoBar: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if viewModel.isScanningProject {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning project")
            } else {
                Image(systemName: viewModel.scanState.symbol)
                    .foregroundStyle(shellStatusColor(for: viewModel))
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Status")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(viewModel.lastStatusMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.isScanningProject {
                    Text(viewModel.scanProgressSummary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.amber)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.workspaceSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Text(viewModel.recommendedActionDetail)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                Button(action: viewModel.performRecommendedAction) {
                    Label(viewModel.recommendedActionTitle, systemImage: "arrow.right.circle")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)
                .help(viewModel.recommendedActionDetail)
                .namedControl("Recommended action: \(viewModel.recommendedActionTitle)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.noticeBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
        .accessibilityElement(children: .contain)
    }
}

private struct ProjectIntelligenceCard: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(projectSummary)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.isProjectLoaded {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            projectPills
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            projectPills
                        }
                    }
                }

                PlanPreviewDisclosure(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var projectPills: some View {
        StatusPill(text: viewModel.profile.packageName, color: Palette.blue, symbol: "shippingbox")
        StatusPill(text: viewModel.snapshot.usesCompose ? "Compose" : "XML/Mixed", color: Palette.teal, symbol: "square.stack.3d.up")
        StatusPill(text: "min SDK \(viewModel.profile.minSDK)", color: Palette.amber, symbol: "iphone.gen3")
    }

    private var projectSummary: String {
        if viewModel.isProjectLoaded {
            return """
            \(viewModel.workspaceSummary). Package \(viewModel.profile.packageName). Current assistant intent: \(viewModel.plan.intent). Commands run inside \(viewModel.projectPathDisplay).
            """
        }
        return "No workspace scanned yet. Select an Android project, then scan it to load Gradle, manifest, source, resource, and test signals."
    }
}

private struct PlanPreviewDisclosure: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.planNeedsRefresh {
                    DiagnosticRowView(row: DiagnosticRow(
                        title: "Plan refresh recommended",
                        detail: "Editor changes can make the current plan stale. Refresh before running verification.",
                        symbol: "arrow.triangle.2.circlepath",
                        severity: "warning"
                    ))
                }

                ForEach(viewModel.plan.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(step.order)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(planStepColor(step)))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(step.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                ToolStateBadge(text: viewModel.displayState(for: step), color: planStepColor(step))
                            }
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(action: { viewModel.generatePlan() }) {
                        Label(viewModel.planNeedsRefresh ? "Refresh Plan" : "Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .namedControl("Regenerate assistant plan", hint: "Refreshes the assistant plan from the current prompt and workspace context.")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)
            }
            .padding(.top, 8)
        } label: {
            Label("Assistant Plan", systemImage: "list.bullet.clipboard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
    }

    private func planStepColor(_ step: AgentPlanStep) -> Color {
        switch viewModel.displaySeverity(for: step) {
        case "ready": return Palette.teal
        case "running": return Palette.amber
        case "failed": return Palette.red
        default: return Palette.blue
        }
    }
}

private struct FileEditorPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @State private var pendingCloseTarget: EditorCloseTarget?
    @State private var editorFindQuery = ""
    @State private var editorReplaceText = ""

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionHeader(title: "Editor", symbol: "curlybraces.square")
                    Spacer()
                    if viewModel.dirtyEditorDocumentCount > 0 {
                        StatusPill(
                            text: "\(viewModel.dirtyEditorDocumentCount) unsaved",
                            color: Palette.amber,
                            symbol: "circle.fill"
                        )
                    }
                }

                if viewModel.openEditorDocuments.isEmpty {
                    EmptyProjectPlaceholder(
                        symbol: "doc.text.magnifyingglass",
                        title: "No file open",
                        message: "Open a project file from Files to edit it here."
                    )
                } else {
                    editorTabs

                    if let document = viewModel.selectedEditorDocument {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(document.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.muted)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                Text(editorMetadata(for: document))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.teal)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Palette.teal.opacity(0.11)))
                            }

                            if let error = document.lastError {
                                Text(error)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: 8) {
                                TextField("Find in file", text: $editorFindQuery)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .namedControl("Find in editor file", hint: "Counts matches in the selected editor document.")
                                TextField("Replace with", text: $editorReplaceText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .namedControl("Replace text in editor file", hint: "Replacement text used by Replace All.")
                                Text(editorFindSummary(in: document))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Palette.muted)
                                    .frame(minWidth: 74, alignment: .trailing)
                                Button(action: { viewModel.replaceInSelectedEditorDocument(find: editorFindQuery, replacement: editorReplaceText) }) {
                                    Label("Replace All", systemImage: "arrow.left.arrow.right")
                                }
                                .buttonStyle(ReadableBorderedButtonStyle())
                                .disabled(editorFindQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .namedControl("Replace all matches in editor file", hint: "Replaces every case-insensitive match in the selected file.")
                                Button(action: { editorFindQuery = "" }) {
                                    Label("Clear", systemImage: "xmark.circle")
                                }
                                .buttonStyle(ReadableBorderedButtonStyle())
                                .disabled(editorFindQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .namedControl("Clear editor find", hint: "Clears the editor find query.")
                            }
                            .controlSize(.small)

                            Text(viewModel.selectedEditorLintSummary)
                                .font(.caption2)
                                .foregroundStyle(viewModel.selectedEditorLintSummary.contains("issue") ? Palette.amber : Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            CodeEditor(
                                text: editorContentBinding,
                                fileName: document.name,
                                accessibilityLabel: "File editor for \(document.name)"
                            )
                            .frame(minHeight: 380, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(document.lastError == nil ? Palette.border : Palette.red.opacity(0.45)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            HStack(spacing: 8) {
                                Button(action: viewModel.saveSelectedEditorDocument) {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                }
                                .disabled(!document.isDirty)
                                .keyboardShortcut("s", modifiers: [.command])
                                .namedControl("Save editor file")

                                Button(action: viewModel.revertSelectedEditorDocument) {
                                    Label("Revert", systemImage: "arrow.uturn.backward")
                                }
                                .disabled(!document.isDirty)
                                .namedControl("Revert editor file")

                                Button(action: { _ = viewModel.saveAndCloseSelectedEditorDocument(); hideEditorIfEmpty() }) {
                                    Label("Save & Close", systemImage: "checkmark.square")
                                }
                                .disabled(!document.isDirty)
                                .namedControl("Save and close editor file", hint: "Saves this file, then closes its editor tab.")

                                Button(action: requestCloseSelectedEditorDocument) {
                                    Label("Close", systemImage: "xmark.circle")
                                }
                                .help(document.isDirty ? "Close this editor tab and confirm discarding unsaved changes." : "Close this editor tab.")
                                .namedControl("Close editor file")

                                Spacer()

                                Button(action: viewModel.saveAllEditorDocuments) {
                                    Label("Save All", systemImage: "tray.and.arrow.down")
                                }
                                .disabled(viewModel.dirtyEditorDocumentCount == 0)
                                .keyboardShortcut("s", modifiers: [.command, .shift])
                                .namedControl("Save all editor files")

                                Button(action: requestCloseAllEditorDocuments) {
                                    Label("Close All", systemImage: "xmark.square")
                                }
                                .disabled(viewModel.openEditorDocuments.isEmpty)
                                .help("Close every open editor tab.")
                                .namedControl("Close all editor files")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .controlSize(.small)

                            HStack(spacing: 8) {
                                Button(action: viewModel.reloadSelectedEditorDocument) {
                                    Label("Reload", systemImage: "arrow.clockwise")
                                }
                                .namedControl("Reload selected editor file", hint: "Reloads this file from disk.")

                                Button(action: viewModel.formatSelectedEditorDocument) {
                                    Label("Format", systemImage: "wand.and.stars")
                                }
                                .namedControl("Format selected editor file", hint: "Removes trailing whitespace while preserving indentation.")

                                Button(action: viewModel.revealSelectedEditorDocumentInFinder) {
                                    Label("Reveal", systemImage: "folder")
                                }
                                .namedControl("Reveal selected editor file", hint: "Shows this file in Finder.")

                                Button(action: viewModel.openSelectedEditorDocumentExternally) {
                                    Label("External", systemImage: "arrow.up.right.square")
                                }
                                .namedControl("Open selected editor file externally", hint: "Opens this file with the default macOS app.")

                                Button(action: { viewModel.copySelectedEditorPath(absolute: false) }) {
                                    Label("Copy Path", systemImage: "doc.on.doc")
                                }
                                .namedControl("Copy selected editor relative path", hint: "Copies the file path relative to the project.")

                                Spacer()
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .controlSize(.small)

                            Text(viewModel.editorStatusSummary)
                                .font(.caption2)
                                .foregroundStyle(viewModel.planNeedsRefresh ? Palette.amber : Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(item: $pendingCloseTarget) { target in
            Alert(
                title: Text(target.alertTitle),
                message: Text(target.alertMessage),
                primaryButton: .destructive(Text(target.confirmTitle)) {
                    close(target, discardingChanges: true)
                },
                secondaryButton: .cancel()
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File editor pane")
        .accessibilityIdentifier("File editor pane")
    }

    private var editorTabs: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 6) {
                ForEach(viewModel.openEditorDocuments) { document in
                    HStack(spacing: 2) {
                        Button {
                            viewModel.selectEditorDocument(document)
                        } label: {
                            HStack(spacing: 5) {
                                if document.isDirty {
                                    Text("Edited")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(isSelected(document) ? Color.white : Palette.amber)
                                }
                                Text(document.name)
                                    .lineLimit(1)
                                    .foregroundColor(isSelected(document) ? Color.white : Palette.ink)
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: 220, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help(document.path)
                        .namedControl("Open editor tab \(document.path)")

                        Button {
                            requestClose(document)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 22, height: 22)
                                .foregroundColor(isSelected(document) ? Color.white : Palette.muted)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(document.isDirty ? "Close and confirm discarding unsaved changes." : "Close this editor tab.")
                        .namedControl("Close editor tab \(document.path)")
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 5)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected(document) ? Palette.blue : Palette.inputBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isSelected(document) ? Palette.blue.opacity(0.75) : Palette.border)
                    )
                }
            }
        }
    }

    private func isSelected(_ document: EditorDocument) -> Bool {
        document.path == viewModel.selectedEditorDocument?.path
    }

    private func lineNumberRange(for document: EditorDocument) -> [Int] {
        let count = max(1, document.content.split(separator: "\n", omittingEmptySubsequences: false).count)
        return Array(1...count)
    }

    private func editorMetadata(for document: EditorDocument) -> String {
        let lineCount = lineNumberRange(for: document).count
        let type = document.name.split(separator: ".").last.map { ".\($0)" } ?? "text"
        return "\(type) · \(lineCount) line\(lineCount == 1 ? "" : "s") · UTF-8"
    }

    private func editorFindSummary(in document: EditorDocument) -> String {
        let query = editorFindQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "Find" }
        var matches = 0
        var searchStart = document.content.startIndex
        while searchStart < document.content.endIndex,
              let range = document.content.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<document.content.endIndex) {
            matches += 1
            searchStart = range.upperBound
        }
        return "\(matches) match\(matches == 1 ? "" : "es")"
    }

    private var editorContentBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedEditorContent },
            set: { viewModel.updateSelectedEditorContent($0) }
        )
    }

    private func requestCloseSelectedEditorDocument() {
        guard let document = viewModel.selectedEditorDocument else { return }
        requestClose(document)
    }

    private func requestClose(_ document: EditorDocument) {
        if document.isDirty {
            pendingCloseTarget = .document(path: document.path, name: document.name)
        } else {
            _ = viewModel.closeEditorDocument(path: document.path)
            hideEditorIfEmpty()
        }
    }

    private func requestCloseAllEditorDocuments() {
        let dirtyCount = viewModel.dirtyEditorDocumentCount
        if dirtyCount > 0 {
            pendingCloseTarget = .all(count: viewModel.openEditorDocuments.count, dirtyCount: dirtyCount)
        } else {
            _ = viewModel.closeAllEditorDocuments()
            hideEditorIfEmpty()
        }
    }

    private func close(_ target: EditorCloseTarget, discardingChanges: Bool) {
        switch target {
        case let .document(path, _):
            _ = viewModel.closeEditorDocument(path: path, discardingChanges: discardingChanges)
        case .all:
            _ = viewModel.closeAllEditorDocuments(discardingChanges: discardingChanges)
        }
        hideEditorIfEmpty()
    }

    private func hideEditorIfEmpty() {
        if viewModel.openEditorDocuments.isEmpty {
            visiblePanels.remove(.editor)
        }
    }
}

private struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let fileName: String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.string = text
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1.0)
        textView.backgroundColor = .white
        textView.insertionPointColor = NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1.0)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityIdentifier("File editor")

        scrollView.documentView = textView
        let ruler = CodeLineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        context.coordinator.textView = textView
        context.coordinator.rulerView = ruler
        context.coordinator.applyHighlighting(fileName: fileName)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            context.coordinator.isUpdatingFromSwiftUI = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isUpdatingFromSwiftUI = false
        }
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.applyHighlighting(fileName: fileName)
        context.coordinator.rulerView?.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: NSTextView?
        weak var rulerView: CodeLineNumberRulerView?
        var isUpdatingFromSwiftUI = false

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingFromSwiftUI else { return }
            parent.text = textView.string
            applyHighlighting(fileName: parent.fileName)
            rulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            rulerView?.needsDisplay = true
        }

        func applyHighlighting(fileName: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let selectedRanges = textView.selectedRanges
            let text = textView.string as NSString
            let fullRange = NSRange(location: 0, length: text.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let baseColor = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.13, alpha: 1.0)

            storage.beginEditing()
            storage.setAttributes([.font: baseFont, .foregroundColor: baseColor], range: fullRange)

            apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: NSColor(calibratedRed: 0.64, green: 0.23, blue: 0.09, alpha: 1.0), range: fullRange, storage: storage)
            apply(pattern: #"//.*"#, color: NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.54, alpha: 1.0), range: fullRange, storage: storage)
            apply(pattern: #"/\*[\s\S]*?\*/"#, color: NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.54, alpha: 1.0), range: fullRange, storage: storage)

            if fileName.lowercased().hasSuffix(".xml") {
                apply(pattern: #"</?[\w:.-]+|/?>"#, color: NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1.0), range: fullRange, storage: storage)
                apply(pattern: #"[\w:.-]+(?=\=)"#, color: NSColor(calibratedRed: 0.06, green: 0.46, blue: 0.43, alpha: 1.0), range: fullRange, storage: storage)
            } else {
                let keywords = [
                    "android", "break", "case", "catch", "class", "data", "default", "do", "else", "enum",
                    "extension", "false", "final", "for", "fun", "if", "import", "in", "interface", "let",
                    "new", "nil", "null", "object", "open", "override", "package", "private", "protected",
                    "public", "return", "sealed", "static", "struct", "switch", "true", "try", "val", "var",
                    "void", "when", "while"
                ].joined(separator: "|")
                apply(pattern: #"(?<![A-Za-z0-9_])(\#(keywords))(?![A-Za-z0-9_])"#, color: NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1.0), range: fullRange, storage: storage)
                apply(pattern: #"@[A-Za-z_][A-Za-z0-9_]*"#, color: NSColor(calibratedRed: 0.70, green: 0.33, blue: 0.04, alpha: 1.0), range: fullRange, storage: storage)
            }

            storage.endEditing()
            textView.selectedRanges = selectedRanges
        }

        private func apply(pattern: String, color: NSColor, range: NSRange, storage: NSTextStorage) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            regex.enumerateMatches(in: storage.string, range: range) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }
}

private final class CodeLineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsDisplayForTextViewScroll),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).setFill()
        bounds.fill()

        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let text = textView.string as NSString
        let textContainerOrigin = textView.textContainerOrigin
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.54, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { _, usedRect, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let lineNumber = text.substring(to: min(characterRange.location, text.length)).filter { $0 == "\n" }.count + 1
            let lineString = "\(lineNumber)" as NSString
            let drawRect = NSRect(
                x: 4,
                y: usedRect.minY + textContainerOrigin.y + 1,
                width: self.ruleThickness - 10,
                height: usedRect.height
            )
            lineString.draw(in: drawRect, withAttributes: attributes)
        }
    }

    @objc private func needsDisplayForTextViewScroll() {
        needsDisplay = true
    }
}

private struct AskAssistantCard: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Label(viewModel.promptContextSummary, systemImage: viewModel.planNeedsRefresh ? "exclamationmark.triangle" : "scope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(viewModel.planNeedsRefresh ? Palette.amber : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(viewModel.promptMetricsSummary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }

            modelRouteSurface

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.prompt)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.blue)
                    .colorScheme(.light)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
                    .help("Describe the Android development task for the plan.")
                    .namedControl("Agent prompt")

                if viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Describe the Android task, crash, UI change, test gap, or release check.")
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                }
            }

            assistantResponseSurface

            ViewThatFits(in: .horizontal) {
                promptToolbar
                VStack(alignment: .leading, spacing: 8) {
                    promptToolbar
                }
            }
            .controlSize(.small)
        }
    }

    private var modelRouteSurface: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                Label(viewModel.assistantModelRouteSummary, systemImage: viewModel.isAssistantThinking ? "cpu.fill" : "cpu")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(viewModel.isAssistantThinking ? Palette.amber : Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Picker("AI mode", selection: $viewModel.assistantModelMode) {
                    ForEach(AssistantModelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 250)
                .namedControl("Assistant model mode", hint: "Selects the Ask routing mode.")
            }

            AssistantModelBindingDropdown(mode: viewModel.assistantModelMode)
                .namedControl("Bound assistant models", hint: "Shows the models bound to the selected Ask mode. The model rows are read-only.")

            Text(viewModel.taskDroidRouteSummary)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !viewModel.assistantModelDetail.isEmpty {
                Text(viewModel.assistantModelDetail)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.noticeBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }

    @ViewBuilder
    private var assistantResponseSurface: some View {
        let response = viewModel.assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = viewModel.assistantActionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !response.isEmpty || !actions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                assistantResponseHeader(hasResponse: !response.isEmpty, hasActions: !actions.isEmpty)

                if !response.isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(response)
                            .font(.caption)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(minHeight: 92, maxHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
                    .namedControl("Assistant response", hint: "Shows the project-specific answer generated from the current prompt.")
                }

                if !actions.isEmpty {
                    Label(actions, systemImage: "bolt.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.teal)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.teal.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.teal.opacity(0.35)))
                        .namedControl("Assistant automatic actions")
                }

                if !viewModel.assistantResponseExportAvailabilityMessage.isEmpty {
                    Text(viewModel.assistantResponseExportAvailabilityMessage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func assistantResponseHeader(hasResponse: Bool, hasActions: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                assistantResponseTitle
                Spacer(minLength: 8)
                assistantResponseHeaderControls(hasResponse: hasResponse, hasActions: hasActions)
            }

            VStack(alignment: .leading, spacing: 6) {
                assistantResponseTitle
                assistantResponseHeaderControls(hasResponse: hasResponse, hasActions: hasActions)
            }
        }
    }

    private var assistantResponseTitle: some View {
        Label("Assistant Response", systemImage: "text.bubble.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ink)
    }

    @ViewBuilder
    private func assistantResponseHeaderControls(hasResponse: Bool, hasActions: Bool) -> some View {
        if hasResponse {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    assistantResponseInlineActions
                    if !viewModel.assistantResponseFeedback.isEmpty {
                        assistantResponseFeedbackBadge
                    }
                    if hasActions {
                        assistantActedBadge
                    }
                }

                HStack(spacing: 6) {
                    assistantResponseActionsMenu
                    if !viewModel.assistantResponseFeedback.isEmpty {
                        assistantResponseFeedbackBadge
                    }
                    if hasActions {
                        assistantActedBadge
                    }
                }
            }
        } else if hasActions {
            assistantActedBadge
        }
    }

    @ViewBuilder
    private var assistantResponseInlineActions: some View {
        Button(action: viewModel.copyAssistantResponse) {
            Label("Copy Response", systemImage: "doc.on.doc")
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .help("Copy the generated assistant response.")
        .namedControl("Copy assistant response", hint: "Copies the generated assistant response to the clipboard.")

        Button(action: viewModel.exportAssistantResponse) {
            Label("Export Response", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .help("Export the generated assistant response as a text file.")
        .namedControl("Export assistant response", hint: "Writes the generated assistant response to a temporary text file.")

        if !viewModel.assistantResponseExportPath.isEmpty {
            Button(action: viewModel.copyAssistantResponseExportPath) {
                Label("Copy Path", systemImage: "link")
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .controlSize(.small)
            .disabled(!viewModel.hasAssistantResponseExportFile)
            .help("Copy the exported assistant response path.")
            .namedControl("Copy assistant response export path", hint: "Copies the exported assistant response file path to the clipboard.")

            Button(action: viewModel.needsAskExportRecoveryAction ? viewModel.exportAssistantResponse : viewModel.openAssistantResponseExport) {
                Label(
                    viewModel.needsAskExportRecoveryAction ? "Re-export" : "Open Export",
                    systemImage: viewModel.needsAskExportRecoveryAction ? "arrow.clockwise.circle" : "arrow.up.right.square"
                )
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .controlSize(.small)
            .disabled(viewModel.needsAskExportRecoveryAction ? viewModel.assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !viewModel.hasAssistantResponseExportFile)
            .help(viewModel.needsAskExportRecoveryAction ? "Export the assistant response again because the previous export path is stale." : "Open the exported assistant response.")
            .namedControl(viewModel.needsAskExportRecoveryAction ? "Re-export assistant response" : "Open assistant response export", hint: viewModel.needsAskExportRecoveryAction ? "Recreates the assistant response export file at a fresh path." : "Opens the exported assistant response text file.")
        }
    }

    private var assistantResponseActionsMenu: some View {
        Menu {
            Button(action: viewModel.copyAssistantResponse) {
                Label("Copy Response", systemImage: "doc.on.doc")
            }
            Button(action: viewModel.exportAssistantResponse) {
                Label("Export Response", systemImage: "square.and.arrow.down")
            }
            if !viewModel.assistantResponseExportPath.isEmpty {
                Button(action: viewModel.copyAssistantResponseExportPath) {
                    Label("Copy Path", systemImage: "link")
                }
                .disabled(!viewModel.hasAssistantResponseExportFile)
                Button(action: viewModel.needsAskExportRecoveryAction ? viewModel.exportAssistantResponse : viewModel.openAssistantResponseExport) {
                    Label(
                        viewModel.needsAskExportRecoveryAction ? "Re-export" : "Open Export",
                        systemImage: viewModel.needsAskExportRecoveryAction ? "arrow.clockwise.circle" : "arrow.up.right.square"
                    )
                }
                .disabled(viewModel.needsAskExportRecoveryAction ? viewModel.assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !viewModel.hasAssistantResponseExportFile)
            }
        } label: {
            HighContrastMenuLabel(title: "Actions", symbol: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .colorScheme(.light)
        .controlSize(.small)
        .help("Open assistant response actions.")
        .namedControl("Assistant response actions", hint: "Shows copy, export, and open actions for the assistant response.")
    }

    private var assistantActedBadge: some View {
        Label("Acted", systemImage: "bolt.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.teal)
    }

    private var assistantResponseFeedbackBadge: some View {
        Text(viewModel.assistantResponseFeedback)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.teal)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.teal.opacity(0.12)))
    }

    private var promptToolbar: some View {
        HStack(spacing: 8) {
            PromptHistoryMenu(viewModel: viewModel)
            Button(action: viewModel.clearPrompt) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Clear the prompt and keep the previous text in history.")
            .namedControl("Clear prompt")
            Button(action: viewModel.restorePreviousPromptDraft) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .help("Restore the previous prompt draft after a preset, history restore, or clear.")
            .namedControl("Restore previous prompt draft", hint: "Swaps the prompt with the previous draft.")
            Spacer()
            Button(action: { viewModel.askAssistant() }) {
                Label(viewModel.isAssistantThinking ? "Thinking" : (viewModel.planNeedsRefresh ? "Refresh Response" : "Ask"), systemImage: viewModel.isAssistantThinking ? "cpu" : "paperplane")
            }
            .buttonStyle(ReadableProminentButtonStyle(color: Palette.teal))
            .disabled(
                viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isScanningProject
                    || viewModel.isRunningCommand
                    || viewModel.isRefreshingDevices
                    || viewModel.isRunningWirelessDebugging
                    || viewModel.isAssistantThinking
            )
            .help("Ask the assistant for a project-specific response and run safe automatic actions requested by the prompt.")
            .keyboardShortcut(.return, modifiers: [.command])
            .namedControl("Ask the assistant")
        }
    }
}

private struct BuildLogCard: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = viewModel.lastCommandSummary {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: summaryIcon(summary))
                        .foregroundStyle(summaryColor(summary))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(summary.title) - \(summary.status) in \(summary.duration)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text(summary.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Label("Console", systemImage: "terminal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    HStack(spacing: 2) {
                        ForEach(ConsoleStreamFilter.allCases) { filter in
                            Button {
                                viewModel.consoleStreamFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(viewModel.consoleStreamFilter == filter ? Color.white : Palette.ink)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(viewModel.consoleStreamFilter == filter ? Palette.blue : Palette.surface)
                                    )
                            }
                            .buttonStyle(.plain)
                            .namedControl("Show console \(filter.rawValue)", hint: "Filters the console to \(filter.rawValue).")
                        }
                    }
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.inputBackground))
                    TextField("Filter output", text: $viewModel.consoleSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 220)
                        .namedControl("Filter command console", hint: "Filters console output by line.")
                    if !viewModel.consoleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: viewModel.clearConsoleSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.muted)
                        .help("Clear console filter.")
                        .namedControl("Clear console filter", hint: "Shows the full console output.")
                    }
                    Spacer()
                    Text(consoleMetadata)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.inputBackground)

                Divider()

                ScrollView(.vertical, showsIndicators: true) {
                    Text(viewModel.filteredCommandOutput.isEmpty ? "Command output appears here after Gradle, ADB, Logcat, or packaging commands run." : viewModel.filteredCommandOutput)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                }
            }
            .frame(minHeight: 220)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if viewModel.isOutputTruncated {
                Text("Older console output was truncated after 80,000 characters. Export the log before running another long command.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.amber)
            }

            ViewThatFits(in: .horizontal) {
                consoleToolbar
                VStack(alignment: .trailing, spacing: 8) {
                    consoleToolbar
                }
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .controlSize(.small)
        }
    }

    private func summaryColor(_ summary: CommandRunSummary) -> Color {
        switch summary.severity {
        case "ready": return Palette.teal
        case "failed": return Palette.red
        default: return Palette.amber
        }
    }

    private func summaryIcon(_ summary: CommandRunSummary) -> String {
        switch summary.severity {
        case "ready": return "checkmark.circle.fill"
        case "failed": return "xmark.octagon.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var consoleMetadata: String {
        let output = viewModel.filteredCommandOutput
        guard !output.isEmpty else { return "0 lines" }
        let lineCount = output.split(separator: "\n", omittingEmptySubsequences: false).count
        let filtered = viewModel.consoleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " filtered"
        return "\(viewModel.consoleStreamFilter.rawValue.lowercased()) · \(lineCount) lines\(filtered)"
    }

    private var consoleToolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            if viewModel.isRunningCommand {
                Button(action: viewModel.stopRunningCommand) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .namedControl("Stop running command")
            }
            Button(action: viewModel.copyConsole) {
                Label("Copy Log", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.commandOutput.isEmpty)
            .namedControl("Copy command console")
            Button(action: viewModel.copyLastCommandPreview) {
                Label("Copy Cmd", systemImage: "terminal")
            }
            .namedControl("Copy last command", hint: "Copies the most recent runnable command.")
            Button(action: viewModel.retryLastCommand) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRunningCommand)
            .namedControl("Retry last command", hint: "Runs the previous command again if it is still valid.")
            Button(action: viewModel.exportConsole) {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.commandOutput.isEmpty)
            .namedControl("Export command console")
            if !viewModel.lastExportPath.isEmpty {
                Button(action: viewModel.openLastExport) {
                    Label("Open Export", systemImage: "arrow.up.right.square")
                }
                .namedControl("Open last export")
            }
            Button(action: viewModel.createDebugReport) {
                Label("Debug Report", systemImage: "doc.text")
            }
            .namedControl("Create debug report")
            Button(action: viewModel.clearOutput) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.commandOutput.isEmpty)
            .namedControl("Clear command console")
        }
    }
}

private struct SessionPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            SessionTabStrip(selection: $viewModel.selectedSessionTab)
                .padding(.horizontal, 16)

            Group {
                switch viewModel.selectedSessionTab {
                case .chat:
                    SessionChatTab(viewModel: viewModel)
                case .diagnostics:
                    SessionDiagnosticsTab(viewModel: viewModel, visiblePanels: $visiblePanels)
                case .checks:
                    SessionChecksTab(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Palette.inspector)
    }
}

private struct SessionTabStrip: View {
    @Binding var selection: SessionPaneTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SessionPaneTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundColor(selection == tab ? Color.white : Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selection == tab ? Palette.blue : Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(selection == tab ? Palette.blue.opacity(0.65) : Palette.border)
                    )
                }
                .buttonStyle(.plain)
                .help("Show \(tab.title)")
                .namedControl("Session tab \(tab.title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session tabs")
    }
}

private extension SessionPaneTab {
    var title: String {
        switch self {
        case .chat: return "Chat"
        case .diagnostics: return "Diagnostics"
        case .checks: return "Checks"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "text.bubble"
        case .diagnostics: return "stethoscope"
        case .checks: return "checklist"
        }
    }
}

private struct SessionChatTab: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(viewModel.chatMessages) { message in
                        ChatBubble(message: message)
                    }
                }
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                StatusPill(text: viewModel.scanState.title, color: shellStatusColor(for: viewModel), symbol: viewModel.scanState.symbol)
                if viewModel.isProjectLoaded {
                    StatusPill(text: viewModel.profile.packageName, color: Palette.blue, symbol: "shippingbox")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct SessionDiagnosticsTab: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Diagnostics", symbol: "stethoscope")
                            Spacer()
                            Button(action: viewModel.createDebugReport) {
                                Label("Report", systemImage: "doc.text")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .controlSize(.small)
                            .namedControl("Create diagnostics report")
                        }
                        ForEach(viewModel.diagnosticRows) { row in
                            DiagnosticRowView(row: row)
                            if row.title == "Ask Export" {
                                HStack(spacing: 8) {
                                    Button(action: viewModel.runAskExportDiagnosticsAction) {
                                        Label(viewModel.askExportDiagnosticsActionTitle, systemImage: viewModel.askExportDiagnosticsActionSymbol)
                                    }
                                    .buttonStyle(ReadableBorderedButtonStyle())
                                    .controlSize(.small)
                                    .disabled(!viewModel.canRunAskExportDiagnosticsAction)
                                    .namedControl("Ask export diagnostics action", hint: "Opens the Ask export file when available or re-exports it when stale.")

                                    if !viewModel.canRunAskExportDiagnosticsAction && !viewModel.askExportDiagnosticsActionDisabledReason.isEmpty {
                                        Text(viewModel.askExportDiagnosticsActionDisabledReason)
                                            .font(.caption2)
                                            .foregroundStyle(Palette.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        Button {
                            visiblePanels.insert(.askAssistant)
                            viewModel.noteOpenedAskForExportRecovery()
                        } label: {
                            Label("Open Ask", systemImage: "text.bubble")
                        }
                        .buttonStyle(ReadableBorderedButtonStyle())
                        .controlSize(.small)
                        .disabled(!viewModel.needsAskExportRecoveryAction)
                        .namedControl("Open Ask for export recovery", hint: "Opens Ask The Assistant so you can re-export the response.")
                        if !viewModel.needsAskExportRecoveryAction && !viewModel.askExportRecoveryDisabledReason.isEmpty {
                            Text(viewModel.askExportRecoveryDisabledReason)
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !viewModel.debugReportPath.isEmpty {
                            Button(action: viewModel.openDebugReport) {
                                Label("Open Report", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(ReadableBorderedButtonStyle())
                            .controlSize(.small)
                            .namedControl("Open diagnostics report")
                        }
                    }
                }

                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Verification", symbol: "checklist")
                        ForEach(viewModel.verificationRows) { row in
                            VerificationRowView(row: row)
                        }
                        HStack(spacing: 8) {
                            Button(action: { viewModel.runCommand(.unitTests) }) {
                                Label("Run Tests", systemImage: "checkmark.seal")
                            }
                            .namedControl("Run unit tests from checks", hint: "Runs the selected unit-test Gradle task.")
                            Button(action: { viewModel.runCommand(.assembleDebug) }) {
                                Label("Build", systemImage: "hammer")
                            }
                            .namedControl("Run build from checks", hint: "Builds the selected variant.")
                            Button(action: { viewModel.runCommand(.logcat) }) {
                                Label("Logcat", systemImage: "doc.text.magnifyingglass")
                            }
                            .namedControl("Capture logcat from checks", hint: "Captures a recent Logcat snapshot for the selected device.")
                        }
                        .buttonStyle(ReadableBorderedButtonStyle())
                        .controlSize(.small)
                    }
                }

                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Safety", symbol: "exclamationmark.shield")
                        ForEach(viewModel.safetyRows) { row in
                            DiagnosticRowView(row: row)
                        }
                    }
                }

                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Context", symbol: "scope")
                        if viewModel.isProjectLoaded {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ContextChip(title: "UI System", value: viewModel.snapshot.usesCompose ? "Compose" : "XML/Mixed")
                                ContextChip(title: "SDK", value: "min \(viewModel.profile.minSDK)")
                                ContextChip(title: "Manifest", value: viewModel.snapshot.hasAndroidManifest ? "Found" : "Missing")
                                ContextChip(title: "Kotlin", value: viewModel.snapshot.usesKotlin ? "Yes" : "No")
                            }
                        } else {
                            Text("Context appears after scanning a selected project.")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct SessionChecksTab: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Verification", symbol: "checklist")
                        ForEach(viewModel.verificationRows) { row in
                            VerificationRowView(row: row)
                        }
                    }
                }

                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Context", symbol: "scope")
                        if viewModel.isProjectLoaded {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ContextChip(title: "UI System", value: viewModel.snapshot.usesCompose ? "Compose" : "XML/Mixed")
                                ContextChip(title: "SDK", value: "min \(viewModel.profile.minSDK)")
                                ContextChip(title: "Manifest", value: viewModel.snapshot.hasAndroidManifest ? "Found" : "Missing")
                                ContextChip(title: "Kotlin", value: viewModel.snapshot.usesKotlin ? "Yes" : "No")
                            }
                        } else {
                            Text("Context appears after scanning a selected project.")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct ContentCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.blue.opacity(0.16))
                    .frame(width: 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            .shadow(color: Palette.cardShadow, radius: 2, x: 0, y: 1)
    }
}

private struct ClosableSectionTitle: View {
    let title: String
    let symbol: String
    let panel: ToolWindowPanel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    init(_ title: String, symbol: String, panel: ToolWindowPanel, visiblePanels: Binding<Set<ToolWindowPanel>>) {
        self.title = title
        self.symbol = symbol
        self.panel = panel
        _visiblePanels = visiblePanels
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Button {
                visiblePanels.remove(panel)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .help("Close \(title)")
            .namedControl("Close \(title) panel", hint: "Hides this tool pane. Reopen it from the side rail.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarSectionTitle: View {
    let title: String
    let symbol: String?

    init(_ title: String, symbol: String? = nil) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .font(.headline.weight(.semibold))
        .foregroundStyle(Palette.ink)
    }
}

@MainActor
private func shellStatusColor(for viewModel: AgentViewModel) -> Color {
    if viewModel.isRunningCommand || viewModel.isScanningProject || viewModel.isRefreshingDevices || viewModel.isRunningWirelessDebugging {
        return Palette.amber
    }
    switch viewModel.scanState {
    case .ready: return Palette.teal
    case .warning: return Palette.amber
    case .failed: return Palette.red
    case .waiting, .scanning: return Palette.blue
    }
}

private extension AndroidCommandKind {
    var shellDescription: String {
        switch self {
        case .unitTests:
            return "Run the selected module's unit test task."
        case .assembleDebug:
            return "Build the selected variant APK."
        case .connectedTests:
            return "Run instrumentation tests on the selected device."
        case .devices:
            return "List attached Android devices."
        case .logcat:
            return "Capture a recent Logcat snapshot."
        case .clearLogcat:
            return "Clear Logcat on the selected device."
        case .launch:
            return "Launch the configured package and activity."
        }
    }
}

private struct ProjectMetricStrip: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Group {
            if viewModel.isProjectLoaded {
                HStack(spacing: 8) {
                    MiniMetric(value: viewModel.snapshot.fileCount.formatted(), label: "Files", color: Palette.blue)
                    MiniMetric(value: viewModel.snapshot.testFileCount.formatted(), label: "Tests", color: Palette.teal)
                    MiniMetric(value: viewModel.snapshot.hasGradleWrapper ? "Wrapper" : "System", label: "Gradle", color: Palette.amber)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.muted)
                    Text(viewModel.isScanningProject ? "Scanning project metrics..." : "Project metrics appear after you choose a project.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            }
        }
    }
}

private struct MiniMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }
}

private struct ProjectFileRow: View {
    let item: ProjectFileItem
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        Button {
            if item.isDirectory {
                viewModel.toggleProjectFolder(item)
            } else {
                openInEditor()
            }
        } label: {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: min(CGFloat(item.depth) * 12, 96))
                if item.isDirectory {
                    Image(systemName: viewModel.isProjectFolderExpanded(item) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 10)
                } else {
                    Color.clear
                        .frame(width: 10, height: 10)
                }
                Image(systemName: item.symbol)
                    .font(.caption)
                    .foregroundStyle(rowIconColor)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    highlightedText(item.name, baseColor: rowTextColor)
                        .font(.system(size: 13, weight: rowWeight))
                        .lineLimit(1)
                    highlightedText(item.path, baseColor: Palette.muted)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if isOpenFile {
                    Text("Open")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.blue.opacity(0.12)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOpenFile ? Palette.blue.opacity(0.35) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isDirectory {
                Button(viewModel.isProjectFolderExpanded(item) ? "Collapse Folder" : "Expand Folder") {
                    viewModel.toggleProjectFolder(item)
                }
            } else {
                Button("Open In Editor") {
                    openInEditor()
                }
                Button("Open Externally") {
                    viewModel.openProjectFileExternally(item)
                }
            }
            Button("Copy Relative Path") {
                viewModel.copyProjectPath(item)
            }
            Button("Copy Absolute Path") {
                viewModel.copyProjectAbsolutePath(item)
            }
            Button("Reveal In Finder") {
                viewModel.revealProjectFileInFinder(item)
            }
        }
        .help(item.path)
        .namedControl(item.isDirectory ? "Toggle folder \(item.path)" : "Open file \(item.path)")
    }

    private var rowWeight: Font.Weight {
        item.isDirectory || item.isSelected ? .semibold : .regular
    }

    private var rowTextColor: Color {
        item.isSelected ? Palette.blue : Palette.ink
    }

    private var rowIconColor: Color {
        if item.isDirectory {
            return viewModel.isProjectFolderExpanded(item) ? Palette.blue : Palette.muted
        }
        return item.isSelected ? Palette.blue : Palette.muted
    }

    private var isOpenFile: Bool {
        !item.isDirectory && viewModel.selectedEditorPath == item.path
    }

    private var rowBackground: Color {
        if isOpenFile { return Palette.blue.opacity(0.14) }
        if item.isSelected { return Palette.blue.opacity(0.08) }
        if item.isDirectory { return Palette.inputBackground.opacity(0.75) }
        return Color.clear
    }

    private func highlightedText(_ text: String, baseColor: Color) -> Text {
        var attributed = AttributedString(text)
        attributed.foregroundColor = baseColor
        let query = viewModel.fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty,
           let range = attributed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].foregroundColor = Palette.ink
            attributed[range].backgroundColor = Palette.diffAmber.opacity(0.75)
        }
        return Text(attributed)
    }

    private func openInEditor() {
        guard !item.isDirectory else {
            viewModel.toggleProjectFolder(item)
            return
        }
        viewModel.openFile(item)
        if viewModel.selectedEditorDocument != nil {
            visiblePanels.insert(.editor)
        }
    }
}

private struct PromptHistoryMenu: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Menu {
            if viewModel.promptHistory.isEmpty {
                Text("No prompt history")
            } else {
                ForEach(viewModel.promptHistory, id: \.self) { value in
                    Button(value) {
                        viewModel.usePromptFromHistory(value)
                    }
                    Button("Remove: \(value.prefix(32))") {
                        viewModel.removePromptHistory(value)
                    }
                }
                Divider()
                Button("Clear Prompt History") {
                    viewModel.clearPromptHistory()
                }
            }
        } label: {
            HighContrastMenuLabel(title: "History", symbol: "clock")
        }
        .help("Restore a previous prompt.")
        .namedControl("Prompt history")
    }
}

private struct HighContrastMenuLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
                .foregroundColor(Palette.ink)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Palette.blue)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
    }
}

private struct ChatBubble: View {
    let message: AgentChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 36)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.speaker)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(message.isUser ? Palette.blue : Palette.teal)
                Text(message.message)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 420, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(message.isUser ? Palette.userBubble : Palette.agentBubble))
            if !message.isUser {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct VerificationRowView: View {
    let row: VerificationRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .foregroundStyle(stateColor)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(row.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Text(row.state)
                .font(.caption2.weight(.bold))
                .foregroundStyle(stateColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(stateColor.opacity(0.12)))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.inputBackground))
        .accessibilityElement(children: .combine)
    }

    private var stateColor: Color {
        switch row.severity {
        case "warning", "optional": return Palette.amber
        case "running": return Palette.amber
        case "neutral": return Palette.blue
        default: return Palette.teal
        }
    }
}

private struct DiagnosticRowView: View {
    let row: DiagnosticRow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.inputBackground))
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch row.severity {
        case "ready": return Palette.teal
        case "failed": return Palette.red
        case "warning", "running": return Palette.amber
        default: return Palette.blue
        }
    }
}

private struct ContextChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.inputBackground))
        .help("\(title): \(value)")
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyProjectPlaceholder: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Palette.muted)
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.inputBackground))
        .accessibilityElement(children: .combine)
    }
}

private struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(Palette.ink)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

private extension View {
    func namedControl(_ label: String, hint: String? = nil) -> some View {
        accessibilityLabel(Text(label))
            .accessibilityHint(Text(hint ?? label))
            .accessibilityIdentifier(label)
    }
}

private struct ReadableBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.ink : Palette.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isEnabled ? buttonBackground(configuration: configuration) : Palette.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? Palette.border : Palette.border.opacity(0.8))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private func buttonBackground(configuration: Configuration) -> Color {
        configuration.isPressed ? Palette.inputBackground : Palette.surface
    }
}

private struct ReadableProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Palette.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(prominentBackground(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? color.opacity(0.65) : Palette.border)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private func prominentBackground(configuration: Configuration) -> Color {
        guard isEnabled else { return Palette.inputBackground }
        return configuration.isPressed ? color.opacity(0.78) : color
    }
}

private enum Palette {
    static let appBackground = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let titleBar = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let sidebar = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let workspace = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let inspector = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let surface = Color.white
    static let inputBackground = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let noticeBackground = Color(red: 0.93, green: 0.96, blue: 0.98)
    static let border = Color.black.opacity(0.10)
    static let darkBorder = Color.white.opacity(0.10)
    static let cardShadow = Color.black.opacity(0.06)
    static let ink = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let muted = Color(red: 0.39, green: 0.45, blue: 0.54)
    static let teal = Color(red: 0.06, green: 0.46, blue: 0.43)
    static let blue = Color(red: 0.15, green: 0.39, blue: 0.92)
    static let railMuted = Color(red: 0.21, green: 0.27, blue: 0.36)
    static let railBackground = Color(red: 0.985, green: 0.99, blue: 1.0, opacity: 0.72)
    static let railSelectedBackground = Color(red: 0.15, green: 0.39, blue: 0.92, opacity: 0.16)
    static let railBorder = Color.black.opacity(0.10)
    static let railSelectedBorder = Color(red: 0.15, green: 0.39, blue: 0.92, opacity: 0.55)
    static let amber = Color(red: 0.70, green: 0.33, blue: 0.04)
    static let red = Color(red: 0.78, green: 0.16, blue: 0.16)
    static let editorHeader = Color(red: 0.07, green: 0.11, blue: 0.18)
    static let editorBackground = Color(red: 0.04, green: 0.07, blue: 0.12)
    static let editorText = Color(red: 0.80, green: 0.84, blue: 0.90)
    static let terminalHeader = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let terminalBackground = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let terminalText = Color(red: 0.82, green: 0.95, blue: 0.88)
    static let diffGreen = Color(red: 0.53, green: 0.94, blue: 0.65)
    static let diffRed = Color(red: 0.98, green: 0.65, blue: 0.65)
    static let diffAmber = Color(red: 0.99, green: 0.88, blue: 0.54)
    static let diffBlue = Color(red: 0.58, green: 0.77, blue: 1.0)
    static let greenText = Color(red: 0.35, green: 0.92, blue: 0.78)
    static let userBubble = Color(red: 0.92, green: 0.96, blue: 1.0)
    static let agentBubble = Color(red: 0.91, green: 0.98, blue: 0.95)
}

@MainActor
public enum AndroidDevAgentUICoverageHarness {
    public static func askAssistantDiagnostics() async -> [String: String] {
        let fixtures = AgentViewModel.coverageFixtures()
        guard fixtures.count >= 4 else { return [:] }
        let loaded = fixtures[3]

        loaded.prompt = "Give me a repo overview around 100 words."
        await loaded.submitAssistantPromptWithModels(runActions: false, allowRemoteModels: false)
        let overview = loaded.assistantResponse
        let overviewChat = loaded.chatMessages.map(\.message).joined(separator: "\n")

        loaded.prompt = "Act as a board game developer and explain how to incorporate Ludo in this project."
        await loaded.submitAssistantPromptWithModels(runActions: true, allowRemoteModels: false)
        let ludo = loaded.assistantResponse

        return [
            "overview": overview,
            "overviewChat": overviewChat,
            "ludo": ludo,
            "actionSummary": loaded.assistantActionSummary,
            "modelStatus": loaded.assistantModelStatus,
            "modelDetail": loaded.assistantModelDetail
        ]
    }

    public static func exercise() -> Int {
        let fixtures = AgentViewModel.coverageFixtures()
        guard fixtures.count >= 6 else {
            return AgentViewModel.exerciseCoverageSurface()
        }

        let empty = fixtures[0]
        let scanning = fixtures[2]
        let loaded = fixtures[3]
        let running = fixtures[4]
        let failed = fixtures[5]
        var touched = AgentViewModel.exerciseCoverageSurface()
        let noPanels = Binding.constant(ToolWindowPanel.defaultVisible)
        let allPanels = Binding.constant(Set(ToolWindowPanel.allCases))

        touched += touch(AgentWorkbenchView())
        touched += touch(ShellTitleBar(viewModel: empty))
        touched += touch(ShellTitleBar(viewModel: running))
        touched += touch(ShellTitleBar(viewModel: failed))
        touched += touch(EmptyToolWindowCanvas(viewModel: empty, visiblePanels: noPanels))
        touched += touch(ToolWindowRail(side: .left, panels: ToolWindowPanel.leftPanels, visiblePanels: noPanels))
        touched += touch(ToolWindowRail(side: .left, panels: ToolWindowPanel.leftPanels, visiblePanels: allPanels))
        touched += touch(ToolWindowRail(side: .right, panels: ToolWindowPanel.rightPanels, visiblePanels: allPanels))
        touched += touch(WorkspaceSidebarPane(viewModel: empty, visiblePanels: allPanels))
        touched += touch(WorkspaceSidebarPane(viewModel: scanning, visiblePanels: allPanels))
        touched += touch(WorkspaceSidebarPane(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(RightToolDockPane(viewModel: empty, visiblePanels: allPanels))
        touched += touch(RightToolDockPane(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(CenterEditorWorkspace(viewModel: empty, visiblePanels: allPanels))
        touched += touch(WorkspacePathCard(viewModel: empty))
        touched += touch(WorkspacePathCard(viewModel: loaded))
        touched += touch(WorkspaceOptionsDisclosure(viewModel: empty))
        touched += touch(WorkspaceOptionsDisclosure(viewModel: loaded))
        touched += touch(AndroidTargetCard(viewModel: loaded))
        touched += touch(SidebarFileBrowser(viewModel: empty, visiblePanels: allPanels))
        touched += touch(SidebarFileBrowser(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(SidebarToolList(viewModel: empty))
        touched += touch(SidebarToolList(viewModel: loaded))
        for command in AndroidCommandKind.allCases {
            touched += touch(SidebarToolRow(command: command, viewModel: loaded))
        }
        touched += touch(ToolStateBadge(text: "Ready", color: Palette.teal))
        touched += touch(ToolStateBadge(text: "Select device", color: Palette.muted))
        touched += touch(MainWorkspaceContentPane(viewModel: empty, visiblePanels: allPanels))
        touched += touch(MainWorkspaceContentPane(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(StatusInfoBar(viewModel: empty))
        touched += touch(StatusInfoBar(viewModel: scanning))
        touched += touch(StatusInfoBar(viewModel: loaded))
        touched += touch(ProjectIntelligenceCard(viewModel: empty))
        touched += touch(ProjectIntelligenceCard(viewModel: loaded))
        touched += touch(PlanPreviewDisclosure(viewModel: empty))
        touched += touch(PlanPreviewDisclosure(viewModel: loaded))
        touched += touch(FileEditorPane(viewModel: empty, visiblePanels: allPanels))
        touched += touch(AskAssistantCard(viewModel: loaded))
        touched += touch(BuildLogCard(viewModel: empty))
        touched += touch(BuildLogCard(viewModel: running))
        touched += touch(BuildLogCard(viewModel: failed))
        touched += touch(SessionPane(viewModel: empty, visiblePanels: allPanels))
        touched += touch(SessionPane(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(SessionChatTab(viewModel: empty))
        touched += touch(SessionChatTab(viewModel: loaded))
        touched += touch(SessionDiagnosticsTab(viewModel: empty, visiblePanels: allPanels))
        touched += touch(SessionDiagnosticsTab(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(SessionChecksTab(viewModel: empty))
        touched += touch(SessionChecksTab(viewModel: loaded))
        touched += touch(ContentCard { Text("Coverage content") })
        touched += touch(SidebarSectionTitle("Coverage", symbol: "checkmark.seal"))
        touched += touch(ProjectMetricStrip(viewModel: empty))
        touched += touch(ProjectMetricStrip(viewModel: loaded))
        touched += touch(MiniMetric(value: "128", label: "Files", color: Palette.blue))

        let selectedFile = loaded.projectFiles.first ?? ProjectFileItem(
            path: "app/src/main/AndroidManifest.xml",
            name: "AndroidManifest.xml",
            depth: 3,
            symbol: "doc.badge.gearshape",
            isSelected: true
        )
        let unselectedFile = ProjectFileItem(
            path: "app/src/main/java/com/example/Coverage.kt",
            name: "Coverage.kt",
            depth: 4,
            symbol: "curlybraces",
            isSelected: false
        )
        loaded.openFile(selectedFile)
        touched += touch(CenterEditorWorkspace(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(FileEditorPane(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(ProjectFileRow(item: selectedFile, viewModel: loaded, visiblePanels: allPanels))
        touched += touch(ProjectFileRow(item: unselectedFile, viewModel: loaded, visiblePanels: allPanels))
        touched += touch(PromptHistoryMenu(viewModel: empty))
        touched += touch(PromptHistoryMenu(viewModel: loaded))
        touched += touch(ChatBubble(message: AgentChatMessage(speaker: "You", message: "Coverage prompt", isUser: true)))
        touched += touch(ChatBubble(message: AgentChatMessage(speaker: "Agent", message: "Coverage response", isUser: false)))
        touched += touch(VerificationRowView(row: VerificationRow(title: "Waiting", detail: "Choose project", symbol: "folder", state: "Waiting", severity: "neutral")))
        touched += touch(VerificationRowView(row: VerificationRow(title: "Blocked", detail: "No device", symbol: "iphone", state: "Blocked", severity: "warning")))
        touched += touch(VerificationRowView(row: VerificationRow(title: "Ready", detail: "testDebugUnitTest", symbol: "checkmark.seal", state: "Ready", severity: "ready")))
        touched += touch(DiagnosticRowView(row: DiagnosticRow(title: "Ready", detail: "OK", symbol: "checkmark.circle", severity: "ready")))
        touched += touch(DiagnosticRowView(row: DiagnosticRow(title: "Failed", detail: "Broken", symbol: "xmark.octagon", severity: "failed")))
        touched += touch(DiagnosticRowView(row: DiagnosticRow(title: "Warning", detail: "Review", symbol: "exclamationmark.triangle", severity: "warning")))
        touched += touch(DiagnosticRowView(row: DiagnosticRow(title: "Neutral", detail: "Pending", symbol: "circle", severity: "neutral")))
        touched += touch(ContextChip(title: "SDK", value: "min 24"))
        touched += touch(EmptyProjectPlaceholder(symbol: "folder.badge.questionmark", title: "No context", message: "Choose a project."))
        touched += touch(SectionHeader(title: "Coverage", symbol: "checkmark.seal"))
        touched += touch(StatusPill(text: "ready", color: Palette.teal, symbol: "checkmark.circle.fill"))

        return touched
    }

    @discardableResult
    private static func touch<V: View>(_ view: V) -> Int {
        _ = view.body
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
        hostingView.layoutSubtreeIfNeeded()
        _ = hostingView.fittingSize
        return 1
    }
}
