import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct NotificationPolicyTests {
    private func disk(
        id: String = "disk-id",
        health: HealthStatus = .good,
        temperature: Int? = 40,
        warning: Int = 50,
        critical: Int = 60
    ) -> DiskInfo {
        TestFixtures.disk(
            id: id,
            health: health,
            temperatureCelsius: temperature,
            temperatureWarningCelsius: warning,
            temperatureCriticalCelsius: critical
        )
    }

    @Test func goodToBadNotifiesOnce() {
        let policy = NotificationPolicy()

        #expect(policy.evaluate(disks: [disk(health: .good)]).isEmpty)

        let notifications = policy.evaluate(disks: [disk(health: .bad)])
        #expect(notifications.count == 1)
        #expect(notifications.first?.kind == .health)
        #expect(notifications.first?.body.contains("Good") == true)
        #expect(notifications.first?.body.contains("Bad") == true)

        #expect(policy.evaluate(disks: [disk(health: .bad)]).isEmpty)
    }

    @Test func firstLaunchBadDoesNotNotify() {
        let policy = NotificationPolicy()

        #expect(policy.evaluate(disks: [disk(health: .bad)]).isEmpty)
        #expect(policy.evaluate(disks: [disk(health: .bad)]).isEmpty)
    }

    @Test func singleUnknownDoesNotNotifyButSecondConsecutiveDoes() {
        let policy = NotificationPolicy()
        _ = policy.evaluate(disks: [disk(health: .good)])

        #expect(policy.evaluate(disks: [disk(health: .unknown)]).isEmpty)

        let notifications = policy.evaluate(disks: [disk(health: .unknown)])
        #expect(notifications.count == 1)
        #expect(notifications.first?.kind == .unknown)

        #expect(policy.evaluate(disks: [disk(health: .unknown)]).isEmpty)
    }

    @Test func removalAfterTwoMissesNotifiesOnce() {
        let policy = NotificationPolicy()
        let present = disk()
        _ = policy.evaluate(disks: [present])

        #expect(policy.evaluate(disks: []).isEmpty)

        let notifications = policy.evaluate(disks: [])
        #expect(notifications.count == 1)
        #expect(notifications.first?.kind == .removed)
        #expect(notifications.first?.diskName == "Test Disk")

        #expect(policy.evaluate(disks: []).isEmpty)
    }

    @Test func reappearanceResetsMissingCount() {
        let policy = NotificationPolicy()
        let present = disk()
        _ = policy.evaluate(disks: [present])

        #expect(policy.evaluate(disks: []).isEmpty)
        #expect(policy.evaluate(disks: [present]).isEmpty)
        #expect(policy.evaluate(disks: []).isEmpty)

        let notifications = policy.evaluate(disks: [])
        #expect(notifications.count == 1)
        #expect(notifications.first?.kind == .removed)
    }

    @Test func temperatureCrossingUsesEffectiveLimits() {
        let policy = NotificationPolicy()

        #expect(policy.evaluate(disks: [disk(temperature: 40, warning: 50, critical: 60)]).isEmpty)

        let warning = policy.evaluate(disks: [disk(temperature: 50, warning: 50, critical: 60)])
        #expect(warning.count == 1)
        #expect(warning.first?.kind == .temperature)
        #expect(warning.first?.body.contains("50 °C") == true)
        #expect(warning.first?.body.contains("warning") == true)

        #expect(policy.evaluate(disks: [disk(temperature: 50, warning: 50, critical: 60)]).isEmpty)

        let critical = policy.evaluate(disks: [disk(temperature: 60, warning: 50, critical: 60)])
        #expect(critical.count == 1)
        #expect(critical.first?.kind == .temperature)
        #expect(critical.first?.body.contains("60 °C") == true)
        #expect(critical.first?.body.contains("critical") == true)
    }

    @Test func temperatureUsesPerDiskReportedLimits() {
        let policy = NotificationPolicy()

        #expect(policy.evaluate(disks: [disk(temperature: 40, warning: 70, critical: 80)]).isEmpty)

        let notifications = policy.evaluate(
            disks: [disk(temperature: 72, warning: 70, critical: 80)]
        )
        #expect(notifications.count == 1)
        #expect(notifications.first?.body.contains("70 °C") == true)
    }

    @Test func disabledNotificationsUpdateStateWithoutPosting() {
        let policy = NotificationPolicy()
        _ = policy.evaluate(disks: [disk(health: .good)])

        #expect(
            policy.evaluate(
                disks: [disk(health: .bad)],
                notificationsEnabled: false
            ).isEmpty
        )
        #expect(
            policy.evaluate(
                disks: [disk(health: .bad)],
                notificationsEnabled: true
            ).isEmpty
        )
    }

    @Test func cautionTransitionNotifiesAndImprovementDoesNot() {
        let policy = NotificationPolicy()
        _ = policy.evaluate(disks: [disk(health: .good)])

        let caution = policy.evaluate(disks: [disk(health: .caution)])
        #expect(caution.count == 1)
        #expect(caution.first?.kind == .health)

        #expect(policy.evaluate(disks: [disk(health: .good)]).isEmpty)
    }
}
