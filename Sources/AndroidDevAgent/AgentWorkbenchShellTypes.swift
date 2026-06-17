import AppKit
import SwiftUI

let agentWorkbenchVisiblePanelsKey = "AndroidDevAgentVisiblePanels"
let agentWorkbenchColorSchemeKey = "AndroidDevAgentColorScheme"
let agentWorkbenchAccentThemeKey = "AndroidDevAgentAccentTheme"
let agentWorkbenchSurfaceStyleKey = "AndroidDevAgentSurfaceStyle"
let agentWorkbenchTextureEnabledKey = "AndroidDevAgentTextureEnabled"
let agentWorkbenchMotionStyleKey = "AndroidDevAgentMotionStyle"
let agentWorkbenchPanelMotionEnabledKey = "AndroidDevAgentPanelMotionEnabled"
let agentWorkbenchSelectionMotionEnabledKey = "AndroidDevAgentSelectionMotionEnabled"
let agentWorkbenchStateMotionEnabledKey = "AndroidDevAgentStateMotionEnabled"
let agentWorkbenchStatusPulseEnabledKey = "AndroidDevAgentStatusPulseEnabled"
let agentWorkbenchEntranceMotionEnabledKey = "AndroidDevAgentEntranceMotionEnabled"

public enum AndroidDevAgentNotifications {
    public static let openAgentSettings = Notification.Name("AndroidDevAgentOpenAgentSettings")
}

enum WorkbenchColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum WorkbenchAccentTheme: String, CaseIterable, Identifiable {
    case pacific
    case violet
    case evergreen
    case graphite
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pacific: return "Pacific"
        case .violet: return "Violet"
        case .evergreen: return "Evergreen"
        case .graphite: return "Graphite"
        case .ember: return "Ember"
        }
    }

    var symbol: String {
        switch self {
        case .pacific: return "water.waves"
        case .violet: return "sparkles"
        case .evergreen: return "leaf"
        case .graphite: return "circle.hexagongrid"
        case .ember: return "flame"
        }
    }

    var accentColor: Color {
        switch self {
        case .pacific: return Color(nsColor: .systemBlue)
        case .violet: return Color(nsColor: .systemPurple)
        case .evergreen: return Color(nsColor: .systemGreen)
        case .graphite: return Color(nsColor: .systemGray)
        case .ember: return Color(nsColor: .systemOrange)
        }
    }

    var companionColor: Color {
        switch self {
        case .pacific: return Color(nsColor: .systemTeal)
        case .violet: return Color(nsColor: .systemIndigo)
        case .evergreen: return Color(nsColor: .systemMint)
        case .graphite: return Color(nsColor: .systemBlue)
        case .ember: return Color(nsColor: .systemPink)
        }
    }
}

enum WorkbenchSurfaceStyle: String, CaseIterable, Identifiable {
    case vibrant
    case balanced
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vibrant: return "Vibrant"
        case .balanced: return "Balanced"
        case .solid: return "Solid"
        }
    }

    var symbol: String {
        switch self {
        case .vibrant: return "square.stack.3d.up.fill"
        case .balanced: return "rectangle.3.group"
        case .solid: return "square.fill"
        }
    }

    var materialEnabled: Bool {
        self != .solid
    }

    var gradientOpacity: Double {
        switch self {
        case .vibrant: return 1.0
        case .balanced: return 0.62
        case .solid: return 0.16
        }
    }

    var textureScale: Double {
        switch self {
        case .vibrant: return 1.0
        case .balanced: return 0.46
        case .solid: return 0.0
        }
    }

    var shadowScale: Double {
        switch self {
        case .vibrant: return 1.0
        case .balanced: return 0.62
        case .solid: return 0.24
        }
    }
}

enum WorkbenchMotionStyle: String, CaseIterable, Identifiable {
    case native
    case snappy
    case gentle
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: return "Native"
        case .snappy: return "Snappy"
        case .gentle: return "Gentle"
        case .minimal: return "Minimal"
        }
    }

    var symbol: String {
        switch self {
        case .native: return "macwindow"
        case .snappy: return "bolt"
        case .gentle: return "leaf"
        case .minimal: return "minus.circle"
        }
    }
}

struct WorkbenchThemeSettings: Equatable {
    var colorSchemePreference: WorkbenchColorSchemePreference
    var accentTheme: WorkbenchAccentTheme
    var surfaceStyle: WorkbenchSurfaceStyle
    var textureEnabled: Bool

    static let `default` = WorkbenchThemeSettings(
        colorSchemePreference: .system,
        accentTheme: .pacific,
        surfaceStyle: .balanced,
        textureEnabled: true
    )

    var preferredColorScheme: ColorScheme? {
        colorSchemePreference.colorScheme
    }

    var accentColor: Color {
        accentTheme.accentColor
    }

    var companionColor: Color {
        accentTheme.companionColor
    }

    var effectiveTextureScale: Double {
        textureEnabled ? surfaceStyle.textureScale : 0
    }
}

struct WorkbenchMotionSettings: Equatable {
    var style: WorkbenchMotionStyle
    var panelTransitionsEnabled: Bool
    var selectionMotionEnabled: Bool
    var stateMotionEnabled: Bool
    var statusPulseEnabled: Bool
    var entranceMotionEnabled: Bool

    static let `default` = WorkbenchMotionSettings(
        style: .native,
        panelTransitionsEnabled: true,
        selectionMotionEnabled: true,
        stateMotionEnabled: true,
        statusPulseEnabled: true,
        entranceMotionEnabled: true
    )

    func allowsPanelMotion(_ reduceMotion: Bool) -> Bool {
        !reduceMotion && style != .minimal && panelTransitionsEnabled
    }

