import Foundation

public final class ProcessRunner {
    public init() {}

    public func run(_ command: ToolCommand, timeoutSeconds: TimeInterval? = nil) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.executable == "/usr/bin/env" && command.arguments.first != "gradle"
                ? command.arguments
                : command.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                let startedAt = Date()
                while process.isRunning {
                    if let timeoutSeconds, Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                        process.terminate()
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        return CommandResult(
                            command: command,
                            exitCode: -2,
                            standardOutput: stdout,
                            standardError: stderr.isEmpty ? "Command timed out after \(Int(timeoutSeconds)) seconds." : stderr
                        )
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CommandResult(command: command, exitCode: process.terminationStatus, standardOutput: stdout, standardError: stderr)
            } catch {
                return CommandResult(
                    command: command,
                    exitCode: -1,
                    standardOutput: "",
                    standardError: error.localizedDescription
                )
            }
        }.value
    }
}
