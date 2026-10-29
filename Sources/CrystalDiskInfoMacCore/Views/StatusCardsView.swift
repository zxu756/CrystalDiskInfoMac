import SwiftUI

struct StatusCardsView: View {
    let disk: DiskInfo

    var body: some View {
        HStack(spacing: 14) {
            StatusCard(
                title: "Health",
                value: disk.health.displayName,
                subtitle: healthSubtitle,
                systemImage: disk.health.symbolName,
                tint: Theme.healthColor(disk.health)
            )

            StatusCard(
                title: "Temperature",
                value: disk.temperatureCelsius.map { "\($0) °C" } ?? "—",
                subtitle: "Warning \(disk.temperatureWarningCelsius) °C · Critical \(disk.temperatureCriticalCelsius) °C",
                systemImage: "thermometer.medium",
                tint: Theme.temperatureColor(
                    disk.temperatureCelsius,
                    warning: disk.temperatureWarningCelsius,
                    critical: disk.temperatureCriticalCelsius
                )
            )

            StatusCard(
                title: "Life",
                value: disk.lifePercent.map { "\($0)%" } ?? "—",
                subtitle: "Remaining life",
                systemImage: "chart.pie.fill",
                tint: Theme.lifeColor(disk.lifePercent)
            )
        }
    }

    private var healthSubtitle: String {
        switch disk.health {
        case .good:
            return disk.smartStatus == .passed
                ? "SMART self-assessment passed"
                : "No health warnings"
        case .caution:
            return "Review SMART attributes"
        case .bad:
            return "Immediate attention recommended"
        case .unknown:
            return "SMART data unavailable"
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(Theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension HealthStatus {
    var displayName: String {
        switch self {
        case .good: return "Good"
        case .caution: return "Caution"
        case .bad: return "Bad"
        case .unknown: return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .good: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.shield.fill"
        case .bad: return "xmark.shield.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

extension SmartStatus {
    var displayName: String {
        switch self {
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        }
    }
}
