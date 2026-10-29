import Foundation

public protocol DiskScanning {
    func scan(policy: TemperaturePolicy) throws -> [DiskInfo]
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
                    policy: policy
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
                        error: error.localizedDescription,
                        policy: policy
                    )
                }
            } catch {
                return DiskMapper.unknown(
                    candidate: candidate,
                    error: error.localizedDescription,
                    policy: policy
                )
            }
        }
    }
}
