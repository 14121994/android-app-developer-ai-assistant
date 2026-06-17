import AppKit
import CryptoKit
import Darwin
import Foundation

enum AndroidDevAgentTelemetryMode: String, CaseIterable, Identifiable {
    case off
    case diagnosticsOnly
    case analytics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .diagnosticsOnly: return "Diagnostics"
        case .analytics: return "Analytics"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "hand.raised"
        case .diagnosticsOnly: return "doc.text.magnifyingglass"
        case .analytics: return "chart.line.uptrend.xyaxis"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "No telemetry events are collected."
        case .diagnosticsOnly:
            return "Local diagnostic events are kept on this Mac and included only when you export a support bundle."
        case .analytics:
            return "Product telemetry is allowed only when a signed build provides a telemetry endpoint."
        }
    }
}

enum AndroidDevAgentCommercialLicenseState: String, Codable, Equatable {
    case trialActive
    case trialExpired
    case subscriptionActive
    case subscriptionGrace
    case subscriptionExpired
    case perpetualActive
    case revoked
    case transferPending
    case unlicensed

    var grantsAccess: Bool {
        switch self {
        case .trialActive, .subscriptionActive, .subscriptionGrace, .perpetualActive:
            return true
        case .trialExpired, .subscriptionExpired, .revoked, .transferPending, .unlicensed:
            return false
        }
    }
}

struct AndroidDevAgentCommercialLicenseSnapshot: Codable, Equatable {
    var state: AndroidDevAgentCommercialLicenseState
    var entitlementID: String
    var planName: String
    var accountEmail: String
    var maskedLicenseKey: String
    var deviceID: String
    var activatedAt: Date?
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var subscriptionRenewsAt: Date?
    var expiresAt: Date?
    var offlineGraceUntil: Date?
    var lastVerifiedAt: Date?
    var lastServerMessage: String

    var hasBackendEntitlement: Bool {
        !entitlementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func evolved(now: Date) -> AndroidDevAgentCommercialLicenseSnapshot {
        var next = self
        switch state {
        case .trialActive:
            if let trialEndsAt, now >= trialEndsAt {
                next.state = .trialExpired
                next.lastServerMessage = "Trial expired."
            }
        case .subscriptionActive:
            if let expiresAt, now >= expiresAt {
                if let offlineGraceUntil, now < offlineGraceUntil {
                    next.state = .subscriptionGrace
                    next.lastServerMessage = "Offline grace active after subscription verification lapsed."
                } else {
                    next.state = .subscriptionExpired
                    next.lastServerMessage = "Subscription expired."
                }
            }
        case .subscriptionGrace:
            if let offlineGraceUntil, now >= offlineGraceUntil {
                next.state = .subscriptionExpired
                next.lastServerMessage = "Offline grace expired."
            }
        case .trialExpired, .subscriptionExpired, .perpetualActive, .revoked, .transferPending, .unlicensed:
            break
        }
        return next
    }
}

struct AndroidDevAgentLicenseBackendEndpoints: Equatable {
    let activation: URL
    let refresh: URL
    let recovery: URL
    let transfer: URL
}

protocol AndroidDevAgentLicenseBackendTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct AndroidDevAgentURLSessionLicenseBackendTransport: AndroidDevAgentLicenseBackendTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AndroidDevAgentLicenseBackendError.nonHTTPResponse
        }
        return (data, httpResponse)
    }
}

enum AndroidDevAgentLicenseBackendError: Error, LocalizedError {
    case nonHTTPResponse
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            return "License backend returned a non-HTTP response."
        case let .backend(message):
            return message
        }
    }
}

struct AndroidDevAgentLicenseActivationRequest: Codable {
    let licenseKey: String
    let accountEmail: String
    let deviceID: String
    let appVersion: String
    let buildNumber: String
    let bundleID: String
    let platform: String
}

struct AndroidDevAgentLicenseRefreshRequest: Codable {
    let entitlementID: String
    let accountEmail: String
    let deviceID: String
    let appVersion: String
    let buildNumber: String
}

struct AndroidDevAgentLicenseRecoveryRequest: Codable {
    let accountEmail: String
    let deviceID: String
    let appVersion: String
}

struct AndroidDevAgentLicenseTransferRequest: Codable {
    let entitlementID: String
    let sourceAccountEmail: String
    let targetAccountEmail: String
    let deviceID: String
    let appVersion: String
}

struct AndroidDevAgentLicenseBackendResponse: Codable {
    let status: String?
    let entitlementID: String?
    let planName: String?
    let accountEmail: String?
    let maskedLicenseKey: String?
    let trialEndsAt: Date?
    let subscriptionRenewsAt: Date?
    let expiresAt: Date?
    let offlineGraceUntil: Date?
    let serverTime: Date?
    let message: String?
}

struct AndroidDevAgentDiagnosticVersionStamp: Codable, Equatable {
    let schemaVersion: String
    let appVersion: String
    let buildNumber: String
    let bundleID: String
    let macOSVersion: String
    let processName: String
    let architecture: String
    let issueID: String
    let createdAt: String

    var displayText: String {
        """
        Diagnostic Schema: \(schemaVersion)
        App Version: \(appVersion)
        Build: \(buildNumber)
        Bundle ID: \(bundleID)
        macOS: \(macOSVersion)
        Process: \(processName)
        Architecture: \(architecture)
        Issue ID: \(issueID)
        Created: \(createdAt)
        """
    }
}

protocol AndroidDevAgentSupportBackendTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct AndroidDevAgentURLSessionSupportBackendTransport: AndroidDevAgentSupportBackendTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AndroidDevAgentSupportBackendError.nonHTTPResponse
        }
        return (data, httpResponse)
    }
}

enum AndroidDevAgentSupportBackendError: Error, LocalizedError {
    case nonHTTPResponse
    case backend(String)
    case missingBundle

    var errorDescription: String? {
        switch self {
        case .nonHTTPResponse:
            return "Support backend returned a non-HTTP response."
        case let .backend(message):
            return message
        case .missingBundle:
            return "Support bundle is missing or no longer readable."
        }
    }
}

struct AndroidDevAgentSupportUploadFile: Codable, Equatable {
    let path: String
    let sha256: String
    let byteCount: Int
    let redacted: Bool
    let truncated: Bool
    let contentBase64: String
}

struct AndroidDevAgentSupportUploadRequest: Codable, Equatable {
    let issueID: String
    let diagnosticVersion: AndroidDevAgentDiagnosticVersionStamp
    let appVersion: String
    let buildNumber: String
    let bundleID: String
    let createdAt: String
    let symbolication: String
    let files: [AndroidDevAgentSupportUploadFile]
}

struct AndroidDevAgentSupportUploadResponse: Codable, Equatable {
    let issueID: String?
    let status: String?
    let message: String?
}

public enum AndroidDevAgentLaunchReadiness {
    public static let telemetryModeKey = "AndroidDevAgentTelemetryMode"
    public static let onboardingCompletedKey = "AndroidDevAgentOnboardingCompleted"
    public static let licenseStateKey = "AndroidDevAgentLicenseState"
    public static let licenseMaskedKey = "AndroidDevAgentLicenseMasked"
    public static let licenseActivatedAtKey = "AndroidDevAgentLicenseActivatedAt"
    public static let licenseSnapshotKey = "AndroidDevAgentLicenseSnapshot"
    public static let licenseDeviceIDKey = "AndroidDevAgentLicenseDeviceID"
    public static let latestSupportBundlePathKey = "AndroidDevAgentLatestSupportBundlePath"
    public static let latestSupportIssueIDKey = "AndroidDevAgentLatestSupportIssueID"
    public static let latestSupportUploadStatusKey = "AndroidDevAgentLatestSupportUploadStatus"
    public static let releaseNotesPathKey = "AndroidDevAgentReleaseNotesPath"
    public static let crashUploadConsentKey = "AndroidDevAgentCrashUploadConsent"
    public static let supportUploadConsentKey = "AndroidDevAgentSupportUploadConsent"

