import Foundation

public enum DiskMapper {
    public static func map(
        candidate: DiskCandidate,
        report: SmartctlReport,
        policy: TemperaturePolicy = .standard
    ) -> DiskInfo {
        let evaluation = HealthEvaluator.evaluate(report: report, policy: policy)
        let model = nonEmpty(report.modelName) ?? candidate.mediaName
        let serial = nonEmpty(report.serialNumber)
        let firmware = nonEmpty(report.firmwareVersion) ?? "Unknown"
        let stableID = serial.map { "\($0)|\(model)" } ?? candidate.bsdName

        let reportedCapacity = report.userCapacity?.bytes ?? 0
        let capacityBytes = reportedCapacity > 0
            ? UInt64(reportedCapacity)
            : candidate.capacityBytes

        let protocolName = nonEmpty(report.device?.deviceProtocol) ?? candidate.deviceProtocol
        let interfaceName = nonEmpty(candidate.deviceProtocol) ?? "Unknown"

        let powerOnHours = intValue(
            report.powerOnTime?.hours ?? report.nvmeSmartHealthInformationLog?.powerOnHours
        )
        let powerCycleCount = intValue(
            report.powerCycleCount ?? report.nvmeSmartHealthInformationLog?.powerCycles
        )

        return DiskInfo(
            id: stableID,
            bsdName: candidate.bsdName,
            model: model,
            serial: serial ?? "Unknown",
            firmware: firmware,
            protocolName: protocolName,
            interfaceName: interfaceName,
            capacityBytes: capacityBytes,
            isInternal: candidate.isInternal,
            smartStatus: smartStatus(report),
            health: evaluation.status,
            temperatureCelsius: evaluation.temperatureCelsius,
            lifePercent: evaluation.lifePercent,
            powerOnHours: powerOnHours,
            powerCycleCount: powerCycleCount,
            unsafeShutdowns: intValue(report.nvmeSmartHealthInformationLog?.unsafeShutdowns),
            mediaErrors: intValue(report.nvmeSmartHealthInformationLog?.mediaErrors),
            attributes: attributes(report),
            readError: readError(report: report, evaluation: evaluation)
        )
    }

    private static func smartStatus(_ report: SmartctlReport) -> SmartStatus {
        switch report.smartStatus?.passed {
        case .some(true):
            return .passed
        case .some(false):
            return .failed
        case .none:
            return .unknown
        }
    }

    private static func attributes(_ report: SmartctlReport) -> [SmartAttribute] {
        if let nvme = report.nvmeSmartHealthInformationLog {
            return nvmeAttributes(nvme)
        }
        if let table = report.ataSmartAttributes?.table {
            return ataAttributes(table)
        }
        return []
    }

    private static func nvmeAttributes(_ log: NVMeSmartLog) -> [SmartAttribute] {
        var rows: [SmartAttribute] = []

        func append(
            id: Int,
            name: String,
            current: Int? = nil,
            threshold: Int? = nil,
            raw: Int64?,
            rawString: String? = nil,
            prefailure: Bool = false
        ) {
            rows.append(
                SmartAttribute(
                    id: id,
                    name: name,
                    current: current,
                    worst: nil,
                    threshold: threshold,
                    rawValue: raw.flatMap { $0 >= 0 ? UInt64($0) : nil },
                    rawString: rawString ?? raw.map { String($0) },
                    isPrefailure: prefailure
                )
            )
        }

        append(
            id: 1,
            name: "Critical Warning",
            raw: log.criticalWarning.map { Int64($0) },
            rawString: log.criticalWarning.map { String(format: "0x%02X", $0) },
            prefailure: true
        )
        append(
            id: 2,
            name: "Temperature",
            current: log.temperature,
            raw: log.temperature.map { Int64($0) },
            rawString: log.temperature.map { "\($0) °C" },
            prefailure: true
        )
        append(
            id: 3,
            name: "Available Spare",
            current: log.availableSpare,
            threshold: log.availableSpareThreshold,
            raw: log.availableSpare.map { Int64($0) },
            rawString: log.availableSpare.map { "\($0)%" },
            prefailure: true
        )
        append(
            id: 4,
            name: "Available Spare Threshold",
            current: log.availableSpareThreshold,
            raw: log.availableSpareThreshold.map { Int64($0) },
            rawString: log.availableSpareThreshold.map { "\($0)%" }
        )
        append(
            id: 5,
            name: "Percentage Used",
            current: log.percentageUsed,
            raw: log.percentageUsed.map { Int64($0) },
            rawString: log.percentageUsed.map { "\($0)%" },
            prefailure: true
        )
        append(id: 6, name: "Data Units Read", raw: log.dataUnitsRead)
        append(id: 7, name: "Data Units Written", raw: log.dataUnitsWritten)
        append(id: 8, name: "Host Read Commands", raw: log.hostReads)
        append(id: 9, name: "Host Write Commands", raw: log.hostWrites)
        append(id: 10, name: "Controller Busy Time", raw: log.controllerBusyTime)
        append(id: 11, name: "Power Cycles", raw: log.powerCycles)
        append(id: 12, name: "Power On Hours", raw: log.powerOnHours, rawString: log.powerOnHours.map { "\($0) h" })
        append(id: 13, name: "Unsafe Shutdowns", raw: log.unsafeShutdowns)
        append(id: 14, name: "Media Errors", raw: log.mediaErrors)
        append(id: 15, name: "Number of Error Log Entries", raw: log.numErrLogEntries)
        append(id: 16, name: "Warning Composite Temperature Time", raw: log.warningTempTime)
        append(id: 17, name: "Critical Composite Temperature Time", raw: log.criticalCompTime)

        for (index, temperature) in (log.temperatureSensors ?? []).enumerated() {
            append(
                id: 18 + index,
                name: "Temperature Sensor \(index + 1)",
                current: temperature,
                raw: Int64(temperature),
                rawString: "\(temperature) °C",
                prefailure: true
            )
        }

        return rows
    }

    private static func ataAttributes(_ table: [AtaSmartAttribute]) -> [SmartAttribute] {
        table.map { row in
            SmartAttribute(
                id: row.id ?? 0,
                name: nonEmpty(row.name) ?? "Attribute \(row.id ?? 0)",
                current: row.value,
                worst: row.worst,
                threshold: row.thresh,
                rawValue: rawUnsigned(row),
                rawString: nonEmpty(row.raw?.string),
                isPrefailure: row.flags?.prefailure ?? false
            )
        }
    }

    private static func readError(
        report: SmartctlReport,
        evaluation: HealthEvaluation
    ) -> String? {
        let diagnostics = (report.smartctl?.messages ?? []).compactMap { message -> String? in
            guard let text = nonEmpty(message.string) else { return nil }
            switch message.severity?.lowercased() {
            case "error", "critical":
                return "smartctl: \(text)"
            default:
                return nil
            }
        }

        if !diagnostics.isEmpty {
            return diagnostics.joined(separator: "\n")
        }

        if evaluation.status == .unknown {
            let reasons = evaluation.reasons.joined(separator: " ")
            return reasons.isEmpty ? "SMART data is unavailable." : reasons
        }

        return nil
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

    private static func intValue(_ value: Int64?) -> Int? {
        guard let value else { return nil }
        return Int(clamping: value)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "unknown" else {
            return nil
        }
        return value
    }
}
