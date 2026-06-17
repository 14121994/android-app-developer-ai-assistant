import Darwin
import Foundation

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public final class ProcessRunner: @unchecked Sendable {
    private let processLock = NSLock()
    private var runningProcess: Process?
    private var terminationGeneration: UInt64 = 0

    public init() {}

    public var hasRunningProcess: Bool {
        let process = activeRunningProcess()
        return process?.isRunning == true
    }

    @discardableResult
    public func terminateRunningProcess() -> Bool {
        processLock.lock()
        terminationGeneration &+= 1
        let process = runningProcess
        processLock.unlock()

        guard let process, process.isRunning else { return false }
        let processID = process.processIdentifier
        let processTreeIDs = [processID] + Self.descendantProcessIDs(of: processID)
        Self.sendSignal(SIGINT, to: processTreeIDs)
        usleep(150_000)
        Self.sendSignal(SIGTERM, to: processTreeIDs)
        return true
    }

    public func run(_ command: ToolCommand, timeoutSeconds: TimeInterval? = nil) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let runGeneration = self.currentTerminationGeneration()

            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.executable == "/usr/bin/env" && command.arguments.first != "gradle"
                ? command.arguments
                : command.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                if !self.registerRunningProcess(process, generation: runGeneration), process.isRunning {
                    process.terminate()
                }
                defer {
                    self.clearRunningProcess(process)
                }

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

    private func activeRunningProcess() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        return runningProcess
    }

    private func currentTerminationGeneration() -> UInt64 {
        processLock.lock()
        defer { processLock.unlock() }
        return terminationGeneration
    }

    private func registerRunningProcess(_ process: Process, generation: UInt64) -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        guard generation == terminationGeneration else { return false }
        runningProcess = process
        return true
    }

    private func clearRunningProcess(_ process: Process) {
        processLock.lock()
        defer { processLock.unlock() }
        if runningProcess === process {
            runningProcess = nil
        }
    }

    private static func sendSignal(_ signal: Int32, to processIDs: [Int32]) {
        for processID in processIDs.reversed() where processID > 0 {
            _ = Darwin.kill(processID, signal)
        }
    }

    private static func descendantProcessIDs(of rootProcessID: Int32) -> [Int32] {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var childrenByParent: [Int32: [Int32]] = [:]

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let processID = Int32(String(parts[0])),
                  let parentProcessID = Int32(String(parts[1])) else {
                continue
            }
            childrenByParent[parentProcessID, default: []].append(processID)
        }

        var descendants: [Int32] = []
        var queue = childrenByParent[rootProcessID] ?? []
        while let processID = queue.first {
            queue.removeFirst()
            descendants.append(processID)
            queue.append(contentsOf: childrenByParent[processID] ?? [])
        }

        return descendants
    }

    public func runBinary(_ command: ToolCommand, timeoutSeconds: TimeInterval? = nil) async -> BinaryCommandResult {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let standardOutput = LockedDataBuffer()
            let standardError = LockedDataBuffer()

            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            func capturedResult(exitCode: Int32, fallbackStandardError: String? = nil, readRemainingData: Bool = true) -> BinaryCommandResult {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                if readRemainingData {
                    standardOutput.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
                    standardError.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                }

                let errorText = String(data: standardError.snapshot(), encoding: .utf8) ?? ""
                return BinaryCommandResult(
                    command: command,
                    exitCode: exitCode,
                    standardOutput: standardOutput.snapshot(),
                    standardError: errorText.isEmpty ? fallbackStandardError ?? "" : errorText
                )
            }

            do {
                try process.run()
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    standardOutput.append(handle.availableData)
                }
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    standardError.append(handle.availableData)
                }
                let startedAt = Date()
                while process.isRunning {
                    if let timeoutSeconds, Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                        process.terminate()
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        return capturedResult(
                            exitCode: -2,
                            fallbackStandardError: "Command timed out after \(Int(timeoutSeconds)) seconds.",
                            readRemainingData: !process.isRunning
                        )
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return capturedResult(exitCode: process.terminationStatus)
            } catch {
                return BinaryCommandResult(
                    command: command,
                    exitCode: -1,
                    standardOutput: Data(),
                    standardError: error.localizedDescription
                )
            }
        }.value
    }
}
