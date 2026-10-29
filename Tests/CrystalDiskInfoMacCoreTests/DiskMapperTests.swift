import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct DiskMapperTests {
    private func fixtureReport(_ name: String) throws -> SmartctlReport {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/\(name)"))
        return try SmartctlReport.decode(data)
    }

    private func report(_ json: [String: Any]) throws -> SmartctlReport {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try SmartctlReport.decode(data)
    }

    private func disk0Candidate() -> DiskCandidate {
        DiskCandidate(
            bsdName: "disk0",
            isInternal: true,
            capacityBytes: 251_000_193_024,
            mediaName: "APPLE SSD AP0256Z",
            deviceProtocol: "Apple Fabric"
        )
    }

    private func disk4Candidate() -> DiskCandidate {
        DiskCandidate(
            bsdName: "disk4",
            isInternal: false,
            capacityBytes: 512_110_190_592,
            mediaName: "INTEL SSDPEKNW512G8",
            deviceProtocol: "PCI-Express"
        )
    }

    @Test func mapsInternalAppleNVMe() throws {
        let info = DiskMapper.map(
            candidate: disk0Candidate(),
            report: try fixtureReport("disk0-apple-nvme.json")
        )

        #expect(info.id == "REDACTED|APPLE SSD AP0256Z")
        #expect(info.bsdName == "disk0")
        #expect(info.model == "APPLE SSD AP0256Z")
        #expect(info.serial == "REDACTED")
        #expect(info.firmware == "241.0.12")
        #expect(info.protocolName == "NVMe")
        #expect(info.interfaceName == "Apple Fabric")
        #expect(info.capacityBytes == 251_000_193_024)
        #expect(info.isInternal == true)
        #expect(info.smartStatus == .passed)
        #expect(info.health == .good)
        #expect(info.temperatureCelsius == 36)
        #expect(info.temperatureWarningCelsius == 50)
        #expect(info.temperatureCriticalCelsius == 60)
        #expect(info.lifePercent == 95)
        #expect(info.powerOnHours == 1695)
        #expect(info.powerCycleCount == 162)
        #expect(info.unsafeShutdowns == 8)
        #expect(info.mediaErrors == 0)
        #expect(info.attributes.map(\.id) == Array(1...17))
        #expect(info.attributes.first?.name == "Critical Warning")
        #expect(info.attributes.last?.name == "Critical Composite Temperature Time")
        #expect(info.attributes[0].rawString == "0x00")
        #expect(info.attributes[1].rawString == "36 °C")
        #expect(info.attributes[2].name == "Available Spare")
        #expect(info.attributes[2].current == 100)
        #expect(info.attributes[2].threshold == 99)
        #expect(info.attributes[2].isPrefailure == true)
        #expect(info.attributes[4].rawString == "5%")
        #expect(info.readError == nil)
        #expect(info.diagnostics.contains { $0.contains("Error Information Log") })
        #expect(info.diagnostics.contains { $0.contains("exit status: 4") })
        #expect(info.healthReasons.isEmpty)
        #expect(info.isStale == false)
        #expect(info.consecutiveFailures == 0)
    }

    @Test func mapsExternalIntelNVMe() throws {
        let info = DiskMapper.map(
            candidate: disk4Candidate(),
            report: try fixtureReport("disk4-intel-nvme.json")
        )

        #expect(info.id == "REDACTED|INTEL SSDPEKNW512G8")
        #expect(info.bsdName == "disk4")
        #expect(info.model == "INTEL SSDPEKNW512G8")
        #expect(info.serial == "REDACTED")
        #expect(info.firmware == "002C")
        #expect(info.protocolName == "NVMe")
        #expect(info.interfaceName == "PCI-Express")
        #expect(info.capacityBytes == 512_110_190_592)
        #expect(info.isInternal == false)
        #expect(info.smartStatus == .passed)
        #expect(info.health == .good)
        #expect(info.temperatureCelsius == 41)
        #expect(info.temperatureWarningCelsius == 77)
        #expect(info.temperatureCriticalCelsius == 80)
        #expect(info.lifePercent == 97)
        #expect(info.powerOnHours == 12236)
        #expect(info.powerCycleCount == 7292)
        #expect(info.unsafeShutdowns == 103)
        #expect(info.mediaErrors == 0)
        #expect(info.attributes.count == 17)
        #expect(info.readError == nil)
    }

    @Test func mapsATAAttributesAndLife() throws {
        let report = try report([
            "model_name": "Test ATA SSD",
            "serial_number": "ATA-123",
            "firmware_version": "FW1",
            "device": ["protocol": "ATA"],
            "smart_status": ["passed": true],
            "ata_smart_attributes": [
                "revision": 16,
                "table": [
                    [
                        "id": 5,
                        "name": "Reallocated_Sector_Ct",
                        "value": 100,
                        "worst": 100,
                        "thresh": 10,
                        "flags": ["prefailure": true],
                        "raw": ["value": 3, "string": "3"]
                    ],
                    [
                        "id": 194,
                        "name": "Temperature_Celsius",
                        "value": 100,
                        "worst": 100,
                        "thresh": 0,
                        "flags": ["prefailure": false],
                        "raw": ["value": 35, "string": "35 (Min/Max 20/45)"]
                    ],
                    [
                        "id": 231,
                        "name": "SSD_Life_Left",
                        "value": 88,
                        "worst": 88,
                        "thresh": 0,
                        "flags": ["prefailure": false],
                        "raw": ["value": 88, "string": "88"]
                    ]
                ]
            ]
        ])

        let candidate = DiskCandidate(
            bsdName: "disk9",
            isInternal: false,
            capacityBytes: 1_000_204_886_016,
            mediaName: "Test ATA SSD",
            deviceProtocol: "SATA"
        )
        let info = DiskMapper.map(candidate: candidate, report: report)

        #expect(info.id == "ATA-123|Test ATA SSD")
        #expect(info.protocolName == "ATA")
        #expect(info.interfaceName == "SATA")
        #expect(info.capacityBytes == 1_000_204_886_016)
        #expect(info.smartStatus == .passed)
        #expect(info.health == .caution)
        #expect(info.temperatureCelsius == 35)
        #expect(info.lifePercent == 88)
        #expect(info.attributes.count == 3)
        #expect(info.attributes[0].rawValue == 3)
        #expect(info.attributes[0].rawString == "3")
        #expect(info.attributes[0].isPrefailure == true)
        #expect(info.attributes[1].rawString == "35 (Min/Max 20/45)")
        #expect(info.readError == nil)
    }

    @Test func ataPrefailureThresholdMapsToBadHealth() throws {
        let report = try report([
            "model_name": "Failing ATA",
            "smart_status": ["passed": true],
            "ata_smart_attributes": [
                "table": [
                    [
                        "id": 10,
                        "name": "Spin_Retry_Count",
                        "value": 100,
                        "worst": 100,
                        "thresh": 100,
                        "flags": ["prefailure": true],
                        "raw": ["value": 0, "string": "0"]
                    ]
                ]
            ]
        ])

        let info = DiskMapper.map(
            candidate: DiskCandidate(
                bsdName: "disk9",
                isInternal: false,
                capacityBytes: 500_000_000_000,
                mediaName: "Failing ATA",
                deviceProtocol: "SATA"
            ),
            report: report
        )

        #expect(info.health == .bad)
        #expect(info.attributes[0].isWarning == true)
        #expect(info.healthReasons.contains { $0.contains("Spin_Retry_Count") })
    }

    @Test func ataPreferredLifeAttributeWins() throws {
        let report = try report([
            "model_name": "Life ATA",
            "smart_status": ["passed": true],
            "ata_smart_attributes": [
                "table": [
                    [
                        "id": 231,
                        "name": "SSD_Life_Left",
                        "value": 88,
                        "worst": 88,
                        "thresh": 0,
                        "flags": ["prefailure": false],
                        "raw": ["value": 88, "string": "88"]
                    ],
                    [
                        "id": 202,
                        "name": "Percent_Lifetime_Remain",
                        "value": 77,
                        "worst": 77,
                        "thresh": 0,
                        "flags": ["prefailure": false],
                        "raw": ["value": 77, "string": "77"]
                    ]
                ]
            ]
        ])

        let info = DiskMapper.map(
            candidate: DiskCandidate(
                bsdName: "disk9",
                isInternal: false,
                capacityBytes: 500_000_000_000,
                mediaName: "Life ATA",
                deviceProtocol: "SATA"
            ),
            report: report
        )

        #expect(info.lifePercent == 77)
    }

    @Test func mapsSCSIIdentity() throws {
        let report = try report([
            "scsi_model_name": "SAS Disk",
            "scsi_serial_number": "SAS-1",
            "smart_status": ["passed": true]
        ])

        let info = DiskMapper.map(candidate: disk4Candidate(), report: report)

        #expect(info.id == "SAS-1|SAS Disk")
        #expect(info.model == "SAS Disk")
        #expect(info.serial == "SAS-1")
        #expect(info.health == .good)
        #expect(info.readError == nil)
    }

    @Test func mediaErrorsExposeHealthReason() throws {
        let report = try report([
            "model_name": "Media NVMe",
            "serial_number": "MEDIA-1",
            "smart_status": ["passed": true],
            "temperature": ["current": 40],
            "nvme_smart_health_information_log": [
                "critical_warning": 0,
                "temperature": 40,
                "available_spare": 100,
                "available_spare_threshold": 10,
                "percentage_used": 3,
                "media_errors": 3
            ]
        ])

        let info = DiskMapper.map(candidate: disk4Candidate(), report: report)

        #expect(info.health == .caution)
        #expect(info.mediaErrors == 3)
        #expect(info.healthReasons.contains { $0.contains("Media errors") })
        #expect(info.readError == nil)
    }

    @Test func reportCapacityWinsOverCandidateCapacity() throws {
        let report = try report([
            "model_name": "Capacity Disk",
            "serial_number": "CAP-1",
            "smart_status": ["passed": true],
            "user_capacity": ["bytes": 500_107_862_016]
        ])

        let info = DiskMapper.map(
            candidate: DiskCandidate(
                bsdName: "disk9",
                isInternal: false,
                capacityBytes: 999,
                mediaName: "Capacity Disk",
                deviceProtocol: "USB"
            ),
            report: report
        )

        #expect(info.capacityBytes == 500_107_862_016)
    }

    @Test func missingOptionalFieldsStayNilAndFallBackToBSDName() throws {
        let report = try report([
            "model_name": "Unknown",
            "smart_status": ["passed": true]
        ])

        let info = DiskMapper.map(
            candidate: DiskCandidate(
                bsdName: "disk9",
                isInternal: false,
                capacityBytes: 123_456,
                mediaName: "USB Disk",
                deviceProtocol: "USB"
            ),
            report: report
        )

        #expect(info.id == "disk9")
        #expect(info.model == "USB Disk")
        #expect(info.serial == "Unknown")
        #expect(info.firmware == "Unknown")
        #expect(info.capacityBytes == 123_456)
        #expect(info.protocolName == "USB")
        #expect(info.interfaceName == "USB")
        #expect(info.health == .good)
        #expect(info.temperatureCelsius == nil)
        #expect(info.lifePercent == nil)
        #expect(info.powerOnHours == nil)
        #expect(info.powerCycleCount == nil)
        #expect(info.unsafeShutdowns == nil)
        #expect(info.mediaErrors == nil)
        #expect(info.attributes.isEmpty)
        #expect(info.readError == nil)
    }

    @Test func missingSMARTMapsToUnknownWithReason() throws {
        let report = try report([
            "model_name": "Bare Disk",
            "serial_number": "BARE-1"
        ])

        let info = DiskMapper.map(
            candidate: DiskCandidate(
                bsdName: "disk9",
                isInternal: false,
                capacityBytes: 123_456,
                mediaName: "Bare Disk",
                deviceProtocol: "USB"
            ),
            report: report
        )

        #expect(info.health == .unknown)
        #expect(info.smartStatus == .unknown)
        #expect(info.attributes.isEmpty)
        #expect(info.readError == "SMART data is unavailable.")
    }
}
