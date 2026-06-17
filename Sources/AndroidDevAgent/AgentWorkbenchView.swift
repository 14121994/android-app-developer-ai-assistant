import AndroidDevAgentCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct AgentWorkbenchView: View {
    @StateObject private var viewModel = AgentViewModel()
    @State private var visiblePanels: Set<ToolWindowPanel>
    @State private var isSettingsPresented = false
    @State private var leftFeaturePaneMounted: Bool
    @State private var rightFeaturePaneMounted: Bool
    @State private var leftFeaturePaneTransitionGeneration = 0
    @State private var rightFeaturePaneTransitionGeneration = 0
    @State private var allowsPaneEntranceAnimation = false
    @AppStorage(agentWorkbenchColorSchemeKey) private var colorSchemePreferenceRaw = WorkbenchColorSchemePreference.system.rawValue
    @AppStorage(agentWorkbenchAccentThemeKey) private var accentThemeRaw = WorkbenchAccentTheme.pacific.rawValue
    @AppStorage(agentWorkbenchSurfaceStyleKey) private var surfaceStyleRaw = WorkbenchSurfaceStyle.balanced.rawValue
    @AppStorage(agentWorkbenchTextureEnabledKey) private var textureEnabled = true
    @AppStorage(agentWorkbenchMotionStyleKey) private var motionStyleRaw = WorkbenchMotionStyle.native.rawValue
    @AppStorage(agentWorkbenchPanelMotionEnabledKey) private var panelMotionEnabled = true
    @AppStorage(agentWorkbenchSelectionMotionEnabledKey) private var selectionMotionEnabled = true
    @AppStorage(agentWorkbenchStateMotionEnabledKey) private var stateMotionEnabled = true
    @AppStorage(agentWorkbenchStatusPulseEnabledKey) private var statusPulseEnabled = true
    @AppStorage(agentWorkbenchEntranceMotionEnabledKey) private var entranceMotionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {
        let initialPanels = Self.loadVisiblePanels()
        _visiblePanels = State(initialValue: initialPanels)
        _leftFeaturePaneMounted = State(initialValue: Self.showsLeftFeaturePane(in: initialPanels))
        _rightFeaturePaneMounted = State(initialValue: Self.showsRightFeaturePane(in: initialPanels))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ShellTitleBar(viewModel: viewModel, isSettingsPresented: $isSettingsPresented)
            Divider()
            HStack(spacing: 0) {
                ToolWindowRail(
                    side: .left,
                    panels: ToolWindowPanel.leftPanels,
                    visiblePanels: $visiblePanels
                )
                Divider()
                HSplitView {
                    if leftFeaturePaneMounted {
                        SlidingFeaturePane(
                            isPresented: showsLeftFeaturePane,
                            edge: .leading,
                            animateOnAppear: allowsPaneEntranceAnimation
                        ) {
                            WorkspaceSidebarPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                        }
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: 460)
                        .transition(WorkbenchMotion.panelTransition(edge: .leading, reduceMotion: reduceMotion, settings: motionSettings))
                    }
                    if visiblePanels.contains(.editor) {
                        CenterEditorWorkspace(viewModel: viewModel, visiblePanels: $visiblePanels)
                            .frame(minWidth: 300, idealWidth: 760, maxWidth: .infinity)
                            .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
                    } else {
                        EmptyToolWindowCanvas(viewModel: viewModel, visiblePanels: $visiblePanels)
                            .frame(minWidth: 280, idealWidth: 560, maxWidth: .infinity)
                            .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
                    }
                    if rightFeaturePaneMounted {
                        SlidingFeaturePane(
                            isPresented: showsRightFeaturePane,
                            edge: .trailing,
                            animateOnAppear: allowsPaneEntranceAnimation
                        ) {
                            RightToolDockPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                        }
                        .frame(minWidth: 280, idealWidth: 420, maxWidth: 560)
                        .transition(WorkbenchMotion.panelTransition(edge: .trailing, reduceMotion: reduceMotion, settings: motionSettings))
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
        .frame(minWidth: 980, idealWidth: 1280, minHeight: 640, idealHeight: 820)
        .background {
            WorkbenchBackdrop()
        }
        .environment(\.workbenchThemeSettings, themeSettings)
        .environment(\.workbenchMotionSettings, motionSettings)
        .preferredColorScheme(themeSettings.preferredColorScheme)
        .tint(themeSettings.accentColor)
        .accentColor(themeSettings.accentColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Android Dev Agent workspace")
        .accessibilityIdentifier("Android Dev Agent workspace shell")
        .animation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings), value: visiblePanels)
        .onAppear {
            reconcileFeaturePaneMounts()
            allowsPaneEntranceAnimation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AndroidDevAgentNotifications.openAgentSettings)) { _ in
            isSettingsPresented = true
        }
        .onChange(of: showsLeftFeaturePane) { _, isPresented in
            updateLeftFeaturePaneMount(isPresented: isPresented)
        }
        .onChange(of: showsRightFeaturePane) { _, isPresented in
            updateRightFeaturePaneMount(isPresented: isPresented)
        }
        .onChange(of: panelMotionActive) { _, _ in
            reconcileFeaturePaneMounts()
        }
        .onChange(of: viewModel.filePanelRevealGeneration) { _, generation in
            if generation > 0 {
                withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                    _ = visiblePanels.insert(.files)
                }
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
        .alert(item: activeAlertBinding, content: alertContent)
    }

    private var themeSettings: WorkbenchThemeSettings {
        WorkbenchThemeSettings(
            colorSchemePreference: WorkbenchColorSchemePreference(rawValue: colorSchemePreferenceRaw) ?? .system,
            accentTheme: WorkbenchAccentTheme(rawValue: accentThemeRaw) ?? .pacific,
            surfaceStyle: WorkbenchSurfaceStyle(rawValue: surfaceStyleRaw) ?? .balanced,
            textureEnabled: textureEnabled
        )
    }

    private var motionSettings: WorkbenchMotionSettings {
        WorkbenchMotionSettings(
            style: WorkbenchMotionStyle(rawValue: motionStyleRaw) ?? .native,
            panelTransitionsEnabled: panelMotionEnabled,
            selectionMotionEnabled: selectionMotionEnabled,
            stateMotionEnabled: stateMotionEnabled,
            statusPulseEnabled: statusPulseEnabled,
            entranceMotionEnabled: entranceMotionEnabled
        )
    }

    private var panelMotionActive: Bool {
        motionSettings.allowsPanelMotion(reduceMotion)
    }

    private var activeAlertBinding: Binding<WorkbenchAlert?> {
        Binding {
            if let confirmation = viewModel.pendingConfirmation {
                return .command(confirmation)
            }
            if let confirmation = viewModel.pendingWirelessDebuggingConfirmation {
                return .wirelessPairing(confirmation)
            }
            return nil
        } set: { _ in
            // Alert button actions clear the corresponding view-model state.
        }
    }

    private func alertContent(for alert: WorkbenchAlert) -> Alert {
        switch alert {
        case let .command(confirmation):
            let primaryButton: Alert.Button = confirmation.kind == .clearLogcat
                ? .destructive(Text("Clear Logs"), action: viewModel.confirmPendingCommand)
                : .default(Text("Run"), action: viewModel.confirmPendingCommand)
            let title: String
            switch confirmation.kind {
            case .clearLogcat:
                title = "Clear Logs?"
            case .launch:
                title = "Launch App?"
            default:
                title = "Run \(confirmation.kind.rawValue)?"
            }
            return Alert(
                title: Text(title),
                message: Text(confirmation.message),
                primaryButton: primaryButton,
                secondaryButton: .cancel(viewModel.cancelPendingCommand)
            )
        case let .wirelessPairing(confirmation):
            let connectText = confirmation.connectAddress.map { "\nConnect address: \($0)" } ?? ""
            return Alert(
                title: Text("Pair Wireless Device?"),
                message: Text("Pairing address: \(confirmation.pairingAddress)\nPairing code: \(confirmation.pairingCode)\(connectText)"),
                primaryButton: .default(Text("Pair"), action: viewModel.confirmWirelessPairing),
                secondaryButton: .cancel(viewModel.cancelWirelessPairing)
            )
        }
    }

    private var showsLeftFeaturePane: Bool {
        Self.showsLeftFeaturePane(in: visiblePanels)
    }

    private var showsMainFeaturePane: Bool {
        Self.showsMainFeaturePane(in: visiblePanels)
    }

    private var showsRightFeaturePane: Bool {
        Self.showsRightFeaturePane(in: visiblePanels)
    }

    private func reconcileFeaturePaneMounts() {
        leftFeaturePaneTransitionGeneration += 1
        rightFeaturePaneTransitionGeneration += 1
        leftFeaturePaneMounted = showsLeftFeaturePane
        rightFeaturePaneMounted = showsRightFeaturePane
    }

    private func updateLeftFeaturePaneMount(isPresented: Bool) {
        leftFeaturePaneTransitionGeneration += 1
        let generation = leftFeaturePaneTransitionGeneration
        if isPresented {
            leftFeaturePaneMounted = true
            return
        }
        guard leftFeaturePaneMounted, panelMotionActive else {
            leftFeaturePaneMounted = false
            return
        }
        schedulePaneUnmount(after: WorkbenchMotion.panelRemovalDelayNanoseconds(reduceMotion: reduceMotion, settings: motionSettings)) {
            guard generation == leftFeaturePaneTransitionGeneration, !showsLeftFeaturePane else { return }
            leftFeaturePaneMounted = false
        }
    }

    private func updateRightFeaturePaneMount(isPresented: Bool) {
        rightFeaturePaneTransitionGeneration += 1
        let generation = rightFeaturePaneTransitionGeneration
        if isPresented {
            rightFeaturePaneMounted = true
            return
        }
        guard rightFeaturePaneMounted, panelMotionActive else {
            rightFeaturePaneMounted = false
            return
        }
        schedulePaneUnmount(after: WorkbenchMotion.panelRemovalDelayNanoseconds(reduceMotion: reduceMotion, settings: motionSettings)) {
            guard generation == rightFeaturePaneTransitionGeneration, !showsRightFeaturePane else { return }
            rightFeaturePaneMounted = false
        }
    }

    private func schedulePaneUnmount(after nanoseconds: UInt64, action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private static func showsLeftFeaturePane(in panels: Set<ToolWindowPanel>) -> Bool {
        ToolWindowPanel.leftPanels.contains { panels.contains($0) }
    }

    private static func showsMainFeaturePane(in panels: Set<ToolWindowPanel>) -> Bool {
        panels.contains(.projectIntelligence)
            || panels.contains(.askAssistant)
            || panels.contains(.commandConsole)
    }

    private static func showsRightFeaturePane(in panels: Set<ToolWindowPanel>) -> Bool {
        showsMainFeaturePane(in: panels) || panels.contains(.session)
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
    @Binding var isSettingsPresented: Bool
    @Environment(\.workbenchThemeSettings) private var themeSettings
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "curlybraces.square.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(themeSettings.accentColor)
                .frame(width: 30, height: 30)
                .background {
                    SurfaceFill(cornerRadius: 8, tint: themeSettings.accentColor.opacity(0.11), material: .ultraThin, textureOpacity: 0.006)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(themeSettings.accentColor.opacity(0.22)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Android Dev Agent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(viewModel.projectSubtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            StatusPill(
                text: viewModel.isRunningCommand ? viewModel.lastCommandTitle : viewModel.confidenceDisplay,
                color: shellStatusColor(for: viewModel),
                symbol: viewModel.isRunningCommand ? "clock.arrow.circlepath" : viewModel.scanState.symbol
            )
            .frame(maxWidth: 280, alignment: .trailing)
            .workbenchPulse(isActive: isBusy)

            Text("v1.0")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    SurfaceFill(cornerRadius: 6, tint: Palette.inputBackground, material: .ultraThin, textureOpacity: 0.004)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border.opacity(0.72)))

            Button {
                isSettingsPresented.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSettingsPresented ? themeSettings.accentColor : Palette.muted)
            .background {
                SurfaceFill(
                    cornerRadius: 7,
                    tint: isSettingsPresented ? themeSettings.accentColor.opacity(0.12) : Palette.controlBackground,
                    material: .ultraThin,
                    textureOpacity: 0.004
                )
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSettingsPresented ? themeSettings.accentColor.opacity(0.38) : Palette.controlBorder))
            .help("Agent Settings")
            .namedControl("Open Agent Settings", hint: "Opens appearance and theme settings.")
            .popover(isPresented: $isSettingsPresented, arrowEdge: .bottom) {
                AgentSettingsPopover()
                    .environment(\.workbenchThemeSettings, themeSettings)
                    .environment(\.workbenchMotionSettings, motionSettings)
            }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel("Busy")
            } else {
                Color.clear
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 82)
        .padding(.trailing, 16)
        .frame(height: 54)
        .background {
            PaneBackdrop(role: .titleBar)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
        }
    }

    private var isBusy: Bool {
        viewModel.isRunningCommand
            || viewModel.isScanningProject
            || viewModel.isRefreshingDevices
            || viewModel.isRunningWirelessDebugging
    }
}

private struct ToolWindowRail: View {
    let side: ToolWindowSide
    let panels: [ToolWindowPanel]
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        VStack(spacing: 7) {
            Text(side == .left ? "Primary" : "Assistant")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                .frame(width: 62, height: 46)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 7)
        .frame(width: 76)
        .background {
            PaneBackdrop(role: .rail)
        }
        .accessibilityElement(children: .contain)
    }

    private func isVisible(_ panel: ToolWindowPanel) -> Bool {
        visiblePanels.contains(panel)
    }

    private func toggle(_ panel: ToolWindowPanel) {
        withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
            if visiblePanels.contains(panel) {
                visiblePanels.remove(panel)
            } else {
                visiblePanels.insert(panel)
            }
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
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchThemeSettings) private var themeSettings
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 62, height: 46)
            .foregroundStyle(foregroundColor)
            .background {
                SurfaceFill(
                    cornerRadius: 8,
                    tint: backgroundTint,
                    material: .ultraThin,
                    textureOpacity: isSelected ? 0.010 : 0.004
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Palette.railSelectedBorder : Palette.railBorder, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeSettings.accentColor)
                        .frame(width: 3, height: 24)
                        .padding(.leading, 4)
                }
            }
            .shadow(color: isSelected ? themeSettings.accentColor.opacity(0.16 * themeSettings.surfaceStyle.shadowScale) : Palette.controlShadow.opacity(themeSettings.surfaceStyle.shadowScale), radius: isSelected ? 5 : 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [.command, .option])
        .help(accessibilityTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityHint(Text(accessibilityHelp))
        .accessibilityIdentifier(identifier)
        .onHover { isHovering = $0 }
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: isHovering)
        .animation(WorkbenchMotion.selection(reduceMotion, settings: motionSettings), value: isSelected)
    }

    private var foregroundColor: Color {
        if isSelected { return themeSettings.accentColor }
        return isHovering ? Palette.ink : Palette.railMuted
    }

    private var backgroundTint: Color {
        if isSelected { return themeSettings.accentColor.opacity(0.16) }
        return isHovering ? Palette.railHoverBackground : Palette.railBackground
    }
}

