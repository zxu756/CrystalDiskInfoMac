import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct SmartctlRunnerTests {
    private struct TestScript {
        let url: URL
        let directory: URL
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/\(name)")
    }

    private func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func makeScript(_ body: String) throws -> TestScript {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdi-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("smartctl")
        try ("#!/bin/sh\nset -u\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return TestScript(url: url, directory: directory)
    }

    private func expectError(_ expected: SmartctlError, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected \(expected), but no error was thrown")
        } catch let error as SmartctlError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected), got \(error)")
        }
    }

    @Test func discoversFirstExecutableCandidate() throws {
        let script = try makeScript("exit 0")
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: ["/nonexistent/smartctl", script.url.path])
        #expect(try runner.discover() == script.url)
    }

    @Test func discoveryThrowsWhenNoCandidateExists() {
        let runner = SmartctlRunner(candidatePaths: ["/nonexistent/a", "/nonexistent/b"])
        expectError(.notInstalled) { _ = try runner.discover() }
    }

    @Test func versionReturnsMajorMinor() throws {
        let script = try makeScript("echo 'smartctl 7.5 2024-12-30 r5714 [Darwin 27.0.0 arm64] (local build)'")
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 1)
        #expect(try runner.version() == "7.5")
    }

    @Test func versionRejectsOlderSmartctl() throws {
        let script = try makeScript("echo 'smartctl 7.3 2022-01-01 r5000 [Darwin 27.0.0 arm64] (local build)'")
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 1)
        expectError(.unsupportedVersion("7.3")) { _ = try runner.version() }
    }

    @Test func readAcceptsUsableJSONWithNonzeroExit() throws {
        let fixture = fixtureURL("disk0-apple-nvme.json")
        let script = try makeScript("cat \(shellQuote(fixture.path))\nexit 4")
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 2)
        let result = try runner.read(bsdName: "disk0")

        #expect(result.exitStatus == 4)
        #expect(result.report.modelName == "APPLE SSD AP0256Z")
        #expect(result.report.smartStatus?.passed == true)
        #expect(result.report.nvmeSmartHealthInformationLog?.percentageUsed == 5)
        #expect(result.rawJSON.isEmpty == false)
    }

    @Test func readAcceptsSCSIIdentity() throws {
        let json = #"{"scsi_model_name":"SAS Disk","scsi_serial_number":"SAS-1","smart_status":{"passed":true}}"#
        let script = try makeScript("""
        cat <<'EOF'
        \(json)
        EOF
        """)
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 2)
        let result = try runner.read(bsdName: "disk9")

        #expect(result.report.scsiModelName == "SAS Disk")
        #expect(result.report.scsiSerialNumber == "SAS-1")
        #expect(result.report.smartStatus?.passed == true)
    }

    @Test func readThrowsInvalidJSON() throws {
        let script = try makeScript("echo 'not-json'\nexit 0")
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 2)
        expectError(.invalidJSON) { _ = try runner.read(bsdName: "disk9") }
    }

    @Test func readTimesOut() throws {
        let script = try makeScript("exec sleep 5")
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 0.2)
        let start = Date()
        expectError(.timeout) { _ = try runner.read(bsdName: "disk9") }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func readPassesArgumentsWithoutShell() throws {
        let fixture = fixtureURL("disk4-intel-nvme.json")
        let script = try makeScript("""
        printf '%s\\n' "$@" > "${0%/*}/args.txt"
        cat \(shellQuote(fixture.path))
        exit 0
        """)
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 2)
        _ = try runner.read(bsdName: "disk4")

        let argsFile = script.url.deletingLastPathComponent().appendingPathComponent("args.txt")
        let lines = try String(contentsOf: argsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(lines == ["-j", "-a", "/dev/disk4"])
    }

    @Test func readRetriesDeviceTypeDetection() throws {
        let fixture = fixtureURL("disk4-intel-nvme.json")
        let script = try makeScript("""
        printf '%s\\n' "$*" >> "${0%/*}/attempts.txt"
        case "$*" in
          *"-d sat"*) cat \(shellQuote(fixture.path)); exit 0 ;;
          *"-d nvme"*) cat \(shellQuote(fixture.path)); exit 0 ;;
          *) echo "Unable to detect device type" >&2; exit 1 ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: script.directory) }

        let runner = SmartctlRunner(candidatePaths: [script.url.path], timeout: 2)
        let result = try runner.read(bsdName: "disk9")

        #expect(result.report.modelName == "INTEL SSDPEKNW512G8")
        #expect(result.exitStatus == 0)

        let attemptsFile = script.url.deletingLastPathComponent().appendingPathComponent("attempts.txt")
        let attempts = try String(contentsOf: attemptsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        #expect(attempts == [
            "-j -a /dev/disk9",
            "-j -a -d sat /dev/disk9"
        ])
    }
}
