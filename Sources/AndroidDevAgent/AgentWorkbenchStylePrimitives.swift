import AppKit
import SwiftUI

enum SurfaceMaterial {
    case ultraThin
    case thin
    case regular
}
struct SurfaceFill: View {
    let cornerRadius: CGFloat
    let tint: Color
    var material: SurfaceMaterial = .thin
    var textureOpacity: Double = 0.006
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.workbenchThemeSettings) var themeSettings

    var body: some View {
        let allowsMaterial = !reduceTransparency && themeSettings.surfaceStyle.materialEnabled
        let gradientOpacity = themeSettings.surfaceStyle.gradientOpacity
        let effectiveTextureOpacity = textureOpacity * themeSettings.effectiveTextureScale

        ZStack {
            if allowsMaterial {
                materialLayer
            }
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tint)

            if !reduceTransparency {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((colorScheme == .dark ? 0.030 : 0.16) * gradientOpacity),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if effectiveTextureOpacity > 0 {
                    SurfaceTexture(opacity: colorScheme == .dark ? effectiveTextureOpacity * 0.70 : effectiveTextureOpacity * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
        }
    }

    @ViewBuilder
    var materialLayer: some View {
        switch material {
        case .ultraThin:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
        case .thin:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.thinMaterial)
        case .regular:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
        }
    }
}

enum PaneBackdropRole {
    case titleBar
    case rail
    case sidebar
    case workspace
    case inspector

    var baseColor: Color {
        switch self {
        case .titleBar:
            return Palette.titleBar
        case .rail:
            return Palette.railSurface
        case .sidebar:
            return Palette.sidebar
        case .workspace:
            return Palette.workspace
        case .inspector:
            return Palette.inspector
        }
    }

    var material: SurfaceMaterial {
        switch self {
        case .titleBar, .rail:
            return .regular
        case .sidebar, .inspector:
            return .thin
        case .workspace:
            return .ultraThin
        }
    }

    func gradientColors(for colorScheme: ColorScheme, settings: WorkbenchThemeSettings) -> [Color] {
        let top = colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.62)
        let bottom = colorScheme == .dark ? Color.black.opacity(0.22) : settings.accentColor.opacity(0.045)
        switch self {
        case .titleBar:
            return [top, settings.accentColor.opacity(colorScheme == .dark ? 0.055 : 0.035), bottom]
        case .rail:
            return [top.opacity(0.75), settings.companionColor.opacity(colorScheme == .dark ? 0.04 : 0.025), bottom.opacity(0.85)]
        case .sidebar, .inspector:
            return [top.opacity(0.45), baseColor, bottom.opacity(0.55)]
        case .workspace:
            return [top.opacity(0.28), baseColor, bottom.opacity(0.35)]
        }
    }

    func textureOpacity(for colorScheme: ColorScheme) -> Double {
        switch self {
        case .titleBar, .rail:
            return colorScheme == .dark ? 0.026 : 0.014
        case .sidebar, .inspector:
            return colorScheme == .dark ? 0.020 : 0.010
        case .workspace:
            return colorScheme == .dark ? 0.016 : 0.008
        }
    }
}

struct WorkbenchBackdrop: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.workbenchThemeSettings) var themeSettings

    var body: some View {
        ZStack {
            Palette.appBackground
            if !reduceTransparency {
                LinearGradient(
                    colors: backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if themeSettings.effectiveTextureScale > 0 {
                    SurfaceTexture(opacity: (colorScheme == .dark ? 0.020 : 0.010) * themeSettings.effectiveTextureScale)
                }
            }
        }
    }

    var backgroundGradient: [Color] {
        if colorScheme == .dark {
            return [
                themeSettings.accentColor.opacity(0.08 * themeSettings.surfaceStyle.gradientOpacity),
                Color.black.opacity(0.10),
                themeSettings.companionColor.opacity(0.06 * themeSettings.surfaceStyle.gradientOpacity)
            ]
        }
        return [
            Color.white.opacity(0.74),
            themeSettings.accentColor.opacity(0.045 * themeSettings.surfaceStyle.gradientOpacity),
            themeSettings.companionColor.opacity(0.035 * themeSettings.surfaceStyle.gradientOpacity)
        ]
    }
}

