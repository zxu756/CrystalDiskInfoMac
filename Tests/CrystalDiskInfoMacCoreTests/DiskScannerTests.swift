import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct DiskScannerTests {
    private struct FakeLister: DiskListing {
        let candidates: [DiskCandidate]

        func physicalDisks() throws -> [DiskCandidate] {
            candidates
        }
    }

    private struct FailingLister: DiskListing {
        func physicalDisks() throws -> [DiskCandidate] {
            throw DiskutilError.commandFailed("boom")
        }
    }

    private final class FakeRunner: SmartctlRunning {
        let results: [String: Result<SmartctlResult, Error>]

        init(results: [String: Result<SmartctlResult, Error>]) {
            self.results = results
        }

        func discover() throws -> URL {
            URL(fileURLWithPath: "/fake/smartctl")
        }

        func version() throws -> String {
            "7.5"
        }

        func read(bsdName: String) throws -> SmartctlResult {
            guard let result = results[bsdName] else {
                throw SmartctlError.deviceUnreadable("no fake result for \(bsdName)")
            }
            return try result.get()
        }
    }

    private final class MissingRunner: SmartctlRunning {
        func discover() throws -> URL {
            throw SmartctlError.notInstalled
        }

        func version() throws -> String {
            throw SmartctlError.notInstalled
        }

        func read(bsdName: String) throws -> SmartctlResult {
            throw SmartctlError.notInstalled
        }
    }

    private final class OldRunner: SmartctlRunning {
        func discover() throws -> URL {
            URL(fileURLWithPath: "/fake/smartctl")
        }

        func version() throws -> String {
            throw SmartctlError.unsupportedVersion("7.3")
        }

        func read(bsdName: String) throws -> SmartctlResult {
            throw SmartctlError.unsupportedVersion("7.3")
        }
    }

    private func candidate(
        _ bsdName: String,
        isInternal: Bool,
        capacity: UInt64,
        mediaName: String,
        bus: String
    ) -> DiskCandidate {
        DiskCandidate(
            bsdName: bsdName,
            isInternal: isInternal,
            capacityBytes: capacity,
            mediaName: mediaName,
            deviceProtocol: bus
        )
    }

    private func result(_ fixture: String) throws -> SmartctlResult {
        let data = try TestFixtures.fixtureData(fixture)
        let report = try SmartctlReport.decode(data)
        return SmartctlResult(
            report: report,
            exitStatus: report.smartctl?.exitStatus ?? 0,
            stderr: "",
            rawJSON: data
        )
    }

    private func disk0Candidate() -> DiskCandidate {
        candidate(
            "disk0",
            isInternal: true,
            capacity: 251_000_193_024,
            mediaName: "APPLE SSD AP0256Z",
            bus: "Apple Fabric"
        )
    }

    private func disk4Candidate() -> DiskCandidate {
        candidate(
            "disk4",
            isInternal: false,
            capacity: 512_110_190_592,
            mediaName: "INTEL SSDPEKNW512G8",
            bus: "PCI-Express"
        )
    }

    @Test func scansAllCandidatesAndMapsReports() throws {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: [disk0Candidate(), disk4Candidate()]),
            runner: FakeRunner(results: [
                "disk0": .success(try result("disk0-apple-nvme.json")),
                "disk4": .success(try result("disk4-intel-nvme.json"))
            ])
        )

        let disks = try scanner.scan(policy: .standard)

        #expect(disks.map(\.bsdName) == ["disk0", "disk4"])
        #expect(disks[0].health == .good)
        #expect(disks[0].temperatureCelsius == 36)
        #expect(disks[1].health == .good)
        #expect(disks[1].temperatureCelsius == 41)
    }

    @Test func oneDeviceFailureBecomesUnknownRow() throws {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: [disk0Candidate(), disk4Candidate()]),
            runner: FakeRunner(results: [
                "disk0": .success(try result("disk0-apple-nvme.json")),
                "disk4": .failure(SmartctlError.deviceUnreadable("Permission denied"))
            ])
        )

        let disks = try scanner.scan(policy: .standard)

        #expect(disks.count == 2)
        #expect(disks[0].health == .good)
        #expect(disks[1].health == .unknown)
        #expect(disks[1].isStale == true)
        #expect(disks[1].consecutiveFailures == 1)
        #expect(disks[1].readError?.contains("Permission denied") == true)
        #expect(disks[1].readError?.contains("Full Disk Access") == true)
        #expect(disks[1].healthReasons.contains { $0.contains("Permission denied") })
    }

    @Test func setupFailurePropagatesInsteadOfHidingAllDisks() throws {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: [disk0Candidate()]),
            runner: FakeRunner(results: [
                "disk0": .failure(SmartctlError.notInstalled)
            ])
        )

        do {
            _ = try scanner.scan(policy: .standard)
            Issue.record("Expected notInstalled to propagate")
        } catch let error as SmartctlError {
            #expect(error == .notInstalled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func discoveryFailurePropagates() {
        let scanner = DiskScanner(
            lister: FailingLister(),
            runner: FakeRunner(results: [:])
        )

        do {
            _ = try scanner.scan(policy: .standard)
            Issue.record("Expected diskutil failure to propagate")
        } catch let error as DiskutilError {
            #expect(error == .commandFailed("boom"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func appliesProvidedTemperaturePolicy() throws {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: [disk4Candidate()]),
            runner: FakeRunner(results: [
                "disk4": .success(try result("disk4-intel-nvme.json"))
            ])
        )
        let policy = TemperaturePolicy(
            useDriveLimits: false,
            warningCelsius: 45,
            criticalCelsius: 55
        )

        let disks = try scanner.scan(policy: policy)

        #expect(disks[0].temperatureWarningCelsius == 45)
        #expect(disks[0].temperatureCriticalCelsius == 55)
    }

    @Test func reportsAvailableSmartctlStatus() {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: []),
            runner: FakeRunner(results: [:])
        )

        #expect(
            scanner.smartctlStatus()
                == .available(version: "7.5", path: "/fake/smartctl")
        )
    }

    @Test func reportsMissingSmartctlStatus() {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: []),
            runner: MissingRunner()
        )

        #expect(scanner.smartctlStatus() == .notInstalled)
    }

    @Test func reportsUnsupportedSmartctlStatus() {
        let scanner = DiskScanner(
            lister: FakeLister(candidates: []),
            runner: OldRunner()
        )

        #expect(scanner.smartctlStatus() == .unsupported(version: "7.3"))
    }
}
