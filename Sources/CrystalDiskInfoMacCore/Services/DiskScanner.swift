import Foundation

public enum SmartctlAvailability: Equatable, Sendable {
    case unknown
    case available(version: String, path: String)
    case notInstalled
    case unsupported(version: String)
    case failed(String)
}

public protocol DiskScanning {
    func scan(policy: TemperaturePolicy) throws -> [DiskInfo]
    func smartctlStatus() -> SmartctlAvailability
}

public extension DiskScanning {
    func smartctlStatus() -> SmartctlAvailability {
        .unknown
    }
}

/// Composes disk discovery, smartctl reads, and domain mapping.
///
/// A failure for one disk produces a visible `Unknown` row with the read
/// reason. A failure of discovery itself throws so the monitor can keep the
/// previous disk list and show an actionable error.
public final class DiskScanner: DiskScanning {
    private let lister: DiskListing
    private let runner: SmartctlRunning

    public init(
        lister: DiskListing = DiskutilLister(),
        runner: SmartctlRunning = SmartctlRunner()
    ) {
        self.lister = lister
        self.runner = runner
    }

    public func scan() throws -> [DiskInfo] {
        try scan(policy: .standard)
    }

    public func scan(policy: TemperaturePolicy) throws -> [DiskInfo] {
        let candidates = try lister.physicalDisks()

        return try candidates.map { candidate in
            do {
                let result = try runner.read(bsdName: candidate.bsdName)
                return DiskMapper.map(
                    candidate: candidate,
                    report: result.report,
                    policy: policy,
                    stderr: result.stderr
                )
            } catch let error as SmartctlError {
                switch error {
                case .notInstalled, .unsupportedVersion, .launchFailed:
                    // Setup-level failures affect every disk; let the monitor
                    // keep the previous list and show one actionable error.
                    throw error
                case .timeout, .invalidJSON, .deviceUnreadable:
                    return DiskMapper.unknown(
                        candidate: candidate,
                        error: Self.permissionGuidance(for: error.localizedDescription),
                        policy: policy
                    )
                }
            } catch {
                return DiskMapper.unknown(
                    candidate: candidate,
                    error: Self.permissionGuidance(for: error.localizedDescription),
                    policy: policy
                )
            }
        }
    }

    private static func permissionGuidance(for message: String) -> String {
        let lowercased = message.lowercased()
        guard lowercased.contains("permission")
            || lowercased.contains("not permitted")
            || lowercased.contains("unable to open") else {
            return message
        }
        return """
        \(message)
        Grant Full Disk Access to CrystalDiskInfo Mac in System Settings > Privacy & Security, then click Recheck.
        """
    }

    public func smartctlStatus() -> SmartctlAvailability {
        do {
            let url = try runner.discover()
            let version = try runner.version()
            return .available(version: version, path: url.path)
        } catch let error as SmartctlError {
            switch error {
            case .notInstalled:
                return .notInstalled
            case .unsupportedVersion(let version):
                return .unsupported(version: version)
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