private struct EmptyToolWindowCanvas: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "curlybraces.square.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .accessibilityHidden(true)
            Text("Android Dev Agent")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(viewModel.isProjectLoaded ? "Workspace context is ready." : "Choose Workspace to scan an Android project, or Ask to draft a plan.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    startWorkspaceButton
                    startAskButton
                    startSessionButton
                }

                VStack(spacing: 8) {
                    startWorkspaceButton
                    HStack(spacing: 8) {
                        startAskButton
                        startSessionButton
                    }
                }
            }
            .controlSize(.small)

            LaunchReadinessOnboardingCard(visiblePanels: $visiblePanels)

            if !savedPanels.isEmpty {
                Button {
                    updateVisiblePanels { panels in
                        panels = savedPanels
                    }
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
        .background {
            PaneBackdrop(role: .workspace)
        }
        .motionEntrance()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Android Dev Agent start area")
    }

    private var savedPanels: Set<ToolWindowPanel> {
        let values = UserDefaults.standard.stringArray(forKey: agentWorkbenchVisiblePanelsKey) ?? []
        return Set(values.compactMap(ToolWindowPanel.init(rawValue:)))
    }

    private var startWorkspaceButton: some View {
        Button {
            updateVisiblePanels { panels in
                panels.insert(.workspace)
            }
        } label: {
            Label("Workspace", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableProminentButtonStyle(color: Palette.blue))
        .namedControl("Open Workspace panel", hint: "Shows project selection and scan controls.")
    }

    private var startAskButton: some View {
        Button {
            updateVisiblePanels { panels in
                panels.insert(.askAssistant)
            }
        } label: {
            Label("Ask", systemImage: "text.bubble")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .namedControl("Open Ask The Assistant panel", hint: "Shows the prompt composer.")
    }

    private var startSessionButton: some View {
        Button {
            updateVisiblePanels { panels in
                panels.insert(.session)
            }
        } label: {
            Label("Session", systemImage: "rectangle.rightthird.inset.filled")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .namedControl("Open Session panel", hint: "Shows chat, diagnostics, and checks.")
    }

    private func updateVisiblePanels(_ update: (inout Set<ToolWindowPanel>) -> Void) {
        withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
            update(&visiblePanels)
        }
    }
}

private struct SlidingFeaturePane<Content: View>: View {
    let isPresented: Bool
    let edge: Edge
    let animateOnAppear: Bool
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings
    @State private var isVisuallyPresented = false

    init(
        isPresented: Bool,
        edge: Edge,
        animateOnAppear: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.edge = edge
        self.animateOnAppear = animateOnAppear
        self.content = content()
    }

    var body: some View {
        content
            .opacity(isVisuallyPresented ? 1 : 0)
            .offset(x: horizontalOffset)
            .clipped()
            .animation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings), value: isVisuallyPresented)
            .onAppear {
                guard animateOnAppear, motionSettings.allowsPanelMotion(reduceMotion) else {
                    isVisuallyPresented = isPresented
                    return
                }
                isVisuallyPresented = false
                DispatchQueue.main.async {
                    withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                        isVisuallyPresented = isPresented
                    }
                }
            }
            .onChange(of: isPresented) { _, presented in
                withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                    isVisuallyPresented = presented
                }
            }
            .onChange(of: motionSettings) { _, settings in
                if !settings.allowsPanelMotion(reduceMotion) {
                    isVisuallyPresented = isPresented
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if !motionSettings.allowsPanelMotion(reduced) {
                    isVisuallyPresented = isPresented
                }
            }
    }

    private var horizontalOffset: CGFloat {
        guard motionSettings.allowsPanelMotion(reduceMotion), !isVisuallyPresented else { return 0 }
        switch edge {
        case .leading:
            return -36
        case .trailing:
            return 36
        default:
            return 0
        }
    }
}

private struct WorkspaceSidebarPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if visiblePanels.contains(.workspace) {
                    FeatureBoundary {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                chooseAndScanButton
                                chooseOnlyButton
                            }

