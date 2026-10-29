import Foundation
import Combine

@MainActor
public final class DiskMonitor: ObservableObject {
    @Published public private(set) var disks: [DiskInfo] = []
    @Published public private(set) var selectedDiskID: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var historySamples: [HistorySample] = []
    @Published public private(set) var smartctlStatus: SmartctlAvailability = .unknown

    public var selectedDisk: DiskInfo? {
        guard let selectedDiskID else { return nil }
        return disks.first { $0.id == selectedDiskID }
    }

    private let scanner: DiskScanning
    private let history: HistoryStoring
    private let notifications: NotificationDelivering?
    private let settingsStore: SettingsStoring?
    private let notificationPolicy: NotificationPolicy
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var failureCounts: [String: Int] = [:]
    private var hasPrunedHistory = false

    public init(
        scanner: DiskScanning,
        history: HistoryStoring,
        notifications: NotificationDelivering? = nil,
        settings: AppSettings = .standard,
        settingsStore: SettingsStoring? = nil,
        notificationPolicy: NotificationPolicy = NotificationPolicy(),
        now: @escaping () -> Date = Date.init
    ) {
        self.scanner = scanner
        self.history = history
        self.notifications = notifications
        self.settings = settings.validated()
        self.settingsStore = settingsStore
        self.notificationPolicy = notificationPolicy
        self.now = now
    }

    init(
        previewDisks: [DiskInfo],
        selectedDiskID: String? = nil,
        lastRefresh: Date? = nil,
        historySamples: [HistorySample] = [],
        settings: AppSettings = .standard
    ) {
        self.scanner = PreviewScanner(disks: previewDisks)
        self.history = PreviewHistoryStore()
        self.notifications = nil
        self.settings = settings.validated()
        self.settingsStore = nil
        self.notificationPolicy = NotificationPolicy()
        self.now = Date.init
        self.disks = previewDisks
        self.selectedDiskID = selectedDiskID ?? previewDisks.first?.id
        self.lastRefresh = lastRefresh
        self.historySamples = historySamples
        self.smartctlStatus = .available(
            version: "7.5",
            path: "/opt/homebrew/bin/smartctl"
        )
    }

    public func selectDisk(id: String) {
        guard disks.contains(where: { $0.id == id }) else {
            return
        }
        selectedDiskID = id
        historySamples = []
        Task { [weak self] in
            await self?.loadHistory(for: id)
        }
    }

