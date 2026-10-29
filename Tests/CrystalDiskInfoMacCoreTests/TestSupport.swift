import Foundation
@testable import CrystalDiskInfoMacCore

enum TestFixtures {
    static func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/\(name)"))
    }

    static func disk(
        id: String = "SERIAL|Test Disk",
        bsdName: String = "disk0",
        model: String = "Test Disk",
        serial: String = "SERIAL",
        firmware: String = "1.0",
        protocolName: String = "NVMe",
        interfaceName: String = "PCI-Express",
        capacityBytes: UInt64 = 500_000_000_000,
        isInternal: Bool = true,
        smartStatus: SmartStatus = .passed,
        health: HealthStatus = .good,
        temperatureCelsius: Int? = 40,
        temperatureWarningCelsius: Int = 50,
        temperatureCriticalCelsius: Int = 60,
        lifePercent: Int? = 95,
        powerOnHours: Int? = 100,
        powerCycleCount: Int? = 10,
        unsafeShutdowns: Int? = 1,
        mediaErrors: Int? = 0,
        attributes: [SmartAttribute] = [],
        readError: String? = nil
    ) -> DiskInfo {
        DiskInfo(
            id: id,
            bsdName: bsdName,
            model: model,
            serial: serial,
            firmware: firmware,
            protocolName: protocolName,
            interfaceName: interfaceName,
            capacityBytes: capacityBytes,
            isInternal: isInternal,
            smartStatus: smartStatus,
            health: health,
            temperatureCelsius: temperatureCelsius,
            temperatureWarningCelsius: temperatureWarningCelsius,
            temperatureCriticalCelsius: temperatureCriticalCelsius,
            lifePercent: lifePercent,
            powerOnHours: powerOnHours,
            powerCycleCount: powerCycleCount,
            unsafeShutdowns: unsafeShutdowns,
            mediaErrors: mediaErrors,
            attributes: attributes,
            readError: readError
        )
    }
}

final class RecordingHistoryStore: HistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: [HistorySample]] = [:]
    private var appendError: Error?

    func setAppendError(_ error: Error?) {
        lock.lock()
        appendError = error
        lock.unlock()
    }

    func append(_ sample: HistorySample, for diskID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        if let appendError {
            throw appendError
        }
        storage[diskID, default: []].append(sample)
    }

    func samples(for diskID: String) throws -> [HistorySample] {
        lock.lock()
        defer { lock.unlock() }
        return storage[diskID] ?? []
    }

    func prune(now: Date) throws {}

    var allSamples: [String: [HistorySample]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class RecordingNotifications: NotificationDelivering, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DiskNotification] = []

    func post(_ notification: DiskNotification) {
        lock.lock()
        storage.append(notification)
        lock.unlock()
    }

    var posted: [DiskNotification] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class MockScanner: DiskScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[DiskInfo], Error>
    private var scanCount = 0
    private var lastPolicy: TemperaturePolicy?
    private var status: SmartctlAvailability = .unknown
    var onScan: (() -> Void)?

    init(disks: [DiskInfo]) {
        self.result = .success(disks)
    }

    init(result: Result<[DiskInfo], Error>) {
        self.result = result
    }

    func setResult(_ newResult: Result<[DiskInfo], Error>) {
        lock.lock()
        result = newResult
        lock.unlock()
    }

    func setStatus(_ newStatus: SmartctlAvailability) {
        lock.lock()
        status = newStatus
        lock.unlock()
    }

    func smartctlStatus() -> SmartctlAvailability {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func scan(policy: TemperaturePolicy) throws -> [DiskInfo] {
        lock.lock()
        scanCount += 1
        lastPolicy = policy
        let current = result
        lock.unlock()

        onScan?()
        return try current.get()
    }

    var numberOfScans: Int {
        lock.lock()
        defer { lock.unlock() }
        return scanCount
    }

    var policyUsed: TemperaturePolicy? {
        lock.lock()
        defer { lock.unlock() }
        return lastPolicy
    }
}

final class BlockingScanner: DiskScanning, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var scanCount = 0
    private let disks: [DiskInfo]

    init(disks: [DiskInfo]) {
        self.disks = disks
    }

    func scan(policy: TemperaturePolicy) throws -> [DiskInfo] {
        lock.lock()
        scanCount += 1
        lock.unlock()

        started.signal()
        release.wait()
        return disks
    }

    var numberOfScans: Int {
        lock.lock()
        defer { lock.unlock() }
        return scanCount
    }
}