                            VStack(spacing: 8) {
                                chooseAndScanButton
                                chooseOnlyButton
                            }
                        }
                        .controlSize(.small)

                        ClosableSectionTitle("Workspace", symbol: "folder", panel: .workspace, visiblePanels: $visiblePanels)
                        WorkspacePathCard(viewModel: viewModel)
                    }
                    .transition(featureTransition)
                }
                if visiblePanels.contains(.androidTarget) {
                    FeatureBoundary {
                        WorkspaceOptionsDisclosure(viewModel: viewModel)
                    }
                    .transition(featureTransition)
                }
                if visiblePanels.contains(.runTools) {
                    FeatureBoundary {
                        SidebarToolList(viewModel: viewModel)
                    }
                    .transition(featureTransition)
                }
                if visiblePanels.contains(.files) {
                    FeatureBoundary {
                        SidebarFileBrowser(viewModel: viewModel, visiblePanels: $visiblePanels)
                    }
                    .transition(featureTransition)
                }
            }
            .padding(16)
            .animation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings), value: visiblePanels)
        }
        .accessibilityLabel("Primary tool pane scroll area")
        .background {
            PaneBackdrop(role: .sidebar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary tool pane")
        .accessibilityIdentifier("Primary tool pane")
    }

    private var featureTransition: AnyTransition {
        WorkbenchMotion.featureTransition(edge: .leading, reduceMotion: reduceMotion, settings: motionSettings)
    }

    private var chooseAndScanButton: some View {
        Button(action: viewModel.chooseProject) {
            Label("Choose and Scan", systemImage: "folder.badge.gearshape")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableProminentButtonStyle(color: Palette.blue))
        .disabled(!viewModel.canEditProjectSelection)
        .help(viewModel.canEditProjectSelection ? "Choose an Android project and scan it immediately." : viewModel.projectSelectionHelpText)
        .namedControl("Choose and scan Android workspace", hint: "Opens a folder picker and starts project scanning.")
    }

    private var chooseOnlyButton: some View {
        Button(action: viewModel.chooseProjectOnly) {
            Label("Select", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(!viewModel.canEditProjectSelection)
        .help(viewModel.canEditProjectSelection ? "Choose a project folder without scanning yet." : viewModel.projectSelectionHelpText)
        .namedControl("Select Android workspace without scanning", hint: "Opens a folder picker and leaves scanning under your control.")
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
                    .workbenchTextField()
                    .font(.caption)
                    .disabled(!viewModel.canEditProjectSelection)
                    .help(viewModel.canEditProjectSelection ? "Paste a project folder path, then press Return to scan." : viewModel.projectSelectionHelpText)
                    .onSubmit(viewModel.scanProject)
                    .namedControl("Android project path", hint: "Paste a project folder path, then press Return to scan.")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        scanOrCancelProjectButton
                        revealProjectButton
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        scanOrCancelProjectButton
                        revealProjectButton
                    }
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
                        .lineLimit(2)
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
                        .disabled(!viewModel.hasMissingRecentProjects)
                        Button("Clear Recent Projects") {
                            viewModel.clearRecentProjects()
                        }
                    } label: {
                        HighContrastMenuLabel(title: "Recent Projects", symbol: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Open a recently scanned Android project.")
                    .namedControl("Recent projects")
                }
            }
        }
    }

    private var scanOrCancelProjectButton: some View {
        Group {
            if viewModel.isScanningProject {
                Button(action: viewModel.cancelScan) {
                    Label("Cancel Scan", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .help("Cancel the current scan.")
                .namedControl("Cancel project scan")
            } else {
                Button(action: viewModel.scanProject) {
                    Label(viewModel.isProjectLoaded ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canScanProject)
                .help(viewModel.projectPathFeedback.detail)
                .namedControl(viewModel.isProjectLoaded ? "Rescan project" : "Scan project")
            }
        }
    }

    private var revealProjectButton: some View {
        Button(action: viewModel.openProjectInFinder) {
            Label("Reveal", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canRevealProjectPath)
        .help(viewModel.projectRevealHelpText)
        .namedControl("Reveal selected project path")
    }
}

private struct WorkspaceOptionsDisclosure: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var isExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        DisclosureGroup(isExpanded: animatedDisclosureBinding($isExpanded, reduceMotion: reduceMotion, settings: motionSettings)) {
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
    @State private var isWirelessConnectionSheetPresented = false

    var body: some View {
        ContentCard(horizontalPadding: 1) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Android Target", symbol: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gradle target")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            gradleModuleDropdown
                            gradleVariantDropdown
                        }

                        VStack(spacing: 8) {
                            gradleModuleDropdown
                            gradleVariantDropdown
                        }
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.canEditBuildTarget)
                    .help(viewModel.buildTargetHelpText)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Device")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            deviceDropdown
                            refreshDevicesButton
                        }

                        VStack(spacing: 8) {
                            deviceDropdown
                            refreshDevicesButton
                        }
                    }
                    .controlSize(.small)
                    Text(viewModel.deviceSummary)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.hasConnectedDevice {
                        connectedDeviceActions
                    }
                    if !viewModel.deviceRecoveryGuidance.isEmpty {
                        Label(viewModel.deviceRecoveryGuidance, systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .namedControl("Android device recovery guidance")
                    }
                    if !viewModel.hasConnectedDevice {
                        connectWirelessDevicesButton
                    }
                }

                Divider()

                if viewModel.shouldShowDeviceScreenPreview {
                    DeviceScreenPreviewPanel(viewModel: viewModel)
                    Divider()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Launch package")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    TextField("Package override for Launch", text: $viewModel.packageOverride)
                        .workbenchTextField()
                        .font(.caption)
                        .disabled(!viewModel.canEditLaunchTarget)
                        .help(viewModel.launchPackageHelpText)
                        .namedControl("Launch package override", hint: "Overrides the detected package used for Launch.")
                    if viewModel.isProjectLoaded {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                detectedLaunchPackageText
                                Spacer(minLength: 0)
                                useDetectedLaunchPackageButton
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                detectedLaunchPackageText
                                useDetectedLaunchPackageButton
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Launch activity")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    TextField("Launch activity, for example .MainActivity", text: $viewModel.launchActivity)
                        .workbenchTextField()
                        .font(.caption)
                        .disabled(!viewModel.canEditLaunchTarget)
                        .help(viewModel.launchActivityHelpText)
                        .namedControl("Launch activity")
                }

                DiagnosticRowView(row: viewModel.launchTargetFeedback)
            }
        }
        .sheet(isPresented: $isWirelessConnectionSheetPresented) {
            WirelessDeviceConnectionSheet(viewModel: viewModel)
        }
    }

    private var gradleModuleDropdown: some View {
        ReadableStringDropdown(
            title: "Module",
            selection: $viewModel.selectedModule,
            options: viewModel.modules,
            symbol: "square.stack.3d.up"
        )
        .namedControl("Gradle module")
    }

    private var gradleVariantDropdown: some View {
        ReadableStringDropdown(
            title: "Variant",
            selection: $viewModel.selectedVariant,
            options: viewModel.buildVariants,
            symbol: "tag"
        )
        .namedControl("Build variant")
    }

    private var deviceDropdown: some View {
        ReadableDeviceDropdown(viewModel: viewModel)
            .disabled(!viewModel.canSelectDevice)
            .help(viewModel.devicePickerHelpText)
            .namedControl("Android device")
    }

    private var refreshDevicesButton: some View {
        Button(action: viewModel.refreshDevices) {
            Label(viewModel.isRefreshingDevices ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(!viewModel.canRefreshDevices)
        .help(viewModel.refreshDevicesHelpText)
        .namedControl("Refresh Android devices")
    }

    private var connectedDeviceActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                disconnectSelectedWirelessDeviceButton
            }

            disconnectSelectedWirelessDeviceButton
        }
        .controlSize(.small)
    }

    private var disconnectSelectedWirelessDeviceButton: some View {
        Button(action: viewModel.disconnectWirelessDevice) {
            Label("Disconnect", systemImage: "wifi.slash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(!viewModel.canDisconnectSelectedWirelessDevice)
        .help(viewModel.canDisconnectSelectedWirelessDevice ? "Disconnect the selected wireless Android device." : "Disconnect is available for connected wireless targets.")
        .namedControl("Disconnect selected wireless Android device")
    }

    private var connectWirelessDevicesButton: some View {
        Button {
            isWirelessConnectionSheetPresented = true
        } label: {
            Label("Connect wireless devices", systemImage: "wifi")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(viewModel.isRunningWirelessDebugging)
        .help(viewModel.isRunningWirelessDebugging ? "Wireless connection is already running." : "Open wireless Android device connection options.")
        .namedControl("Connect wireless devices", hint: "Opens QR code and pairing code connection options.")
    }

    private var detectedLaunchPackageText: some View {
        Text("Detected: \(viewModel.profile.packageName)")
            .font(.caption2)
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.75)
    }

    private var useDetectedLaunchPackageButton: some View {
        Button(action: viewModel.resetLaunchPackageToDetected) {
            Label("Use Detected", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(!viewModel.canResetLaunchPackageToDetected)
        .help(viewModel.launchPackageHelpText)
        .namedControl("Use detected launch package", hint: "Copies the detected package into the launch package field.")
    }
}

private enum WirelessConnectionMethod: String, CaseIterable, Identifiable {
    case qrCode = "Scan via QR Code"
    case pairingCode = "Scan via pairing code"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .qrCode: return "qrcode"
        case .pairingCode: return "number"
        }
    }
}

private struct WirelessDeviceConnectionSheet: View {
    @ObservedObject var viewModel: AgentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: WirelessConnectionMethod = .qrCode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Connect wireless devices", systemImage: "wifi")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if viewModel.isRunningWirelessDebugging {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Wireless connection running")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .help("Close")
                .namedControl("Close wireless device connection")
            }

            WirelessDeviceDiscoveryList(viewModel: viewModel)

            WirelessConnectionMethodSelector(selection: $selectedMethod)

            switch selectedMethod {
            case .qrCode:
                WirelessQRCodeConnectionPanel(viewModel: viewModel)
            case .pairingCode:
                if viewModel.hasSelectedWirelessDebuggingDevice {
                    WirelessPairingCodeConnectionPanel(viewModel: viewModel)
                } else {
                    Text("Select a discovered wireless device to pair with code.")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(viewModel.wirelessDebuggingStatus)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 430)
        .background {
            PaneBackdrop(role: .inspector)
        }
        .foregroundStyle(Palette.ink)
        .onAppear(perform: viewModel.prepareWirelessDeviceConnectionSheet)
    }
}

private struct WirelessDeviceDiscoveryList: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Available devices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if viewModel.isRunningWirelessDebugging {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning wireless devices")
                }
                Button(action: viewModel.refreshWirelessDebuggingDevices) {
                    Label(viewModel.isRunningWirelessDebugging ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)
                .disabled(!viewModel.canRefreshWirelessDebuggingDevices)
                .help(viewModel.wirelessDiscoveryHelpText)
                .namedControl("Scan wireless debugging devices")
            }

            if viewModel.wirelessDebuggingDevices.isEmpty {
                Text(viewModel.wirelessDeviceDiscoveryStatus)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background {
                        SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.006)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.66)))
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.wirelessDebuggingDevices) { device in
                        WirelessDebuggingDeviceRow(
                            device: device,
                            isSelected: viewModel.selectedWirelessDebuggingDeviceID == device.id
                        ) {
                            viewModel.selectWirelessDebuggingDevice(device)
                        }
                    }
                }
            }
        }
    }
}