struct PaneBackdrop: View {
    let role: PaneBackdropRole
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.workbenchThemeSettings) var themeSettings

    var body: some View {
        let allowsMaterial = !reduceTransparency && themeSettings.surfaceStyle.materialEnabled

        ZStack {
            if allowsMaterial {
                materialLayer
            }
            role.baseColor
            if !reduceTransparency {
                LinearGradient(
                    colors: role.gradientColors(for: colorScheme, settings: themeSettings).map { $0.opacity(themeSettings.surfaceStyle.gradientOpacity) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                let textureOpacity = role.textureOpacity(for: colorScheme) * themeSettings.effectiveTextureScale
                if textureOpacity > 0 {
                    SurfaceTexture(opacity: textureOpacity)
                }
            }
        }
    }

    @ViewBuilder
    var materialLayer: some View {
        switch role.material {
        case .ultraThin:
            Rectangle().fill(.ultraThinMaterial)
        case .thin:
            Rectangle().fill(.thinMaterial)
        case .regular:
            Rectangle().fill(.regularMaterial)
        }
    }
}

struct SurfaceTexture: View {
    let opacity: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            let columns = max(1, Int(size.width / cell))
            let rows = max(1, Int(size.height / cell))
            let speckle = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)

            for row in 0...rows {
                for column in 0...columns {
                    let seed = (column * 37 + row * 61) % 23
                    guard seed == 0 || seed == 11 else { continue }
                    let x = CGFloat(column) * cell + CGFloat((row * 7 + column * 3) % 9)
                    let y = CGFloat(row) * cell + CGFloat((column * 5 + row * 2) % 9)
                    let rect = CGRect(x: x, y: y, width: 0.7, height: 0.7)
                    context.fill(Path(ellipseIn: rect), with: .color(speckle))
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ContentCard<Content: View>: View {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let accentColor: Color?
    let content: Content
    @Environment(\.workbenchThemeSettings) var themeSettings

    init(
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 12,
        accentColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.accentColor = accentColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .thin, textureOpacity: 0.010)
            }
            .overlay(alignment: .leading) {
                if let accentColor {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 2)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Palette.cardBorder, lineWidth: 1)
            )
            .shadow(color: Palette.cardShadow.opacity(themeSettings.surfaceStyle.shadowScale), radius: 7, x: 0, y: 2)
            .layoutPriority(1)
    }
}

struct FeatureBoundary<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.workbenchThemeSettings) var themeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.groupBackground, material: .ultraThin, textureOpacity: 0.006)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.featureBorder, lineWidth: 1)
        )
        .shadow(color: Palette.groupShadow.opacity(themeSettings.surfaceStyle.shadowScale), radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ClosableSectionTitle: View {
    let title: String
    let symbol: String
    let panel: ToolWindowPanel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings

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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button {
                withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                    _ = visiblePanels.remove(panel)
                }
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.inputBackground.opacity(0.001)))
            .help("Close \(title)")
            .namedControl("Close \(title) panel", hint: "Hides this tool pane. Reopen it from the side rail.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarSectionTitle: View {
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
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
}

@MainActor
func shellStatusColor(for viewModel: AgentViewModel) -> Color {
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

extension AndroidCommandKind {
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

struct ProjectMetricStrip: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Group {
            if viewModel.isProjectLoaded {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        metricCards
                    }

                    VStack(spacing: 8) {
                        metricCards
                    }
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
                .background {
                    SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.006)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.66)))
            }
        }
    }

    @ViewBuilder
    var metricCards: some View {
        MiniMetric(value: viewModel.snapshot.fileCount.formatted(), label: "Files", color: Palette.blue)
        MiniMetric(value: viewModel.snapshot.testFileCount.formatted(), label: "Tests", color: Palette.teal)
        MiniMetric(value: viewModel.snapshot.hasGradleWrapper ? "Wrapper" : "System", label: "Gradle", color: Palette.amber)
    }
}

