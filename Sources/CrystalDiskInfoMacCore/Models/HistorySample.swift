import Foundation

public struct HistorySample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let health: HealthStatus
    public let temperatureCelsius: Int?
    public let lifePercent: Int?
    public let powerOnHours: Int?

    public init(
        timestamp: Date,
        health: HealthStatus,
        temperatureCelsius: Int?,
        lifePercent: Int?,
        powerOnHours: Int?
    ) {
        self.timestamp = timestamp
        self.health = health
        self.temperatureCelsius = temperatureCelsius
        self.lifePercent = lifePercent
        self.powerOnHours = powerOnHours
    }
}
