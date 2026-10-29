import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct SmartTableTests {
    private func appleSSDReport() throws -> SmartctlReport {
        try SmartctlReport.decode(TestFixtures.fixtureData("disk0-apple-nvme.json"))
    }

    @Test func nvmeRowsFollowFixtureOrder() throws {
        let info = DiskMapper.map(
            candidate: DiskCandidate(
                bsdName: "disk0",
                isInternal: true,
                capacityBytes: 251_000_193_024,
                mediaName: "APPLE SSD AP0256Z",
                deviceProtocol: "Apple Fabric"
            ),
            report: try appleSSDReport()
        )

        let rows = info.attributes.map(SmartTableRow.init)

        #expect(rows.count == 17)
        #expect(rows.map(\.id) == Array(1...17))
        #expect(rows[0].attribute.name == "Critical Warning")
        #expect(rows[1].attribute.name == "Temperature")
        #expect(rows[16].attribute.name == "Critical Composite Temperature Time")
        #expect(rows[0].currentDisplay == "—")
        #expect(rows[0].worstDisplay == "—")
        #expect(rows[0].thresholdDisplay == "—")
        #expect(rows[0].rawDisplay == "0x00")
        #expect(rows[1].rawDisplay == "36 °C")
        #expect(rows[2].currentDisplay == "100")
        #expect(rows[2].thresholdDisplay == "99")
    }

    @Test func nilValuesRenderAsDashAndSortLast() {
        let row = SmartTableRow(
            attribute: SmartAttribute(
                id: 6,
                name: "Data Units Read",
                current: nil,
                worst: nil,
                threshold: nil,
                rawValue: 132_548_427,
                rawString: nil,
                isPrefailure: false
            )
        )

        #expect(row.currentDisplay == "—")
        #expect(row.worstDisplay == "—")
        #expect(row.thresholdDisplay == "—")
        #expect(row.rawDisplay == "132548427")
        #expect(row.currentSortValue == Int.max)
        #expect(row.worstSortValue == Int.max)
        #expect(row.thresholdSortValue == Int.max)
    }

    @Test func rawStringIsPreservedOverNumericValue() {
        let rawString = "35 (Min/Max 20/45)"
        let row = SmartTableRow(
            attribute: SmartAttribute(
                id: 194,
                name: "Temperature_Celsius",
                current: 100,
                worst: 100,
                threshold: 0,
                rawValue: 35,
                rawString: rawString,
                isPrefailure: false
            )
        )

        #expect(row.rawDisplay == rawString)
        #expect(row.attribute.rawValue == 35)
        #expect(row.attribute.rawString == rawString)
    }

    @Test func prefailureAtThresholdIsWarning() {
        let warning = SmartTableRow(
            attribute: SmartAttribute(
                id: 3,
                name: "Available Spare",
                current: 5,
                worst: nil,
                threshold: 10,
                rawValue: 5,
                rawString: "5%",
                isPrefailure: true
            )
        )

        #expect(warning.isWarning)
        #expect(warning.tooltip.contains("Raw: 5%"))
        #expect(warning.tooltip.contains("Prefailure: Yes"))
        #expect(warning.tooltip.contains("At or below threshold: Yes"))

        let notPrefailure = SmartTableRow(
            attribute: SmartAttribute(
                id: 4,
                name: "Available Spare Threshold",
                current: 10,
                worst: nil,
                threshold: 10,
                rawValue: 10,
                rawString: "10%",
                isPrefailure: false
            )
        )
        #expect(notPrefailure.isWarning == false)

        let aboveThreshold = SmartTableRow(
            attribute: SmartAttribute(
                id: 3,
                name: "Available Spare",
                current: 100,
                worst: nil,
                threshold: 10,
                rawValue: 100,
                rawString: "100%",
                isPrefailure: true
            )
        )
        #expect(aboveThreshold.isWarning == false)
    }

    @Test func nvmeSeverityRowsAreMarkedWarnings() {
        func row(id: Int, name: String, current: Int?, raw: UInt64) -> SmartTableRow {
            SmartTableRow(
                attribute: SmartAttribute(
                    id: id,
                    name: name,
                    current: current,
                    worst: nil,
                    threshold: nil,
                    rawValue: raw,
                    rawString: "\(raw)",
                    isPrefailure: false
                )
            )
        }

        #expect(row(id: 1, name: "Critical Warning", current: nil, raw: 1).isWarning)
        #expect(row(id: 1, name: "Critical Warning", current: nil, raw: 0).isWarning == false)
        #expect(row(id: 5, name: "Percentage Used", current: 90, raw: 90).isWarning)
        #expect(row(id: 5, name: "Percentage Used", current: 89, raw: 89).isWarning == false)
        #expect(row(id: 14, name: "Media Errors", current: nil, raw: 1).isWarning)
        #expect(row(id: 14, name: "Media Errors", current: nil, raw: 0).isWarning == false)
    }

    @Test func ataMediaRowsAreMarkedWarnings() {
        for name in [
            "Reallocated_Sector_Ct",
            "Current_Pending_Sector",
            "Offline_Uncorrectable"
        ] {
            let row = SmartTableRow(
                attribute: SmartAttribute(
                    id: 5,
                    name: name,
                    current: 100,
                    worst: 100,
                    threshold: 10,
                    rawValue: 1,
                    rawString: "1",
                    isPrefailure: true
                )
            )
            #expect(row.isWarning, "expected warning for \(name)")
        }
    }

    @Test func ataRowsMapAcrossAllColumns() {
        let row = SmartTableRow(
            attribute: SmartAttribute(
                id: 5,
                name: "Reallocated_Sector_Ct",
                current: 100,
                worst: 100,
                threshold: 10,
                rawValue: 3,
                rawString: "3",
                isPrefailure: true
            )
        )

        #expect(row.id == 5)
        #expect(row.currentDisplay == "100")
        #expect(row.worstDisplay == "100")
        #expect(row.thresholdDisplay == "10")
        #expect(row.rawDisplay == "3")
        #expect(row.isWarning == true)
        #expect(row.currentSortValue == 100)
        #expect(row.thresholdSortValue == 10)
    }
}
