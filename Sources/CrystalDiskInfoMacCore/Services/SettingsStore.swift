import Foundation

public protocol SettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public final class SettingsStore: SettingsStoring {
    public static let defaultKey = "CrystalDiskInfoMac.settings.v1"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = SettingsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .standard
        }
        return settings.validated()
    }

    public func save(_ settings: AppSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(settings.validated()) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