    public func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshTask != nil {
                startAutoRefresh()
            }
        }

        let scanner = self.scanner
        let policy = settings.temperaturePolicy

        let status = await Task.detached(priority: .userInitiated) {
            scanner.smartctlStatus()
        }.value
        smartctlStatus = status

        switch status {
        case .notInstalled:
            errorMessage = SmartctlError.notInstalled.errorDescription
            return
        case .unsupported(let version):
            errorMessage = SmartctlError.unsupportedVersion(version).errorDescription
            return
        default:
            break
        }

        let scanned: [DiskInfo]
        do {
            scanned = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(policy: policy)
            }.value
        } catch {
            errorMessage = Self.message(for: error)
            return
        }

        await applyScan(scanned)
    }

    public func apply(settings newSettings: AppSettings) {
        let validated = newSettings.validated()
        settings = validated
        settingsStore?.save(validated)

        if refreshTask != nil {
            startAutoRefresh()
        }
    }

    public func startAutoRefresh() {
        stopAutoRefresh()

        let interval = Duration.seconds(settings.refreshMinutes * 60)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }

                guard let self, !Task.isCancelled else {
                    break
                }
                await self.refresh()
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func applyScan(_ scanned: [DiskInfo]) async {
        let timestamp = now()
        let reconciled = reconcile(scanned)
        disks = reconciled
        lastRefresh = timestamp

        if selectedDiskID == nil || !reconciled.contains(where: { $0.id == selectedDiskID }) {
            selectedDiskID = reconciled.first?.id
        }

        let history = self.history
        let shouldPruneHistory = !hasPrunedHistory
        hasPrunedHistory = true
        let writes: [(HistorySample, String)] = reconciled
            .filter { !$0.isStale }
            .map { disk in
                (
                    HistorySample(
                        timestamp: timestamp,
                        health: disk.health,
                        temperatureCelsius: disk.temperatureCelsius,
                        lifePercent: disk.lifePercent,
                        powerOnHours: disk.powerOnHours
                    ),
                    disk.id
                )
            }

        let historyError: String? = await Task.detached(priority: .utility) {
            if shouldPruneHistory {
                try? history.prune(now: timestamp)
            }

            var firstError: String?
            for (sample, diskID) in writes {
                do {
                    try history.append(sample, for: diskID)
                } catch {
                    if firstError == nil {
                        firstError = "Could not save history: \(error.localizedDescription)"
                    }
                }
            }
            return firstError
        }.value

        await loadHistory(for: selectedDiskID)

        let pendingNotifications = notificationPolicy.evaluate(
            disks: reconciled,
            notificationsEnabled: settings.notificationsEnabled
        )
        if let notifications {
            for notification in pendingNotifications {
                notifications.post(notification)
            }
        }

        errorMessage = historyError
    }

    private static func message(for error: Error) -> String {
        if let smartctlError = error as? SmartctlError {
            return smartctlError.errorDescription ?? smartctlError.localizedDescription
        }
        return "Unable to refresh disks: \(error.localizedDescription)"
    }

    private func loadHistory(for diskID: String?) async {
        guard let diskID else {
            historySamples = []
            return
        }

        let history = self.history
        let samples = await Task.detached(priority: .utility) {
            (try? history.samples(for: diskID)) ?? []
        }.value

        if selectedDiskID == diskID {
            historySamples = samples
        }
    }

    private func reconcile(_ scanned: [DiskInfo]) -> [DiskInfo] {
        scanned.map { disk in
            guard disk.health == .unknown else {
                failureCounts[disk.id] = 0
                return disk
            }

            guard let previous = disks.first(where: { $0.bsdName == disk.bsdName }) else {
                failureCounts[disk.id] = max(failureCounts[disk.id] ?? 0, 1)
                return disk
            }

            let failures = (failureCounts[previous.id] ?? 0) + 1
            failureCounts[previous.id] = failures

            if failures < 2 {
                return staleCopy(of: previous, error: disk.readError, failures: failures)
            }

            return unknownCopy(of: previous, error: disk.readError, failures: failures)
        }
    }

    private func staleCopy(of previous: DiskInfo, error: String?, failures: Int) -> DiskInfo {
        DiskInfo(
            id: previous.id,
            bsdName: previous.bsdName,
            model: previous.model,
            serial: previous.serial,
            firmware: previous.firmware,
            protocolName: previous.protocolName,
            interfaceName: previous.interfaceName,
            capacityBytes: previous.capacityBytes,
            isInternal: previous.isInternal,
            smartStatus: previous.smartStatus,
            health: previous.health,
            temperatureCelsius: previous.temperatureCelsius,
            temperatureWarningCelsius: previous.temperatureWarningCelsius,
            temperatureCriticalCelsius: previous.temperatureCriticalCelsius,
            lifePercent: previous.lifePercent,
            powerOnHours: previous.powerOnHours,
            powerCycleCount: previous.powerCycleCount,
            unsafeShutdowns: previous.unsafeShutdowns,
            mediaErrors: previous.mediaErrors,
            attributes: previous.attributes,
            readError: error,
            isStale: true,
            consecutiveFailures: failures,
            healthReasons: previous.healthReasons,
            diagnostics: previous.diagnostics
        )
    }

    private func unknownCopy(of previous: DiskInfo, error: String?, failures: Int) -> DiskInfo {
        let reason = error ?? "SMART data could not be read."
        return DiskInfo(
            id: previous.id,
            bsdName: previous.bsdName,
            model: previous.model,
            serial: previous.serial,
            firmware: previous.firmware,
            protocolName: previous.protocolName,
            interfaceName: previous.interfaceName,
            capacityBytes: previous.capacityBytes,
            isInternal: previous.isInternal,
            smartStatus: .unknown,
            health: .unknown,
            temperatureCelsius: nil,
            temperatureWarningCelsius: previous.temperatureWarningCelsius,
            temperatureCriticalCelsius: previous.temperatureCriticalCelsius,
            lifePercent: nil,
            powerOnHours: nil,
            powerCycleCount: nil,
            unsafeShutdowns: nil,
            mediaErrors: nil,
            attributes: [],
            readError: reason,
            isStale: true,
            consecutiveFailures: failures,
            healthReasons: [reason],
            diagnostics: []
        )
    }
}

private final class PreviewScanner: DiskScanning {
    private let disks: [DiskInfo]

    init(disks: [DiskInfo]) {
        self.disks = disks
    }

    func scan(policy: TemperaturePolicy) throws -> [DiskInfo] {
        disks
    }
}

private final class PreviewHistoryStore: HistoryStoring {
    func append(_ sample: HistorySample, for diskID: String) throws {}
    func samples(for diskID: String) throws -> [HistorySample] {
        PreviewData.historySamples(for: diskID)
    }
    func prune(now: Date) throws {}
}

extension DiskMonitor {
    public static var live: DiskMonitor {
        let settingsStore = SettingsStore()
        return DiskMonitor(
            scanner: DiskScanner(),
            history: JSONHistoryStore(),
            notifications: NotificationService(),
            settings: settingsStore.load(),
            settingsStore: settingsStore
        )
    }