struct MiniMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .ultraThin, textureOpacity: 0.006)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }
}

struct ProjectFileRow: View {
    let item: ProjectFileItem
    @ObservedObject var viewModel: AgentViewModel
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings

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
                        .accessibilityHidden(true)
                }
                Image(systemName: item.symbol)
                    .font(.caption)
                    .foregroundStyle(rowIconColor)
                    .frame(width: 16)
                highlightedText(item.name, baseColor: rowTextColor)
                    .font(.system(size: 13, weight: rowWeight))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                Spacer(minLength: 0)
                if isOpenFile {
                    Text("Open")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.blue)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.blue.opacity(0.12)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
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

    var rowWeight: Font.Weight {
        item.isDirectory || item.isSelected ? .semibold : .regular
    }

    var rowTextColor: Color {
        item.isSelected ? Palette.blue : Palette.ink
    }

    var rowIconColor: Color {
        if item.isDirectory {
            return viewModel.isProjectFolderExpanded(item) ? Palette.blue : Palette.muted
        }
        return item.isSelected ? Palette.blue : Palette.muted
    }

    var isOpenFile: Bool {
        !item.isDirectory && viewModel.selectedEditorPath == item.path
    }

    var rowBackground: Color {
        if isOpenFile { return Palette.blue.opacity(0.14) }
        if item.isSelected { return Palette.blue.opacity(0.08) }
        if item.isDirectory { return Palette.inputBackground.opacity(0.75) }
        return Color.clear
    }

    func highlightedText(_ text: String, baseColor: Color) -> Text {
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

    func openInEditor() {
        guard !item.isDirectory else {
            viewModel.toggleProjectFolder(item)
            return
        }
        viewModel.openFile(item)
        if viewModel.selectedEditorDocument != nil {
            withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                _ = visiblePanels.insert(.editor)
            }
        }
    }
}

struct PromptHistoryMenu: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        Menu {
            if viewModel.promptHistory.isEmpty {
                Text("No prompt history")
            } else {
                ForEach(viewModel.promptHistory, id: \.self) { value in
                    Button(promptHistoryTitle(value)) {
                        viewModel.usePromptFromHistory(value)
                    }
                    Button("Remove: \(promptHistoryTitle(value, limit: 32))") {
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
        .disabled(viewModel.promptHistory.isEmpty)
        .help(viewModel.promptHistory.isEmpty ? "No prompt history is available yet." : "Restore a previous prompt.")
        .namedControl("Prompt history")
    }

    func promptHistoryTitle(_ value: String, limit: Int = 64) -> String {
        let compact = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard compact.count > limit else { return compact }
        return "\(compact.prefix(limit))..."
    }
}

struct HighContrastMenuLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
                .foregroundColor(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Palette.blue)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 28)
        .background {
            SurfaceFill(cornerRadius: 7, tint: Palette.controlBackground, material: .ultraThin, textureOpacity: 0.004)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
    }
}

struct ChatBubble: View {
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
                    .lineLimit(1)
                Text(message.message)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(minWidth: 160, idealWidth: 340, maxWidth: 420, alignment: .leading)
            .background {
                SurfaceFill(cornerRadius: 8, tint: message.isUser ? Palette.userBubble : Palette.agentBubble, material: .ultraThin, textureOpacity: 0.004)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke((message.isUser ? Palette.blue : Palette.teal).opacity(0.18)))
            if !message.isUser {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct VerificationRowView: View {
    let row: VerificationRow
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(row.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Palette.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(row.state)
                .font(.caption2.weight(.bold))
                .foregroundStyle(stateColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(stateColor.opacity(0.12)))
        }
        .padding(10)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.inputBackground, material: .ultraThin, textureOpacity: 0.004)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.42)))
        .accessibilityElement(children: .combine)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: row)
    }

    var stateColor: Color {
        switch row.severity {
        case "warning", "optional": return Palette.amber
        case "running": return Palette.amber
        case "neutral": return Palette.blue
        default: return Palette.teal
        }
    }
}

