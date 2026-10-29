import Foundation
import Darwin

/// A successful smartctl read. `exitStatus` is smartctl's diagnostic bitmask
/// (from the JSON payload when available) and is deliberately separate from
/// whether the report is usable.
public struct SmartctlResult: Sendable {
    public let report: SmartctlReport
    public let exitStatus: Int
    public let stderr: String
    public let rawJSON: Data

    public init(report: SmartctlReport, exitStatus: Int, stderr: String, rawJSON: Data) {
        self.report = report
        self.exitStatus = exitStatus
        self.stderr = stderr
        self.rawJSON = rawJSON
    }
}

public enum SmartctlError: Error, Equatable, Sendable {
    case notInstalled
    case unsupportedVersion(String)
    case timeout
    case launchFailed(String)
    case invalidJSON
    case deviceUnreadable(String)
}

extension SmartctlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "smartctl was not found. Install smartmontools with: brew install smartmontools"
        case .unsupportedVersion(let version):
            return "smartctl \(version) is too old. Version 7.4 or later is required."
        case .timeout:
            return "smartctl did not respond before the timeout."
        case .launchFailed(let message):
            return "Could not launch smartctl: \(message)"
        case .invalidJSON:
            return "smartctl returned output that could not be parsed."
        case .deviceUnreadable(let message):
            return "Could not read SMART data from the device. \(message)"
        }
    }
}

public protocol SmartctlRunning {
    func discover() throws -> URL
    func version() throws -> String
    func read(bsdName: String) throws -> SmartctlResult
}

/// Runs the user-installed `smartctl` executable. No shell is involved:
/// arguments are passed directly to `Process`.
public final class SmartctlRunner: SmartctlRunning {
    public static var defaultCandidatePaths: [String] {
        var paths = [
            "/opt/homebrew/bin/smartctl",
            "/usr/local/bin/smartctl",
            "/usr/bin/smartctl"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                paths.append("\(directory)/smartctl")
            }
        }
        return paths
    }

    private let candidatePaths: [String]
    private let timeout: TimeInterval
    private let maxCaptureBytes: Int

    public init(
        candidatePaths: [String] = SmartctlRunner.defaultCandidatePaths,
        timeout: TimeInterval = 10,
        maxCaptureBytes: Int = 8 * 1024 * 1024
    ) {
        self.candidatePaths = candidatePaths
        self.timeout = timeout
        self.maxCaptureBytes = maxCaptureBytes
    }

    public func discover() throws -> URL {
        var seen = Set<String>()
        for path in candidatePaths where seen.insert(path).inserted {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: path) else {
                continue
            }
            return URL(fileURLWithPath: path)
        }
        throw SmartctlError.notInstalled
    }

    public func version() throws -> String {
        let executable = try discover()
        let output = try run(executable: executable, arguments: ["--version"], timeout: timeout)
        let text = String(decoding: output.stdout, as: UTF8.self)

        guard let parsed = Self.parseVersion(text) else {
            throw SmartctlError.unsupportedVersion("unknown")
        }
        guard parsed.major > 7 || (parsed.major == 7 && parsed.minor >= 4) else {
            throw SmartctlError.unsupportedVersion("\(parsed.major).\(parsed.minor)")
        }
        return "\(parsed.major).\(parsed.minor)"
    }

    public func read(bsdName: String) throws -> SmartctlResult {
        let executable = try discover()
        let device = bsdName.hasPrefix("/dev/") ? bsdName : "/dev/\(bsdName)"
        let deviceTypes: [String?] = [nil, "sat", "nvme"]
        var lastError = SmartctlError.deviceUnreadable("smartctl returned no data for \(device).")

        for deviceType in deviceTypes {
            var arguments = ["-j", "-a"]
            if let deviceType {
                arguments.append(contentsOf: ["-d", deviceType])
            }
            arguments.append(device)

            let output = try run(executable: executable, arguments: arguments, timeout: timeout)
            let stderr = String(decoding: output.stderr, as: UTF8.self)
            let detectionFailure = stderr.contains("Unable to detect device type")

            guard !output.stdout.isEmpty else {
                lastError = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .deviceUnreadable("smartctl returned no output for \(device).")
                    : .deviceUnreadable(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                if detectionFailure { continue }
                throw lastError
            }

            let report: SmartctlReport
            do {
                report = try SmartctlReport.decode(output.stdout)
            } catch {
                lastError = .invalidJSON
                if detectionFailure { continue }
                throw lastError
            }

            guard Self.isUsable(report) else {
                lastError = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .deviceUnreadable("smartctl did not return identity and SMART data for \(device).")
                    : .deviceUnreadable(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                if detectionFailure { continue }
                throw lastError
            }

            return SmartctlResult(
                report: report,
                exitStatus: report.smartctl?.exitStatus ?? Int(output.terminationStatus),
                stderr: stderr,
                rawJSON: output.stdout
            )
        }

        throw lastError
    }

    private static func parseVersion(_ output: String) -> (major: Int, minor: Int)? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "smartctl" else { continue }
            let parts = fields[1].split(separator: ".")
            guard parts.count >= 2,
                  let major = Int(parts[0]),
                  let minor = Int(parts[1]) else {
                continue
            }
            return (major, minor)
        }
        return nil
    }

    private static func isUsable(_ report: SmartctlReport) -> Bool {
        guard let model = report.modelName, !model.isEmpty else { return false }
        return report.smartStatus != nil
            || report.nvmeSmartHealthInformationLog != nil
            || report.ataSmartAttributes?.table != nil
    }

    private struct ProcessOutput {
        let stdout: Data
        let stderr: Data
        let terminationStatus: Int32
    }

    private final class DataCollector {
        private let limit: Int
        private let lock = NSLock()
        private var data = Data()

        init(limit: Int) {
            self.limit = max(limit, 0)
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            guard data.count < limit else { return }
            data.append(contentsOf: chunk.prefix(limit - data.count))
        }

        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }

        do {
            try process.run()
        } catch {
            throw SmartctlError.launchFailed(error.localizedDescription)
        }

        let stdoutCollector = DataCollector(limit: maxCaptureBytes)
        let stderrCollector = DataCollector(limit: maxCaptureBytes)
        let stdoutDone = DispatchSemaphore(value: 0)
        let stderrDone = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            Self.drain(stdoutPipe.fileHandleForReading, into: stdoutCollector)
            stdoutDone.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            Self.drain(stderrPipe.fileHandleForReading, into: stderrCollector)
            stderrDone.signal()
        }

        if termination.wait(timeout: .now() + max(timeout, 0)) == .timedOut {
            process.terminate()
            if termination.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 1)
            }
            _ = stdoutDone.wait(timeout: .now() + 1)
            _ = stderrDone.wait(timeout: .now() + 1)
            throw SmartctlError.timeout
        }

        _ = stdoutDone.wait(timeout: .now() + 1)
        _ = stderrDone.wait(timeout: .now() + 1)

        return ProcessOutput(
            stdout: stdoutCollector.value,
            stderr: stderrCollector.value,
            terminationStatus: process.terminationStatus
        )
    }

    private static func drain(_ handle: FileHandle, into collector: DataCollector) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            collector.append(chunk)
        }
    }
}
