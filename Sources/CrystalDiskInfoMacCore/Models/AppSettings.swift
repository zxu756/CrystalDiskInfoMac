import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static let allowedRefreshMinutes = [1, 5, 10, 30, 60]
    public static let standard = AppSettings()

    public var refreshMinutes: Int
    public var temperaturePolicy: TemperaturePolicy
    public var showMenuBarTemperature: Bool
    public var notificationsEnabled: Bool
    public var launchAtLogin: Bool

    public init(
        refreshMinutes: Int = 5,
        temperaturePolicy: TemperaturePolicy = .standard,
        showMenuBarTemperature: Bool = false,
        notificationsEnabled: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.refreshMinutes = refreshMinutes
        self.temperaturePolicy = temperaturePolicy
        self.showMenuBarTemperature = showMenuBarTemperature
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
    }

    /// Returns a settings value with unsupported or unsafe fields reset to
    /// product defaults. Valid fields are preserved.
    public func validated() -> AppSettings {
        var result = self

        if !Self.allowedRefreshMinutes.contains(refreshMinutes) {
            result.refreshMinutes = 5
        }

        let warning = temperaturePolicy.warningCelsius
        let critical = temperaturePolicy.criticalCelsius
        if !(0...120).contains(warning)
            || !(0...120).contains(critical)
            || warning >= critical {
            result.temperaturePolicy = TemperaturePolicy(
                useDriveLimits: temperaturePolicy.useDriveLimits,
                warningCelsius: 50,
                criticalCelsius: 60
            )
        }

        return result
    }
}
