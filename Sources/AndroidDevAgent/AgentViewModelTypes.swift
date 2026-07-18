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
        case .launch: return 180
        }
    }

    var riskSummary: String {
        switch self {
        case .connectedTests:
            return "Instrumentation tests can install, launch, and control the selected device."
        case .clearLogcat:
            return "This clears Logcat on the selected device."
        case .launch:
            return "This builds and installs the selected variant on the selected device, replacing an existing installation, then launches the configured package/activity."
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
        friendlyName
    }

    var friendlyName: String {
        if let model = metadataValue(for: "model") {
            return model.replacingOccurrences(of: "_", with: " ")
        }
        if let product = metadataValue(for: "product") {
            return product.replacingOccurrences(of: "_", with: " ")
        }
        if let device = metadataValue(for: "device") {
            return device.replacingOccurrences(of: "_", with: " ")
        }
        return isNetworkSerial ? "Wireless Android Device" : id
    }

    var isNetworkSerial: Bool {
        id.contains(":") || id.contains("._adb-tls-connect._tcp")
    }

    private func metadataValue(for key: String) -> String? {
        let prefix = "\(key):"
        guard let rawValue = name
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(rawValue.dropFirst(prefix.count)).nilIfEmpty
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

struct WirelessDebuggingDevice: Identifiable, Hashable {
    let id: String
    let serviceName: String
    let host: String
    let connectAddress: String?
    let pairingAddress: String?

    var displayName: String {
        let cleanedName = serviceName
            .replacingOccurrences(of: "_", with: " ")
            .nilIfEmpty
        return cleanedName ?? "Wireless Android Device"
    }

    var detail: String {
        var parts: [String] = []
        if let connectAddress {
            parts.append("Connect \(connectAddress)")
        }
        if let pairingAddress {
            parts.append("Pair \(pairingAddress)")
        }
        return parts.isEmpty ? "Wireless debugging service discovered" : parts.joined(separator: " | ")
    }

    var capabilitySummary: String {
        switch (connectAddress != nil, pairingAddress != nil) {
        case (true, true):
            return "Connect and pair"
        case (true, false):
            return "Connect"
        case (false, true):
            return "Pair"
        default:
            return "Discovered"
        }
    }
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
        exists ? "\(name) - \(displayPath)" : "Missing: \(name)"
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

struct EditorScopedDiff: Hashable {
    let lines: [String]
    let addedLineCount: Int
    let removedLineCount: Int
    let changedLineCount: Int

    var summary: String {
        "\(addedLineCount) added, \(removedLineCount) removed, \(changedLineCount) changed"
    }
}

struct EditorSecretFinding: Hashable {
    let lineNumber: Int
    let label: String

    var summary: String {
        "\(label) on line \(lineNumber)"
    }
}

enum EditorSaveSafetyError: LocalizedError {
    case blocked(String)

    var errorDescription: String? {
        switch self {
        case let .blocked(message):
            return message
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
