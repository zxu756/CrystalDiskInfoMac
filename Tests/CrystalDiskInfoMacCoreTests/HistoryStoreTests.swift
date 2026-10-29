import Testing
import Foundation
@testable import CrystalDiskInfoMacCore

struct HistoryStoreTests {
    private final class Clock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdi-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sample(
        at timestamp: Date,
        health: HealthStatus = .good,
        temperature: Int? = 40,
        life: Int? = 95,
        hours: Int? = 100
    ) -> HistorySample {
        HistorySample(
            timestamp: timestamp,
            health: health,
            temperatureCelsius: temperature,
            lifePercent: life,
            powerOnHours: hours
        )
    }

    @Test func appendAndReloadRoundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now

        let store = JSONHistoryStore(directory: directory, now: { now })
        let samples = [
            sample(at: now.addingTimeInterval(-120)),
            sample(at: now.addingTimeInterval(-60), health: .caution, temperature: 55),
            sample(at: now, health: .bad, temperature: 61, life: 90, hours: 101)
        ]

        for sample in samples {
            try store.append(sample, for: "SERIAL|Model")
        }

        #expect(try store.samples(for: "SERIAL|Model") == samples)

        let reloaded = JSONHistoryStore(directory: directory, now: { now })
        #expect(try reloaded.samples(for: "SERIAL|Model") == samples)
    }

    @Test func diskIDsAreIsolated() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now

        let store = JSONHistoryStore(directory: directory, now: { now })
        let first = sample(at: now, temperature: 31)
        let second = sample(at: now, temperature: 52)

        try store.append(first, for: "SERIAL-A|Model-A")
        try store.append(second, for: "SERIAL-B|Model-B")

        #expect(try store.samples(for: "SERIAL-A|Model-A") == [first])
        #expect(try store.samples(for: "SERIAL-B|Model-B") == [second])

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(files.filter { $0.pathExtension == "json" }.count == 2)
    }

    @Test func appendPrunesSamplesOlderThan30Days() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now

        let store = JSONHistoryStore(directory: directory, retentionDays: 30, now: { now })
        try store.append(sample(at: now.addingTimeInterval(-31 * day)), for: "diskA")
        try store.append(sample(at: now.addingTimeInterval(-30 * day)), for: "diskA")
        try store.append(sample(at: now.addingTimeInterval(-29 * day)), for: "diskA")

        let samples = try store.samples(for: "diskA")
        #expect(samples.map(\.timestamp) == [
            now.addingTimeInterval(-30 * day),
            now.addingTimeInterval(-29 * day)
        ])
    }

    @Test func pruneUsesExactRetentionBoundary() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(now)

        let store = JSONHistoryStore(directory: directory, retentionDays: 30, now: { clock.now })
        try store.append(sample(at: now), for: "diskA")

        try store.prune(now: now.addingTimeInterval(30 * day))
        #expect(try store.samples(for: "diskA").count == 1)

        try store.prune(now: now.addingTimeInterval(30 * day + 1))
        #expect(try store.samples(for: "diskA").isEmpty)
    }

    @Test func enforcesSampleCapKeepingNewest() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now

        let store = JSONHistoryStore(directory: directory, maxSamplesPerDisk: 3, now: { now })
        let timestamps = (-4...0).map { now.addingTimeInterval(Double($0)) }
        for timestamp in timestamps {
            try store.append(sample(at: timestamp), for: "diskA")
        }

        let samples = try store.samples(for: "diskA")
        #expect(samples.map(\.timestamp) == Array(timestamps.suffix(3)))
    }

    @Test func defaultsMatchProductRetention() {
        #expect(JSONHistoryStore.defaultRetentionDays == 30)
        #expect(JSONHistoryStore.defaultMaxSamplesPerDisk == 100_000)
    }

    @Test func corruptFileIsBackedUpAndIgnored() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now

        let store = JSONHistoryStore(directory: directory, now: { now })
        try store.append(sample(at: now), for: "SERIAL|Model")

        let filesBefore = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let jsonFile = try #require(filesBefore.first { $0.pathExtension == "json" })
        try Data("not json".utf8).write(to: jsonFile)

        #expect(try store.samples(for: "SERIAL|Model").isEmpty)

        let filesAfter = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(filesAfter.contains { $0.lastPathComponent.contains(".corrupt-") })
        #expect(FileManager.default.fileExists(atPath: jsonFile.path) == false)

        try store.append(sample(at: now), for: "SERIAL|Model")
        #expect(try store.samples(for: "SERIAL|Model").count == 1)
    }

    @Test func concurrentAppendsAreSerialized() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now
        let store = JSONHistoryStore(directory: directory, maxSamplesPerDisk: 1_000, now: { now })

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            try? store.append(
                sample(at: now.addingTimeInterval(Double(index))),
                for: "diskA"
            )
        }

        #expect(try store.samples(for: "diskA").count == 50)
    }

    @Test func createsDirectoryAndWritesValidJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdi-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now

        #expect(FileManager.default.fileExists(atPath: directory.path) == false)

        let store = JSONHistoryStore(directory: directory, now: { now })
        let appended = sample(at: now)
        try store.append(appended, for: "diskA")

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(files.filter { $0.pathExtension == "json" }.count == 1)
        #expect(files.allSatisfy { !$0.lastPathComponent.hasSuffix(".tmp") })

        let jsonFile = try #require(files.first { $0.pathExtension == "json" })
        let data = try Data(contentsOf: jsonFile)
        let decoded = try JSONDecoder().decode([HistorySample].self, from: data)
        #expect(decoded == [appended])
    }
}