private struct WirelessDebuggingDeviceRow: View {
    let device: WirelessDebuggingDevice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "wifi")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Palette.blue : Palette.muted)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(device.detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Text(device.capabilitySummary)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? Palette.blue : Palette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill((isSelected ? Palette.blue : Palette.muted).opacity(0.10)))
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SurfaceFill(cornerRadius: 8, tint: isSelected ? Palette.blue.opacity(0.08) : Palette.surface, material: .ultraThin, textureOpacity: 0.006)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Palette.blue.opacity(0.55) : Palette.border))
        }
        .buttonStyle(.plain)
        .namedControl(device.displayName, hint: "Selects this wireless Android device.")
    }
}

private struct WirelessConnectionMethodSelector: View {
    @Binding var selection: WirelessConnectionMethod

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WirelessConnectionMethod.allCases) { method in
                Button {
                    selection = method
                } label: {
                    Label(method.rawValue, systemImage: method.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(WirelessConnectionMethodButtonStyle(isSelected: selection == method))
                .namedControl(method.rawValue)
            }
        }
        .padding(3)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.004)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.68)))
        .namedControl("Wireless connection method")
    }
}

private struct WirelessConnectionMethodButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(buttonBackground(isPressed: configuration.isPressed))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func buttonBackground(isPressed: Bool) -> Color {
        if isSelected {
            return isPressed ? Palette.blue.opacity(0.82) : Palette.blue
        }
        return isPressed ? Palette.inputBackground : Palette.surface
    }
}

private struct WirelessPairingCodeConnectionPanel: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan via pairing code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    wirelessPairingCodeField
                    pairWirelessButton
                }

                VStack(spacing: 8) {
                    wirelessPairingCodeField
                    pairWirelessButton
                }
            }

            wirelessConnectionButtons
        }
        .controlSize(.small)
    }

    private var wirelessPairingCodeField: some View {
        TextField("Code", text: $viewModel.wirelessPairingCode)
            .workbenchTextField()
            .font(.caption)
            .foregroundStyle(Palette.ink)
            .disabled(!viewModel.canEditWirelessDebuggingFields)
            .namedControl("Wireless pairing code", hint: "Enter only the pairing code. The pairing address is discovered and shown in the confirmation popup.")
    }

    private var pairWirelessButton: some View {
        Button(action: viewModel.pairWirelessDevice) {
            Label("Pair", systemImage: "link.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(!viewModel.canPairWirelessDevice)
        .help(viewModel.wirelessPairingHelpText)
        .namedControl("Pair wireless Android device")
    }

    private var wirelessConnectionButtons: some View {
        HStack(spacing: 8) {
            Button(action: viewModel.connectWirelessDevice) {
                Label(viewModel.wirelessConnectActionTitle, systemImage: "wifi")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .disabled(!viewModel.canConnectWirelessDevice)
            .help(viewModel.wirelessConnectHelpText)
            .namedControl("Connect wireless Android device")

            Button(action: viewModel.disconnectWirelessDevice) {
                Label("Disconnect", systemImage: "wifi.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .disabled(!viewModel.canDisconnectWirelessDevice)
            .help(viewModel.wirelessDisconnectHelpText)
            .namedControl("Disconnect wireless Android device")
        }
    }
}

private struct WirelessQRCodeConnectionPanel: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Scan via QR Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    generateQRCodeButton
                    scanDevicesButton
                    clearQRCodeButton
                }

                VStack(spacing: 8) {
                    generateQRCodeButton
                    scanDevicesButton
                    clearQRCodeButton
                }
            }

            if let qrImage = viewModel.wirelessQRCodeImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180, minHeight: 150, maxHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
                    .accessibilityLabel("Wireless Debugging QR code")
            }

            if viewModel.hasSelectedWirelessDebuggingDevice || viewModel.canConnectWirelessDevice {
                Button(action: viewModel.connectWirelessDevice) {
                    Label(viewModel.wirelessConnectActionTitle, systemImage: "wifi")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)
                .disabled(!viewModel.canConnectWirelessDevice)
                .help(viewModel.wirelessConnectHelpText)
                .namedControl("Connect QR paired wireless Android device")
            }

            Text(viewModel.wirelessQRCodeStatus)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var generateQRCodeButton: some View {
        Button(action: viewModel.generateWirelessQRCode) {
            Label("QR Code", systemImage: "qrcode")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(!viewModel.canGenerateWirelessQRCode)
        .help(viewModel.wirelessQRCodeHelpText)
        .namedControl("Generate wireless debugging QR code")
    }

    private var scanDevicesButton: some View {
        Button(action: viewModel.refreshWirelessDebuggingDevices) {
            Label(viewModel.isRunningWirelessDebugging ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(!viewModel.canRefreshWirelessDebuggingDevices)
        .help(viewModel.wirelessDiscoveryHelpText)
        .namedControl("Scan wireless devices after QR")
    }

    private var clearQRCodeButton: some View {
        Button(action: viewModel.clearWirelessQRCode) {
            Label("Clear QR", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .disabled(viewModel.wirelessQRCodeImage == nil)
        .help(viewModel.wirelessQRCodeImage == nil ? "No QR code is currently shown." : "Hide the generated Wireless Debugging QR code.")
        .namedControl("Clear wireless debugging QR code")
    }
}

private struct DeviceScreenPreviewPanel: View {
    @ObservedObject var viewModel: AgentViewModel
    private let imagePadding: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Device Screen")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.muted)

                Spacer(minLength: 0)
            }

            previewFrame

            Text(viewModel.devicePreviewUpdatedSummary)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(viewModel.devicePreviewUpdatedSummary)
        }
    }

    private var previewFrame: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)

                if let image = viewModel.devicePreviewImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .padding(imagePadding)
                        .accessibilityLabel("Rendered Android device screen")
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .accessibilityHidden(true)
                        Text(viewModel.hasConnectedDevice ? "No frame" : "No target")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white)
                        Text(viewModel.hasConnectedDevice ? "Waiting for frame" : "Connect a device")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                    .multilineTextAlignment(.center)
                    .padding(12)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        guard abs(value.translation.width) < 6, abs(value.translation.height) < 6 else { return }
                        sendTap(at: value.location, in: proxy.size)
                    }
            )
        }
        .aspectRatio(previewAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 356)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.border.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .layoutPriority(2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Android device screen preview")
        .help(viewModel.deviceTapHelpText)
    }

    private var previewAspectRatio: CGFloat {
        guard let image = viewModel.devicePreviewImage,
              let size = pixelSize(for: image),
              size.width > 0,
              size.height > 0 else {
            return 9.0 / 20.0
        }
        return size.width / size.height
    }

    private func sendTap(at location: CGPoint, in containerSize: CGSize) {
        guard viewModel.hasConnectedDevice,
              let image = viewModel.devicePreviewImage,
              let imageSize = pixelSize(for: image),
              imageSize.width > 0,
              imageSize.height > 0 else {
            return
        }

        let imageRect = aspectFitRect(
            imageSize: imageSize,
            containerSize: containerSize,
            padding: imagePadding
        )
        guard imageRect.contains(location) else { return }

        let relativeX = (location.x - imageRect.minX) / imageRect.width
        let relativeY = (location.y - imageRect.minY) / imageRect.height
        let x = clampedPixel(relativeX * imageSize.width, upperBound: imageSize.width)
        let y = clampedPixel(relativeY * imageSize.height, upperBound: imageSize.height)
        DispatchQueue.main.async {
            viewModel.sendDeviceTap(x: x, y: y)
        }
    }

    private func pixelSize(for image: NSImage) -> CGSize? {
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        return image.size
    }

    private func aspectFitRect(imageSize: CGSize, containerSize: CGSize, padding: CGFloat) -> CGRect {
        let availableSize = CGSize(
            width: max(1, containerSize.width - (padding * 2)),
            height: max(1, containerSize.height - (padding * 2))
        )
        let scale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: padding + ((availableSize.width - displayedSize.width) / 2),
            y: padding + ((availableSize.height - displayedSize.height) / 2),
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    private func clampedPixel(_ value: CGFloat, upperBound: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        let maximum = max(0, Int(upperBound.rounded()) - 1)
        return min(max(0, rounded), maximum)
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
            .help(viewModel.refreshDevicesHelpText)
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
                isEnabled: viewModel.canSelectDevice
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private var selectedDeviceTitle: String {
        viewModel.selectedDeviceDisplayName
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minWidth: 118, maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background {
            SurfaceFill(
                cornerRadius: 7,
                tint: isEnabled ? Palette.controlBackground : Palette.inputBackground,
                material: .ultraThin,
                textureOpacity: 0.004
            )
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
        .opacity(isEnabled ? 1 : 0.78)
    }
}

struct AssistantModelBindingDropdown: View {
    let mode: AssistantModelMode
    @State private var showsModels = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(WorkbenchMotion.state(reduceMotion, settings: motionSettings)) {
                    showsModels.toggle()
                }
            } label: {
                DropdownLabel(
                    title: showsModels ? "Hide models bound to \(mode.title)" : "Models bound to \(mode.title)",
                    value: mode.boundModelSummary,
                    symbol: "cpu",
                    isEnabled: true
                )
            }
            .buttonStyle(.plain)

            if showsModels {
                modelBindingDetails
            }
        }
        .help("Show the models bound to \(mode.title). Model rows are informational only.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Models bound to \(mode.title)")
        .accessibilityHint("Shows a read-only inline list of models used by this Ask mode.")
    }

    private var modelBindingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                    .foregroundStyle(Palette.blue)
                    .accessibilityHidden(true)
                Text("\(mode.title) mode bindings")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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
        .padding(10)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.006)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(model.route)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)

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
    @State private var showsAllProjectFiles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        DisclosureGroup(isExpanded: animatedDisclosureBinding($isExpanded, reduceMotion: reduceMotion, settings: motionSettings)) {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        fileSearchField
                        clearFileSearchButton
                    }

                    VStack(spacing: 6) {
                        fileSearchField
                        clearFileSearchButton
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        fileTreeExpansionButtons
                        Spacer(minLength: 0)
                        fileTreeRescanButton
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fileTreeExpansionButtons
                        fileTreeRescanButton
                    }
                }
                .buttonStyle(ReadableBorderedButtonStyle())
                .controlSize(.small)

                if viewModel.isProjectLoaded {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.projectPathDisplay)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.78)
                            .textSelection(.enabled)
                        Text(viewModel.fileSearchSummary)
                            .font(.caption2)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        SurfaceFill(cornerRadius: 8, tint: Palette.inputBackground, material: .ultraThin, textureOpacity: 0.004)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.34)))

                    if viewModel.filteredProjectFiles.isEmpty {
                        EmptyProjectPlaceholder(
                            symbol: "doc.text.magnifyingglass",
                            title: "No key files found",
                            message: viewModel.fileSearchQuery.isEmpty ? "The scan found Android markers but no common Gradle, manifest, Kotlin, Java, or XML files." : "No scanned file matches the current search."
                        )
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(visibleProjectFiles) { item in
                                ProjectFileRow(item: item, viewModel: viewModel, visiblePanels: $visiblePanels)
                            }
                            if hiddenProjectFileCount > 0 {
                                Button {
                                    showsAllProjectFiles.toggle()
                                } label: {
                                    Label(showsAllProjectFiles ? "Show Fewer Files" : "Show \(hiddenProjectFileCount) More", systemImage: showsAllProjectFiles ? "chevron.up.circle" : "chevron.down.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(ReadableBorderedButtonStyle())
                                .controlSize(.small)
                                .help(showsAllProjectFiles ? "Collapse the file tree back to the most relevant visible files." : "Show the remaining indexed project files.")
                                .namedControl(showsAllProjectFiles ? "Show fewer project files" : "Show more project files")
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

    private var fileSearchField: some View {
        TextField("Search files", text: $viewModel.fileSearchQuery)
            .workbenchTextField()
            .font(.caption)
            .disabled(!viewModel.isProjectLoaded)
            .help(viewModel.isProjectLoaded ? "Filter indexed project files by name or path." : viewModel.projectPathFeedback.detail)
            .namedControl("Search project files", hint: "Filters indexed project files by name or path.")
    }

    @ViewBuilder
    private var clearFileSearchButton: some View {
        if !viewModel.fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button(action: viewModel.clearFileSearch) {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .help("Clear file search.")
            .namedControl("Clear file search", hint: "Clears the current file filter.")
        }
    }

    private var fileTreeExpansionButtons: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.expandAllProjectFolders) {
                Label("Expand", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.isProjectLoaded)
            .help(viewModel.isProjectLoaded ? "Expand all folders." : viewModel.projectPathFeedback.detail)
            .namedControl("Expand all project folders")

            Button(action: viewModel.collapseAllProjectFolders) {
                Label("Collapse", systemImage: "minus.square")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.isProjectLoaded)
            .help(viewModel.isProjectLoaded ? "Collapse all folders." : viewModel.projectPathFeedback.detail)
            .namedControl("Collapse all project folders")
        }
    }

    private var fileTreeRescanButton: some View {
        Button(action: viewModel.scanProject) {
            Label("Rescan", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canScanProject)
        .help(viewModel.canScanProject ? "Rescan the workspace and refresh the file tree." : viewModel.projectPathFeedback.detail)
        .namedControl("Rescan project files", hint: "Refreshes project analysis and indexed files.")
    }

    private var visibleProjectFiles: [ProjectFileItem] {
        guard !showsAllProjectFiles else { return viewModel.filteredProjectFiles }
        return Array(viewModel.filteredProjectFiles.prefix(14))
    }

    private var hiddenProjectFileCount: Int {
        showsAllProjectFiles ? 0 : max(0, viewModel.filteredProjectFiles.count - visibleProjectFiles.count)
    }

}

private struct SidebarToolList: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var isExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        DisclosureGroup(isExpanded: animatedDisclosureBinding($isExpanded, reduceMotion: reduceMotion, settings: motionSettings)) {
            VStack(spacing: 8) {
                if viewModel.isRunningCommand {
                    runningCommandStopButton
                }
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

    private var runningCommandStopButton: some View {
        Button(action: viewModel.stopRunningCommand) {
            Label(viewModel.runningCommandStopTitle, systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableProminentButtonStyle(color: Palette.red))
        .help(viewModel.runningCommandStopHelpText)
        .namedControl(viewModel.runningCommandStopTitle, hint: viewModel.runningCommandStopHelpText)
    }
}

private struct SidebarToolRow: View {
    let command: AndroidCommandKind
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Button {
            viewModel.runCommand(command)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: command.symbol)
                    .foregroundStyle(Palette.blue)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(command.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        ToolStateBadge(text: stateText, color: stateColor)
                        Spacer(minLength: 0)
                    }
                    Text(command.requiresDevice ? "Device Tool" : "Android Tool")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    Text(command.shellDescription)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
            }
            .padding(10)
            .frame(minHeight: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.006)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.72)))
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
        case "Confirm", "Running": return Palette.amber
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
            .background {
                SurfaceFill(cornerRadius: 6, tint: color.opacity(0.10), material: .ultraThin, textureOpacity: 0.003)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.18)))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MainWorkspaceContentPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                StatusInfoBar(viewModel: viewModel)

                if visiblePanels.contains(.projectIntelligence) {
                    FeatureBoundary {
                        ClosableSectionTitle("Project Intelligence", symbol: "brain.head.profile", panel: .projectIntelligence, visiblePanels: $visiblePanels)
                        ProjectIntelligenceCard(viewModel: viewModel)
                    }
                    .transition(featureTransition)
                }

                if visiblePanels.contains(.askAssistant) {
                    FeatureBoundary {
                        ClosableSectionTitle("Ask The Assistant", symbol: "text.bubble", panel: .askAssistant, visiblePanels: $visiblePanels)
                        AskAssistantCard(viewModel: viewModel)
                    }
                    .transition(featureTransition)
                }

                if visiblePanels.contains(.commandConsole) {
                    FeatureBoundary {
                        ClosableSectionTitle("Command Console", symbol: "terminal", panel: .commandConsole, visiblePanels: $visiblePanels)
                        BuildLogCard(viewModel: viewModel)
                    }
                    .transition(featureTransition)
                }
            }
            .padding(22)
            .animation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings), value: visiblePanels)
        }
        .accessibilityLabel("Assistant feature pane scroll area")
        .background {
            PaneBackdrop(role: .workspace)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant feature pane")
        .accessibilityIdentifier("Assistant feature pane")
    }

    private var featureTransition: AnyTransition {
        WorkbenchMotion.featureTransition(edge: .trailing, reduceMotion: reduceMotion, settings: motionSettings)
    }
}