    public static var preview: DiskMonitor {
        let disks = PreviewData.disks
        return DiskMonitor(
            previewDisks: disks,
            selectedDiskID: disks.first?.id,
            lastRefresh: PreviewData.timestamp,
            historySamples: PreviewData.appleHistory
        )
    }
}

private enum PreviewData {
    static let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    static let disks: [DiskInfo] = [appleSSD, intelSSD]

    static let appleHistory = historySamples(for: "REDACTED|APPLE SSD AP0256Z")

    static func historySamples(for diskID: String) -> [HistorySample] {
        let isIntel = diskID.localizedCaseInsensitiveContains("INTEL")
        let baseTemperature = isIntel ? 41 : 36
        let life = isIntel ? 97 : 95
        let hours = isIntel ? 12236 : 1695

        return (0..<288).map { index in
            let sampleTime = timestamp.addingTimeInterval(
                -Double(287 - index) * 300
            )
            let temperature = baseTemperature
                + Int((sin(Double(index) / 18.0) * 2).rounded())
            return HistorySample(
                timestamp: sampleTime,
                health: .good,
                temperatureCelsius: temperature,
                lifePercent: life,
                powerOnHours: hours
            )
        }
    }

    private static let appleSSD = DiskInfo(
        id: "REDACTED|APPLE SSD AP0256Z",
        bsdName: "disk0",
        model: "APPLE SSD AP0256Z",
        serial: "REDACTED",
        firmware: "241.0.12",
        protocolName: "NVMe",
        interfaceName: "Apple Fabric",
        capacityBytes: 251_000_193_024,
        isInternal: true,
        smartStatus: .passed,
        health: .good,
        temperatureCelsius: 36,
        temperatureWarningCelsius: 50,
        temperatureCriticalCelsius: 60,
        lifePercent: 95,
        powerOnHours: 1695,
        powerCycleCount: 162,
        unsafeShutdowns: 8,
        mediaErrors: 0,
        attributes: appleAttributes,
        readError: nil
    )

    private static let intelSSD = DiskInfo(
        id: "REDACTED|INTEL SSDPEKNW512G8",
        bsdName: "disk4",
        model: "INTEL SSDPEKNW512G8",
        serial: "REDACTED",
        firmware: "002C",
        protocolName: "NVMe",
        interfaceName: "PCI-Express",
        capacityBytes: 512_110_190_592,
        isInternal: false,
        smartStatus: .passed,
        health: .good,
        temperatureCelsius: 41,
        temperatureWarningCelsius: 77,
        temperatureCriticalCelsius: 80,
        lifePercent: 97,
        powerOnHours: 12236,
        powerCycleCount: 7292,
        unsafeShutdowns: 103,
        mediaErrors: 0,
        attributes: intelAttributes,
        readError: nil
    )

    private static let appleAttributes: [SmartAttribute] = [
        SmartAttribute(
            id: 1,
            name: "Critical Warning",
            current: nil,
            worst: nil,
            threshold: nil,
            rawValue: 0,
            rawString: "0x00",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 2,
            name: "Temperature",
            current: 36,
            worst: nil,
            threshold: nil,
            rawValue: 36,
            rawString: "36 °C",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 3,
            name: "Available Spare",
            current: 100,
            worst: nil,
            threshold: 99,
            rawValue: 100,
            rawString: "100%",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 5,
            name: "Percentage Used",
            current: 5,
            worst: nil,
            threshold: nil,
            rawValue: 5,
            rawString: "5%",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 12,
            name: "Power On Hours",
            current: nil,
            worst: nil,
            threshold: nil,
            rawValue: 1695,
            rawString: "1,695 h",
            isPrefailure: false
        )
    ]

    private static let intelAttributes: [SmartAttribute] = [
        SmartAttribute(
            id: 1,
            name: "Critical Warning",
            current: nil,
            worst: nil,
            threshold: nil,
            rawValue: 0,
            rawString: "0x00",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 2,
            name: "Temperature",
            current: 41,
            worst: nil,
            threshold: nil,
            rawValue: 41,
            rawString: "41 °C",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 3,
            name: "Available Spare",
            current: 100,
            worst: nil,
            threshold: 10,
            rawValue: 100,
            rawString: "100%",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 5,
            name: "Percentage Used",
            current: 3,
            worst: nil,
            threshold: nil,
            rawValue: 3,
            rawString: "3%",
            isPrefailure: true
        ),
        SmartAttribute(
            id: 12,
            name: "Power On Hours",
            current: nil,
            worst: nil,
            threshold: nil,
            rawValue: 12236,
            rawString: "12,236 h",
            isPrefailure: false
        )
    ]
}