    func allowsSelectionMotion(_ reduceMotion: Bool) -> Bool {
        !reduceMotion && style != .minimal && selectionMotionEnabled
    }

    func allowsStateMotion(_ reduceMotion: Bool) -> Bool {
        !reduceMotion && style != .minimal && stateMotionEnabled
    }

    func allowsStatusPulse(_ reduceMotion: Bool) -> Bool {
        !reduceMotion && style != .minimal && statusPulseEnabled
    }

    func allowsEntranceMotion(_ reduceMotion: Bool) -> Bool {
        !reduceMotion && style != .minimal && entranceMotionEnabled
    }
}

struct WorkbenchThemeSettingsKey: EnvironmentKey {
    static let defaultValue = WorkbenchThemeSettings.default
}

struct WorkbenchMotionSettingsKey: EnvironmentKey {
    static let defaultValue = WorkbenchMotionSettings.default
}

extension EnvironmentValues {
    var workbenchThemeSettings: WorkbenchThemeSettings {
        get { self[WorkbenchThemeSettingsKey.self] }
        set { self[WorkbenchThemeSettingsKey.self] = newValue }
    }

    var workbenchMotionSettings: WorkbenchMotionSettings {
        get { self[WorkbenchMotionSettingsKey.self] }
        set { self[WorkbenchMotionSettingsKey.self] = newValue }
    }
}

enum WorkbenchMotion {
    static func panel(_ reduceMotion: Bool, settings: WorkbenchMotionSettings) -> Animation? {
        guard settings.allowsPanelMotion(reduceMotion) else { return nil }
        switch settings.style {
        case .native:
            return .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.06)
        case .snappy:
            return .easeOut(duration: 0.16)
        case .gentle:
            return .spring(response: 0.46, dampingFraction: 0.92, blendDuration: 0.08)
        case .minimal:
            return nil
        }
    }

    static func selection(_ reduceMotion: Bool, settings: WorkbenchMotionSettings) -> Animation? {
        guard settings.allowsSelectionMotion(reduceMotion) else { return nil }
        switch settings.style {
        case .native:
            return .spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.04)
        case .snappy:
            return .easeOut(duration: 0.12)
        case .gentle:
            return .spring(response: 0.34, dampingFraction: 0.90, blendDuration: 0.06)
        case .minimal:
            return nil
        }
    }

    static func press(_ reduceMotion: Bool, settings: WorkbenchMotionSettings) -> Animation? {
        guard !reduceMotion, settings.style != .minimal else { return nil }
        switch settings.style {
        case .native:
            return .easeOut(duration: 0.10)
        case .snappy:
            return .easeOut(duration: 0.07)
        case .gentle:
            return .easeOut(duration: 0.14)
        case .minimal:
            return nil
        }
    }

    static func state(_ reduceMotion: Bool, settings: WorkbenchMotionSettings) -> Animation? {
        guard settings.allowsStateMotion(reduceMotion) else { return nil }
        switch settings.style {
        case .native:
            return .easeInOut(duration: 0.18)
        case .snappy:
            return .easeOut(duration: 0.11)
        case .gentle:
            return .easeInOut(duration: 0.26)
        case .minimal:
            return nil
        }
    }

    static func entrance(_ reduceMotion: Bool, settings: WorkbenchMotionSettings) -> Animation? {
        guard settings.allowsEntranceMotion(reduceMotion) else { return nil }
        switch settings.style {
        case .native:
            return .spring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.08)
        case .snappy:
            return .easeOut(duration: 0.16)
        case .gentle:
            return .spring(response: 0.50, dampingFraction: 0.94, blendDuration: 0.10)
        case .minimal:
            return nil
        }
    }

    static func panelTransition(edge: Edge, reduceMotion: Bool, settings: WorkbenchMotionSettings) -> AnyTransition {
        guard settings.allowsPanelMotion(reduceMotion) else { return .opacity }
        let removalScale = settings.style == .gentle ? 0.98 : 0.985
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .opacity.combined(with: .scale(scale: removalScale))
        )
    }

    static func featureTransition(edge: Edge, reduceMotion: Bool, settings: WorkbenchMotionSettings) -> AnyTransition {
        guard settings.allowsPanelMotion(reduceMotion) else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge).combined(with: .opacity)
        )
    }

    static func panelRemovalDelayNanoseconds(reduceMotion: Bool, settings: WorkbenchMotionSettings) -> UInt64 {
        guard settings.allowsPanelMotion(reduceMotion) else { return 0 }
        switch settings.style {
        case .native:
            return 320_000_000
        case .snappy:
            return 170_000_000
        case .gentle:
            return 430_000_000
        case .minimal:
            return 0
        }
    }

    static func quietTransition(_ reduceMotion: Bool, settings: WorkbenchMotionSettings) -> AnyTransition {
        guard settings.allowsStateMotion(reduceMotion) else { return .opacity }
        let yOffset: CGFloat = settings.style == .gentle ? 7 : 5
        let scale = settings.style == .snappy ? 0.99 : 0.985
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: scale, anchor: .top)).combined(with: .offset(y: yOffset)),
            removal: .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
        )
    }
}

enum ToolWindowSide: Equatable {
    case left
    case right
}

enum ToolWindowPanel: String, CaseIterable, Hashable, Identifiable {
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

enum WorkbenchAlert: Identifiable {
    case command(CommandConfirmation)
    case wirelessPairing(WirelessDebuggingConfirmation)

    var id: String {
        switch self {
        case let .command(confirmation):
            return "command-\(confirmation.id)"
        case let .wirelessPairing(confirmation):
            return "wireless-\(confirmation.id)"
        }
    }
}