private struct RightToolDockPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        Group {
            if showsMainFeatures && visiblePanels.contains(.session) {
                combinedPaneContent
            } else {
                singlePaneContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PaneBackdrop(role: .inspector)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Right assistant dock")
        .accessibilityIdentifier("Right assistant dock")
        .animation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings), value: visiblePanels)
    }

    @ViewBuilder
    private var combinedPaneContent: some View {
        VStack(spacing: 0) {
            MainWorkspaceContentPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                .frame(minHeight: 300, maxHeight: .infinity)
                .clipped()
                .transition(featureTransition)

            Divider()

            SessionPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                .frame(minHeight: 240, maxHeight: .infinity)
                .clipped()
                .transition(featureTransition)
        }
    }

    @ViewBuilder
    private var singlePaneContent: some View {
        VStack(spacing: 0) {
            if showsMainFeatures {
                MainWorkspaceContentPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(featureTransition)
            }

            if visiblePanels.contains(.session) {
                SessionPane(viewModel: viewModel, visiblePanels: $visiblePanels)
                    .frame(maxHeight: .infinity)
                    .transition(featureTransition)
            }
        }
    }

    private var showsMainFeatures: Bool {
        visiblePanels.contains(.projectIntelligence)
            || visiblePanels.contains(.askAssistant)
            || visiblePanels.contains(.commandConsole)
    }

    private var featureTransition: AnyTransition {
        WorkbenchMotion.featureTransition(edge: .trailing, reduceMotion: reduceMotion, settings: motionSettings)
    }
}