    private static let logsFolderName = "AndroidDevAgent"
    private static let telemetryFileName = "telemetry-events.jsonl"
    private static let privacyAuditFileName = "privacy-audit.jsonl"
    private static let crashFileName = "latest-crash.log"
    private static let launchFileName = "launch.log"
    private static let issueFileName = "issue-id.txt"
    private static let diagnosticVersionFileName = "diagnostic-version.txt"
    private static let redactionSummaryFileName = "redaction-summary.txt"
    private static let symbolicationFileName = "crash-symbolication.txt"
    private static let diagnosticSchemaVersion = "1.0"
    private static let maxSupportUploadFileBytes = 512_000
    private static let maxSupportUploadBytes = 5_000_000
    private static var licenseBackendTransport: AndroidDevAgentLicenseBackendTransport = AndroidDevAgentURLSessionLicenseBackendTransport()
    private static var licenseBackendEndpointOverride: AndroidDevAgentLicenseBackendEndpoints?
    private static var supportBackendTransport: AndroidDevAgentSupportBackendTransport = AndroidDevAgentURLSessionSupportBackendTransport()
    private static var supportUploadEndpointOverride: URL?

    public static func installCrashReporting() {
        do {
            try prepareSupportDirectories()
            configureCrashSignalPath()
            NSSetUncaughtExceptionHandler(androidDevAgentUncaughtExceptionHandler)
            [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP].forEach { signalNumber in
                Darwin.signal(signalNumber, androidDevAgentSignalHandler)
            }
            appendLaunchLog("Crash reporting installed. Reports stay local until the user exports a support bundle.")
        } catch {
            NSLog("Android Dev Agent crash reporting setup failed: \(error.localizedDescription)")
        }
    }

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let preferred = base.appendingPathComponent(logsFolderName, isDirectory: true)
        return writableDirectory(preferred: preferred, fallbackRelativePath: "\(logsFolderName)/Support")
    }

    public static var logsDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let preferred = base.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent(logsFolderName, isDirectory: true)
        return writableDirectory(preferred: preferred, fallbackRelativePath: "\(logsFolderName)/Logs")
    }

    public static var telemetryLogURL: URL {
        logsDirectory.appendingPathComponent(telemetryFileName)
    }

    public static var privacyAuditLogURL: URL {
        logsDirectory.appendingPathComponent(privacyAuditFileName)
    }

    public static var latestCrashReportURL: URL {
        logsDirectory.appendingPathComponent(crashFileName)
    }

    public static var launchLogURL: URL {
        logsDirectory.appendingPathComponent(launchFileName)
    }

    public static var telemetryModeRaw: String {
        UserDefaults.standard.string(forKey: telemetryModeKey) ?? AndroidDevAgentTelemetryMode.off.rawValue
    }

    static var telemetryMode: AndroidDevAgentTelemetryMode {
        AndroidDevAgentTelemetryMode(rawValue: telemetryModeRaw) ?? .off
    }

    public static var telemetrySummary: String {
        let mode = telemetryMode
        if mode == .analytics && telemetryEndpoint == nil {
            return "Analytics allowed by setting, but no telemetry endpoint is configured; events stay local at \(displayPath(telemetryLogURL.path))."
        }
        if mode == .analytics {
            return "Analytics allowed for signed builds using the configured endpoint."
        }
        if mode == .diagnosticsOnly {
            return "Local diagnostic events are kept at \(displayPath(telemetryLogURL.path)) and exported only in a redacted support bundle."
        }
        return mode.detail
    }

    public static var telemetrySeverity: String {
        telemetryMode == .analytics && telemetryEndpoint == nil ? "warning" : "ready"
    }

    public static var crashReportingSummary: String {
        "Local crash capture writes issue IDs, version/build metadata, and a deduplication hint to \(displayPath(latestCrashReportURL.path)); upload remains off without consent and a crash backend."
    }

    public static var crashReportingSeverity: String {
        isWritableDirectory(logsDirectory) ? "ready" : "warning"
    }

    public static var supportUploadSummary: String {
        let endpointSummary = supportUploadEndpoint == nil
            ? "Support upload endpoint is not configured."
            : "Support upload endpoint is configured."
        let consentSummary = UserDefaults.standard.bool(forKey: supportUploadConsentKey)
            ? "User consent is enabled."
            : "User consent is off."
        let latestStatus = UserDefaults.standard.string(forKey: latestSupportUploadStatusKey)?.nilIfEmpty
            ?? "No support bundle has been uploaded yet."
        return "\(endpointSummary) \(consentSummary) \(latestStatus)"
    }

    public static var supportUploadSeverity: String {
        guard supportUploadEndpoint != nil else { return "warning" }
        return UserDefaults.standard.bool(forKey: supportUploadConsentKey) ? "ready" : "neutral"
    }

    public static var crashSymbolicationSummary: String {
        let crashEndpoint = crashReportingEndpoint == nil
            ? "Crash endpoint is not configured."
            : "Crash endpoint is configured."
        let symbolEndpoint = symbolUploadEndpoint == nil
            ? "Symbol upload endpoint is not configured."
            : "Symbol upload endpoint is configured."
        let symbolID = configuredSymbolIdentifier.nilIfEmpty ?? "not stamped"
        return "\(crashEndpoint) \(symbolEndpoint) Support bundles include \(symbolicationFileName) with dSYM UUID \(symbolID), bundle ID, build, and atos/lldb routing hints."
    }

    public static var crashSymbolicationSeverity: String {
        crashReportingEndpoint != nil && symbolUploadEndpoint != nil ? "ready" : "warning"
    }

    public static var diagnosticVersionStampSummary: String {
        let stamp = diagnosticVersionStamp(issueID: latestSupportIssueID)
        return "Schema \(stamp.schemaVersion), app \(stamp.appVersion) (\(stamp.buildNumber)), bundle \(stamp.bundleID), issue \(stamp.issueID)."
    }

    public static var diagnosticVersionStampSeverity: String {
        "ready"
    }

    public static var onboardingSummary: String {
        isOnboardingCompleted
            ? "First-run onboarding is complete."
            : "First-run onboarding is available from the start screen and Settings."
    }

    public static var onboardingSeverity: String {
        isOnboardingCompleted ? "ready" : "warning"
    }

    public static var isOnboardingCompleted: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompletedKey)
    }

    public static var licenseSummary: String {
        let snapshot = currentLicenseSnapshot()
        return "\(licenseStateSummary(snapshot)) \(licenseBackendConfigurationSummary)"
    }

    public static var licenseSeverity: String {
        let snapshot = currentLicenseSnapshot()
        return snapshot.state.grantsAccess && licenseBackendEndpoints != nil ? "ready" : "warning"
    }

    public static var privacyAuditSummary: String {
        "Provider-sharing, telemetry, license, onboarding, and support-bundle consent events are logged locally at \(displayPath(privacyAuditLogURL.path))."
    }

    public static var privacyAuditSeverity: String {
        isWritableDirectory(logsDirectory) ? "ready" : "warning"
    }

    public static var supportRedactionSummary: String {
        "Support exports redact API keys, bearer tokens, passwords, signing credentials, and common secret-shaped values before writing the bundle."
    }

    public static var supportRedactionSeverity: String {
        "ready"
    }

    public static var releaseNotesSummary: String {
        let path = resolvedReleaseNotesPath
        guard !path.isEmpty else {
            return "Release notes have not been generated for this build."
        }
        return FileManager.default.fileExists(atPath: path)
            ? "Release notes available at \(displayPath(path))."
            : "Release notes path is stale: \(displayPath(path))."
    }

    public static var releaseNotesSeverity: String {
        let path = resolvedReleaseNotesPath
        guard !path.isEmpty else { return "warning" }
        return FileManager.default.fileExists(atPath: path) ? "ready" : "warning"
    }

    public static func activateLicense(_ rawKey: String, accountEmail: String) async -> String {
        let normalized = normalizeLicenseKey(rawKey)
        guard isValidLicenseKey(normalized) else {
            return "License key must use ADA-XXXX-XXXX-XXXX-XXXX format."
        }
        let normalizedEmail = normalizeAccountEmail(accountEmail)
        guard isValidAccountEmail(normalizedEmail) else {
            return "Account email is required for activation and recovery."
        }
        guard let endpoints = licenseBackendEndpoints else {
            recordPrivacyAudit("license_activation_blocked", metadata: ["reason": "backend_missing"])
            return "License backend is not configured for activation, entitlement refresh, account recovery, and transfer."
        }

        do {
            let response: AndroidDevAgentLicenseBackendResponse = try await sendLicenseRequest(
                endpoint: endpoints.activation,
                body: AndroidDevAgentLicenseActivationRequest(
                    licenseKey: normalized,
                    accountEmail: normalizedEmail,
                    deviceID: stableLicenseDeviceID(),
                    appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "unknown"),
                    buildNumber: bundleValue("CFBundleVersion", defaultValue: "unknown"),
                    bundleID: bundleValue("CFBundleIdentifier", defaultValue: "unknown"),
                    platform: "macOS"
                )
            )
            let snapshot = licenseSnapshot(
                from: response,
                fallbackState: .subscriptionActive,
                fallbackAccountEmail: normalizedEmail,
                fallbackMaskedLicenseKey: maskedLicenseKey(normalized)
            )
            saveLicenseSnapshot(snapshot)
            recordTelemetryEvent("license_activated", metadata: ["state": snapshot.state.rawValue])
            recordPrivacyAudit("license_backend_activated", metadata: ["state": snapshot.state.rawValue])
            return licenseActionMessage(snapshot, defaultMessage: "License activated.")
        } catch {
            recordPrivacyAudit("license_activation_failed", metadata: ["reason": redactedSupportText(error.localizedDescription)])
            return "License activation failed: \(error.localizedDescription)"
        }
    }

    public static func refreshLicenseEntitlement() async -> String {
        let snapshot = currentLicenseSnapshot()
        if snapshot.state == .trialActive {
            return licenseStateSummary(snapshot)
        }
        guard snapshot.hasBackendEntitlement else {
            return "No activated backend entitlement is available to refresh."
        }
        guard let endpoints = licenseBackendEndpoints else {
            return "License backend is not configured for entitlement refresh."
        }

        do {
            let response: AndroidDevAgentLicenseBackendResponse = try await sendLicenseRequest(
                endpoint: endpoints.refresh,
                body: AndroidDevAgentLicenseRefreshRequest(
                    entitlementID: snapshot.entitlementID,
                    accountEmail: snapshot.accountEmail,
                    deviceID: snapshot.deviceID,
                    appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "unknown"),
                    buildNumber: bundleValue("CFBundleVersion", defaultValue: "unknown")
                )
            )
            let refreshed = licenseSnapshot(
                from: response,
                fallbackState: snapshot.state.grantsAccess ? .subscriptionActive : snapshot.state,
                fallbackAccountEmail: snapshot.accountEmail,
                fallbackMaskedLicenseKey: snapshot.maskedLicenseKey,
                previous: snapshot
            )
            saveLicenseSnapshot(refreshed)
            recordTelemetryEvent("license_refreshed", metadata: ["state": refreshed.state.rawValue])
            recordPrivacyAudit("license_entitlement_refreshed", metadata: ["state": refreshed.state.rawValue])
            return licenseActionMessage(refreshed, defaultMessage: "License verified.")
        } catch {
            if let graceSnapshot = offlineGraceSnapshot(from: snapshot, error: error) {
                saveLicenseSnapshot(graceSnapshot)
                recordTelemetryEvent("license_offline_grace", metadata: ["state": graceSnapshot.state.rawValue])
                recordPrivacyAudit("license_offline_grace", metadata: ["until": isoString(graceSnapshot.offlineGraceUntil)])
                return licenseStateSummary(graceSnapshot)
            }
            recordPrivacyAudit("license_refresh_failed", metadata: ["reason": redactedSupportText(error.localizedDescription)])
            return "License refresh failed: \(error.localizedDescription)"
        }
    }

    public static func recoverLicenseAccount(_ accountEmail: String) async -> String {
        let normalizedEmail = normalizeAccountEmail(accountEmail)
        guard isValidAccountEmail(normalizedEmail) else {
            return "Enter the account email used for purchase or subscription."
        }
        guard let endpoints = licenseBackendEndpoints else {
            return "License recovery backend is not configured."
        }

        do {
            let response: AndroidDevAgentLicenseBackendResponse = try await sendLicenseRequest(
                endpoint: endpoints.recovery,
                body: AndroidDevAgentLicenseRecoveryRequest(
                    accountEmail: normalizedEmail,
                    deviceID: stableLicenseDeviceID(),
                    appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "unknown")
                )
            )
            recordTelemetryEvent("license_recovery_requested")
            recordPrivacyAudit("license_account_recovery_requested")
            return response.message?.nilIfEmpty ?? "Recovery email sent."
        } catch {
            recordPrivacyAudit("license_recovery_failed", metadata: ["reason": redactedSupportText(error.localizedDescription)])
            return "Account recovery failed: \(error.localizedDescription)"
        }
    }

    public static func transferLicense(to targetAccountEmail: String) async -> String {
        let normalizedEmail = normalizeAccountEmail(targetAccountEmail)
        guard isValidAccountEmail(normalizedEmail) else {
            return "Enter the destination account email for license transfer."
        }
        var snapshot = currentLicenseSnapshot()
        guard snapshot.hasBackendEntitlement, snapshot.state.grantsAccess else {
            return "No active backend entitlement is available to transfer."
        }
        guard let endpoints = licenseBackendEndpoints else {
            return "License transfer backend is not configured."
        }

        do {
            let response: AndroidDevAgentLicenseBackendResponse = try await sendLicenseRequest(
                endpoint: endpoints.transfer,
                body: AndroidDevAgentLicenseTransferRequest(
                    entitlementID: snapshot.entitlementID,
                    sourceAccountEmail: snapshot.accountEmail,
                    targetAccountEmail: normalizedEmail,
                    deviceID: snapshot.deviceID,
                    appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "unknown")
                )
            )
            snapshot.state = .transferPending
            snapshot.lastVerifiedAt = response.serverTime ?? Date()
            snapshot.lastServerMessage = response.message?.nilIfEmpty ?? "License transfer pending for \(normalizedEmail)."
            snapshot.offlineGraceUntil = nil
            saveLicenseSnapshot(snapshot)
            recordTelemetryEvent("license_transfer_requested")
            recordPrivacyAudit("license_transfer_requested")
            return snapshot.lastServerMessage
        } catch {
            recordPrivacyAudit("license_transfer_failed", metadata: ["reason": redactedSupportText(error.localizedDescription)])
            return "License transfer failed: \(error.localizedDescription)"
        }
    }

    public static func deactivateLicense() {
        UserDefaults.standard.removeObject(forKey: licenseSnapshotKey)
        UserDefaults.standard.removeObject(forKey: licenseStateKey)
        UserDefaults.standard.removeObject(forKey: licenseMaskedKey)
        UserDefaults.standard.removeObject(forKey: licenseActivatedAtKey)
        recordTelemetryEvent("license_deactivated")
        recordPrivacyAudit("license_local_state_removed")
    }

    public static func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
        recordTelemetryEvent("onboarding_completed")
        recordPrivacyAudit("onboarding_completed")
    }

    public static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
        recordTelemetryEvent("onboarding_reset")
        recordPrivacyAudit("onboarding_reset")
    }

    public static func setSupportUploadConsent(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: supportUploadConsentKey)
        recordPrivacyAudit(enabled ? "support_upload_consent_enabled" : "support_upload_consent_disabled")
    }

    public static func setCrashUploadConsent(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: crashUploadConsentKey)
        recordPrivacyAudit(enabled ? "crash_upload_consent_enabled" : "crash_upload_consent_disabled")
    }

    public static func recordTelemetryEvent(_ name: String, metadata: [String: String] = [:]) {
        guard telemetryMode != .off else { return }
        do {
            try prepareSupportDirectories()
            var payload = metadata
            payload["event"] = name
            payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
            payload["mode"] = telemetryMode.rawValue
            if telemetryMode == .analytics, telemetryEndpoint == nil {
                payload["delivery"] = "local-only-no-endpoint"
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else { return }
            try append(line + "\n", to: telemetryLogURL)
        } catch {
            do {
                try appendTelemetryFallback(name: name, metadata: metadata, error: error)
            } catch {
                NSLog("Android Dev Agent telemetry logging failed: \(error.localizedDescription)")
            }
        }
    }

    public static func recordPrivacyAudit(_ name: String, metadata: [String: String] = [:]) {
        var payload = metadata
        payload["event"] = name
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else { return }
            try append(line + "\n", to: privacyAuditLogURL)
        } catch {
            NSLog("Android Dev Agent privacy audit logging failed: \(error.localizedDescription)")
        }
    }

    public static func createSupportBundle(report: String) throws -> URL {
        try prepareSupportDirectories()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-dev-agent-support-\(formatter.string(from: Date()))", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try FileManager.default.removeItem(at: bundleURL)
        }
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let issueID = makeSupportIssueID(seed: report)
        let stamp = diagnosticVersionStamp(issueID: issueID)
        UserDefaults.standard.set(issueID, forKey: latestSupportIssueIDKey)
        try redactedSupportText(report).write(to: bundleURL.appendingPathComponent("support-report.txt"), atomically: true, encoding: .utf8)
        try issueManifest(issueID: issueID, stamp: stamp).write(to: bundleURL.appendingPathComponent(issueFileName), atomically: true, encoding: .utf8)
        try stamp.displayText.write(to: bundleURL.appendingPathComponent(diagnosticVersionFileName), atomically: true, encoding: .utf8)
        try redactionManifest.write(to: bundleURL.appendingPathComponent(redactionSummaryFileName), atomically: true, encoding: .utf8)
        try launchReadinessManifest(issueID: issueID, stamp: stamp).write(to: bundleURL.appendingPathComponent("launch-readiness.txt"), atomically: true, encoding: .utf8)
        try crashSymbolicationManifest(issueID: issueID, stamp: stamp).write(to: bundleURL.appendingPathComponent(symbolicationFileName), atomically: true, encoding: .utf8)
        copyRedactedIfPresent(launchLogURL, to: bundleURL.appendingPathComponent(launchFileName))
        copyRedactedIfPresent(latestCrashReportURL, to: bundleURL.appendingPathComponent(crashFileName))
        copyRedactedIfPresent(telemetryLogURL, to: bundleURL.appendingPathComponent(telemetryFileName))
        copyRedactedIfPresent(privacyAuditLogURL, to: bundleURL.appendingPathComponent(privacyAuditFileName))
        if let releaseNotesPath = resolvedReleaseNotesPath.nilIfEmpty {
            copyIfPresent(URL(fileURLWithPath: releaseNotesPath), to: bundleURL.appendingPathComponent("release-notes.md"))
        }
        UserDefaults.standard.set(bundleURL.path, forKey: latestSupportBundlePathKey)
        recordTelemetryEvent("support_bundle_created")
        recordPrivacyAudit("support_bundle_created", metadata: ["redaction": "enabled", "issueID": issueID])
        return bundleURL
    }

    public static func uploadLatestSupportBundle() async -> String {
        guard let path = UserDefaults.standard.string(forKey: latestSupportBundlePathKey)?.nilIfEmpty else {
            let message = "Create a support bundle before uploading."
            UserDefaults.standard.set(message, forKey: latestSupportUploadStatusKey)
            return message
        }
        return await uploadSupportBundle(at: URL(fileURLWithPath: path))
    }

    public static func uploadSupportBundle(at bundleURL: URL) async -> String {
        guard UserDefaults.standard.bool(forKey: supportUploadConsentKey) else {
            let message = "Support upload needs explicit user consent in Settings > Launch."
            UserDefaults.standard.set(message, forKey: latestSupportUploadStatusKey)
            recordPrivacyAudit("support_bundle_upload_blocked", metadata: ["reason": "consent_missing"])
            return message
        }
        guard let endpoint = supportUploadEndpoint else {
            let message = "Support upload endpoint is not configured for this build."
            UserDefaults.standard.set(message, forKey: latestSupportUploadStatusKey)
            recordPrivacyAudit("support_bundle_upload_blocked", metadata: ["reason": "endpoint_missing"])
            return message
        }
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            let message = AndroidDevAgentSupportBackendError.missingBundle.localizedDescription
            UserDefaults.standard.set(message, forKey: latestSupportUploadStatusKey)
            recordPrivacyAudit("support_bundle_upload_blocked", metadata: ["reason": "bundle_missing"])
            return message
        }

        do {
            let request = try supportUploadURLRequest(endpoint: endpoint, bundleURL: bundleURL)
            let (data, response) = try await supportBackendTransport.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                let body = String(data: data, encoding: .utf8)?.nilIfEmpty ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
                throw AndroidDevAgentSupportBackendError.backend("HTTP \(response.statusCode): \(body.prefix(300))")
            }
            let decoded = try? JSONDecoder().decode(AndroidDevAgentSupportUploadResponse.self, from: data)
            let issueID = decoded?.issueID?.nilIfEmpty ?? supportIssueID(in: bundleURL) ?? latestSupportIssueID
            let backendMessage = decoded?.message?.nilIfEmpty ?? decoded?.status?.nilIfEmpty ?? "accepted"
            let message = "Support bundle uploaded for issue \(issueID): \(backendMessage)."
            UserDefaults.standard.set(issueID, forKey: latestSupportIssueIDKey)
            UserDefaults.standard.set(message, forKey: latestSupportUploadStatusKey)
            recordTelemetryEvent("support_bundle_uploaded", metadata: ["issueID": issueID])
            recordPrivacyAudit("support_bundle_uploaded", metadata: ["issueID": issueID])
            return message
        } catch {
            let message = "Support bundle upload failed: \(error.localizedDescription)"
            UserDefaults.standard.set(message, forKey: latestSupportUploadStatusKey)
            recordPrivacyAudit("support_bundle_upload_failed", metadata: ["reason": redactedSupportText(error.localizedDescription)])
            return message
        }
    }

    public static func redactedSupportText(_ text: String) -> String {
        let sensitiveMarkers = [
            "api_key",
            "apikey",
            "authorization",
            "bearer ",
            "client_secret",
            "keychain",
            "notarytool",
            "private_key",
            "password",
            "secret",
            "signing_identity",
            "store_password",
            "token"
        ]
        let lineRedacted = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let rawLine = String(line)
            let lowered = rawLine.lowercased()
            guard sensitiveMarkers.contains(where: { lowered.contains($0) }) else {
                return rawLine
            }
            if let delimiterRange = rawLine.range(of: ":") ?? rawLine.range(of: "=") {
                return String(rawLine[..<delimiterRange.upperBound]) + " [REDACTED]"
            }
            return "[REDACTED]"
        }.joined(separator: "\n")

        return redactPatterns(in: lineRedacted)
    }

    public static func openSupportDirectory() {
        try? prepareSupportDirectories()
        NSWorkspace.shared.open(supportDirectory)
    }

    public static func openLogsDirectory() {
        try? prepareSupportDirectories()
        NSWorkspace.shared.open(logsDirectory)
    }

    public static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static func launchReadinessManifest(issueID: String, stamp: AndroidDevAgentDiagnosticVersionStamp) -> String {
        """
        Android Dev Agent Launch Readiness

        Issue ID: \(issueID)
        Diagnostic Stamp: schema \(stamp.schemaVersion), app \(stamp.appVersion) (\(stamp.buildNumber)), bundle \(stamp.bundleID)
        Crash Reporting: \(crashReportingSummary)
        Crash Symbolication: \(crashSymbolicationSummary)
        Telemetry: \(telemetrySummary)
        License: \(licenseSummary)
        Onboarding: \(onboardingSummary)
        Privacy Audit: \(privacyAuditSummary)
        Support Redaction: \(supportRedactionSummary)
        Support Upload: \(supportUploadSummary)
        Diagnostic Version: \(diagnosticVersionStampSummary)
        Release Notes: \(releaseNotesSummary)
        Support Directory: \(displayPath(supportDirectory.path))
        Logs Directory: \(displayPath(logsDirectory.path))
        """
    }

    private static var redactionManifest: String {
        """
        Android Dev Agent Support Redaction

        Status: enabled
        Applied Before: bundle write and bundle upload
        Line Markers: api_key, apikey, authorization, bearer, client_secret, keychain, notarytool, password, secret, signing_identity, token
        Regex Rules: OpenAI keys, GitHub tokens, bearer tokens, key/value secrets, private keys, password assignments, authorization headers
        Manual Review: required before forwarding externally when support needs raw logs
        """
    }

    private static func issueManifest(issueID: String, stamp: AndroidDevAgentDiagnosticVersionStamp) -> String {
        """
        Issue ID: \(issueID)
        Created: \(stamp.createdAt)
        App Version: \(stamp.appVersion)
        Build: \(stamp.buildNumber)
        Bundle ID: \(stamp.bundleID)
        Upload Status: \(UserDefaults.standard.string(forKey: latestSupportUploadStatusKey)?.nilIfEmpty ?? "not uploaded")
        """
    }

    private static func crashSymbolicationManifest(issueID: String, stamp: AndroidDevAgentDiagnosticVersionStamp) -> String {
        """
        Android Dev Agent Crash Symbolication

        Issue ID: \(issueID)
        App Version: \(stamp.appVersion)
        Build: \(stamp.buildNumber)
        Bundle ID: \(stamp.bundleID)
        Architecture: \(stamp.architecture)
        dSYM UUID: \(configuredSymbolIdentifier.nilIfEmpty ?? "not configured")
        Crash Endpoint: \(crashReportingEndpoint?.absoluteString ?? "not configured")
        Symbol Upload Endpoint: \(symbolUploadEndpoint?.absoluteString ?? "not configured")
        Crash Report: \(displayPath(latestCrashReportURL.path))
        Deduplication: latest-crash.log records the crash deduplication key and issue ID.
        Symbolication: upload the matching dSYM for this build, then route macOS crash addresses through atos or lldb using the app binary and UUID above.
        """
    }

    private static var resolvedReleaseNotesPath: String {
        if let path = UserDefaults.standard.string(forKey: releaseNotesPathKey), !path.isEmpty {
            return path
        }
        if let resourceName = Bundle.main.infoDictionary?["AndroidDevAgentReleaseNotesResource"] as? String {
            let url = Bundle.main.resourceURL?.appendingPathComponent(resourceName)
            if let url, FileManager.default.fileExists(atPath: url.path) {
                return url.path
            }
        }
        return Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md")?.path ?? ""
    }

    private static var telemetryEndpoint: String? {
        let environmentEndpoint = ProcessInfo.processInfo.environment["ANDROID_DEV_AGENT_TELEMETRY_ENDPOINT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentEndpoint, !environmentEndpoint.isEmpty {
            return environmentEndpoint
        }
        return (Bundle.main.infoDictionary?["AndroidDevAgentTelemetryEndpoint"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static var crashReportingEndpoint: URL? {
        configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_CRASH_REPORTING_ENDPOINT",
            bundleKey: "AndroidDevAgentCrashReportingEndpoint"
        )
    }

    private static var supportUploadEndpoint: URL? {
        if let supportUploadEndpointOverride {
            return supportUploadEndpointOverride
        }
        return configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_SUPPORT_UPLOAD_ENDPOINT",
            bundleKey: "AndroidDevAgentSupportUploadEndpoint"
        ) ?? crashReportingEndpoint
    }

    private static var symbolUploadEndpoint: URL? {
        configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_SYMBOL_UPLOAD_ENDPOINT",
            bundleKey: "AndroidDevAgentSymbolUploadEndpoint"
        )
    }

    private static var configuredSymbolIdentifier: String {
        ProcessInfo.processInfo.environment["ANDROID_DEV_AGENT_DSYM_UUID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? (Bundle.main.infoDictionary?["AndroidDevAgentDSYMUUID"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            ?? ""
    }

    private static var licenseBackendEndpoints: AndroidDevAgentLicenseBackendEndpoints? {
        if let licenseBackendEndpointOverride {
            return licenseBackendEndpointOverride
        }
        guard let activation = configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_LICENSE_ACTIVATION_URL",
            bundleKey: "AndroidDevAgentLicenseActivationURL"
        ) else {
            return nil
        }

        let refresh = configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_LICENSE_REFRESH_URL",
            bundleKey: "AndroidDevAgentLicenseRefreshURL"
        ) ?? siblingLicenseEndpoint(from: activation, replacingLastPathComponentWith: "refresh")
        let recovery = configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_LICENSE_RECOVERY_URL",
            bundleKey: "AndroidDevAgentLicenseRecoveryURL"
        ) ?? siblingLicenseEndpoint(from: activation, replacingLastPathComponentWith: "recover")
        let transfer = configuredHTTPSEndpoint(
            environmentKey: "ANDROID_DEV_AGENT_LICENSE_TRANSFER_URL",
            bundleKey: "AndroidDevAgentLicenseTransferURL"
        ) ?? siblingLicenseEndpoint(from: activation, replacingLastPathComponentWith: "transfer")

        guard let refresh, let recovery, let transfer else { return nil }
        return AndroidDevAgentLicenseBackendEndpoints(
            activation: activation,
            refresh: refresh,
            recovery: recovery,
            transfer: transfer
        )
    }

    private static var licenseBackendConfigurationSummary: String {
        if licenseBackendEndpoints == nil {
            return "License backend is not configured for activation, entitlement refresh, account recovery, and transfer."
        }
        return "Backend endpoints are configured for activation, entitlement refresh, account recovery, and transfer."
    }

    private static func currentLicenseSnapshot(now: Date = Date()) -> AndroidDevAgentCommercialLicenseSnapshot {
        let defaults = UserDefaults.standard
        if let rawSnapshot = defaults.data(forKey: licenseSnapshotKey),
           let decoded = try? JSONDecoder().decode(AndroidDevAgentCommercialLicenseSnapshot.self, from: rawSnapshot) {
            let evolved = decoded.evolved(now: now)
            if evolved != decoded {
                saveLicenseSnapshot(evolved)
            }
            return evolved
        }
        if let migrated = migratedLegacyLicenseSnapshot(now: now) {
            saveLicenseSnapshot(migrated)
            return migrated
        }
        let trial = AndroidDevAgentCommercialLicenseSnapshot(
            state: .trialActive,
            entitlementID: "",
            planName: "Trial",
            accountEmail: "",
            maskedLicenseKey: "",
            deviceID: stableLicenseDeviceID(),
            activatedAt: nil,
            trialStartedAt: now,
            trialEndsAt: now.addingTimeInterval(TimeInterval(configuredInteger(
                environmentKey: "ANDROID_DEV_AGENT_LICENSE_TRIAL_DAYS",
                bundleKey: "AndroidDevAgentLicenseTrialDays",
                defaultValue: 14
            )) * 86_400),
            subscriptionRenewsAt: nil,
            expiresAt: nil,
            offlineGraceUntil: nil,
            lastVerifiedAt: nil,
            lastServerMessage: "Trial started."
        )
        saveLicenseSnapshot(trial)
        return trial
    }

    private static func migratedLegacyLicenseSnapshot(now: Date) -> AndroidDevAgentCommercialLicenseSnapshot? {
        guard UserDefaults.standard.string(forKey: licenseStateKey) == "active" else {
            return nil
        }
        let activatedAt = parsedISODate(UserDefaults.standard.string(forKey: licenseActivatedAtKey)) ?? now
        return AndroidDevAgentCommercialLicenseSnapshot(
            state: .perpetualActive,
            entitlementID: "",
            planName: "Legacy Local License",
            accountEmail: "",
            maskedLicenseKey: UserDefaults.standard.string(forKey: licenseMaskedKey) ?? "license saved",
            deviceID: stableLicenseDeviceID(),
            activatedAt: activatedAt,
            trialStartedAt: nil,
            trialEndsAt: nil,
            subscriptionRenewsAt: nil,
            expiresAt: nil,
            offlineGraceUntil: nil,
            lastVerifiedAt: nil,
            lastServerMessage: "Migrated from local launch-readiness license state."
        )
    }

    private static func saveLicenseSnapshot(_ snapshot: AndroidDevAgentCommercialLicenseSnapshot) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: licenseSnapshotKey)
        }
        defaults.set(snapshot.state.rawValue, forKey: licenseStateKey)
        if snapshot.maskedLicenseKey.isEmpty {
            defaults.removeObject(forKey: licenseMaskedKey)
        } else {
            defaults.set(snapshot.maskedLicenseKey, forKey: licenseMaskedKey)
        }
        if let activatedAt = snapshot.activatedAt {
            defaults.set(isoFormatter.string(from: activatedAt), forKey: licenseActivatedAtKey)
        } else {
            defaults.removeObject(forKey: licenseActivatedAtKey)
        }
    }

    private static func licenseSnapshot(
        from response: AndroidDevAgentLicenseBackendResponse,
        fallbackState: AndroidDevAgentCommercialLicenseState,
        fallbackAccountEmail: String,
        fallbackMaskedLicenseKey: String,
        previous: AndroidDevAgentCommercialLicenseSnapshot? = nil,
        now: Date = Date()
    ) -> AndroidDevAgentCommercialLicenseSnapshot {
        let state = commercialLicenseState(from: response.status) ?? fallbackState
        let verifiedAt = response.serverTime ?? now
        let graceUntil = response.offlineGraceUntil
            ?? verifiedAt.addingTimeInterval(TimeInterval(configuredInteger(
                environmentKey: "ANDROID_DEV_AGENT_LICENSE_OFFLINE_GRACE_DAYS",
                bundleKey: "AndroidDevAgentLicenseOfflineGraceDays",
                defaultValue: 7
            )) * 86_400)
        return AndroidDevAgentCommercialLicenseSnapshot(
            state: state,
            entitlementID: response.entitlementID?.nilIfEmpty ?? previous?.entitlementID ?? "",
            planName: response.planName?.nilIfEmpty ?? previous?.planName ?? "Android Dev Agent Pro",
            accountEmail: normalizeAccountEmail(response.accountEmail ?? fallbackAccountEmail),
            maskedLicenseKey: response.maskedLicenseKey?.nilIfEmpty ?? previous?.maskedLicenseKey ?? fallbackMaskedLicenseKey,
            deviceID: previous?.deviceID.nilIfEmpty ?? stableLicenseDeviceID(),
            activatedAt: previous?.activatedAt ?? verifiedAt,
            trialStartedAt: previous?.trialStartedAt,
            trialEndsAt: response.trialEndsAt ?? previous?.trialEndsAt,
            subscriptionRenewsAt: response.subscriptionRenewsAt ?? previous?.subscriptionRenewsAt,
            expiresAt: response.expiresAt ?? previous?.expiresAt,
            offlineGraceUntil: graceUntil,
            lastVerifiedAt: verifiedAt,
            lastServerMessage: response.message?.nilIfEmpty ?? previous?.lastServerMessage ?? "License verified."
        ).evolved(now: now)
    }

    private static func offlineGraceSnapshot(
        from snapshot: AndroidDevAgentCommercialLicenseSnapshot,
        error: Error,
        now: Date = Date()
    ) -> AndroidDevAgentCommercialLicenseSnapshot? {
        guard snapshot.state.grantsAccess, snapshot.state != .trialActive else {
            return nil
        }
        let graceUntil = snapshot.offlineGraceUntil
            ?? (snapshot.lastVerifiedAt ?? snapshot.activatedAt ?? now).addingTimeInterval(TimeInterval(configuredInteger(
                environmentKey: "ANDROID_DEV_AGENT_LICENSE_OFFLINE_GRACE_DAYS",
                bundleKey: "AndroidDevAgentLicenseOfflineGraceDays",
                defaultValue: 7
            )) * 86_400)
        guard now < graceUntil else { return nil }
        var next = snapshot
        next.state = .subscriptionGrace
        next.offlineGraceUntil = graceUntil
        next.lastServerMessage = "Backend unreachable; offline grace is active. \(error.localizedDescription)"
        return next
    }

    private static func licenseStateSummary(_ snapshot: AndroidDevAgentCommercialLicenseSnapshot) -> String {
        switch snapshot.state {
        case .trialActive:
            return "Trial active until \(displayDate(snapshot.trialEndsAt))."
        case .trialExpired:
            return "Trial expired on \(displayDate(snapshot.trialEndsAt))."
        case .subscriptionActive:
            let renewal = snapshot.subscriptionRenewsAt.map { " Renewal \(displayDate($0))." } ?? ""
            let grace = snapshot.offlineGraceUntil.map { " Offline grace until \(displayDate($0))." } ?? ""
            return "Subscription active for \(snapshot.planName) with \(snapshot.maskedLicenseKey.nilIfEmpty ?? "backend entitlement").\(renewal)\(grace)"
        case .subscriptionGrace:
            return "Offline grace active until \(displayDate(snapshot.offlineGraceUntil)) for \(snapshot.planName)."
        case .subscriptionExpired:
            return "Subscription expired for \(snapshot.planName)."
        case .perpetualActive:
            return "Perpetual license active with \(snapshot.maskedLicenseKey.nilIfEmpty ?? "backend entitlement")."
        case .revoked:
            return "License revoked. \(snapshot.lastServerMessage)"
        case .transferPending:
            return "License transfer pending. \(snapshot.lastServerMessage)"
        case .unlicensed:
            return "No commercial entitlement is active."
        }
    }

    private static func licenseActionMessage(
        _ snapshot: AndroidDevAgentCommercialLicenseSnapshot,
        defaultMessage: String
    ) -> String {
        let backendMessage = snapshot.lastServerMessage.nilIfEmpty ?? defaultMessage
        switch snapshot.state {
        case .subscriptionActive:
            return "Subscription active for \(snapshot.planName)."
        case .perpetualActive:
            return "Perpetual license activated."
        case .trialActive:
            return "Trial active until \(displayDate(snapshot.trialEndsAt))."
        case .subscriptionGrace:
            return licenseStateSummary(snapshot)
        case .trialExpired, .subscriptionExpired, .revoked, .transferPending, .unlicensed:
            return backendMessage
        }
    }

    private static func sendLicenseRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        endpoint: URL,
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AndroidDevAgent/\(bundleValue("CFBundleShortVersionString", defaultValue: "unknown"))", forHTTPHeaderField: "User-Agent")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await licenseBackendTransport.data(for: request)
        guard (200...299).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.nilIfEmpty ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw AndroidDevAgentLicenseBackendError.backend("HTTP \(response.statusCode): \(body.prefix(300))")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResponseBody.self, from: data)
    }

    private static func commercialLicenseState(from status: String?) -> AndroidDevAgentCommercialLicenseState? {
        let normalized = status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "trial", "trial_active":
            return .trialActive
        case "active", "subscription", "subscription_active":
            return .subscriptionActive
        case "grace", "offline_grace", "subscription_grace":
            return .subscriptionGrace
        case "expired", "subscription_expired":
            return .subscriptionExpired
        case "perpetual", "perpetual_active":
            return .perpetualActive
        case "revoked":
            return .revoked
        case "transfer", "transfer_pending", "transferred":
            return .transferPending
        case "unlicensed", "none":
            return .unlicensed
        default:
            return nil
        }
    }

    private static func stableLicenseDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: licenseDeviceIDKey)?.nilIfEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: licenseDeviceIDKey)
        return generated
    }

    private static func configuredHTTPSEndpoint(environmentKey: String, bundleKey: String) -> URL? {
        if let raw = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: raw),
           isHTTPSURL(url) {
            return url
        }
        if let raw = (Bundle.main.infoDictionary?[bundleKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: raw),
           isHTTPSURL(url) {
            return url
        }
        return nil
    }

    private static func siblingLicenseEndpoint(
        from activation: URL,
        replacingLastPathComponentWith pathComponent: String
    ) -> URL? {
        var url = activation
        url.deleteLastPathComponent()
        url.appendPathComponent(pathComponent)
        return isHTTPSURL(url) ? url : nil
    }

    private static func configuredInteger(environmentKey: String, bundleKey: String, defaultValue: Int) -> Int {
        if let raw = ProcessInfo.processInfo.environment[environmentKey],
           let value = Int(raw),
           value > 0 {
            return value
        }
        if let value = Bundle.main.infoDictionary?[bundleKey] as? Int, value > 0 {
            return value
        }
        if let raw = Bundle.main.infoDictionary?[bundleKey] as? String,
           let value = Int(raw),
           value > 0 {
            return value
        }
        return defaultValue
    }

    private static func normalizeAccountEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValidAccountEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@")
        guard parts.count == 2, parts[0].isEmpty == false, parts[1].contains(".") else {
            return false
        }
        return !email.contains(" ")
    }

    private static var isoFormatter: ISO8601DateFormatter {
        ISO8601DateFormatter()
    }

    private static func isoString(_ date: Date?) -> String {
        guard let date else { return "" }
        return isoFormatter.string(from: date)
    }

    private static func parsedISODate(_ raw: String?) -> Date? {
        guard let raw = raw?.nilIfEmpty else { return nil }
        return isoFormatter.date(from: raw)
    }

    private static func displayDate(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static var latestSupportIssueID: String {
        UserDefaults.standard.string(forKey: latestSupportIssueIDKey)?.nilIfEmpty
            ?? "not assigned"
    }

    private static func diagnosticVersionStamp(issueID: String) -> AndroidDevAgentDiagnosticVersionStamp {
        AndroidDevAgentDiagnosticVersionStamp(
            schemaVersion: diagnosticSchemaVersion,
            appVersion: bundleValue("CFBundleShortVersionString", defaultValue: "0.0.0"),
            buildNumber: bundleValue("CFBundleVersion", defaultValue: "0"),
            bundleID: bundleValue("CFBundleIdentifier", defaultValue: "unknown.bundle"),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processName: ProcessInfo.processInfo.processName,
            architecture: runtimeArchitecture,
            issueID: issueID,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private static var runtimeArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func makeSupportIssueID(seed: String, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        let date = formatter.string(from: now)
        let material = "\(bundleValue("CFBundleIdentifier", defaultValue: "unknown"))|\(seed)|\(now.timeIntervalSince1970)|\(UUID().uuidString)"
        let suffix = String(sha256Hex(Data(material.utf8)).prefix(8)).uppercased()
        return "ADA-\(date)-\(suffix)"
    }

    private static func supportIssueID(in bundleURL: URL) -> String? {
        let url = bundleURL.appendingPathComponent(issueFileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("Issue ID:") else { return nil }
                return String(line).replacingOccurrences(of: "Issue ID:", with: "").nilIfEmpty
            }
            .first
    }

    private static func supportUploadURLRequest(endpoint: URL, bundleURL: URL) throws -> URLRequest {
        let issueID = supportIssueID(in: bundleURL) ?? makeSupportIssueID(seed: bundleURL.lastPathComponent)
        let stamp = diagnosticVersionStamp(issueID: issueID)
        let payload = AndroidDevAgentSupportUploadRequest(
            issueID: issueID,
            diagnosticVersion: stamp,
            appVersion: stamp.appVersion,
            buildNumber: stamp.buildNumber,
            bundleID: stamp.bundleID,
            createdAt: stamp.createdAt,
            symbolication: crashSymbolicationManifest(issueID: issueID, stamp: stamp),
            files: try supportUploadFiles(in: bundleURL)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AndroidDevAgent/\(stamp.appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(issueID, forHTTPHeaderField: "X-Android-Dev-Agent-Issue")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(payload)
        return request
    }

    private static func supportUploadFiles(in bundleURL: URL) throws -> [AndroidDevAgentSupportUploadFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AndroidDevAgentSupportBackendError.missingBundle
        }

        var files: [AndroidDevAgentSupportUploadFile] = []
        var totalBytes = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: bundleURL.path + "/", with: "")
            let rawData = try Data(contentsOf: fileURL)
            let redactedData: Data
            let wasRedacted: Bool
            if let text = String(data: rawData, encoding: .utf8) {
                let redactedText = redactedSupportText(text)
                redactedData = Data(redactedText.utf8)
                wasRedacted = redactedText != text
            } else {
                redactedData = rawData
                wasRedacted = false
            }

            let availableBytes = max(0, maxSupportUploadBytes - totalBytes)
            if availableBytes == 0 { break }
            let fileLimit = min(maxSupportUploadFileBytes, availableBytes)
            let truncated = redactedData.count > fileLimit
            let uploadData = truncated ? Data(redactedData.prefix(fileLimit)) : redactedData
            totalBytes += uploadData.count
            files.append(AndroidDevAgentSupportUploadFile(
                path: relativePath,
                sha256: sha256Hex(uploadData),
                byteCount: uploadData.count,
                redacted: wasRedacted,
                truncated: truncated,
                contentBase64: uploadData.base64EncodedString()
            ))
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", Int($0)) }
            .joined()
    }

    private static func prepareSupportDirectories() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private static func appendLaunchLog(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        try? append(line, to: launchLogURL)
    }

    fileprivate static func appendCrashReport(_ report: String, deduplicationKey: String = "unknown") {
        let issueID = makeSupportIssueID(seed: deduplicationKey)
        let stamp = diagnosticVersionStamp(issueID: issueID)
        UserDefaults.standard.set(issueID, forKey: latestSupportIssueIDKey)
        let text = """

        --- \(ISO8601DateFormatter().string(from: Date())) ---
        Issue ID: \(issueID)
        Diagnostic Schema: \(stamp.schemaVersion)
        App Version: \(stamp.appVersion)
        Build: \(stamp.buildNumber)
        Bundle ID: \(stamp.bundleID)
        dSYM UUID: \(configuredSymbolIdentifier.nilIfEmpty ?? "not configured")
        Deduplication Key: \(deduplicationKey)
        Upload Consent: \(UserDefaults.standard.bool(forKey: crashUploadConsentKey) ? "enabled" : "disabled")
        Symbolication: pending matching dSYM upload for build \(stamp.buildNumber)
        \(redactedSupportText(report))

        """
        try? append(text, to: latestCrashReportURL)
    }

    private static func append(_ text: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = Data(text.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private static func configureCrashSignalPath() {
        if let pointer = androidDevAgentCrashPathPointer {
            free(pointer)
        }
        androidDevAgentCrashPathPointer = strdup(latestCrashReportURL.path)
    }

    private static func appendTelemetryFallback(name: String, metadata: [String: String], error: Error) throws {
        var payload = metadata
        payload["event"] = name
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        payload["mode"] = telemetryMode.rawValue
        payload["delivery"] = "local-fallback"
        payload["primaryPathError"] = error.localizedDescription
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else { return }
        let fallbackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(logsFolderName)/Logs", isDirectory: true)
            .appendingPathComponent(telemetryFileName)
        try append(line + "\n", to: fallbackURL)
    }

    private static func writableDirectory(preferred: URL, fallbackRelativePath: String) -> URL {
        if isWritableDirectory(preferred) {
            return preferred
        }
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent(fallbackRelativePath, isDirectory: true)
        _ = isWritableDirectory(fallback)
        return fallback
    }

    private static func isWritableDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let probe = url.appendingPathComponent(".write-test-\(UUID().uuidString)")
            try Data().write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private static func redactPatterns(in text: String) -> String {
        let replacements: [(pattern: String, template: String)] = [
            (#"sk-[A-Za-z0-9_\-]{8,}"#, "sk-[REDACTED]"),
            (#"gh[pousr]_[A-Za-z0-9_]{8,}"#, "gh[REDACTED]"),
            (#"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}"#, "$1[REDACTED]"),
            (#"(?i)("?(api[_-]?key|token|secret|password|store[_-]?password|key[_-]?password)"?\s*[:=]\s*)"[^"\n]+"#, "$1\"[REDACTED]\""),
            (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "[REDACTED PRIVATE KEY]"),
            (#"(?i)(authorization\s*[:=]\s*)[^\n]+"#, "$1[REDACTED]")
        ]
        return replacements.reduce(text) { current, replacement in
            current.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }
    }

    private static func bundleValue(_ key: String, defaultValue: String) -> String {
        (Bundle.main.infoDictionary?[key] as? String)?.nilIfEmpty ?? defaultValue
    }

    private static func isHTTPSURL(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue) else { return false }
        return isHTTPSURL(url)
    }

    private static func isHTTPSURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.isEmpty == false
    }

    private static func normalizeLicenseKey(_ rawKey: String) -> String {
        rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func isValidLicenseKey(_ key: String) -> Bool {
        let parts = key.split(separator: "-").map(String.init)
        guard parts.count == 5, parts.first == "ADA" else { return false }
        return parts.dropFirst().allSatisfy { part in
            part.count == 4 && part.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }

    private static func maskedLicenseKey(_ key: String) -> String {
        let suffix = String(key.suffix(4))
        return "ADA-****-****-****-\(suffix)"
    }

    private static func copyIfPresent(_ source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.copyItem(at: source, to: destination)
    }

    private static func copyRedactedIfPresent(_ source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        guard let text = try? String(contentsOf: source, encoding: .utf8) else {
            copyIfPresent(source, to: destination)
            return
        }
        try? redactedSupportText(text).write(to: destination, atomically: true, encoding: .utf8)
    }

    static func withCoverageLicenseBackend<T>(
        failingRefresh: Bool = false,
        operation: () async -> T
    ) async -> T {
        let previousTransport = licenseBackendTransport
        let previousEndpoints = licenseBackendEndpointOverride
        licenseBackendTransport = AndroidDevAgentMockLicenseBackendTransport(failingRefresh: failingRefresh)
        licenseBackendEndpointOverride = AndroidDevAgentLicenseBackendEndpoints(
            activation: URL(string: "https://license.example.com/android-dev-agent/activate")!,
            refresh: URL(string: "https://license.example.com/android-dev-agent/refresh")!,
            recovery: URL(string: "https://license.example.com/android-dev-agent/recover")!,
            transfer: URL(string: "https://license.example.com/android-dev-agent/transfer")!
        )
        defer {
            licenseBackendTransport = previousTransport
            licenseBackendEndpointOverride = previousEndpoints
        }
        return await operation()
    }

    static func withCoverageSupportBackend<T>(operation: () async -> T) async -> T {
        let previousTransport = supportBackendTransport
        let previousEndpoint = supportUploadEndpointOverride
        supportBackendTransport = AndroidDevAgentMockSupportBackendTransport()
        supportUploadEndpointOverride = URL(string: "https://support.example.com/android-dev-agent/bundles")!
        defer {
            supportBackendTransport = previousTransport
            supportUploadEndpointOverride = previousEndpoint
        }
        return await operation()
    }
}

struct AndroidDevAgentMockLicenseBackendTransport: AndroidDevAgentLicenseBackendTransport {
    let failingRefresh: Bool

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if failingRefresh, request.url?.lastPathComponent == "refresh" {
            throw AndroidDevAgentLicenseBackendError.backend("network offline")
        }
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let accountEmail = extractedJSONValue(named: "accountEmail", from: body)
            ?? extractedJSONValue(named: "sourceAccountEmail", from: body)
            ?? "launch@example.com"
        let targetEmail = extractedJSONValue(named: "targetAccountEmail", from: body) ?? "new-owner@example.com"
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let response: [String: String]

        switch request.url?.lastPathComponent {
        case "activate":
            response = [
                "status": "subscription_active",
                "entitlementID": "ent_coverage_android_dev_agent",
                "planName": "Android Dev Agent Pro",
                "accountEmail": accountEmail,
                "maskedLicenseKey": "ADA-****-****-****-MNOP",
                "subscriptionRenewsAt": formatter.string(from: now.addingTimeInterval(30 * 86_400)),
                "offlineGraceUntil": formatter.string(from: now.addingTimeInterval(7 * 86_400)),
                "serverTime": formatter.string(from: now),
                "message": "Coverage activation succeeded."
            ]
        case "refresh":
            response = [
                "status": "subscription_active",
                "entitlementID": "ent_coverage_android_dev_agent",
                "planName": "Android Dev Agent Pro",
                "accountEmail": accountEmail,
                "maskedLicenseKey": "ADA-****-****-****-MNOP",
                "subscriptionRenewsAt": formatter.string(from: now.addingTimeInterval(30 * 86_400)),
                "offlineGraceUntil": formatter.string(from: now.addingTimeInterval(7 * 86_400)),
                "serverTime": formatter.string(from: now),
                "message": "Coverage entitlement verified."
            ]
        case "recover":
            response = [
                "status": "subscription_active",
                "message": "Recovery email sent."
            ]
        case "transfer":
            response = [
                "status": "transfer_pending",
                "serverTime": formatter.string(from: now),
                "message": "License transfer pending for \(targetEmail)."
            ]
        default:
            response = [
                "status": "subscription_active",
                "message": "Coverage response."
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://license.example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, http)
    }

    private func extractedJSONValue(named name: String, from body: String) -> String? {
        let pattern = #""\#(name)"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let range = Range(match.range(at: 1), in: body) else {
            return nil
        }
        return String(body[range])
    }
}

struct AndroidDevAgentMockSupportBackendTransport: AndroidDevAgentSupportBackendTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let issueID = request.value(forHTTPHeaderField: "X-Android-Dev-Agent-Issue") ?? "ADA-COVERAGE"
        let response = [
            "issueID": issueID,
            "status": "accepted",
            "message": "Coverage support bundle accepted."
        ]
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://support.example.com")!,
            statusCode: 202,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, http)
    }
}

private var androidDevAgentCrashPathPointer: UnsafeMutablePointer<CChar>?

private func androidDevAgentUncaughtExceptionHandler(_ exception: NSException) {
    let stack = exception.callStackSymbols.joined(separator: "\n")
    AndroidDevAgentLaunchReadiness.appendCrashReport(
        """
        Uncaught exception: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        \(stack)
        """,
        deduplicationKey: "exception:\(exception.name.rawValue):\(exception.reason ?? "unknown")"
    )
}

private func androidDevAgentSignalHandler(_ signalNumber: Int32) {
    guard let path = androidDevAgentCrashPathPointer else {
        Darwin.signal(signalNumber, SIG_DFL)
        Darwin.raise(signalNumber)
        return
    }

    let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
    if descriptor >= 0 {
        let message = "Fatal signal captured by Android Dev Agent. See macOS crash logs for the full stack.\n"
        message.withCString { pointer in
            _ = Darwin.write(descriptor, pointer, strlen(pointer))
        }
        Darwin.close(descriptor)
    }
    Darwin.signal(signalNumber, SIG_DFL)
    Darwin.raise(signalNumber)
}
