import Foundation
import UserNotifications

public protocol NotificationDelivering {
    func post(_ notification: DiskNotification)
}

public protocol UserNotificationCentering: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

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

public final class NotificationService: NSObject, NotificationDelivering, UNUserNotificationCenterDelegate {
    private enum AuthorizationState {
        case notRequested
        case requesting
        case authorized
        case denied
    }

    private let center: UserNotificationCentering
    private let lock = NSLock()
    private var state: AuthorizationState = .notRequested
    private var pending: [DiskNotification] = []

    public init(center: UserNotificationCentering = UNUserNotificationCenter.current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    public func post(_ notification: DiskNotification) {
        var shouldRequest = false

        lock.lock()
        switch state {
        case .authorized:
            lock.unlock()
            deliver(notification)
            return
        case .denied:
            lock.unlock()
            return
        case .requesting:
            pending.append(notification)
            lock.unlock()
            return
        case .notRequested:
            state = .requesting
            pending.append(notification)
            shouldRequest = true
            lock.unlock()
        }

        if shouldRequest {
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                self?.finishAuthorization(granted: granted)
            }
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func finishAuthorization(granted: Bool) {
        lock.lock()
        state = granted ? .authorized : .denied
        let queued = pending
        pending.removeAll()
        lock.unlock()

        if granted {
            for notification in queued {
                deliver(notification)
            }
        }
    }

    private func deliver(_ notification: DiskNotification) {
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
