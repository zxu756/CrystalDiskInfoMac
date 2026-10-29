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

    public func selectDisk(id: String) {
        guard disks.contains(where: { $0.id == id }) else {
            return
        }
        selectedDiskID = id
    }

    public func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let scanner = self.scanner
        let policy = settings.temperaturePolicy

        let scanned: [DiskInfo]
        do {
            scanned = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(policy: policy)
            }.value
        } catch {
            errorMessage = Self.message(for: error)
            return
        }

        applyScan(scanned)
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

    private func applyScan(_ scanned: [DiskInfo]) {
        let timestamp = now()
        disks = scanned
        lastRefresh = timestamp

        if selectedDiskID == nil || !scanned.contains(where: { $0.id == selectedDiskID }) {
            selectedDiskID = scanned.first?.id
        }

        var historyError: String?
        for disk in scanned {
            let sample = HistorySample(
                timestamp: timestamp,
                health: disk.health,
                temperatureCelsius: disk.temperatureCelsius,
                lifePercent: disk.lifePercent,
                powerOnHours: disk.powerOnHours
            )
            do {
                try history.append(sample, for: disk.id)
            } catch {
                if historyError == nil {
                    historyError = "Could not save history: \(error.localizedDescription)"
                }
            }
        }

        let pendingNotifications = notificationPolicy.evaluate(
            disks: scanned,
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
}