private struct CenterEditorWorkspace: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>

    var body: some View {
        FeatureBoundary {
            FileEditorPane(viewModel: viewModel, visiblePanels: $visiblePanels)
        }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                PaneBackdrop(role: .workspace)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        ViewThatFits(in: .horizontal) {
            statusHorizontalLayout
            statusVerticalLayout
        }
        .padding(12)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.noticeBackground, material: .ultraThin, textureOpacity: 0.006)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.62)))
        .accessibilityElement(children: .contain)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: viewModel.scanState)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: viewModel.isScanningProject)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: viewModel.lastStatusMessage)
    }

    private var statusHorizontalLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            statusLeadingContent
            Spacer(minLength: 10)
            recommendedActionBlock(horizontalAlignment: .trailing, textAlignment: .trailing)
        }
    }

    private var statusVerticalLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLeadingContent
            recommendedActionBlock(horizontalAlignment: .leading, textAlignment: .leading)
        }
    }

    private var statusLeadingContent: some View {
        HStack(alignment: .top, spacing: 10) {
            if viewModel.isScanningProject {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning project")
                    .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
            } else {
                Image(systemName: viewModel.scanState.symbol)
                    .foregroundStyle(shellStatusColor(for: viewModel))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                    .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
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
                        .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
                }
            }
        }
        .layoutPriority(1)
    }

    private func recommendedActionBlock(horizontalAlignment: HorizontalAlignment, textAlignment: TextAlignment) -> some View {
        VStack(alignment: horizontalAlignment, spacing: 4) {
            Text(viewModel.workspaceSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.75)
            Text(viewModel.recommendedActionDetail)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: viewModel.performRecommendedAction) {
                Label(viewModel.recommendedActionTitle, systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .controlSize(.small)
            .help(viewModel.recommendedActionDetail)
            .namedControl("Recommended action: \(viewModel.recommendedActionTitle)")
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        DisclosureGroup(isExpanded: animatedDisclosureBinding($isExpanded, reduceMotion: reduceMotion, settings: motionSettings)) {
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
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    planStepTitle(step)
                                    ToolStateBadge(text: viewModel.displayState(for: step), color: planStepColor(step))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    planStepTitle(step)
                                    ToolStateBadge(text: viewModel.displayState(for: step), color: planStepColor(step))
                                }
                            }
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .layoutPriority(1)
                    }
                }

                HStack {
                    Spacer()
                    Button(action: { viewModel.generatePlan() }) {
                        Label(viewModel.planNeedsRefresh ? "Refresh Plan" : "Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!viewModel.canGeneratePlan)
                    .help(viewModel.generatePlanHelpText)
                    .namedControl("Regenerate assistant plan", hint: viewModel.generatePlanHelpText)
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

    private func planStepTitle(_ step: AgentPlanStep) -> some View {
        Text(step.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FileEditorPane: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @State private var pendingCloseTarget: EditorCloseTarget?
    @State private var editorFindQuery = ""
    @State private var editorReplaceText = ""
    @Namespace private var editorTabSelectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        SectionHeader(title: "Editor", symbol: "curlybraces.square")
                        Spacer(minLength: 8)
                        editorDirtyPill
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Editor", symbol: "curlybraces.square")
                        editorDirtyPill
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
                            editorDocumentHeader(document)

                            if let error = document.lastError {
                                Text(error)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            editorFindBar(document)

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
                            .background {
                                SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .thin, textureOpacity: 0.004)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(document.lastError == nil ? Palette.border : Palette.red.opacity(0.45)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            editorPrimaryActionBar(for: document)
                            editorSecondaryActionBar

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

    @ViewBuilder
    private var editorDirtyPill: some View {
        if viewModel.dirtyEditorDocumentCount > 0 {
            StatusPill(
                text: "\(viewModel.dirtyEditorDocumentCount) unsaved",
                color: Palette.amber,
                symbol: "circle.fill"
            )
        }
    }

    private func editorDocumentHeader(_ document: EditorDocument) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                editorDocumentPath(document)
                Spacer(minLength: 8)
                editorMetadataBadge(document)
            }

            VStack(alignment: .leading, spacing: 6) {
                editorDocumentPath(document)
                editorMetadataBadge(document)
            }
        }
    }

    private func editorDocumentPath(_ document: EditorDocument) -> some View {
        Text(document.path)
            .font(.caption.monospaced())
            .foregroundStyle(Palette.muted)
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
            .minimumScaleFactor(0.78)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func editorMetadataBadge(_ document: EditorDocument) -> some View {
        Text(editorMetadata(for: document))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.teal)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.teal.opacity(0.11)))
    }

    private func editorFindBar(_ document: EditorDocument) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                editorFindField
                editorReplaceField
                editorFindSummaryLabel(document)
                editorFindActions(document)
            }

            VStack(alignment: .leading, spacing: 6) {
                editorFindField
                editorReplaceField
                HStack(spacing: 8) {
                    editorFindSummaryLabel(document)
                    editorFindActions(document)
                }
            }
        }
        .controlSize(.small)
    }

    private var editorFindField: some View {
        TextField("Find in file", text: $editorFindQuery)
            .workbenchTextField()
            .font(.caption)
            .namedControl("Find in editor file", hint: "Counts matches in the selected editor document.")
    }

    private var editorReplaceField: some View {
        TextField("Replace with", text: $editorReplaceText)
            .workbenchTextField()
            .font(.caption)
            .namedControl("Replace text in editor file", hint: "Replacement text used by Replace All.")
    }

    private func editorFindSummaryLabel(_ document: EditorDocument) -> some View {
        Text(editorFindSummary(in: document))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .frame(minWidth: 74, alignment: .trailing)
    }

    private func editorFindActions(_ document: EditorDocument) -> some View {
        let hasQuery = !editorFindQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let matchCount = editorFindMatchCount(in: document)
        return HStack(spacing: 8) {
            Button(action: { viewModel.replaceInSelectedEditorDocument(find: editorFindQuery, replacement: editorReplaceText) }) {
                Label("Replace All", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .disabled(!hasQuery)
            .help(!hasQuery ? "Enter text to find before replacing." : (matchCount == 0 ? "Run replacement and report if no matches are found." : "Replace all matches in this file."))
            .namedControl("Replace all matches in editor file", hint: "Replaces every case-insensitive match in the selected file.")

            Button(action: { editorFindQuery = "" }) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(ReadableBorderedButtonStyle())
            .namedControl("Clear editor find", hint: "Clears the editor find query.")
        }
    }

    private func editorPrimaryActionBar(for document: EditorDocument) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                editorDocumentActions(for: document)
                Spacer(minLength: 8)
                editorBulkActions
            }

            VStack(alignment: .leading, spacing: 6) {
                editorDocumentActions(for: document)
                editorBulkActions
            }
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
    }

    private func editorDocumentActions(for document: EditorDocument) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                saveEditorButton(for: document)
                revertEditorButton(for: document)
                saveAndCloseEditorButton(for: document)
                closeEditorButton(for: document)
            }

            VStack(alignment: .leading, spacing: 6) {
                saveEditorButton(for: document)
                revertEditorButton(for: document)
                saveAndCloseEditorButton(for: document)
                closeEditorButton(for: document)
            }
        }
    }

    private func saveEditorButton(for document: EditorDocument) -> some View {
        Button(action: viewModel.saveSelectedEditorDocument) {
            Label("Save", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .disabled(!document.isDirty)
        .help(document.isDirty ? "Save through scoped diff, secret scan, and undo checkpoint gates." : "No unsaved changes to save.")
        .keyboardShortcut("s", modifiers: [.command])
        .namedControl("Save editor file")
    }

    private func revertEditorButton(for document: EditorDocument) -> some View {
        Button(action: viewModel.revertSelectedEditorDocument) {
            Label("Revert", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
        }
        .disabled(!document.isDirty)
        .help(document.isDirty ? "Revert this file to the last saved content." : "No unsaved changes to revert.")
        .namedControl("Revert editor file")
    }

    private func saveAndCloseEditorButton(for document: EditorDocument) -> some View {
        Button(action: { _ = viewModel.saveAndCloseSelectedEditorDocument(); hideEditorIfEmpty() }) {
            Label("Save & Close", systemImage: "checkmark.square")
                .frame(maxWidth: .infinity)
        }
        .disabled(!document.isDirty)
        .help(document.isDirty ? "Save this file, then close its editor tab." : "No unsaved changes to save before closing.")
        .namedControl("Save and close editor file", hint: "Saves this file, then closes its editor tab.")
    }

    private func closeEditorButton(for document: EditorDocument) -> some View {
        Button(action: requestCloseSelectedEditorDocument) {
            Label("Close", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .help(document.isDirty ? "Close this editor tab and confirm discarding unsaved changes." : "Close this editor tab.")
        .namedControl("Close editor file")
    }

    private var editorBulkActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                saveAllEditorButton
                closeAllEditorButton
            }

            VStack(alignment: .leading, spacing: 6) {
                saveAllEditorButton
                closeAllEditorButton
            }
        }
    }

    private var saveAllEditorButton: some View {
        Button(action: viewModel.saveAllEditorDocuments) {
            Label("Save All", systemImage: "tray.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .disabled(viewModel.dirtyEditorDocumentCount == 0)
        .help(viewModel.dirtyEditorDocumentCount == 0 ? "No open editor files have unsaved changes." : "Save all open editor files with unsaved changes.")
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .namedControl("Save all editor files")
    }

    private var closeAllEditorButton: some View {
        Button(action: requestCloseAllEditorDocuments) {
            Label("Close All", systemImage: "xmark.square")
                .frame(maxWidth: .infinity)
        }
        .disabled(viewModel.openEditorDocuments.isEmpty)
        .help(viewModel.openEditorDocuments.isEmpty ? "No editor tabs are open." : (viewModel.dirtyEditorDocumentCount == 0 ? "Close every open editor tab." : "Close all editor tabs and confirm discarding unsaved changes."))
        .namedControl("Close all editor files")
    }

    private var editorSecondaryActionBar: some View {
        ViewThatFits(in: .horizontal) {
            editorDiskActions
            VStack(alignment: .leading, spacing: 6) {
                editorDiskActions
            }
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
    }

    private var editorDiskActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                reloadEditorButton
                formatEditorButton
                revealEditorButton
                externalEditorButton
                copyEditorPathButton
            }

            VStack(alignment: .leading, spacing: 6) {
                reloadEditorButton
                formatEditorButton
                revealEditorButton
                externalEditorButton
                copyEditorPathButton
            }
        }
    }

    private var reloadEditorButton: some View {
        Button(action: viewModel.reloadSelectedEditorDocument) {
            Label("Reload", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.hasSelectedEditorFileOnDisk)
        .help(viewModel.selectedEditorDiskActionHelpText)
        .namedControl("Reload selected editor file", hint: "Reloads this file from disk.")
    }

    private var formatEditorButton: some View {
        Button(action: viewModel.formatSelectedEditorDocument) {
            Label("Format", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canFormatSelectedEditorDocument)
        .help(viewModel.selectedEditorFormatHelpText)
        .namedControl("Format selected editor file", hint: "Removes trailing whitespace while preserving indentation.")
    }

    private var revealEditorButton: some View {
        Button(action: viewModel.revealSelectedEditorDocumentInFinder) {
            Label("Reveal", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.hasSelectedEditorFileOnDisk)
        .help(viewModel.selectedEditorDiskActionHelpText)
        .namedControl("Reveal selected editor file", hint: "Shows this file in Finder.")
    }

    private var externalEditorButton: some View {
        Button(action: viewModel.openSelectedEditorDocumentExternally) {
            Label("External", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.hasSelectedEditorFileOnDisk)
        .help(viewModel.selectedEditorDiskActionHelpText)
        .namedControl("Open selected editor file externally", hint: "Opens this file with the default macOS app.")
    }

    private var copyEditorPathButton: some View {
        Button(action: { viewModel.copySelectedEditorPath(absolute: false) }) {
            Label("Copy Path", systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .namedControl("Copy selected editor relative path", hint: "Copies the file path relative to the project.")
    }

    private var editorTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                                        .lineLimit(1)
                                }
                                Text(document.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .minimumScaleFactor(0.78)
                                    .foregroundColor(isSelected(document) ? Color.white : Palette.ink)
                            }
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 88, idealWidth: 150, maxWidth: 220, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help(document.path)
                        .namedControl("Open editor tab \(document.path)")

                        Button {
                            requestClose(document)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 24, height: 24)
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
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Palette.inputBackground)
                        if isSelected(document) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Palette.blue)
                                .matchedGeometryEffect(id: "editorTabSelection", in: editorTabSelectionNamespace)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isSelected(document) ? Palette.blue.opacity(0.75) : Palette.border)
                    )
                }
            }
        }
        .animation(WorkbenchMotion.selection(reduceMotion, settings: motionSettings), value: viewModel.selectedEditorDocument?.path)
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
        let matches = editorFindMatchCount(in: document)
        return "\(matches) match\(matches == 1 ? "" : "es")"
    }

    private func editorFindMatchCount(in document: EditorDocument) -> Int {
        let query = editorFindQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }
        var matches = 0
        var searchStart = document.content.startIndex
        while searchStart < document.content.endIndex,
              let range = document.content.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<document.content.endIndex) {
            matches += 1
            searchStart = range.upperBound
        }
        return matches
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
            withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                _ = visiblePanels.remove(.editor)
            }
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
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.string = text
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
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
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.backgroundColor = .clear
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
            let baseColor = NSColor.labelColor

            storage.beginEditing()
            storage.setAttributes([.font: baseFont, .foregroundColor: baseColor], range: fullRange)

            apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemOrange, range: fullRange, storage: storage)
            apply(pattern: #"//.*"#, color: .secondaryLabelColor, range: fullRange, storage: storage)
            apply(pattern: #"/\*[\s\S]*?\*/"#, color: .secondaryLabelColor, range: fullRange, storage: storage)

            if fileName.lowercased().hasSuffix(".xml") {
                apply(pattern: #"</?[\w:.-]+|/?>"#, color: .systemBlue, range: fullRange, storage: storage)
                apply(pattern: #"[\w:.-]+(?=\=)"#, color: .systemTeal, range: fullRange, storage: storage)
            } else {
                let keywords = [
                    "android", "break", "case", "catch", "class", "data", "default", "do", "else", "enum",
                    "extension", "false", "final", "for", "fun", "if", "import", "in", "interface", "let",
                    "new", "nil", "null", "object", "open", "override", "package", "private", "protected",
                    "public", "return", "sealed", "static", "struct", "switch", "true", "try", "val", "var",
                    "void", "when", "while"
                ].joined(separator: "|")
                apply(pattern: #"(?<![A-Za-z0-9_])(\#(keywords))(?![A-Za-z0-9_])"#, color: .systemBlue, range: fullRange, storage: storage)
                apply(pattern: #"@[A-Za-z_][A-Za-z0-9_]*"#, color: .systemOrange, range: fullRange, storage: storage)
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
        ruleThickness = 44
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
        NSColor.controlBackgroundColor.withAlphaComponent(0.78).setFill()
        bounds.fill()
        NSColor.separatorColor.withAlphaComponent(0.72).setStroke()
        NSBezierPath.strokeLine(
            from: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY),
            to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY)
        )

        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        let visibleRect = textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let text = textView.string as NSString
        let textContainerOrigin = textView.textContainerOrigin
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { _, usedRect, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let lineNumber = text.substring(to: min(characterRange.location, text.length)).filter { $0 == "\n" }.count + 1
            let lineString = "\(lineNumber)" as NSString
            let drawRect = NSRect(
                x: 4,
                y: usedRect.minY + textContainerOrigin.y - visibleRect.minY + 1,
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

private struct BuildLogCard: View {
    @ObservedObject var viewModel: AgentViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

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
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(summary.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                }
                .padding(10)
                .background {
                    SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.006)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.66)))
                .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
            }

            VStack(alignment: .leading, spacing: 0) {
                consoleHeader
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.inputBackground)

                Divider()

                ScrollView(.vertical, showsIndicators: false) {
                    let consoleOutput = viewModel.filteredCommandOutput.isEmpty ? "Command output appears here after Gradle, ADB, Logcat, or packaging commands run." : viewModel.filteredCommandOutput
                    Text(consoleOutput)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Command console output")
                .accessibilityValue(Text(accessibilityLongTextSummary(viewModel.filteredCommandOutput.isEmpty ? "Command output appears here after Gradle, ADB, Logcat, or packaging commands run." : viewModel.filteredCommandOutput)))
                .accessibilityHint("Shows command output with the current console filter applied.")
                .accessibilityIdentifier("Command console output")
            }
            .frame(minHeight: 220)
            .background {
                SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .thin, textureOpacity: 0.006)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.68)))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if viewModel.isOutputTruncated {
                Text("Older console output was truncated after 80,000 characters. Export the log before running another long command.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.amber)
                    .transition(WorkbenchMotion.quietTransition(reduceMotion, settings: motionSettings))
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
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: viewModel.lastCommandSummary)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: viewModel.isOutputTruncated)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: viewModel.isRunningCommand)
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

    private var consoleHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                consoleTitle
                consoleFilterGroup
                consoleSearchControl
                Spacer(minLength: 8)
                consoleMetadataLabel
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    consoleTitle
                    Spacer(minLength: 8)
                    consoleMetadataLabel
                }
                consoleFilterGroup
                consoleSearchControl
            }
        }
    }

    private var consoleTitle: some View {
        Label("Console", systemImage: "terminal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
    }

    private var consoleFilterGroup: some View {
        HStack(spacing: 2) {
            ForEach(ConsoleStreamFilter.allCases) { filter in
                Button {
                    viewModel.consoleStreamFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(viewModel.consoleStreamFilter == filter ? Color.white : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.consoleStreamFilter == filter ? Palette.blue : Palette.surface)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.commandOutput.isEmpty)
                .help(viewModel.commandOutput.isEmpty ? "Run a command before filtering console output." : "Show \(filter.rawValue) console output.")
                .namedControl("Show console \(filter.rawValue)", hint: "Filters the console to \(filter.rawValue).")
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.inputBackground))
    }

    private var consoleSearchControl: some View {
        HStack(spacing: 6) {
            TextField("Filter output", text: $viewModel.consoleSearchQuery)
                .workbenchTextField()
                .font(.caption)
                .frame(minWidth: 120, idealWidth: 180, maxWidth: 220)
                .disabled(viewModel.commandOutput.isEmpty)
                .help(viewModel.commandOutput.isEmpty ? "Run a command before filtering console output." : "Filter console output by line.")
                .namedControl("Filter command console", hint: "Filters console output by line.")
            if !viewModel.consoleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: viewModel.clearConsoleSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .help("Clear console filter.")
                .namedControl("Clear console filter", hint: "Shows the full console output.")
            }
        }
    }

    private var consoleMetadataLabel: some View {
        Text(consoleMetadata)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    private var consoleToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                consoleExecutionActions
                consoleExportActions
                consoleClearAction
            }

            VStack(alignment: .leading, spacing: 6) {
                consoleExecutionActions
                consoleExportActions
                consoleClearAction
            }
        }
    }

    private var consoleExecutionActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if viewModel.isRunningCommand {
                    stopCommandButton
                }
                copyConsoleButton
                copyLastCommandButton
                retryCommandButton
            }

            VStack(alignment: .leading, spacing: 6) {
                if viewModel.isRunningCommand {
                    stopCommandButton
                }
                copyConsoleButton
                copyLastCommandButton
                retryCommandButton
            }
        }
    }

    private var stopCommandButton: some View {
        Button(action: viewModel.stopRunningCommand) {
            Label("Stop", systemImage: "stop.circle")
                .frame(maxWidth: .infinity)
        }
        .help("Stop the currently running command.")
        .namedControl("Stop running command")
    }

    private var copyConsoleButton: some View {
        Button(action: viewModel.copyConsole) {
            Label("Copy Log", systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .disabled(viewModel.commandOutput.isEmpty)
        .help("Copies the currently visible console output, including active stream and search filters.")
        .namedControl("Copy command console", hint: "Copies the currently visible console output, including active stream and search filters.")
    }

    private var copyLastCommandButton: some View {
        Button(action: viewModel.copyLastCommandPreview) {
            Label("Copy Cmd", systemImage: "terminal")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.hasRunnableCommandHistory)
        .help(viewModel.hasRunnableCommandHistory ? "Copy the most recent runnable command." : "Run a command before copying its preview.")
        .namedControl("Copy last command", hint: "Copies the most recent runnable command.")
    }

    private var retryCommandButton: some View {
        Button(action: viewModel.retryLastCommand) {
            Label("Retry", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canRetryLastCommand)
        .help(viewModel.hasRunnableCommandHistory ? "Run the previous command again if it is still valid." : "Run a command before retrying.")
        .namedControl("Retry last command", hint: "Runs the previous command again if it is still valid.")
    }

    private var consoleExportActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                exportConsoleButton
                if !viewModel.lastExportPath.isEmpty {
                    openLastExportButton
                    if !viewModel.lastExportAvailabilityMessage.isEmpty {
                        exportMissingLabel
                    }
                }
                debugReportButton
            }

            VStack(alignment: .leading, spacing: 6) {
                exportConsoleButton
                if !viewModel.lastExportPath.isEmpty {
                    openLastExportButton
                    if !viewModel.lastExportAvailabilityMessage.isEmpty {
                        exportMissingLabel
                    }
                }
                debugReportButton
            }
        }
    }

    private var exportConsoleButton: some View {
        Button(action: viewModel.exportConsole) {
            Label(viewModel.isConsoleViewFiltered ? "Export Full" : "Export", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .disabled(viewModel.commandOutput.isEmpty)
        .help(viewModel.consoleExportHelpText)
        .namedControl("Export command console", hint: viewModel.consoleExportHelpText)
    }

    private var openLastExportButton: some View {
        Button(action: viewModel.openLastExport) {
            Label("Open Export", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.hasLastExportFile)
        .help(viewModel.lastExportAvailabilityMessage.isEmpty ? "Open the most recent \(viewModel.lastExportSourceTitle.lowercased()) export file." : viewModel.lastExportAvailabilityMessage)
        .namedControl("Open last export")
    }

    private var exportMissingLabel: some View {
        Label("Export missing", systemImage: "exclamationmark.triangle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.amber)
            .help(viewModel.lastExportAvailabilityMessage)
    }

    private var debugReportButton: some View {
        Button(action: viewModel.createDebugReport) {
            Label("Debug Report", systemImage: "doc.text")
                .frame(maxWidth: .infinity)
        }
        .help("Export a diagnostics report with project, device, command, and console context.")
        .namedControl("Create debug report")
    }

    private var consoleClearAction: some View {
        Button(action: viewModel.clearOutput) {
            Label("Clear", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .disabled(viewModel.commandOutput.isEmpty)
        .help(viewModel.commandOutput.isEmpty ? "No console output to clear." : "Clear the command console output.")
        .namedControl("Clear command console")
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
                .lineLimit(1)
                .minimumScaleFactor(0.82)
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
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.inspector, material: .thin, textureOpacity: 0.012)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.featureBorder, lineWidth: 1.35)
        )
        .padding(10)
    }
}

private struct SessionTabStrip: View {
    @Binding var selection: SessionPaneTab
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

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
                    .frame(minHeight: 30)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Palette.surface)
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Palette.blue)
                                .matchedGeometryEffect(id: "sessionSelection", in: selectionNamespace)
                        }
                    }
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
        .animation(WorkbenchMotion.selection(reduceMotion, settings: motionSettings), value: selection)
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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.chatMessages) { message in
                        ChatBubble(message: message)
                    }
                }
                .padding(.top, 8)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    sessionStatusPills
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    sessionStatusPills
                }
            }
        }
    }

    @ViewBuilder
    private var sessionStatusPills: some View {
        StatusPill(text: viewModel.scanState.title, color: shellStatusColor(for: viewModel), symbol: viewModel.scanState.symbol)
        if viewModel.isProjectLoaded {
            StatusPill(text: viewModel.profile.packageName, color: Palette.blue, symbol: "shippingbox")
        }
    }
}

