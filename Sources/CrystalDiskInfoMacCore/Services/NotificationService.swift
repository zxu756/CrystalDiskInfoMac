import Foundation
import UserNotifications

public protocol NotificationDelivering {
    func post(_ notification: DiskNotification)
}

public protocol UserNotificationCentering {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: UserNotificationCentering {}

public final class NotificationService: NotificationDelivering {
    private let center: UserNotificationCentering
    private var didRequestAuthorization = false

    public init(center: UserNotificationCentering = UNUserNotificationCenter.current()) {
        self.center = center
    }

    public func post(_ notification: DiskNotification) {
        if !didRequestAuthorization {
            didRequestAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}
