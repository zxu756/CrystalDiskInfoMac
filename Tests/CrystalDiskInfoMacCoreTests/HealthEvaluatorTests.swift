import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct HealthEvaluatorTests {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/\(name)"))
    }

    private func report(_ json: [String: Any]) throws -> SmartctlReport {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try SmartctlReport.decode(data)
    }

    private func nvmeReport(
        passed: Bool? = true,
        criticalWarning: Int = 0,
        temperature: Int? = 40,
        includeTemperatureBlock: Bool = true,
        spare: Int? = 100,
        spareThreshold: Int? = 10,
        percentageUsed: Int? = 3,
        mediaErrors: Int64? = 0,
        opLimit: Int? = nil,
        criticalLimit: Int? = nil
    ) throws -> SmartctlReport {
        var nvme: [String: Any] = ["critical_warning": criticalWarning]
        if let temperature { nvme["temperature"] = temperature }
        if let spare { nvme["available_spare"] = spare }
        if let spareThreshold { nvme["available_spare_threshold"] = spareThreshold }
        if let percentageUsed { nvme["percentage_used"] = percentageUsed }
        if let mediaErrors { nvme["media_errors"] = mediaErrors }

        var root: [String: Any] = [
            "model_name": "Test NVMe",
            "device": ["protocol": "NVMe"],
            "nvme_smart_health_information_log": nvme
        ]
        if let passed {
            root["smart_status"] = ["passed": passed]
        }
        if let temperature, includeTemperatureBlock {
            var block: [String: Any] = ["current": temperature]
            if let opLimit { block["op_limit_max"] = opLimit }
            if let criticalLimit { block["critical_limit_max"] = criticalLimit }
            root["temperature"] = block
        }
        return try report(root)
    }

    private func ataReport(
        passed: Bool? = true,
        attributes: [[String: Any]]
    ) throws -> SmartctlReport {
        var root: [String: Any] = [
            "model_name": "Test ATA",
            "device": ["protocol": "ATA"],
            "ata_smart_attributes": ["revision": 16, "table": attributes]
        ]
        if let passed {
            root["smart_status"] = ["passed": passed]
        }
        return try report(root)
    }

    private func attribute(
        id: Int,
        name: String,
        value: Int,
        thresh: Int = 0,
        prefailure: Bool = false,
        raw: Int64 = 0,
        rawString: String? = nil
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "value": value,
            "worst": 100,
            "thresh": thresh,
            "flags": ["prefailure": prefailure],
            "raw": ["value": raw, "string": rawString ?? "\(raw)"]
        ]
    }

    @Test func disk0FixtureIsGoodWithGlobalLimits() throws {
        let evaluation = HealthEvaluator.evaluate(report: try SmartctlReport.decode(fixture("disk0-apple-nvme.json")))

        #expect(evaluation.status == .good)
        #expect(evaluation.temperatureCelsius == 36)
        #expect(evaluation.lifePercent == 95)
        #expect(evaluation.effectiveWarning == 50)
        #expect(evaluation.effectiveCritical == 60)
        #expect(evaluation.reasons.isEmpty)
    }

    @Test func disk4FixtureIsGoodWithDriveLimits() throws {
        let evaluation = HealthEvaluator.evaluate(report: try SmartctlReport.decode(fixture("disk4-intel-nvme.json")))

        #expect(evaluation.status == .good)
        #expect(evaluation.temperatureCelsius == 41)
        #expect(evaluation.lifePercent == 97)
        #expect(evaluation.effectiveWarning == 77)
        #expect(evaluation.effectiveCritical == 80)
        #expect(evaluation.reasons.isEmpty)
    }

    @Test func nvmeCriticalWarningIsBad() throws {
        let evaluation = HealthEvaluator.evaluate(report: try nvmeReport(criticalWarning: 1))

        #expect(evaluation.status == .bad)
        #expect(evaluation.reasons.contains { $0.contains("critical warning") })
    }

    @Test func nvmeSpareBelowThresholdIsBad() throws {
        let evaluation = HealthEvaluator.evaluate(report: try nvmeReport(spare: 5, spareThreshold: 10))

        #expect(evaluation.status == .bad)
        #expect(evaluation.reasons.contains { $0.contains("below threshold") })
    }

    @Test func nvmeSpareAtThresholdIsCautionUnlessThresholdIs100() throws {
        let atTen = HealthEvaluator.evaluate(report: try nvmeReport(spare: 10, spareThreshold: 10))
        #expect(atTen.status == .caution)

        let atOneHundred = HealthEvaluator.evaluate(report: try nvmeReport(spare: 100, spareThreshold: 100))
        #expect(atOneHundred.status == .good)
    }

    @Test func nvmeMediaErrorsAreCaution() throws {
        let evaluation = HealthEvaluator.evaluate(report: try nvmeReport(mediaErrors: 1))

        #expect(evaluation.status == .caution)
        #expect(evaluation.reasons.contains { $0.contains("Media errors") })
    }

    @Test func nvmePercentageUsedBoundaries() throws {
        let atNinety = HealthEvaluator.evaluate(report: try nvmeReport(percentageUsed: 90))
        #expect(atNinety.status == .caution)

        let atOneHundred = HealthEvaluator.evaluate(report: try nvmeReport(percentageUsed: 100))
        #expect(atOneHundred.status == .bad)
    }

    @Test func nvmeTemperatureUsesDriveLimits() throws {
        let caution = HealthEvaluator.evaluate(
            report: try nvmeReport(temperature: 78, opLimit: 77, criticalLimit: 80)
        )
        #expect(caution.status == .caution)
        #expect(caution.effectiveWarning == 77)
        #expect(caution.effectiveCritical == 80)

        let bad = HealthEvaluator.evaluate(
            report: try nvmeReport(temperature: 80, opLimit: 77, criticalLimit: 80)
        )
        #expect(bad.status == .bad)
    }

    @Test func globalPolicyOverridesDriveLimits() throws {
        let policy = TemperaturePolicy(useDriveLimits: false, warningCelsius: 50, criticalCelsius: 60)

        let caution = HealthEvaluator.evaluate(
            report: try nvmeReport(temperature: 55, opLimit: 77, criticalLimit: 80),
            policy: policy
        )
        #expect(caution.status == .caution)
        #expect(caution.effectiveWarning == 50)
        #expect(caution.effectiveCritical == 60)

        let bad = HealthEvaluator.evaluate(
            report: try nvmeReport(temperature: 60, opLimit: 77, criticalLimit: 80),
            policy: policy
        )
        #expect(bad.status == .bad)
    }

    @Test func temperatureFallsBackToNVMELog() throws {
        let evaluation = HealthEvaluator.evaluate(
            report: try nvmeReport(temperature: 55, includeTemperatureBlock: false)
        )

        #expect(evaluation.temperatureCelsius == 55)
        #expect(evaluation.status == .caution)
    }

    @Test func temperatureFallsBackToATAAttribute() throws {
        let evaluation = HealthEvaluator.evaluate(
            report: try ataReport(attributes: [
                attribute(
                    id: 194,
                    name: "Temperature_Celsius",
                    value: 100,
                    raw: 65,
                    rawString: "65 (Min/Max 20/45)"
                )
            ])
        )

        #expect(evaluation.temperatureCelsius == 65)
        #expect(evaluation.status == .bad)
    }

    @Test func ataPrefailureAtThresholdIsBad() throws {
        let evaluation = HealthEvaluator.evaluate(
            report: try ataReport(attributes: [
                attribute(id: 10, name: "Spin_Retry_Count", value: 100, thresh: 100, prefailure: true)
            ])
        )

        #expect(evaluation.status == .bad)
        #expect(evaluation.reasons.contains { $0.contains("Spin_Retry_Count") })
    }

    @Test func ataMediaDegradationAttributesAreCaution() throws {
        let cases = [
            (5, "Reallocated_Sector_Ct"),
            (197, "Current_Pending_Sector"),
            (198, "Offline_Uncorrectable")
        ]

        for (id, name) in cases {
            let evaluation = HealthEvaluator.evaluate(
                report: try ataReport(attributes: [
                    attribute(id: id, name: name, value: 100, raw: 1)
                ])
            )
            #expect(evaluation.status == .caution, "expected caution for \(name)")
        }
    }

    @Test func ataZeroThresholdDoesNotTriggerPrefailure() throws {
        let evaluation = HealthEvaluator.evaluate(
            report: try ataReport(attributes: [
                attribute(id: 10, name: "Spin_Retry_Count", value: 0, thresh: 0, prefailure: true)
            ])
        )

        #expect(evaluation.status == .good)
    }

    @Test func missingSMARTPayloadIsUnknown() throws {
        let evaluation = HealthEvaluator.evaluate(report: try report(["model_name": "Bare Disk"]))

        #expect(evaluation.status == .unknown)
        #expect(evaluation.reasons == ["SMART data is unavailable."])
        #expect(evaluation.lifePercent == nil)
        #expect(evaluation.temperatureCelsius == nil)
    }

    @Test func smartSelfAssessmentFailureIsBad() throws {
        let evaluation = HealthEvaluator.evaluate(report: try nvmeReport(passed: false))

        #expect(evaluation.status == .bad)
        #expect(evaluation.reasons.contains { $0.contains("SMART self-assessment failed") })
    }
}
