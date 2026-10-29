import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct DiskutilListerTests {
    private final class QueryRecorder {
        var devices: [String] = []
    }

    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/\(name)")
    }

    private static func infoDictionary(for bsdName: String) -> [String: Any] {
        switch bsdName {
        case "disk0":
            return [
                "DeviceIdentifier": "disk0",
                "ParentWholeDisk": "disk0",
                "VirtualOrPhysical": "Unknown",
                "Internal": true,
                "TotalSize": 251_000_193_024,
                "MediaName": "APPLE SSD AP0256Z",
                "BusProtocol": "Apple Fabric"
            ]
        case "disk4":
            return [
                "DeviceIdentifier": "disk4",
                "ParentWholeDisk": "disk4",
                "VirtualOrPhysical": "Physical",
                "Internal": false,
                "TotalSize": 512_110_190_592,
                "MediaName": "INTEL SSDPEKNW512G8",
                "BusProtocol": "PCI-Express"
            ]
        case "disk1", "disk2", "disk3":
            return [
                "DeviceIdentifier": bsdName,
                "ParentWholeDisk": bsdName,
                "VirtualOrPhysical": "Virtual",
                "Internal": true,
                "TotalSize": 245_107_195_904,
                "MediaName": "APPLE SSD AP0256Z",
                "BusProtocol": "Apple Fabric"
            ]
        case "disk5":
            return [
                "DeviceIdentifier": "disk5",
                "ParentWholeDisk": "disk5",
                "VirtualOrPhysical": "Virtual",
                "Internal": false,
                "TotalSize": 511_900_434_432,
                "MediaName": "INTEL SSDPEKNW512G8",
                "BusProtocol": "PCI-Express"
            ]
        default:
            return [
                "DeviceIdentifier": bsdName,
                "ParentWholeDisk": bsdName,
                "VirtualOrPhysical": "Virtual",
                "Internal": false,
                "TotalSize": 40_000_000,
                "MediaName": "Disk Image",
                "BusProtocol": "Disk Image"
            ]
        }
    }

    private static func infoPlist(for bsdName: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: infoDictionary(for: bsdName),
            format: .xml,
            options: 0
        )
    }

    private func expectError(_ expected: DiskutilError, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected \(expected), but no error was thrown")
        } catch let error as DiskutilError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }

    @Test func listsPhysicalWholeDisksOnly() throws {
        let listData = try Data(contentsOf: Self.fixtureURL("diskutil-list.plist"))
        let recorder = QueryRecorder()

        let lister = DiskutilLister(runner: { _, arguments in
            if arguments == ["list", "-plist"] {
                return listData
            }
            guard arguments.count == 3,
                  arguments[0] == "info",
                  arguments[1] == "-plist",
                  arguments[2].hasPrefix("/dev/") else {
                Issue.record("Unexpected diskutil arguments: \(arguments)")
                return Data()
            }
            let bsdName = String(arguments[2].dropFirst("/dev/".count))
            recorder.devices.append(bsdName)
            return try Self.infoPlist(for: bsdName)
        })

        let disks = try lister.physicalDisks()

        #expect(disks.map(\.bsdName) == ["disk0", "disk4"])
        #expect(recorder.devices == (0...21).map { "disk\($0)" })

        #expect(disks[0].isInternal == true)
        #expect(disks[0].capacityBytes == 251_000_193_024)
        #expect(disks[0].mediaName == "APPLE SSD AP0256Z")
        #expect(disks[0].deviceProtocol == "Apple Fabric")

        #expect(disks[1].isInternal == false)
        #expect(disks[1].capacityBytes == 512_110_190_592)
        #expect(disks[1].mediaName == "INTEL SSDPEKNW512G8")
        #expect(disks[1].deviceProtocol == "PCI-Express")
    }

    @Test func malformedListPlistThrows() {
        let lister = DiskutilLister(runner: { _, _ in Data("not a plist".utf8) })
        expectError(.invalidPlist) { _ = try lister.physicalDisks() }
    }

    @Test func malformedInfoPlistThrows() throws {
        let listData = try Data(contentsOf: Self.fixtureURL("diskutil-list.plist"))
        let lister = DiskutilLister(runner: { _, arguments in
            if arguments == ["list", "-plist"] {
                return listData
            }
            return Data("not a plist".utf8)
        })
        expectError(.invalidPlist) { _ = try lister.physicalDisks() }
    }
}