struct DiagnosticRowView: View {
    let row: DiagnosticRow
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.inputBackground, material: .ultraThin, textureOpacity: 0.004)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.38)))
        .accessibilityElement(children: .combine)
        .animation(WorkbenchMotion.state(reduceMotion, settings: motionSettings), value: row)
    }

    var color: Color {
        switch row.severity {
        case "ready": return Palette.teal
        case "failed": return Palette.red
        case "warning", "running": return Palette.amber
        default: return Palette.blue
        }
    }
}

struct ContextChip: View {
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
                .truncationMode(.middle)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.inputBackground, material: .ultraThin, textureOpacity: 0.004)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.34)))
        .help("\(title): \(value)")
        .accessibilityElement(children: .combine)
    }
}

struct EmptyProjectPlaceholder: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.blue)
                .frame(width: 42, height: 42)
                .background {
                    SurfaceFill(cornerRadius: 8, tint: Palette.blue.opacity(0.10), material: .ultraThin, textureOpacity: 0.004)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.blue.opacity(0.18)))
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(message)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.noticeBackground, material: .ultraThin, textureOpacity: 0.008)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.52)))
        .motionEntrance()
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                SurfaceFill(cornerRadius: 7, tint: color.opacity(0.10), material: .ultraThin, textureOpacity: 0.004)
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.22)))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func accessibilityLongTextSummary(_ text: String, previewLimit: Int = 420) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "No content." }

    let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
    let normalizedPreview = trimmed.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )
    let preview: String
    if normalizedPreview.count > previewLimit {
        preview = "\(String(normalizedPreview.prefix(previewLimit)))..."
    } else {
        preview = normalizedPreview
    }

    return "\(lineCount) line\(lineCount == 1 ? "" : "s"), \(trimmed.count) characters. Preview: \(preview)"
}

func animatedDisclosureBinding(
    _ binding: Binding<Bool>,
    reduceMotion: Bool,
    settings: WorkbenchMotionSettings
) -> Binding<Bool> {
    Binding {
        binding.wrappedValue
    } set: { isExpanded in
        withAnimation(WorkbenchMotion.panel(reduceMotion, settings: settings)) {
            binding.wrappedValue = isExpanded
        }
    }
}

struct MotionEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings
    @State var didAppear = false

    func body(content: Content) -> some View {
        content
            .opacity(didAppear ? 1 : 0)
            .offset(y: motionSettings.allowsEntranceMotion(reduceMotion) && !didAppear ? 6 : 0)
            .scaleEffect(motionSettings.allowsEntranceMotion(reduceMotion) && !didAppear ? 0.985 : 1)
            .onAppear {
                if !motionSettings.allowsEntranceMotion(reduceMotion) {
                    didAppear = true
                } else {
                    withAnimation(WorkbenchMotion.entrance(false, settings: motionSettings)) {
                        didAppear = true
                    }
                }
            }
    }
}

