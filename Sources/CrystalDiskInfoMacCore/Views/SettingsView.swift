import SwiftUI
import Combine

@MainActor
final class SettingsViewState: ObservableObject {
    @Published var draft: AppSettings
    @Published var launchAtLoginError: String?

    init(settings: AppSettings, launchAtLogin: LaunchAtLoginManaging) {
        var draft = settings.validated()
        draft.launchAtLogin = launchAtLogin.isEnabled
        self.draft = draft
    }

    func applyLaunchAtLogin(using manager: LaunchAtLoginManaging) -> Bool {
        guard draft.launchAtLogin != manager.isEnabled else {
            launchAtLoginError = nil
            return true
        }

        do {
            try manager.setEnabled(draft.launchAtLogin)
            launchAtLoginError = nil
            return true
        } catch {
            launchAtLoginError = error.localizedDescription
            return false
        }
    }
}

public struct SettingsView: View {
    @StateObject private var state: SettingsViewState

    private let smartctlStatus: SmartctlAvailability
    private let launchAtLogin: LaunchAtLoginManaging
    private let onRecheck: () -> Void
    private let onSave: (AppSettings) -> Void
    private let onCancel: () -> Void

    public init(
        settings: AppSettings,
        smartctlStatus: SmartctlAvailability = .unknown,
        launchAtLogin: LaunchAtLoginManaging = LaunchAtLoginManager(),
        onRecheck: @escaping () -> Void = {},
        onSave: @escaping (AppSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _state = StateObject(
            wrappedValue: SettingsViewState(
                settings: settings,
                launchAtLogin: launchAtLogin
            )
        )
        self.smartctlStatus = smartctlStatus
        self.launchAtLogin = launchAtLogin
        self.onRecheck = onRecheck
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    Picker("Refresh interval", selection: $state.draft.refreshMinutes) {
                        ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                            Text(refreshLabel(minutes)).tag(minutes)
                        }
                    }

                    Toggle("Launch at login", isOn: launchAtLoginBinding)

                    if let error = state.launchAtLoginError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Temperature") {
                    Toggle("Use drive-reported limits", isOn: useDriveLimitsBinding)

                    Stepper(
                        "Warning: \(state.draft.temperaturePolicy.warningCelsius) °C",
                        value: warningBinding,
                        in: 0...120
                    )

                    Stepper(
                        "Critical: \(state.draft.temperaturePolicy.criticalCelsius) °C",
                        value: criticalBinding,
                        in: 0...120
                    )

                    Text("Global limits are used when a drive does not report its own limits.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if !isTemperatureValid {
                        Text("Warning must be below critical.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.caution)
                    }
                }

                Section("Menu Bar & Alerts") {
                    Toggle(
                        "Show hottest temperature in the menu bar",
                        isOn: $state.draft.showMenuBarTemperature
                    )
                    Toggle(
                        "Enable notifications",
                        isOn: $state.draft.notificationsEnabled
                    )
                }

                Section("History") {
                    LabeledContent(
                        "Retention",
                        value: "\(JSONHistoryStore.defaultRetentionDays) days"
                    )
                    LabeledContent(
                        "Sample cap",
                        value: "\(JSONHistoryStore.defaultMaxSamplesPerDisk.formatted()) per disk"
                    )
                }

                Section("smartctl") {
                    smartctlStatusView
                }

                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    Text("Inspired by CrystalDiskInfo (MIT, hiyohiyo). smartctl is a separate GPLv2 executable from smartmontools and is not bundled with this app.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)

                Button("Save") {
                    guard state.applyLaunchAtLogin(using: launchAtLogin) else {
                        return
                    }
                    onSave(state.draft.validated())
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isTemperatureValid)
            }
            .padding(12)
        }
        .frame(width: 560, height: 480)
    }

    private var useDriveLimitsBinding: Binding<Bool> {
        Binding(
            get: { state.draft.temperaturePolicy.useDriveLimits },
            set: { value in
                var policy = state.draft.temperaturePolicy
                policy.useDriveLimits = value
                state.draft.temperaturePolicy = policy
            }
        )
    }

    private var warningBinding: Binding<Int> {
        Binding(
            get: { state.draft.temperaturePolicy.warningCelsius },
            set: { value in
                var policy = state.draft.temperaturePolicy
                policy.warningCelsius = value
                state.draft.temperaturePolicy = policy
            }
        )
    }

    private var criticalBinding: Binding<Int> {
        Binding(
            get: { state.draft.temperaturePolicy.criticalCelsius },
            set: { value in
                var policy = state.draft.temperaturePolicy
                policy.criticalCelsius = value
                state.draft.temperaturePolicy = policy
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { state.draft.launchAtLogin },
            set: { value in
                state.draft.launchAtLogin = value
                state.launchAtLoginError = nil
            }
        )
    }

    private var isTemperatureValid: Bool {
        let policy = state.draft.temperaturePolicy
        return policy.warningCelsius < policy.criticalCelsius
            && (0...120).contains(policy.warningCelsius)
            && (0...120).contains(policy.criticalCelsius)
    }

    @ViewBuilder
    private var smartctlStatusView: some View {
        switch smartctlStatus {
        case .available(let version, let path):
            Label("smartctl \(version)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.good)

            Text(path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

        case .notInstalled:
            SmartctlSetupView(onRecheck: onRecheck)

        case .unsupported(let version):
            Label("smartctl \(version) is too old", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)

            Text("Version 7.4 or later is required. Upgrade with: brew upgrade smartmontools")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Recheck", action: onRecheck)

        case .failed(let message):
            Label("smartctl error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Recheck", action: onRecheck)

        case .unknown:
            Text("Checking smartctl…")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshLabel(_ minutes: Int) -> String {
        minutes == 1 ? "Every minute" : "Every \(minutes) minutes"
    }
}
