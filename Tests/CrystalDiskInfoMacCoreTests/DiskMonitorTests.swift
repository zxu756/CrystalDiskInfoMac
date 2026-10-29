import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

@MainActor
struct DiskMonitorTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeMonitor(
        scanner: DiskScanning,
        history: HistoryStoring = RecordingHistoryStore(),
        notifications: NotificationDelivering? = nil,
        settings: AppSettings = .standard,
        settingsStore: SettingsStoring? = nil,
        notificationPolicy: NotificationPolicy = NotificationPolicy()
    ) -> DiskMonitor {
        let now = fixedNow
        return DiskMonitor(
            scanner: scanner,
            history: history,
            notifications: notifications,
            settings: settings,
            settingsStore: settingsStore,
            notificationPolicy: notificationPolicy,
            now: { now }
        )
    }

    @Test func firstRefreshSelectsFirstDiskAndExposesAll() async {
        let disk0 = TestFixtures.disk(id: "disk0-id", bsdName: "disk0")
        let disk4 = TestFixtures.disk(id: "disk4-id", bsdName: "disk4", isInternal: false)
        let scanner = MockScanner(disks: [disk0, disk4])
        let monitor = makeMonitor(scanner: scanner)

        await monitor.refresh()

        #expect(monitor.disks.map(\.bsdName) == ["disk0", "disk4"])
        #expect(monitor.selectedDiskID == "disk0-id")
        #expect(monitor.selectedDisk?.bsdName == "disk0")
        #expect(monitor.isRefreshing == false)
        #expect(monitor.lastRefresh == fixedNow)
        #expect(monitor.errorMessage == nil)
        #expect(scanner.numberOfScans == 1)
    }

    @Test func refreshAppendsHistorySamples() async {
        let disk = TestFixtures.disk(
            id: "disk0-id",
            health: .caution,
            temperatureCelsius: 55,
            lifePercent: 90,
            powerOnHours: 123
        )
        let history = RecordingHistoryStore()
        let monitor = makeMonitor(
            scanner: MockScanner(disks: [disk]),
            history: history
        )

        await monitor.refresh()

        let samples = (try? history.samples(for: "disk0-id")) ?? []
        #expect(samples.count == 1)
        #expect(samples.first?.timestamp == fixedNow)
        #expect(samples.first?.health == .caution)
        #expect(samples.first?.temperatureCelsius == 55)
        #expect(samples.first?.lifePercent == 90)
        #expect(samples.first?.powerOnHours == 123)
        #expect(monitor.lastRefresh == fixedNow)
    }

    @Test func overlappingRefreshDoesNotStartSecondScan() async {
        let scanner = BlockingScanner(disks: [TestFixtures.disk()])
        let monitor = makeMonitor(scanner: scanner)

        let first = Task { await monitor.refresh() }
        await Task.detached { scanner.started.wait() }.value
        #expect(monitor.isRefreshing == true)

        await monitor.refresh()
        #expect(scanner.numberOfScans == 1)

        scanner.release.signal()
        await first.value

        #expect(scanner.numberOfScans == 1)
        #expect(monitor.isRefreshing == false)
    }

    @Test func missingSmartctlKeepsPriorDisksAndShowsSetupError() async {
        let disk = TestFixtures.disk(id: "disk0-id", bsdName: "disk0")
        let scanner = MockScanner(disks: [disk])
        let monitor = makeMonitor(scanner: scanner)

        await monitor.refresh()
        let firstRefresh = monitor.lastRefresh

        scanner.setResult(.failure(SmartctlError.notInstalled))
        await monitor.refresh()

        #expect(monitor.disks.count == 1)
        #expect(monitor.disks.first?.id == "disk0-id")
        #expect(monitor.errorMessage?.contains("smartmontools") == true)
        #expect(monitor.errorMessage?.contains("brew install") == true)
        #expect(monitor.lastRefresh == firstRefresh)

        scanner.setResult(.success([disk]))
        await monitor.refresh()
        #expect(monitor.errorMessage == nil)
    }

    @Test func selectedDiskStaysStableWhenStillPresent() async {
        let disk0 = TestFixtures.disk(id: "disk0-id", bsdName: "disk0")
        let disk4 = TestFixtures.disk(id: "disk4-id", bsdName: "disk4", isInternal: false)
        let scanner = MockScanner(disks: [disk0, disk4])
        let monitor = makeMonitor(scanner: scanner)

        await monitor.refresh()
        monitor.selectDisk(id: "disk4-id")
        await monitor.refresh()

        #expect(monitor.selectedDiskID == "disk4-id")
    }

    @Test func healthTransitionPostsNotificationOnce() async {
        let good = TestFixtures.disk(id: "disk-id", health: .good)
        let bad = TestFixtures.disk(id: "disk-id", health: .bad)
        let scanner = MockScanner(disks: [good])
        let notifications = RecordingNotifications()
        let monitor = makeMonitor(scanner: scanner, notifications: notifications)

        await monitor.refresh()
        #expect(notifications.posted.isEmpty)

        scanner.setResult(.success([bad]))
        await monitor.refresh()
        #expect(notifications.posted.count == 1)
        #expect(notifications.posted.first?.kind == .health)

        await monitor.refresh()
        #expect(notifications.posted.count == 1)
    }

    @Test func applySettingsUpdatesScannerPolicyAndPersists() async {
        let scanner = MockScanner(disks: [TestFixtures.disk()])
        let store = InMemorySettingsStore()
        let monitor = makeMonitor(scanner: scanner, settingsStore: store)
        let policy = TemperaturePolicy(useDriveLimits: false, warningCelsius: 45, criticalCelsius: 55)

        monitor.apply(
            settings: AppSettings(
                refreshMinutes: 10,
                temperaturePolicy: policy,
                showMenuBarTemperature: true
            )
        )
        await monitor.refresh()

        #expect(scanner.policyUsed == policy)
        #expect(monitor.settings.refreshMinutes == 10)
        #expect(store.saved?.refreshMinutes == 10)
    }

    @Test func historyFailureDoesNotDropDisks() async {
        let disk = TestFixtures.disk()
        let history = RecordingHistoryStore()
        history.setAppendError(NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "disk full"
        ]))
        let monitor = makeMonitor(
            scanner: MockScanner(disks: [disk]),
            history: history
        )

        await monitor.refresh()

        #expect(monitor.disks.count == 1)
        #expect(monitor.errorMessage?.contains("Could not save history") == true)
    }
}

private final class InMemorySettingsStore: SettingsStoring {
    var saved: AppSettings?

    func load() -> AppSettings {
        saved ?? .standard
    }

    func save(_ settings: AppSettings) {
        saved = settings
    }
}
