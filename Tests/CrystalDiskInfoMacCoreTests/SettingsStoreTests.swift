import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct SettingsStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "cdi-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, suite)
    }

    @Test func roundTripsSettings() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, key: "settings")
        let settings = AppSettings(
            refreshMinutes: 10,
            temperaturePolicy: TemperaturePolicy(
                useDriveLimits: false,
                warningCelsius: 45,
                criticalCelsius: 55
            ),
            showMenuBarTemperature: true,
            notificationsEnabled: false,
            launchAtLogin: true
        )

        store.save(settings)

        #expect(store.load() == settings)
    }

    @Test func invalidValuesFallBackWithoutLosingOtherFields() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, key: "settings")
        let invalid = AppSettings(
            refreshMinutes: 3,
            temperaturePolicy: TemperaturePolicy(
                useDriveLimits: true,
                warningCelsius: 70,
                criticalCelsius: 60
            ),
            showMenuBarTemperature: true,
            notificationsEnabled: false,
            launchAtLogin: true
        )

        store.save(invalid)

        let loaded = store.load()
        #expect(loaded.refreshMinutes == 5)
        #expect(loaded.temperaturePolicy.warningCelsius == 50)
        #expect(loaded.temperaturePolicy.criticalCelsius == 60)
        #expect(loaded.temperaturePolicy.useDriveLimits == true)
        #expect(loaded.showMenuBarTemperature == true)
        #expect(loaded.notificationsEnabled == false)
        #expect(loaded.launchAtLogin == true)
    }

    @Test func corruptDataFallsBackToDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, key: "settings")
        defaults.set(Data("not json".utf8), forKey: "settings")

        #expect(store.load() == .standard)
    }

    @Test func missingDataFallsBackToDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, key: "settings")

        #expect(store.load() == .standard)
    }
}