private struct SessionDiagnosticsTab: View {
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                SectionHeader(title: "Diagnostics", symbol: "stethoscope")
                                Spacer(minLength: 8)
                                diagnosticsReportButton
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader(title: "Diagnostics", symbol: "stethoscope")
                                diagnosticsReportButton
                            }
                        }
                        ForEach(viewModel.diagnosticRows) { row in
                            DiagnosticRowView(row: row)
                            if row.title == "Ask Response Export" {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 8) {
                                        askExportDiagnosticsButton
                                        askExportDiagnosticsDisabledText
                                        Spacer(minLength: 0)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        askExportDiagnosticsButton
                                        askExportDiagnosticsDisabledText
                                    }
                                }
                            }
                        }
                        Button {
                            withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                                _ = visiblePanels.insert(.askAssistant)
                            }
                            viewModel.noteOpenedAskForExportRecovery()
                        } label: {
                            Label("Open Ask", systemImage: "text.bubble")
                        }
                        .buttonStyle(ReadableBorderedButtonStyle())
                        .controlSize(.small)
                        .disabled(!viewModel.needsAskExportRecoveryAction)
                        .help(viewModel.needsAskExportRecoveryAction ? "Open Ask The Assistant so you can re-export the response." : viewModel.askExportRecoveryDisabledReason)
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
                            .disabled(!viewModel.hasDebugReportFile)
                            .help(viewModel.debugReportAvailabilityMessage.isEmpty ? "Open the latest diagnostics report." : viewModel.debugReportAvailabilityMessage)
                            .namedControl("Open diagnostics report")
                            if !viewModel.debugReportAvailabilityMessage.isEmpty {
                                Label("Report missing", systemImage: "exclamationmark.triangle")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.amber)
                                    .help(viewModel.debugReportAvailabilityMessage)
                            }
                        }
                    }
                }

                ContentCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Verification", symbol: "checklist")
                        ForEach(viewModel.verificationRows) { row in
                            VerificationRowView(row: row)
                        }
                        ViewThatFits(in: .horizontal) {
                            verificationActionButtons
                            VStack(alignment: .leading, spacing: 6) {
                                verificationActionButtons
                            }
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

                LaunchReadinessDiagnosticsCard(viewModel: viewModel)

                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Context", symbol: "scope")
                        if viewModel.isProjectLoaded {
                            LazyVGrid(columns: contextGridColumns, spacing: 8) {
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

    private var diagnosticsReportButton: some View {
        Button(action: viewModel.createDebugReport) {
            Label("Report", systemImage: "doc.text")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .help("Export a diagnostics report with project, device, command, and console context.")
        .namedControl("Create diagnostics report")
    }

    private var askExportDiagnosticsButton: some View {
        Button(action: viewModel.runAskExportDiagnosticsAction) {
            Label(viewModel.askExportDiagnosticsActionTitle, systemImage: viewModel.askExportDiagnosticsActionSymbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(!viewModel.canRunAskExportDiagnosticsAction)
        .help(viewModel.askExportDiagnosticsActionHelpText)
        .namedControl("Ask export diagnostics action", hint: "Opens the Ask export file when available or re-exports it when stale.")
    }

    @ViewBuilder
    private var askExportDiagnosticsDisabledText: some View {
        if !viewModel.canRunAskExportDiagnosticsAction && !viewModel.askExportDiagnosticsActionDisabledReason.isEmpty {
            Text(viewModel.askExportDiagnosticsActionDisabledReason)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var verificationActionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                runUnitTestsButton
                runBuildButton
                runLogcatButton
            }

            VStack(alignment: .leading, spacing: 6) {
                runUnitTestsButton
                runBuildButton
                runLogcatButton
            }
        }
    }

    private var runUnitTestsButton: some View {
        Button(action: { viewModel.runCommand(.unitTests) }) {
            Label("Run Tests", systemImage: "checkmark.seal")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canRunCommand(.unitTests))
        .help(viewModel.commandHelpText(.unitTests))
        .namedControl("Run unit tests from diagnostics", hint: "Runs the selected unit-test Gradle task.")
    }

    private var runBuildButton: some View {
        Button(action: { viewModel.runCommand(.assembleDebug) }) {
            Label("Build", systemImage: "hammer")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canRunCommand(.assembleDebug))
        .help(viewModel.commandHelpText(.assembleDebug))
        .namedControl("Run build from diagnostics", hint: "Builds the selected variant.")
    }

    private var runLogcatButton: some View {
        Button(action: { viewModel.runCommand(.logcat) }) {
            Label("Logcat", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canRunCommand(.logcat))
        .help(viewModel.commandHelpText(.logcat))
        .namedControl("Capture logcat from diagnostics", hint: "Captures a recent Logcat snapshot for the selected device.")
    }

    private var contextGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8)]
    }
}

private struct SessionChecksTab: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
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
                            LazyVGrid(columns: contextGridColumns, spacing: 8) {
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

    private var contextGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8)]
    }
}

