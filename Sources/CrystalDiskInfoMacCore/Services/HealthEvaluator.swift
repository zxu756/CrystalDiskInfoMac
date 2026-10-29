import Foundation

public struct TemperaturePolicy: Codable, Equatable, Sendable {
    public var useDriveLimits: Bool
    public var warningCelsius: Int
    public var criticalCelsius: Int

    public static let standard = TemperaturePolicy()

    public init(
        useDriveLimits: Bool = true,
        warningCelsius: Int = 50,
        criticalCelsius: Int = 60
    ) {
        self.useDriveLimits = useDriveLimits
        self.warningCelsius = warningCelsius
        self.criticalCelsius = criticalCelsius
    }
}

public struct HealthEvaluation: Equatable, Sendable {
    public let status: HealthStatus
    public let reasons: [String]
    public let effectiveWarning: Int
    public let effectiveCritical: Int
    public let lifePercent: Int?
    public let temperatureCelsius: Int?

    public init(
        status: HealthStatus,
        reasons: [String],
        effectiveWarning: Int,
        effectiveCritical: Int,
        lifePercent: Int?,
        temperatureCelsius: Int?
    ) {
        self.status = status
        self.reasons = reasons
        self.effectiveWarning = effectiveWarning
        self.effectiveCritical = effectiveCritical
        self.lifePercent = lifePercent
        self.temperatureCelsius = temperatureCelsius
    }
}

public enum HealthEvaluator {
    public static func evaluate(
        report: SmartctlReport,
        policy: TemperaturePolicy = .standard
    ) -> HealthEvaluation {
        let temperature = resolveTemperature(report)
        let (warning, critical) = effectiveLimits(report: report, policy: policy)
        let nvme = report.nvmeSmartHealthInformationLog
        let attributes = report.ataSmartAttributes?.table ?? []

        let hasAssessment = report.smartStatus?.passed != nil
        let hasSMART = hasAssessment || nvme != nil || !attributes.isEmpty

        var status: HealthStatus = hasSMART ? .good : .unknown
        var reasons: [String] = []

        if !hasSMART {
            reasons.append("SMART data is unavailable.")
        }

        if report.smartStatus?.passed == false {
            status = max(status, .bad)
            reasons.append("SMART self-assessment failed.")
        }

        if let nvme {
            if let criticalWarning = nvme.criticalWarning, criticalWarning != 0 {
                status = max(status, .bad)
                reasons.append("NVMe critical warning is set (0x\(String(criticalWarning, radix: 16))).")
            }

            if let spare = nvme.availableSpare, let threshold = nvme.availableSpareThreshold {
                if spare < threshold {
                    status = max(status, .bad)
                    reasons.append("Available spare \(spare)% is below threshold \(threshold)%.")
                } else if spare == threshold, threshold != 100 {
                    status = max(status, .caution)
                    reasons.append("Available spare \(spare)% is at threshold \(threshold)%.")
                }
            }

            if let mediaErrors = nvme.mediaErrors, mediaErrors > 0 {
                status = max(status, .caution)
                reasons.append("Media errors: \(mediaErrors).")
            }

            if let used = nvme.percentageUsed {
                if used >= 100 {
                    status = max(status, .bad)
                    reasons.append("Percentage used \(used)% has reached its limit.")
                } else if used >= 90 {
                    status = max(status, .caution)
                    reasons.append("Percentage used is \(used)%.")
                }
            }
        }

        for attribute in attributes {
            if isPrefailure(attribute),
               let current = attribute.value,
               let threshold = attribute.thresh,
               threshold > 0,
               current <= threshold {
                status = max(status, .bad)
                reasons.append(
                    "ATA attribute \(attributeName(attribute)) is at or below its threshold (\(current) ≤ \(threshold))."
                )
            }

            if isMediaDegradationAttribute(attribute),
               let raw = rawUnsigned(attribute),
               raw > 0 {
                status = max(status, .caution)
                reasons.append("ATA attribute \(attributeName(attribute)) raw value is \(raw).")
            }
        }

        if let temperature {
            if temperature >= critical {
                status = max(status, .bad)
                reasons.append(
                    "Temperature \(temperature) °C is at or above the critical limit (\(critical) °C)."
                )
            } else if temperature >= warning {
                status = max(status, .caution)
                reasons.append(
                    "Temperature \(temperature) °C is at or above the warning limit (\(warning) °C)."
                )
            }
        }

        return HealthEvaluation(
            status: status,
            reasons: reasons,
            effectiveWarning: warning,
            effectiveCritical: critical,
            lifePercent: lifePercent(report),
            temperatureCelsius: temperature
        )
    }

