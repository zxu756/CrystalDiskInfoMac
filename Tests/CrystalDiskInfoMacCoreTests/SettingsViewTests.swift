import Testing
import Foundation
import SwiftUI
@testable import CrystalDiskInfoMacCore

struct SettingsViewTests {
    private final class FakeLaunchAtLogin: LaunchAtLoginManaging {
        var isEnabled: Bool
        var failure: Error?

        init(isEnabled: Bool, failure: Error? = nil) {
            self.isEnabled = isEnabled
            self.failure = failure
        }

        func setEnabled(_ enabled: Bool) throws {
            if let failure {
                throw failure
            }
            isEnabled = enabled
        }
    }

    @MainActor
    @Test func settingsViewRendersAtExpectedSize() {
        let renderer = ImageRenderer(
            content: SettingsView(
                settings: .standard,
                smartctlStatus: .available(
                    version: "7.5",
                    path: "/opt/homebrew/bin/smartctl"
                ),
                launchAtLogin: FakeLaunchAtLogin(isEnabled: false),
                onRecheck: {},
                onSave: { _ in },
                onCancel: {}
            )
        )
        renderer.proposedSize = .init(width: 560, height: 480)

        #expect(renderer.nsImage != nil)
        #expect(renderer.nsImage?.size == CGSize(width: 560, height: 480))
    }

    @MainActor
    @Test func missingSmartctlRendersSetupText() {
        #expect(SmartctlSetup.installCommand == "brew install smartmontools")

        let renderer = ImageRenderer(
            content: SettingsView(
                settings: .standard,
                smartctlStatus: .notInstalled,
                launchAtLogin: FakeLaunchAtLogin(isEnabled: false),
                onRecheck: {},
                onSave: { _ in },
                onCancel: {}
            )
        )
        renderer.proposedSize = .init(width: 560, height: 480)

        #expect(renderer.nsImage != nil)
    }

    @MainActor
    @Test func temperatureOverrideChangesEffectiveLimits() throws {
        let state = SettingsViewState(
            settings: .standard,
            launchAtLogin: FakeLaunchAtLogin(isEnabled: false)
        )

        var policy = state.draft.temperaturePolicy
        policy.useDriveLimits = false
        policy.warningCelsius = 45
        policy.criticalCelsius = 55
        state.draft.temperaturePolicy = policy

        let report = try SmartctlReport.decode(
            TestFixtures.fixtureData("disk4-intel-nvme.json")
        )
        let evaluation = HealthEvaluator.evaluate(
            report: report,
            policy: state.draft.temperaturePolicy
        )

        #expect(evaluation.effectiveWarning == 45)
        #expect(evaluation.effectiveCritical == 55)
    }

    @MainActor
    @Test func draftPreservesOtherSettings() {
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
        let state = SettingsViewState(
            settings: settings,
            launchAtLogin: FakeLaunchAtLogin(isEnabled: true)
        )

        #expect(state.draft.refreshMinutes == 10)
        #expect(state.draft.temperaturePolicy == settings.temperaturePolicy)
        #expect(state.draft.showMenuBarTemperature == true)
        #expect(state.draft.notificationsEnabled == false)
        #expect(state.draft.launchAtLogin == true)
    }

    @MainActor
    @Test func launchAtLoginSuccessUpdatesDraft() {
        let manager = FakeLaunchAtLogin(isEnabled: false)
        let state = SettingsViewState(settings: .standard, launchAtLogin: manager)

        state.setLaunchAtLogin(true, using: manager)

        #expect(state.draft.launchAtLogin == true)
        #expect(state.launchAtLoginError == nil)
    }

    @MainActor
    @Test func launchAtLoginFailureIsSurfaced() {
        let manager = FakeLaunchAtLogin(
            isEnabled: false,
            failure: LaunchAtLoginError.requiresApproval
        )
        let state = SettingsViewState(settings: .standard, launchAtLogin: manager)

        state.setLaunchAtLogin(true, using: manager)

        #expect(state.launchAtLoginError?.contains("approval") == true)
        #expect(state.draft.launchAtLogin == false)
    }
}
