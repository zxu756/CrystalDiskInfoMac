import Foundation

public protocol HistoryStoring {
    func append(_ sample: HistorySample, for diskID: String) throws
    func samples(for diskID: String) throws -> [HistorySample]
    func prune(now: Date) throws
}

/// Stores one JSON array of samples per stable disk id.
///
/// The stable id is sanitized for the filename and suffixed with a stable
/// FNV-1a hash so two ids that differ only in punctuation cannot collide.
/// Writes use `.atomic`; corrupt files are moved aside and ignored.
public final class JSONHistoryStore: HistoryStoring {
    public static let defaultRetentionDays = 30
    public static let defaultMaxSamplesPerDisk = 100_000

    public static var defaultDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("CrystalDiskInfoMac", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }

    private let directory: URL
    private let retentionDays: Int
    private let maxSamplesPerDisk: Int
    private let now: () -> Date

    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(
        directory: URL = JSONHistoryStore.defaultDirectory,
        retentionDays: Int = JSONHistoryStore.defaultRetentionDays,
        maxSamplesPerDisk: Int = JSONHistoryStore.defaultMaxSamplesPerDisk,
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.retentionDays = max(1, retentionDays)
        self.maxSamplesPerDisk = max(1, maxSamplesPerDisk)
        self.now = now

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    public func append(_ sample: HistorySample, for diskID: String) throws {
        let url = fileURL(for: diskID)
        let current = now()
        var samples = loadRawSamples(at: url)
        samples.append(sample)
        samples = pruned(samples, now: current)
        try save(samples, to: url)
    }

    public func samples(for diskID: String) throws -> [HistorySample] {
        let url = fileURL(for: diskID)
        let raw = loadRawSamples(at: url)
        let samples = pruned(raw, now: now())
        if samples.count != raw.count {
            try save(samples, to: url)
        }
        return samples
    }

    public func prune(now: Date) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension == "json" {
            let raw = loadRawSamples(at: url)
            let samples = pruned(raw, now: now)
            if samples.count != raw.count {
                try save(samples, to: url)
            }
        }
    }

    private func pruned(_ samples: [HistorySample], now: Date) -> [HistorySample] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        var result = samples.filter { $0.timestamp >= cutoff }
        result.sort { $0.timestamp < $1.timestamp }
        if result.count > maxSamplesPerDisk {
            result = Array(result.suffix(maxSamplesPerDisk))
        }
        return result
    }

    private func fileURL(for diskID: String) -> URL {
        directory.appendingPathComponent(Self.fileName(for: diskID), isDirectory: false)
    }

    private static func fileName(for diskID: String) -> String {
        let characters = diskID.map { character -> Character in
            if character.isLetter || character.isNumber
                || character == "-" || character == "_" || character == "." {
                return character
            }
            return "_"
        }
        var sanitized = String(characters)
        if sanitized.isEmpty {
            sanitized = "disk"
        }
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100))
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in diskID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hashHex = String(hash, radix: 16)
        let paddedHash = String(repeating: "0", count: max(0, 16 - hashHex.count)) + hashHex

        return "\(sanitized)-\(paddedHash).json"
    }

    private func loadRawSamples(at url: URL) -> [HistorySample] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([HistorySample].self, from: data)
        } catch {
            backupCorruptFile(at: url)
            return []
        }
    }

    private func save(_ samples: [HistorySample], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(samples)
        try data.write(to: url, options: .atomic)
    }

    private func backupCorruptFile(at url: URL) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = "\(url.lastPathComponent).corrupt-\(timestamp)"
        let directory = url.deletingLastPathComponent()

        var destination = directory.appendingPathComponent(baseName)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName)-\(counter)")
            counter += 1
        }

        try? FileManager.default.moveItem(at: url, to: destination)
    }
}
