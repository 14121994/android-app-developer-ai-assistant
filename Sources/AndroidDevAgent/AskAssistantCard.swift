import AndroidDevAgentCore
import SwiftUI

struct AskAssistantCard: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var isAssistantResponseExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    promptContextLabel
                    Spacer(minLength: 8)
                    promptMetricsLabel
                }

                VStack(alignment: .leading, spacing: 4) {
                    promptContextLabel
                    promptMetricsLabel
                }
            }

            modelRouteSurface

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.prompt)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.blue)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104)
                    .disabled(!viewModel.canEditAssistantPrompt)
                    .padding(8)
                    .background {
                        SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .thin, textureOpacity: 0.004)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.70)))
                    .help(viewModel.assistantPromptHelpText)
                    .namedControl("Agent prompt")

                if viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Describe the Android task, crash, UI change, test gap, or release check.")
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var promptContextLabel: some View {
        Label(viewModel.promptContextSummary, systemImage: viewModel.planNeedsRefresh ? "exclamationmark.triangle" : "scope")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(viewModel.planNeedsRefresh ? Palette.amber : Palette.muted)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var promptMetricsLabel: some View {
        Text(viewModel.promptMetricsSummary)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    private var modelRouteSurface: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    assistantRouteLabel
                    Spacer(minLength: 8)
                    assistantModePicker
                }

                VStack(alignment: .leading, spacing: 7) {
                    assistantRouteLabel
                    assistantModePicker
                }
            }

            AssistantModelBindingDropdown(mode: viewModel.assistantModelMode)
                .namedControl("Bound assistant models", hint: "Shows the models bound to the selected Ask mode. The model rows are read-only.")

            Divider()

            assistantPrivacySurface

            Text(viewModel.taskDroidRouteSummary)
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            AssistantModelSetupPanel(viewModel: viewModel)

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
        .background {
            SurfaceFill(cornerRadius: 8, tint: Palette.noticeBackground, material: .ultraThin, textureOpacity: 0.006)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.64)))
    }

    private var assistantPrivacySurface: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    Toggle(isOn: $viewModel.assistantAllowsProviderSharing) {
                        Label(viewModel.assistantPrivacySummary, systemImage: viewModel.assistantAllowsProviderSharing ? "network" : "lock.shield")
                    }
                    .toggleStyle(.switch)
                    .disabled(!viewModel.canEditAssistantPrivacyConsent)
                    .help(viewModel.assistantProviderSharingHelpText)
                    .namedControl("Assistant provider sharing consent", hint: viewModel.assistantProviderSharingHelpText)

                    Spacer(minLength: 8)

                    Label(viewModel.assistantProviderAccountSummary, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $viewModel.assistantAllowsProviderSharing) {
                        Label(viewModel.assistantPrivacySummary, systemImage: viewModel.assistantAllowsProviderSharing ? "network" : "lock.shield")
                    }
                    .toggleStyle(.switch)
                    .disabled(!viewModel.canEditAssistantPrivacyConsent)
                    .help(viewModel.assistantProviderSharingHelpText)
                    .namedControl("Assistant provider sharing consent", hint: viewModel.assistantProviderSharingHelpText)

                    Label(viewModel.assistantProviderAccountSummary, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(viewModel.assistantPrivacyDisclosure)
                .font(.caption2)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.assistantPayloadPrivacySummary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(viewModel.assistantAllowsProviderSharing ? Palette.amber : Palette.teal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var assistantRouteLabel: some View {
        Label(viewModel.assistantModelRouteSummary, systemImage: viewModel.isAssistantThinking ? "cpu.fill" : "cpu")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(viewModel.isAssistantThinking ? Palette.amber : Palette.ink)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var assistantModePicker: some View {
        Picker("AI mode", selection: $viewModel.assistantModelMode) {
            ForEach(AssistantModelMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(minWidth: 190, idealWidth: 230, maxWidth: 250)
        .disabled(!viewModel.canEditAssistantModelMode)
        .help(viewModel.assistantModelModeHelpText)
        .namedControl("Assistant model mode", hint: viewModel.assistantModelModeHelpText)
    }

    @ViewBuilder
    private var assistantResponseSurface: some View {
        let response = viewModel.assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = viewModel.assistantActionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !response.isEmpty || !actions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                assistantResponseHeader(hasResponse: !response.isEmpty, hasActions: !actions.isEmpty)

                if !response.isEmpty {
                    if needsAssistantResponseExpansion(response) {
                        Button {
                            isAssistantResponseExpanded.toggle()
                        } label: {
                            Label(isAssistantResponseExpanded ? "Collapse Response" : "Show Full Response", systemImage: isAssistantResponseExpanded ? "chevron.up.circle" : "chevron.down.circle")
                        }
                        .buttonStyle(ReadableBorderedButtonStyle())
                        .controlSize(.small)
                        .help(isAssistantResponseExpanded ? "Collapse the assistant response to a concise preview." : "Show the full assistant response text in this panel.")
                        .namedControl(isAssistantResponseExpanded ? "Collapse assistant response" : "Show full assistant response")
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        Text(displayedAssistantResponse(response))
                            .font(.caption)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 92, maxHeight: 180)
                    .background {
                        SurfaceFill(cornerRadius: 8, tint: Palette.surface, material: .thin, textureOpacity: 0.006)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border.opacity(0.66)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isAssistantResponseExpanded ? "Full assistant response" : "Assistant response preview")
                    .accessibilityValue(Text(accessibilityLongTextSummary(response)))
                    .accessibilityHint(isAssistantResponseExpanded ? "Shows the full project-specific answer generated from the current prompt." : "Shows a concise preview. Use Show Full Response to expand the full text.")
                    .accessibilityIdentifier("Assistant response")
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
            .lineLimit(1)
            .minimumScaleFactor(0.82)
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
        .controlSize(.small)
        .help("Open assistant response actions.")
        .namedControl("Assistant response actions", hint: "Shows copy, export, and open actions for the assistant response.")
    }

    private var assistantActedBadge: some View {
        Label("Acted", systemImage: "bolt.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.teal)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var assistantResponseFeedbackBadge: some View {
        Text(viewModel.assistantResponseFeedback)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.teal)
            .lineLimit(1)
            .truncationMode(.middle)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.teal.opacity(0.12)))
    }

    private var promptToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                promptDraftActions
                Spacer(minLength: 8)
                askAssistantButton
            }

            VStack(alignment: .leading, spacing: 8) {
                promptDraftActions
                askAssistantButton
            }
        }
    }

    private var promptDraftActions: some View {
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
            .disabled(!viewModel.canRestorePreviousPromptDraft)
            .help(viewModel.canRestorePreviousPromptDraft ? "Restore the previous prompt draft after a preset, history restore, or clear." : "No previous prompt draft is available.")
            .namedControl("Restore previous prompt draft", hint: "Swaps the prompt with the previous draft.")
        }
    }

    private var askAssistantButton: some View {
        Button(action: { viewModel.askAssistant() }) {
            Label(viewModel.isAssistantThinking ? "Thinking" : (viewModel.planNeedsRefresh ? "Refresh Response" : "Ask"), systemImage: viewModel.isAssistantThinking ? "cpu" : "paperplane")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableProminentButtonStyle(color: Palette.teal))
        .disabled(!viewModel.canAskAssistant)
        .help(viewModel.askAssistantHelpText)
        .keyboardShortcut(.return, modifiers: [.command])
        .namedControl("Ask the assistant")
    }

    private func needsAssistantResponseExpansion(_ response: String) -> Bool {
        response.count > 900 || response.split(separator: "\n", omittingEmptySubsequences: false).count > 10
    }

    private func displayedAssistantResponse(_ response: String) -> String {
        guard needsAssistantResponseExpansion(response), !isAssistantResponseExpanded else { return response }
        let normalizedLines = response
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(8)
            .map(String.init)
            .joined(separator: "\n")
        if normalizedLines.count > 900 {
            return "\(String(normalizedLines.prefix(900)))...\n\nFull response available from Show Full Response, Copy Response, or Export Response."
        }
        return "\(normalizedLines)\n\nFull response available from Show Full Response, Copy Response, or Export Response."
    }
}
