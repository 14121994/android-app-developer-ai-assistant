import SwiftUI

struct AssistantModelSetupPanel: View {
    @ObservedObject var viewModel: AgentViewModel
    @State private var openAIKeyDraft = ""
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        DisclosureGroup(isExpanded: animatedDisclosureBinding($isExpanded, reduceMotion: reduceMotion, settings: motionSettings)) {
            VStack(alignment: .leading, spacing: 9) {
                Text(viewModel.assistantModelSetupSummary)
                    .font(.caption2)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $viewModel.assistantPrefersTaskDroid) {
                    Label("Use TaskDroid", systemImage: "server.rack")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!viewModel.canEditAssistantModelMode)
                .namedControl("Use TaskDroid planner")

                VStack(alignment: .leading, spacing: 5) {
                    TextField("https://planner.example.com", text: $viewModel.assistantTaskDroidBaseURLText)
                        .workbenchTextField()
                        .font(.caption.monospaced())
                        .disabled(!viewModel.canEditAssistantModelMode)
                        .help(viewModel.assistantTaskDroidURLHelpText)
                        .namedControl("TaskDroid base URL", hint: viewModel.assistantTaskDroidURLHelpText)
                    Text(viewModel.assistantTaskDroidValidationMessage)
                        .font(.caption2)
                        .foregroundStyle(taskDroidValidationColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("360", text: $viewModel.assistantTaskDroidTimeoutText)
                        .workbenchTextField()
                        .font(.caption.monospacedDigit())
                        .frame(width: 86)
                        .disabled(!viewModel.canEditAssistantModelMode)
                        .help(viewModel.assistantTaskDroidTimeoutHelpText)
                        .namedControl("TaskDroid timeout", hint: viewModel.assistantTaskDroidTimeoutHelpText)
                    Text(viewModel.assistantTaskDroidTimeoutValidationMessage)
                        .font(.caption2)
                        .foregroundStyle(viewModel.assistantTaskDroidTimeoutSeconds == nil ? Palette.amber : Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    SecureField("OpenAI API key", text: $openAIKeyDraft)
                        .workbenchTextField()
                        .font(.caption.monospaced())
                        .disabled(!viewModel.canEditAssistantModelMode)
                        .namedControl("OpenAI API key")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            saveOpenAIKeyButton
                            clearOpenAIKeyButton
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            saveOpenAIKeyButton
                            clearOpenAIKeyButton
                        }
                    }
                    Text(viewModel.assistantCredentialStatus)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.assistantCredentialStatus.contains("not configured") ? Palette.amber : Palette.teal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Model Setup", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
    }

    private var saveOpenAIKeyButton: some View {
        Button(action: saveOpenAIKey) {
            Label("Save Key", systemImage: "key")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.canEditAssistantModelMode)
        .namedControl("Save OpenAI key")
    }

    private var clearOpenAIKeyButton: some View {
        Button(action: viewModel.clearAssistantOpenAIAPIKey) {
            Label("Clear Key", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(!viewModel.canEditAssistantModelMode)
        .namedControl("Clear OpenAI key")
    }

    private var taskDroidValidationColor: Color {
        viewModel.assistantTaskDroidValidationMessage.contains("valid") ? Palette.amber : Palette.muted
    }

    private func saveOpenAIKey() {
        viewModel.saveAssistantOpenAIAPIKey(openAIKeyDraft)
        openAIKeyDraft = ""
    }
}