    private static func effectiveLimits(
        report: SmartctlReport,
        policy: TemperaturePolicy
    ) -> (warning: Int, critical: Int) {
        guard policy.useDriveLimits else {
            return (policy.warningCelsius, policy.criticalCelsius)
        }
        guard let warning = report.temperature?.opLimitMax,
              let critical = report.temperature?.criticalLimitMax,
              warning < critical else {
            return (policy.warningCelsius, policy.criticalCelsius)
        }
        return (warning, critical)
    }

    private static func resolveTemperature(_ report: SmartctlReport) -> Int? {
        if let current = report.temperature?.current {
            return current
        }
        if let nvmeTemperature = report.nvmeSmartHealthInformationLog?.temperature {
            return nvmeTemperature
        }
        for id in [194, 190] {
            if let attribute = report.ataSmartAttributes?.table?.first(where: { $0.id == id }),
               let temperature = temperatureFromAttribute(attribute) {
                return temperature
            }
        }
        return nil
    }

    private static func temperatureFromAttribute(_ attribute: AtaSmartAttribute) -> Int? {
        if let string = attribute.raw?.string,
           let parsed = leadingInteger(string),
           (0...120).contains(Int(parsed)) {
            return Int(parsed)
        }

        if let raw = attribute.raw?.value, raw >= 0 {
            let lowByte = Int(raw & 0xFF)
            if (0...120).contains(lowByte) {
                return lowByte
            }
            let whole = Int(clamping: raw)
            if (0...120).contains(whole) {
                return whole
            }
        }

        return nil
    }

    private static func lifePercent(_ report: SmartctlReport) -> Int? {
        if let used = report.nvmeSmartHealthInformationLog?.percentageUsed {
            return min(100, max(0, 100 - used))
        }

        guard let attributes = report.ataSmartAttributes?.table, !attributes.isEmpty else {
            return nil
        }

        let preferredNames = [
            "percent_lifetime_remain",
            "media_wearout_indicator",
            "ssd_life_left",
            "remaining_lifetime_perc"
        ]
        for preferred in preferredNames {
            if let attribute = attributes.first(where: { normalizedName($0.name) == preferred }),
               let value = lifeValue(attribute) {
                return value
            }
        }

        for id in [202, 233, 231] {
            if let attribute = attributes.first(where: { $0.id == id }),
               let value = lifeValue(attribute) {
                return value
            }
        }

        return nil
    }

    private static func lifeValue(_ attribute: AtaSmartAttribute) -> Int? {
        if let current = attribute.value, (0...100).contains(current) {
            return current
        }
        if let raw = rawUnsigned(attribute), raw <= 100 {
            return Int(raw)
        }
        return nil
    }

    private static func normalizedName(_ name: String?) -> String {
        (name ?? "")
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func isPrefailure(_ attribute: AtaSmartAttribute) -> Bool {
        if let prefailure = attribute.flags?.prefailure {
            return prefailure
        }
        return attribute.flags?.string?.hasPrefix("P") ?? false
    }

    private static func isMediaDegradationAttribute(_ attribute: AtaSmartAttribute) -> Bool {
        if let id = attribute.id, [5, 197, 198].contains(id) {
            return true
        }
        let name = normalizedName(attribute.name)
        return name.contains("reallocated_sector")
            || name.contains("current_pending")
            || name.contains("offline_uncorrectable")
    }

    private static func attributeName(_ attribute: AtaSmartAttribute) -> String {
        if let name = attribute.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let id = attribute.id {
            return "ID \(id)"
        }
        return "unknown attribute"
    }

    private static func rawUnsigned(_ attribute: AtaSmartAttribute) -> UInt64? {
        if let value = attribute.raw?.value {
            return value >= 0 ? UInt64(value) : nil
        }
        if let parsed = leadingInteger(attribute.raw?.string), parsed >= 0 {
            return UInt64(parsed)
        }
        return nil
    }

    private static func leadingInteger(_ string: String?) -> Int64? {
        guard let string else { return nil }
        let trimmed = string.drop(while: { $0 == " " || $0 == "\t" })
        let digits = trimmed.prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : Int64(digits)
    }
}