struct WorkbenchPulseModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchThemeSettings) var themeSettings
    @Environment(\.workbenchMotionSettings) var motionSettings
    @State var pulse = false

    func body(content: Content) -> some View {
        let allowsPulse = motionSettings.allowsStatusPulse(reduceMotion)
        content
            .scaleEffect(isActive && allowsPulse && pulse ? pulseScale : 1)
            .shadow(
                color: isActive && allowsPulse ? themeSettings.accentColor.opacity(pulse ? pulseOpacity : 0.05) : Color.clear,
                radius: isActive && allowsPulse ? (pulse ? pulseRadius : 2) : 0,
                x: 0,
                y: 1
            )
            .animation(isActive && allowsPulse ? pulseAnimation : nil, value: pulse)
            .onAppear {
                pulse = isActive && allowsPulse
            }
            .onChange(of: isActive) { _, active in
                pulse = active && allowsPulse
            }
            .onChange(of: reduceMotion) { _, reduced in
                pulse = isActive && motionSettings.allowsStatusPulse(reduced)
            }
            .onChange(of: motionSettings) { _, settings in
                pulse = isActive && settings.allowsStatusPulse(reduceMotion)
            }
    }

    var pulseAnimation: Animation {
        switch motionSettings.style {
        case .native:
            return .easeInOut(duration: 1.15).repeatForever(autoreverses: true)
        case .snappy:
            return .easeInOut(duration: 0.78).repeatForever(autoreverses: true)
        case .gentle:
            return .easeInOut(duration: 1.65).repeatForever(autoreverses: true)
        case .minimal:
            return .easeInOut(duration: 1.15).repeatForever(autoreverses: true)
        }
    }

    var pulseScale: CGFloat {
        switch motionSettings.style {
        case .gentle: return 1.008
        case .snappy: return 1.010
        case .native, .minimal: return 1.012
        }
    }

    var pulseOpacity: Double {
        switch motionSettings.style {
        case .gentle: return 0.14
        case .snappy: return 0.16
        case .native, .minimal: return 0.18
        }
    }

    var pulseRadius: CGFloat {
        switch motionSettings.style {
        case .gentle: return 5
        case .snappy: return 4
        case .native, .minimal: return 7
        }
    }
}

extension View {
    func motionEntrance() -> some View {
        modifier(MotionEntranceModifier())
    }

    func workbenchPulse(isActive: Bool) -> some View {
        modifier(WorkbenchPulseModifier(isActive: isActive))
    }

    func namedControl(_ label: String, hint: String? = nil) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(label))
            .accessibilityHint(Text(hint ?? label))
            .accessibilityIdentifier(label)
    }

    func workbenchTextField() -> some View {
        modifier(WorkbenchTextFieldModifier())
    }
}

struct WorkbenchTextFieldModifier: ViewModifier {
    @Environment(\.isEnabled) var isEnabled

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background {
                SurfaceFill(
                    cornerRadius: 7,
                    tint: isEnabled ? Palette.inputBackground : Palette.groupBackground,
                    material: .ultraThin,
                    textureOpacity: 0.004
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? Palette.controlBorder : Palette.border.opacity(0.48), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.76)
    }
}

struct ReadableBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.workbenchThemeSettings) var themeSettings
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.ink : Palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background {
                SurfaceFill(
                    cornerRadius: 7,
                    tint: isEnabled ? buttonBackground(configuration: configuration) : Palette.inputBackground,
                    material: .ultraThin,
                    textureOpacity: 0.006
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? Palette.controlBorder : Palette.border.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Palette.controlShadow.opacity((configuration.isPressed ? 0.35 : 1) * themeSettings.surfaceStyle.shadowScale), radius: configuration.isPressed ? 1 : 3, x: 0, y: configuration.isPressed ? 0 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.82)
            .scaleEffect(configuration.isPressed && WorkbenchMotion.press(reduceMotion, settings: motionSettings) != nil ? 0.985 : 1)
            .animation(WorkbenchMotion.press(reduceMotion, settings: motionSettings), value: configuration.isPressed)
    }

    func buttonBackground(configuration: Configuration) -> Color {
        configuration.isPressed ? Palette.controlPressedBackground : Palette.controlBackground
    }
}

