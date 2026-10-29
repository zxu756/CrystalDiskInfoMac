import Foundation

public struct DiskNotification: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case health
        case temperature
        case mediaErrors
        case unknown
        case removed
    }

    public let kind: Kind
    public let diskID: String
    public let diskName: String
    public let title: String
    public let body: String

    public init(
        kind: Kind,
        diskID: String,
        diskName: String,
        title: String,
        body: String
    ) {
        self.kind = kind
        self.diskID = diskID
        self.diskName = diskName
        self.title = title
        self.body = body
    }
}

/// Transition-based notification rules.
///
/// A disk's first observation only establishes a baseline: a pre-existing Bad
/// disk does not alert on launch. Unknown and removal alerts require two
/// consecutive observations. Repeated states do not re-alert.
public final class NotificationPolicy {
    private enum TemperatureBand: Int, Comparable {
        case normal = 0
        case warning = 1
        case critical = 2

        static func < (lhs: TemperatureBand, rhs: TemperatureBand) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct DiskState {
        var name: String
        var health: HealthStatus
        var temperatureBand: TemperatureBand
        var mediaErrors: Int? = nil
        var unknownCount = 0
        var unknownNotified = false
        var missingCount = 0
    }

    private var states: [String: DiskState] = [:]

    public init() {}

    public func reset() {
        states.removeAll()
    }

    public func evaluate(
        disks: [DiskInfo],
        notificationsEnabled: Bool = true
    ) -> [DiskNotification] {
        var notifications: [DiskNotification] = []
        var presentIDs = Set<String>()

        for disk in disks {
            presentIDs.insert(disk.id)
            let band = temperatureBand(for: disk)

            if var state = states[disk.id] {
                state.name = disk.model
                state.missingCount = 0

                if disk.health == .unknown {
                    state.unknownCount += 1
                    let reachedFailureGrace = disk.consecutiveFailures >= 2
                    if (state.unknownCount == 2 || reachedFailureGrace), !state.unknownNotified {
                        state.unknownNotified = true
                        if notificationsEnabled {
                            notifications.append(unknownNotification(for: disk))
                        }
                    }
                } else {
                    state.unknownCount = 0
                    state.unknownNotified = false

                    let worsened = disk.health > state.health
                    if worsened, disk.health == .caution || disk.health == .bad {
                        if notificationsEnabled {
                            notifications.append(
                                healthNotification(for: disk, previous: state.health)
                            )
                        }
                    }
                }

                if let mediaErrors = disk.mediaErrors {
                    if let previousErrors = state.mediaErrors,
                       mediaErrors > previousErrors,
                       notificationsEnabled {
                        notifications.append(
                            mediaErrorNotification(
                                for: disk,
                                previous: previousErrors,
                                current: mediaErrors
                            )
                        )
                    }
                    state.mediaErrors = mediaErrors
                }

                if notificationsEnabled,
                   let band,
                   band > state.temperatureBand {
                    notifications.append(temperatureNotification(for: disk, band: band))
                }

                if let band {
                    state.temperatureBand = band
                }
                state.health = disk.health
                states[disk.id] = state
            } else {
                var state = DiskState(
                    name: disk.model,
                    health: disk.health,
                    temperatureBand: band ?? .normal
                )
                state.mediaErrors = disk.mediaErrors
                if disk.health == .unknown {
                    state.unknownCount = 1
                }
                states[disk.id] = state
            }
        }

        for (id, var state) in states where !presentIDs.contains(id) {
            state.missingCount += 1
            if state.missingCount >= 2 {
                if notificationsEnabled {
                    notifications.append(removedNotification(diskID: id, name: state.name))
                }
                states.removeValue(forKey: id)
            } else {
                states[id] = state
            }
        }

        return notifications
    }

    private func temperatureBand(for disk: DiskInfo) -> TemperatureBand? {
        guard let temperature = disk.temperatureCelsius else {
            return nil
        }
        if temperature >= disk.temperatureCriticalCelsius {
            return .critical
        }
        if temperature >= disk.temperatureWarningCelsius {
            return .warning
        }
        return .normal
    }

    private func healthNotification(
        for disk: DiskInfo,
        previous: HealthStatus
    ) -> DiskNotification {
        DiskNotification(
            kind: .health,
            diskID: disk.id,
            diskName: disk.model,
            title: "\(disk.model) health changed",
            body: "Health changed from \(label(previous)) to \(label(disk.health))."
        )
    }

    private func temperatureNotification(
        for disk: DiskInfo,
        band: TemperatureBand
    ) -> DiskNotification {
        let isCritical = band == .critical
        let limit = isCritical
            ? disk.temperatureCriticalCelsius
            : disk.temperatureWarningCelsius
        let temperature = disk.temperatureCelsius ?? 0

        return DiskNotification(
            kind: .temperature,
            diskID: disk.id,
            diskName: disk.model,
            title: "\(disk.model) temperature \(isCritical ? "critical" : "warning")",
            body: "Temperature is \(temperature) °C; the \(isCritical ? "critical" : "warning") limit is \(limit) °C."
        )
    }

    private func mediaErrorNotification(
        for disk: DiskInfo,
        previous: Int,
        current: Int
    ) -> DiskNotification {
        DiskNotification(
            kind: .mediaErrors,
            diskID: disk.id,
            diskName: disk.model,
            title: "\(disk.model) media errors increased",
            body: "Media errors increased from \(previous) to \(current)."
        )
    }

    private func unknownNotification(for disk: DiskInfo) -> DiskNotification {
        DiskNotification(
            kind: .unknown,
            diskID: disk.id,
            diskName: disk.model,
            title: "\(disk.model) health is unknown",
            body: "SMART data could not be read for two consecutive refreshes."
        )
    }

    private func removedNotification(diskID: String, name: String) -> DiskNotification {
        DiskNotification(
            kind: .removed,
            diskID: diskID,
            diskName: name,
            title: "\(name) is no longer available",
            body: "The disk was not found for two consecutive refreshes."
        )
    }

    private func label(_ status: HealthStatus) -> String {
        switch status {
        case .good: return "Good"
        case .caution: return "Caution"
        case .bad: return "Bad"
        case .unknown: return "Unknown"
        }
    }
}
