import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct SmartctlModelsTests {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/\(name)"))
    }

    @Test func decodesInternalAppleSSD() throws {
        let report = try SmartctlReport.decode(fixture("disk0-apple-nvme.json"))

        #expect(report.modelName == "APPLE SSD AP0256Z")
        #expect(report.smartctl?.exitStatus == 4)
        #expect(report.smartStatus?.passed == true)
        #expect(report.temperature?.current == 36)
        #expect(report.nvmeSmartHealthInformationLog?.temperature == 36)
        #expect(report.nvmeSmartHealthInformationLog?.percentageUsed == 5)
        #expect(report.nvmeSmartHealthInformationLog?.availableSpare == 100)
        #expect(report.nvmeSmartHealthInformationLog?.availableSpareThreshold == 99)
        #expect(report.nvmeSmartHealthInformationLog?.powerOnHours == 1695)
        #expect(report.nvmeSmartHealthInformationLog?.powerCycles == 162)
        #expect(report.nvmeSmartHealthInformationLog?.unsafeShutdowns == 8)
        #expect(report.nvmeSmartHealthInformationLog?.mediaErrors == 0)
        #expect(report.smartctl?.messages?.first?.severity == "error")
        #expect(report.ataSmartAttributes == nil)
    }

    @Test func decodesExternalIntelNVMe() throws {
        let report = try SmartctlReport.decode(fixture("disk4-intel-nvme.json"))

        #expect(report.modelName == "INTEL SSDPEKNW512G8")
        #expect(report.smartctl?.exitStatus == 0)
        #expect(report.smartStatus?.passed == true)
        #expect(report.temperature?.current == 41)
        #expect(report.temperature?.opLimitMax == 77)
        #expect(report.temperature?.criticalLimitMax == 80)
        #expect(report.nvmeSmartHealthInformationLog?.percentageUsed == 3)
        #expect(report.nvmeSmartHealthInformationLog?.powerOnHours == 12236)
        #expect(report.nvmeSmartHealthInformationLog?.mediaErrors == 0)
    }

    @Test func malformedDataThrows() {
        let data = Data("not-json".utf8)
        #expect(throws: Error.self) {
            _ = try SmartctlReport.decode(data)
        }
    }
}
