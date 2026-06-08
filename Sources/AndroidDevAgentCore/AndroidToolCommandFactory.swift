import Foundation

public enum AndroidToolCommandFactory {
    public static func gradleTask(title: String, rootPath: String, task: String) -> ToolCommand {
        gradleCommand(title: title, rootPath: rootPath, task: task)
    }

    public static func gradleTest(rootPath: String) -> ToolCommand {
        gradleCommand(title: "Run Unit Tests", rootPath: rootPath, task: "testDebugUnitTest")
    }

    public static func assembleDebug(rootPath: String) -> ToolCommand {
        gradleCommand(title: "Assemble Debug", rootPath: rootPath, task: "assembleDebug")
    }

    public static func connectedAndroidTest(rootPath: String) -> ToolCommand {
        gradleCommand(title: "Run Instrumentation Tests", rootPath: rootPath, task: "connectedDebugAndroidTest")
    }

    public static func listDevices(rootPath: String) -> ToolCommand {
        return adbCommand(
            title: "List Android Devices",
            rootPath: rootPath,
            arguments: ["devices", "-l"]
        )
    }

    public static func mdnsServices(rootPath: String) -> ToolCommand {
        adbCommand(
            title: "Discover Wireless Debugging Services",
            rootPath: rootPath,
            arguments: ["mdns", "services"]
        )
    }

    public static func pairWirelessDevice(rootPath: String, hostPort: String, pairingCode: String) -> ToolCommand {
        adbCommand(
            title: "Pair Wireless Device",
            rootPath: rootPath,
            arguments: ["pair", hostPort, pairingCode]
        )
    }

    public static func connectWirelessDevice(rootPath: String, hostPort: String) -> ToolCommand {
        adbCommand(
            title: "Connect Wireless Device",
            rootPath: rootPath,
            arguments: ["connect", hostPort]
        )
    }

    public static func disconnectWirelessDevice(rootPath: String, hostPort: String) -> ToolCommand {
        adbCommand(
            title: "Disconnect Wireless Device",
            rootPath: rootPath,
            arguments: ["disconnect", hostPort]
        )
    }

    public static func logcatSnapshot(rootPath: String, lines: Int = 250, deviceSerial: String? = nil) -> ToolCommand {
        var arguments = ["logcat", "-d", "-t", "\(lines)"]
        if let deviceSerial, !deviceSerial.isEmpty {
            arguments = ["-s", deviceSerial] + arguments
        }
        return adbCommand(
            title: "Capture Logcat Snapshot",
            rootPath: rootPath,
            arguments: arguments
        )
    }

    public static func launchApp(rootPath: String, packageName: String, activityName: String = ".MainActivity", deviceSerial: String? = nil) -> ToolCommand {
        var arguments = ["shell", "am", "start", "-n", "\(packageName)/\(activityName)"]
        if let deviceSerial, !deviceSerial.isEmpty {
            arguments = ["-s", deviceSerial] + arguments
        }
        return adbCommand(
            title: "Launch App",
            rootPath: rootPath,
            arguments: arguments
        )
    }

    public static func clearLogcat(rootPath: String, deviceSerial: String? = nil) -> ToolCommand {
        var arguments = ["logcat", "-c"]
        if let deviceSerial, !deviceSerial.isEmpty {
            arguments = ["-s", deviceSerial] + arguments
        }
        return adbCommand(
            title: "Clear Logcat",
            rootPath: rootPath,
            arguments: arguments
        )
    }

    private static func gradleCommand(title: String, rootPath: String, task: String) -> ToolCommand {
        let wrapper = URL(fileURLWithPath: rootPath).appendingPathComponent("gradlew").path
        let fileManager = FileManager.default
        if fileManager.isExecutableFile(atPath: wrapper) {
            return ToolCommand(
                title: title,
                executable: wrapper,
                arguments: [task, "--no-daemon", "--console=plain"],
                workingDirectory: rootPath
            )
        }
        if fileManager.fileExists(atPath: wrapper) {
            return ToolCommand(
                title: title,
                executable: "/bin/sh",
                arguments: ["./gradlew", task, "--no-daemon", "--console=plain"],
                workingDirectory: rootPath
            )
        }
        return ToolCommand(
            title: title,
            executable: "/usr/bin/env",
            arguments: ["gradle", task, "--no-daemon", "--console=plain"],
            workingDirectory: rootPath
        )
    }

    private static func adbPath() -> String {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["ANDROID_HOME"],
            environment["ANDROID_SDK_ROOT"],
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Android/sdk"
        ].compactMap { $0 }

        for sdkRoot in candidates {
            let path = URL(fileURLWithPath: sdkRoot).appendingPathComponent("platform-tools/adb").path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return "/usr/bin/env"
    }

    private static func adbCommand(title: String, rootPath: String, arguments: [String]) -> ToolCommand {
        let executable = adbPath()
        if executable == "/usr/bin/env" {
            return ToolCommand(
                title: title,
                executable: executable,
                arguments: ["adb"] + arguments,
                workingDirectory: rootPath
            )
        }
        return ToolCommand(
            title: title,
            executable: executable,
            arguments: arguments,
            workingDirectory: rootPath
        )
    }
}
