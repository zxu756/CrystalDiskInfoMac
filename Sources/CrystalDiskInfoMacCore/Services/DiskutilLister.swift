import Foundation
import Darwin

/// A physical whole disk discovered through `diskutil`.
public struct DiskCandidate: Equatable, Sendable {
    public let bsdName: String
    public let isInternal: Bool
    public let capacityBytes: UInt64
    public let mediaName: String
    public let deviceProtocol: String

    public init(
        bsdName: String,
        isInternal: Bool,
        capacityBytes: UInt64,
        mediaName: String,
        deviceProtocol: String
    ) {
        self.bsdName = bsdName
        self.isInternal = isInternal
        self.capacityBytes = capacityBytes
        self.mediaName = mediaName
        self.deviceProtocol = deviceProtocol
    }
}

public enum DiskutilError: Error, Equatable, Sendable {
    case commandFailed(String)
    case invalidPlist
}

extension DiskutilError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "diskutil failed: \(message)"
        case .invalidPlist:
            return "diskutil returned data that could not be parsed."
        }
    }
}

public protocol DiskListing {
    func physicalDisks() throws -> [DiskCandidate]
}

/// Enumerates whole physical disks, excluding APFS synthesized volumes,
/// partitions, and mounted disk images.
///
/// `diskutil list` has no reliable physical flag of its own, so each whole
/// disk is inspected with `diskutil info -plist`. On macOS 27 the internal
/// Apple SSD reports `VirtualOrPhysical = Unknown`, while synthesized APFS
/// containers and disk images report `Virtual`; both are handled explicitly.
public final class DiskutilLister: DiskListing {
    public typealias CommandRunner = (URL, [String]) throws -> Data

    private let diskutilURL: URL
    private let timeout: TimeInterval
    private let runner: CommandRunner

    public init(
        diskutilURL: URL = URL(fileURLWithPath: "/usr/sbin/diskutil"),
        timeout: TimeInterval = 10,
        runner: CommandRunner? = nil
    ) {
        self.diskutilURL = diskutilURL
        self.timeout = timeout
        self.runner = runner ?? { executable, arguments in
            try Self.runProcess(
                executable: executable,
                arguments: arguments,
                timeout: timeout
            )
        }
    }

    public func physicalDisks() throws -> [DiskCandidate] {
        let listData = try runner(diskutilURL, ["list", "-plist"])
        let list = try Self.plistDictionary(from: listData)
        let names = try Self.wholeDiskNames(in: list)

        var candidates: [DiskCandidate] = []
        candidates.reserveCapacity(names.count)

        for name in names {
            let infoData = try runner(diskutilURL, ["info", "-plist", "/dev/\(name)"])
            let info = try Self.plistDictionary(from: infoData)
            if let candidate = Self.makeCandidate(bsdName: name, info: info) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    private static func wholeDiskNames(in list: [String: Any]) throws -> [String] {
        let allDisks: [String]
        if let names = list["AllDisks"] as? [String] {
            allDisks = names
        } else if let entries = list["AllDisksAndPartitions"] as? [[String: Any]] {
            allDisks = entries.compactMap { $0["DeviceIdentifier"] as? String }
        } else {
            throw DiskutilError.invalidPlist
        }

        let unique = Set(allDisks.filter(isWholeDisk))
        guard !unique.isEmpty else { return [] }

        return unique.sorted {
            let lhsNumber = diskNumber($0)
            let rhsNumber = diskNumber($1)
            return lhsNumber == rhsNumber ? $0 < $1 : lhsNumber < rhsNumber
        }
    }

    private static func isWholeDisk(_ name: String) -> Bool {
        guard name.hasPrefix("disk") else { return false }
        let suffix = name.dropFirst("disk".count)
        return !suffix.isEmpty && suffix.allSatisfy { $0.isNumber }
    }

    private static func diskNumber(_ name: String) -> Int {
        Int(name.dropFirst("disk".count)) ?? Int.max
    }

    private static func makeCandidate(bsdName: String, info: [String: Any]) -> DiskCandidate? {
        if let virtualOrPhysical = info["VirtualOrPhysical"] as? String,
           virtualOrPhysical == "Virtual" {
            return nil
        }

        if let parent = info["ParentWholeDisk"] as? String, parent != bsdName {
            return nil
        }

        if let whole = info["WholeDisk"] as? Bool, whole == false {
            return nil
        }

        let busProtocol = (info["BusProtocol"] as? String)
            ?? (info["Protocol"] as? String)
            ?? ""
        let mediaName = (info["MediaName"] as? String) ?? ""

        if busProtocol == "Disk Image" || mediaName == "Disk Image" {
            return nil
        }

        return DiskCandidate(
            bsdName: bsdName,
            isInternal: info["Internal"] as? Bool ?? false,
            capacityBytes: uint64(info["TotalSize"]) ?? 0,
            mediaName: mediaName.isEmpty ? "Unknown" : mediaName,
            deviceProtocol: busProtocol.isEmpty ? "Unknown" : busProtocol
        )
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? Int64, value >= 0 {
            return UInt64(value)
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        return nil
    }

    private static func plistDictionary(from data: Data) throws -> [String: Any] {
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = object as? [String: Any] else {
                throw DiskutilError.invalidPlist
            }
            return dictionary
        } catch let error as DiskutilError {
            throw error
        } catch {
            throw DiskutilError.invalidPlist
        }
    }

    private final class DataBox {
        private let lock = NSLock()
        private var data = Data()

        func set(_ newData: Data) {
            lock.lock()
            data = newData
            lock.unlock()
        }

        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Data {
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
            throw DiskutilError.commandFailed(error.localizedDescription)
        }

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let stdoutDone = DispatchSemaphore(value: 0)
        let stderrDone = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            stdoutBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            stdoutDone.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
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
            throw DiskutilError.commandFailed("diskutil timed out")
        }

        _ = stdoutDone.wait(timeout: .now() + 1)
        _ = stderrDone.wait(timeout: .now() + 1)

        let stdout = stdoutBox.value
        let stderr = stderrBox.value

        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DiskutilError.commandFailed(
                message.isEmpty ? "diskutil exited with status \(process.terminationStatus)" : message
            )
        }

        return stdout
    }
}
