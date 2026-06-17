import SwiftUI

struct AgentSettingsPopover: View {
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
    @Environment(\.workbenchThemeSettings) private var themeSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(themeSettings.accentColor)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text("Agent Settings")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(themeSettings.accentTheme.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(themeSettings.accentColor)
                        .lineLimit(1)
                    Text(currentMotionStyle.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }

                AgentSettingsSection(title: "Appearance", symbol: "circle.lefthalf.filled") {
                    Picker("Appearance", selection: $colorSchemePreferenceRaw) {
                        ForEach(WorkbenchColorSchemePreference.allCases) { preference in
                            Text(preference.title).tag(preference.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .namedControl("Theme appearance")
                }

                AgentSettingsSection(title: "Accent", symbol: "paintpalette") {
                    LazyVGrid(columns: accentGridColumns, spacing: 8) {
                        ForEach(WorkbenchAccentTheme.allCases) { theme in
                            AgentAccentThemeButton(
                                theme: theme,
                                isSelected: accentThemeRaw == theme.rawValue
                            ) {
                                accentThemeRaw = theme.rawValue
                            }
                        }
                    }
                }

                AgentSettingsSection(title: "Surface", symbol: "square.stack.3d.up") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            surfaceStyleButtons
                        }

                        VStack(spacing: 8) {
                            surfaceStyleButtons
                        }
                    }

                    Toggle(isOn: $textureEnabled) {
                        Label("Subtle texture", systemImage: "circle.grid.cross")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(surfaceStyleRaw == WorkbenchSurfaceStyle.solid.rawValue)
                    .namedControl("Toggle subtle texture", hint: "Controls fine texture on workbench surfaces.")
                }

                AgentSettingsSection(title: "Motion", symbol: "sparkles") {
                    LazyVGrid(columns: motionGridColumns, spacing: 8) {
                        ForEach(WorkbenchMotionStyle.allCases) { style in
                            AgentMotionStyleButton(
                                style: style,
                                isSelected: motionStyleRaw == style.rawValue
                            ) {
                                motionStyleRaw = style.rawValue
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Toggle(isOn: $panelMotionEnabled) {
                            Label("Panel transitions", systemImage: "sidebar.leading")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .namedControl("Toggle panel transitions")

                        Toggle(isOn: $selectionMotionEnabled) {
                            Label("Selection glide", systemImage: "cursorarrow")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .namedControl("Toggle selection glide")

                        Toggle(isOn: $stateMotionEnabled) {
                            Label("State feedback", systemImage: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .namedControl("Toggle state feedback motion")

                        Toggle(isOn: $statusPulseEnabled) {
                            Label("Running pulse", systemImage: "waveform.path.ecg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .namedControl("Toggle command running pulse")

                        Toggle(isOn: $entranceMotionEnabled) {
                            Label("Empty-state entrance", systemImage: "rectangle.on.rectangle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .namedControl("Toggle empty-state entrance motion")
                    }
                    .disabled(currentMotionStyle == .minimal)
                    .opacity(currentMotionStyle == .minimal ? 0.56 : 1)
                }

                LaunchReadinessSettingsSection()

                HStack {
                    Spacer(minLength: 0)
                    Button(action: resetAgentSettings) {
                        Label("Reset Settings", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(ReadableBorderedButtonStyle())
                    .controlSize(.small)
                    .namedControl("Reset agent settings")
                }
            }
            .padding(16)
        }
        .frame(width: 380)
        .frame(maxHeight: 640)
        .background {
            PaneBackdrop(role: .inspector)
        }
    }

    private var accentGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 8)]
    }

    private var motionGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 8)]
    }

    private var currentMotionStyle: WorkbenchMotionStyle {
        WorkbenchMotionStyle(rawValue: motionStyleRaw) ?? .native
    }

    @ViewBuilder
    private var surfaceStyleButtons: some View {
        ForEach(WorkbenchSurfaceStyle.allCases) { style in
            AgentSurfaceStyleButton(
                style: style,
                isSelected: surfaceStyleRaw == style.rawValue
            ) {
                surfaceStyleRaw = style.rawValue
                if style == .solid {
                    textureEnabled = false
                }
            }
        }
    }

    private func resetAgentSettings() {
        colorSchemePreferenceRaw = WorkbenchColorSchemePreference.system.rawValue
        accentThemeRaw = WorkbenchAccentTheme.pacific.rawValue
        surfaceStyleRaw = WorkbenchSurfaceStyle.balanced.rawValue
        textureEnabled = true
        motionStyleRaw = WorkbenchMotionStyle.native.rawValue
        panelMotionEnabled = true
        selectionMotionEnabled = true
        stateMotionEnabled = true
        statusPulseEnabled = true
        entranceMotionEnabled = true
    }
}

struct AgentSettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.groupBackground, material: .ultraThin, textureOpacity: 0.004)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.featureBorder))
    }
}

struct AgentAccentThemeButton: View {
    let theme: WorkbenchAccentTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AccentThemeSwatch(theme: theme)
                Text(theme.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? theme.accentColor : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : theme.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accentColor : Palette.muted)
                    .frame(width: 16)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background {
                SurfaceFill(
                    cornerRadius: 8,
                    tint: isSelected ? theme.accentColor.opacity(0.12) : Palette.controlBackground,
                    material: .ultraThin,
                    textureOpacity: 0.004
                )
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? theme.accentColor.opacity(0.48) : Palette.controlBorder))
        }
        .buttonStyle(.plain)
        .help(theme.title)
        .namedControl("Set \(theme.title) accent theme")
    }
}

private struct AccentThemeSwatch: View {
    let theme: WorkbenchAccentTheme

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.companionColor)
                .offset(x: 5, y: 0)
            Circle()
                .fill(theme.accentColor)
                .offset(x: -5, y: 0)
        }
        .frame(width: 24, height: 18)
        .accessibilityHidden(true)
    }
}

struct AgentSurfaceStyleButton: View {
    let style: WorkbenchSurfaceStyle
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.workbenchThemeSettings) private var themeSettings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : style.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? themeSettings.accentColor : Palette.muted)
                    .frame(width: 16)
                Text(style.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? themeSettings.accentColor : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                SurfaceFill(
                    cornerRadius: 8,
                    tint: isSelected ? themeSettings.accentColor.opacity(0.12) : Palette.controlBackground,
                    material: .ultraThin,
                    textureOpacity: 0.004
                )
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? themeSettings.accentColor.opacity(0.48) : Palette.controlBorder))
        }
        .buttonStyle(.plain)
        .namedControl("Set \(style.title) surface style")
    }
}

struct AgentMotionStyleButton: View {
    let style: WorkbenchMotionStyle
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.workbenchThemeSettings) private var themeSettings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : style.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? themeSettings.accentColor : Palette.muted)
                    .frame(width: 16)
                Text(style.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? themeSettings.accentColor : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background {
                SurfaceFill(
                    cornerRadius: 8,
                    tint: isSelected ? themeSettings.accentColor.opacity(0.12) : Palette.controlBackground,
                    material: .ultraThin,
                    textureOpacity: 0.004
                )
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? themeSettings.accentColor.opacity(0.48) : Palette.controlBorder))
        }
        .buttonStyle(.plain)
        .help(style.title)
        .namedControl("Set \(style.title) motion style")
    }
}