struct ReadableProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.workbenchThemeSettings) var themeSettings
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.workbenchMotionSettings) var motionSettings
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(prominentBackground(configuration: configuration))
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(isEnabled ? 0.20 : 0.04), Color.black.opacity(isEnabled ? 0.10 : 0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isEnabled ? Color.white.opacity(0.22) : Palette.border, lineWidth: 1)
            )
            .shadow(color: color.opacity((configuration.isPressed ? 0.12 : 0.24) * themeSettings.surfaceStyle.shadowScale), radius: configuration.isPressed ? 1 : 5, x: 0, y: configuration.isPressed ? 0 : 2)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? 1 : 0.84)
            .scaleEffect(configuration.isPressed && WorkbenchMotion.press(reduceMotion, settings: motionSettings) != nil ? 0.985 : 1)
            .animation(WorkbenchMotion.press(reduceMotion, settings: motionSettings), value: configuration.isPressed)
    }

    func prominentBackground(configuration: Configuration) -> Color {
        guard isEnabled else { return Palette.inputBackground }
        return configuration.isPressed ? color.opacity(0.78) : color
    }
}

enum Palette {
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let titleBar = Color(nsColor: .windowBackgroundColor).opacity(0.90)
    static let sidebar = Color(nsColor: .controlBackgroundColor).opacity(0.70)
    static let workspace = Color(nsColor: .windowBackgroundColor).opacity(0.52)
    static let inspector = Color(nsColor: .controlBackgroundColor).opacity(0.70)
    static let railSurface = Color(nsColor: .windowBackgroundColor).opacity(0.84)
    static let surface = Color(nsColor: .controlBackgroundColor).opacity(0.92)
    static let groupBackground = Color(nsColor: .windowBackgroundColor).opacity(0.30)
    static let inputBackground = Color(nsColor: .textBackgroundColor).opacity(0.82)
    static let noticeBackground = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let controlBackground = Color(nsColor: .controlBackgroundColor).opacity(0.88)
    static let controlPressedBackground = Color(nsColor: .selectedControlColor).opacity(0.20)
    static let border = Color(nsColor: .separatorColor).opacity(0.62)
    static let controlBorder = Color(nsColor: .separatorColor).opacity(0.58)
    static let cardBorder = Color(nsColor: .separatorColor).opacity(0.44)
    static let featureBorder = Color(nsColor: .separatorColor).opacity(0.38)
    static let darkBorder = Color.white.opacity(0.10)
    static let cardShadow = Color.black.opacity(0.055)
    static let groupShadow = Color.black.opacity(0.030)
    static let controlShadow = Color.black.opacity(0.055)
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let teal = Color(nsColor: .systemTeal)
    static let blue = Color.accentColor
    static let railMuted = Color(nsColor: .secondaryLabelColor)
    static let railBackground = Color(nsColor: .controlBackgroundColor).opacity(0.45)
    static let railHoverBackground = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let railSelectedBackground = Color.accentColor.opacity(0.16)
    static let railBorder = Color(nsColor: .separatorColor).opacity(0.52)
    static let railSelectedBorder = Color.accentColor.opacity(0.56)
    static let amber = Color(nsColor: .systemOrange)
    static let red = Color(nsColor: .systemRed)
    static let editorHeader = Color(nsColor: .controlBackgroundColor)
    static let editorBackground = Color(nsColor: .textBackgroundColor)
    static let editorText = Color(nsColor: .labelColor)
    static let terminalHeader = Color(nsColor: .controlBackgroundColor)
    static let terminalBackground = Color(nsColor: .textBackgroundColor)
    static let terminalText = Color(nsColor: .labelColor)
    static let diffGreen = Color(nsColor: .systemGreen)
    static let diffRed = Color(nsColor: .systemRed)
    static let diffAmber = Color(nsColor: .systemYellow)
    static let diffBlue = Color(nsColor: .systemBlue)
    static let greenText = Color(nsColor: .systemMint)
    static let userBubble = Color.accentColor.opacity(0.12)
    static let agentBubble = Color(nsColor: .systemTeal).opacity(0.12)
}