@MainActor
public enum AndroidDevAgentUICoverageHarness {
    public static func wirelessDisconnectDiagnostics() -> [String: String] {
        AgentViewModel.wirelessDisconnectCoverageDiagnostics()
    }

    public static func deviceTestStopDiagnostics() -> [String: String] {
        AgentViewModel.deviceTestStopCoverageDiagnostics()
    }

    public static func editorSaveSafetyDiagnostics() -> [String: String] {
        AgentViewModel.editorSaveSafetyCoverageDiagnostics()
    }

    public static func assistantPrivacyDiagnostics() -> [String: String] {
        AgentViewModel.assistantPrivacyCoverageDiagnostics()
    }

    public static func assistantModelSetupDiagnostics() -> [String: String] {
        AgentViewModel.assistantModelSetupCoverageDiagnostics()
    }

    public static func launchReadinessDiagnostics() async -> [String: String] {
        await AgentViewModel.launchReadinessCoverageDiagnostics()
    }

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
        let settingsHidden = Binding.constant(false)

        touched += touch(AgentWorkbenchView())
        touched += touch(ShellTitleBar(viewModel: empty, isSettingsPresented: settingsHidden))
        touched += touch(ShellTitleBar(viewModel: running, isSettingsPresented: settingsHidden))
        touched += touch(ShellTitleBar(viewModel: failed, isSettingsPresented: settingsHidden))
        touched += touch(AgentSettingsPopover())
        touched += touch(LaunchReadinessSettingsSection())
        touched += touch(AgentSettingsSection(title: "Coverage", symbol: "gearshape") { Text("Theme") })
        touched += touch(AgentAccentThemeButton(theme: .pacific, isSelected: true) {})
        touched += touch(AgentSurfaceStyleButton(style: .balanced, isSelected: true) {})
        touched += touch(AgentMotionStyleButton(style: .native, isSelected: true) {})
        touched += touch(EmptyToolWindowCanvas(viewModel: empty, visiblePanels: noPanels))
        touched += touch(LaunchReadinessOnboardingCard(visiblePanels: allPanels))
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
        touched += touch(WirelessDeviceConnectionSheet(viewModel: empty))
        touched += touch(WirelessDeviceDiscoveryList(viewModel: loaded))
        touched += touch(WirelessQRCodeConnectionPanel(viewModel: empty))
        touched += touch(WirelessPairingCodeConnectionPanel(viewModel: empty))
        if let wirelessDevice = loaded.wirelessDebuggingDevices.first {
            touched += touch(WirelessDebuggingDeviceRow(device: wirelessDevice, isSelected: true) {})
        }
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
        touched += touch(AssistantModelSetupPanel(viewModel: loaded))
        touched += touch(BuildLogCard(viewModel: empty))
        touched += touch(BuildLogCard(viewModel: running))
        touched += touch(BuildLogCard(viewModel: failed))
        touched += touch(SessionPane(viewModel: empty, visiblePanels: allPanels))
        touched += touch(SessionPane(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(SessionChatTab(viewModel: empty))
        touched += touch(SessionChatTab(viewModel: loaded))
        touched += touch(SessionDiagnosticsTab(viewModel: empty, visiblePanels: allPanels))
        touched += touch(SessionDiagnosticsTab(viewModel: loaded, visiblePanels: allPanels))
        touched += touch(LaunchReadinessDiagnosticsCard(viewModel: loaded))
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
