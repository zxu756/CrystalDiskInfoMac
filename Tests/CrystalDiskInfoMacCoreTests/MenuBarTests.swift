import Testing
import Foundation
import SwiftUI
import UserNotifications
@testable import CrystalDiskInfoMacCore

struct MenuBarTests {
    private final class FakeNotificationCenter: UserNotificationCentering, @unchecked Sendable {
        var delegate: UNUserNotificationCenterDelegate?
        var authorizationRequests = 0
        var requests: [UNNotificationRequest] = []

        func requestAuthorization(
            options: UNAuthorizationOptions,
            completionHandler: @escaping @Sendable (Bool, Error?) -> Void
        ) {
            authorizationRequests += 1
            completionHandler(true, nil)
        }

        func add(
            _ request: UNNotificationRequest,
            withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
        ) {
            requests.append(request)
            completionHandler?(nil)
        }
    }

    @Test func hottestTemperaturePicksHighestValidValue() {
        let disks = [
            TestFixtures.disk(id: "a", temperatureCelsius: 36),
            TestFixtures.disk(id: "b", temperatureCelsius: 41),
            TestFixtures.disk(id: "c", temperatureCelsius: nil),
            TestFixtures.disk(id: "d", temperatureCelsius: 200)
        ]

        #expect(MenuBarSummary.hottestTemperature(in: disks) == 41)

        let label = MenuBarSummary.label(for: disks, showTemperature: true)
        #expect(label.title == "41°")
        #expect(label.systemImage == "thermometer.medium")
    }

    @Test func menuBarLabelUsesNeutralIconWithoutTemperature() {
        let disks = [TestFixtures.disk(temperatureCelsius: nil)]

        #expect(MenuBarSummary.hottestTemperature(in: disks) == nil)

        let label = MenuBarSummary.label(for: disks, showTemperature: true)
        #expect(label.title == nil)
        #expect(label.systemImage == "internaldrive")

        let hidden = MenuBarSummary.label(
            for: [TestFixtures.disk(temperatureCelsius: 41)],
            showTemperature: false
        )
        #expect(hidden.title == nil)
        #expect(hidden.systemImage == "internaldrive")
    }

    @Test func diskTitleIncludesHealthTemperatureAndLife() {
        let disk = TestFixtures.disk(
            model: "Test Disk",
            health: .caution,
            temperatureCelsius: 55,
            lifePercent: 88
        )

        #expect(
            MenuBarSummary.diskTitle(for: disk)
                == "Test Disk · Caution · 55 °C · 88% life"
        )
    }

    @MainActor
    @Test func menuBarViewRendersWithTwoDisks() {
        let renderer = ImageRenderer(
            content: MenuBarView(
                model: .preview,
                onOpen: { _ in },
                onSettings: {},
                onQuit: {}
            )
            .frame(width: 380, height: 220)
        )

        #expect(renderer.nsImage != nil)
    }

    @Test func notificationServiceRequestsAuthorizationOnceAndDeliversContent() {
        let center = FakeNotificationCenter()
        let service = NotificationService(center: center)
        let notification = DiskNotification(
            kind: .health,
            diskID: "disk-id",
            diskName: "Test Disk",
            title: "Test Disk health changed",
            body: "Health changed from Good to Bad."
        )

        service.post(notification)
        service.post(notification)

        #expect(center.authorizationRequests == 1)
        #expect(center.requests.count == 2)
        #expect(center.delegate != nil)
        #expect(center.requests.first?.content.title == "Test Disk health changed")
        #expect(center.requests.first?.content.body == "Health changed from Good to Bad.")
        #expect(center.requests.first?.content.sound != nil)
    }
}
