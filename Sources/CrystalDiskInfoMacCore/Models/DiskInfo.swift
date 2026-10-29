import Foundation

public enum SmartStatus: String, Codable, CaseIterable, Sendable {
    case passed
    case failed
    case unknown
}

public struct SmartAttribute: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let current: Int?
    public let worst: Int?
    public let threshold: Int?
    public let rawValue: UInt64?
    public let rawString: String?
    public let isPrefailure: Bool

    public init(
        id: Int,
        name: String,
        current: Int?,
        worst: Int?,
        threshold: Int?,
        rawValue: UInt64?,
        rawString: String?,
        isPrefailure: Bool
    ) {
        self.id = id
        self.name = name
        self.current = current
        self.worst = worst
        self.threshold = threshold
        self.rawValue = rawValue
        self.rawString = rawString
        self.isPrefailure = isPrefailure
    }

    /// A prefailure attribute at or below its nonzero threshold is a warning row.
    public var isWarning: Bool {
        guard isPrefailure, let current, let threshold, threshold > 0 else {
            return false
        }
        return current <= threshold
    }
}

public struct DiskInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let bsdName: String
    public let model: String
    public let serial: String
    public let firmware: String
    public let protocolName: String
    public let interfaceName: String
    public let capacityBytes: UInt64
    public let isInternal: Bool
    public let smartStatus: SmartStatus
    public let health: HealthStatus
    public let temperatureCelsius: Int?
    public let temperatureWarningCelsius: Int
    public let temperatureCriticalCelsius: Int
    public let lifePercent: Int?
    public let powerOnHours: Int?
    public let powerCycleCount: Int?
    public let unsafeShutdowns: Int?
    public let mediaErrors: Int?
    public let attributes: [SmartAttribute]
    public let readError: String?

    public init(
        id: String,
        bsdName: String,
        model: String,
        serial: String,
        firmware: String,
        protocolName: String,
        interfaceName: String,
        capacityBytes: UInt64,
        isInternal: Bool,
        smartStatus: SmartStatus,
        health: HealthStatus,
        temperatureCelsius: Int?,
        temperatureWarningCelsius: Int,
        temperatureCriticalCelsius: Int,
        lifePercent: Int?,
        powerOnHours: Int?,
        powerCycleCount: Int?,
        unsafeShutdowns: Int?,
        mediaErrors: Int?,
        attributes: [SmartAttribute],
        readError: String?
    ) {
        self.id = id
        self.bsdName = bsdName
        self.model = model
        self.serial = serial
        self.firmware = firmware
        self.protocolName = protocolName
        self.interfaceName = interfaceName
        self.capacityBytes = capacityBytes
        self.isInternal = isInternal
        self.smartStatus = smartStatus
        self.health = health
        self.temperatureCelsius = temperatureCelsius
        self.temperatureWarningCelsius = temperatureWarningCelsius
        self.temperatureCriticalCelsius = temperatureCriticalCelsius
        self.lifePercent = lifePercent
        self.powerOnHours = powerOnHours
        self.powerCycleCount = powerCycleCount
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.attributes = attributes
        self.readError = readError
    }
}
