import SwiftUI

struct LaunchReadinessSettingsSection: View {
    @AppStorage(AndroidDevAgentLaunchReadiness.telemetryModeKey) private var telemetryModeRaw = AndroidDevAgentTelemetryMode.off.rawValue
    @AppStorage(AndroidDevAgentLaunchReadiness.onboardingCompletedKey) private var onboardingCompleted = false
    @AppStorage(AndroidDevAgentLaunchReadiness.licenseStateKey) private var licenseState = ""
    @AppStorage(AndroidDevAgentLaunchReadiness.licenseMaskedKey) private var licenseMasked = ""
    @AppStorage(AndroidDevAgentLaunchReadiness.supportUploadConsentKey) private var supportUploadConsent = false
    @AppStorage(AndroidDevAgentLaunchReadiness.crashUploadConsentKey) private var crashUploadConsent = false
    @State private var licenseKey = ""
    @State private var accountEmail = ""
    @State private var transferEmail = ""
    @State private var licenseMessage = AndroidDevAgentLaunchReadiness.licenseSummary
    @State private var isLicenseRequestRunning = false

    var body: some View {
        AgentSettingsSection(title: "Launch", symbol: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Telemetry", selection: $telemetryModeRaw) {
                    ForEach(AndroidDevAgentTelemetryMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: telemetryModeRaw) { _, newValue in
                    AndroidDevAgentLaunchReadiness.recordPrivacyAudit("telemetry_mode_changed", metadata: ["mode": newValue])
                }
                .namedControl("Telemetry mode")

                DiagnosticRowView(row: DiagnosticRow(
                    title: "Telemetry",
                    detail: AndroidDevAgentLaunchReadiness.telemetrySummary,
                    symbol: telemetryMode.symbol,
                    severity: AndroidDevAgentLaunchReadiness.telemetrySeverity
                ))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        supportUploadConsentToggle
                        crashUploadConsentToggle
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        supportUploadConsentToggle
                        crashUploadConsentToggle
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            activationKeyField
                            accountEmailField
                            activateButton
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            activationKeyField
                            accountEmailField
                            activateButton
                        }
                    }
                    DiagnosticRowView(row: DiagnosticRow(
                        title: "License",
                        detail: licenseDetail,
                        symbol: "key.horizontal",
                        severity: AndroidDevAgentLaunchReadiness.licenseSeverity
                    ))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            refreshLicenseButton
                            recoverAccountButton
                            transferEmailField
                            transferLicenseButton
                            if !licenseState.isEmpty {
                                deactivateLicenseButton
                            }
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                refreshLicenseButton
                                recoverAccountButton
                                if !licenseState.isEmpty {
                                    deactivateLicenseButton
                                }
                            }
                            HStack(spacing: 8) {
                                transferEmailField
                                transferLicenseButton
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        onboardingButton
                        logsButton
                        supportButton
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        onboardingButton
                        HStack(spacing: 8) {
                            logsButton
                            supportButton
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private var telemetryMode: AndroidDevAgentTelemetryMode {
        AndroidDevAgentTelemetryMode(rawValue: telemetryModeRaw) ?? .off
    }

    private var licenseDetail: String {
        if isLicenseRequestRunning {
            return "Contacting license backend..."
        }
        if !licenseMessage.isEmpty {
            return licenseMessage
        }
        if !licenseMasked.isEmpty {
            return "Stored entitlement \(licenseMasked)."
        }
        return AndroidDevAgentLaunchReadiness.licenseSummary
    }

    private var activationKeyField: some View {
        TextField("ADA-XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
            .textFieldStyle(.plain)
            .font(.caption.monospaced())
            .workbenchTextField()
            .namedControl("License activation key")
    }

    private var accountEmailField: some View {
        TextField("account@example.com", text: $accountEmail)
            .textFieldStyle(.plain)
            .font(.caption)
            .workbenchTextField()
            .namedControl("License account email")
    }

    private var transferEmailField: some View {
        TextField("new-owner@example.com", text: $transferEmail)
            .textFieldStyle(.plain)
            .font(.caption)
            .workbenchTextField()
            .namedControl("License transfer account")
    }

    private var supportUploadConsentToggle: some View {
        Toggle("Support Upload", isOn: $supportUploadConsent)
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: supportUploadConsent) { _, newValue in
                AndroidDevAgentLaunchReadiness.setSupportUploadConsent(newValue)
            }
            .namedControl("Support upload consent")
    }

    private var crashUploadConsentToggle: some View {
        Toggle("Crash Upload", isOn: $crashUploadConsent)
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: crashUploadConsent) { _, newValue in
                AndroidDevAgentLaunchReadiness.setCrashUploadConsent(newValue)
            }
            .namedControl("Crash upload consent")
    }

    private var activateButton: some View {
        Button(action: activateLicense) {
            Label(isLicenseRequestRunning ? "Working" : "Activate", systemImage: "key")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(isLicenseRequestRunning || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .namedControl("Activate license")
    }

    private var refreshLicenseButton: some View {
        Button(action: refreshLicense) {
            Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(isLicenseRequestRunning)
        .namedControl("Refresh license")
    }

    private var recoverAccountButton: some View {
        Button(action: recoverAccount) {
            Label("Recover", systemImage: "envelope.badge.shield.half.filled")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(isLicenseRequestRunning || accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .namedControl("Recover license account")
    }

    private var transferLicenseButton: some View {
        Button(action: transferLicense) {
            Label("Transfer", systemImage: "arrow.left.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(isLicenseRequestRunning || transferEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .namedControl("Transfer license")
    }

    private var deactivateLicenseButton: some View {
        Button(action: deactivateLicense) {
            Label("Remove", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(isLicenseRequestRunning)
        .namedControl("Remove local license")
    }

    private var onboardingButton: some View {
        Button(action: toggleOnboarding) {
            Label(onboardingCompleted ? "Show Onboarding" : "Complete Onboarding", systemImage: "list.bullet.clipboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .namedControl("Toggle onboarding")
    }

    private var logsButton: some View {
        Button(action: AndroidDevAgentLaunchReadiness.openLogsDirectory) {
            Label("Logs", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .namedControl("Open launch logs")
    }

    private var supportButton: some View {
        Button(action: AndroidDevAgentLaunchReadiness.openSupportDirectory) {
            Label("Support", systemImage: "folder.badge.gearshape")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .namedControl("Open support folder")
    }

    private func activateLicense() {
        performLicenseRequest {
            await AndroidDevAgentLaunchReadiness.activateLicense(licenseKey, accountEmail: accountEmail)
        } completion: { message in
            if message.contains("active") || message.contains("activated") {
                licenseKey = ""
            }
        }
    }

    private func refreshLicense() {
        performLicenseRequest {
            await AndroidDevAgentLaunchReadiness.refreshLicenseEntitlement()
        }
    }

    private func recoverAccount() {
        performLicenseRequest {
            await AndroidDevAgentLaunchReadiness.recoverLicenseAccount(accountEmail)
        }
    }

    private func transferLicense() {
        performLicenseRequest {
            await AndroidDevAgentLaunchReadiness.transferLicense(to: transferEmail)
        } completion: { message in
            if message.localizedCaseInsensitiveContains("transfer") {
                transferEmail = ""
            }
        }
    }

    private func deactivateLicense() {
        AndroidDevAgentLaunchReadiness.deactivateLicense()
        licenseMessage = AndroidDevAgentLaunchReadiness.licenseSummary
    }

    private func toggleOnboarding() {
        if onboardingCompleted {
            AndroidDevAgentLaunchReadiness.resetOnboarding()
        } else {
            AndroidDevAgentLaunchReadiness.markOnboardingCompleted()
        }
    }

    private func performLicenseRequest(
        operation: @escaping () async -> String,
        completion: @escaping (String) -> Void = { _ in }
    ) {
        guard !isLicenseRequestRunning else { return }
        isLicenseRequestRunning = true
        Task {
            let message = await operation()
            await MainActor.run {
                licenseMessage = message
                isLicenseRequestRunning = false
                completion(message)
            }
        }
    }
}

struct LaunchReadinessDiagnosticsCard: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        SectionHeader(title: "Launch Readiness", symbol: "checkmark.shield")
                        Spacer(minLength: 8)
                        supportBundleActions
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        SectionHeader(title: "Launch Readiness", symbol: "checkmark.shield")
                        supportBundleActions
                    }
                }

                ForEach(viewModel.launchReadinessRows) { row in
                    DiagnosticRowView(row: row)
                }
            }
        }
    }

    private var supportBundleActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                supportBundleButton
                uploadSupportBundleButton
                openSupportBundleButton
            }
            VStack(alignment: .leading, spacing: 6) {
                supportBundleButton
                uploadSupportBundleButton
                openSupportBundleButton
            }
        }
    }

    private var supportBundleButton: some View {
        Button(action: viewModel.createSupportBundle) {
            Label("Support Bundle", systemImage: "shippingbox.and.arrow.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .help("Export support diagnostics with launch readiness, crash, telemetry, license, release notes, project, device, and console context.")
        .namedControl("Create support bundle")
    }

    private var uploadSupportBundleButton: some View {
        Button(action: viewModel.uploadSupportBundle) {
            Label(viewModel.supportBundleUploadActionTitle, systemImage: viewModel.supportBundleUploadActionSymbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(!viewModel.canUploadSupportBundle)
        .help(viewModel.supportBundleUploadHelpText)
        .namedControl("Upload support bundle")
    }

    private var openSupportBundleButton: some View {
        Button(action: viewModel.openSupportBundle) {
            Label("Open Bundle", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .controlSize(.small)
        .disabled(!viewModel.hasSupportBundleFile)
        .help(viewModel.supportBundleAvailabilityMessage.isEmpty ? "Open the latest support bundle." : viewModel.supportBundleAvailabilityMessage)
        .namedControl("Open support bundle")
    }
}

struct LaunchReadinessOnboardingCard: View {
    @Binding var visiblePanels: Set<ToolWindowPanel>
    @AppStorage(AndroidDevAgentLaunchReadiness.onboardingCompletedKey) private var onboardingCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workbenchMotionSettings) private var motionSettings

    var body: some View {
        if !onboardingCompleted {
            ContentCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Launch Setup", symbol: "list.bullet.clipboard")
                    HStack(alignment: .top, spacing: 8) {
                        onboardingStep(title: "Workspace", symbol: "folder", panels: [.workspace])
                        onboardingStep(title: "Ask", symbol: "text.bubble", panels: [.askAssistant])
                        onboardingStep(title: "Diagnostics", symbol: "stethoscope", panels: [.session])
                    }
                    Button(action: completeOnboarding) {
                        Label("Done", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ReadableProminentButtonStyle(color: Palette.teal))
                    .controlSize(.small)
                    .namedControl("Complete launch onboarding")
                }
            }
            .frame(maxWidth: 460)
            .motionEntrance()
        }
    }

    private func onboardingStep(title: String, symbol: String, panels: Set<ToolWindowPanel>) -> some View {
        Button {
            withAnimation(WorkbenchMotion.panel(reduceMotion, settings: motionSettings)) {
                visiblePanels.formUnion(panels)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(ReadableBorderedButtonStyle())
        .namedControl("Onboarding \(title)")
    }

    private func completeOnboarding() {
        AndroidDevAgentLaunchReadiness.markOnboardingCompleted()
    }
}
