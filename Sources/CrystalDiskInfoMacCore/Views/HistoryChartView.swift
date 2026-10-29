import SwiftUI
import Charts
import Foundation
import Combine

public enum HistoryWindow: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case oneDay
    case sevenDays
    case thirtyDays

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .oneHour: return "1h"
        case .oneDay: return "24h"
        case .sevenDays: return "7d"
        case .thirtyDays: return "30d"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        case .sevenDays: return 7 * 86_400
        case .thirtyDays: return 30 * 86_400
        }
    }

    public func startDate(now: Date) -> Date {
        now.addingTimeInterval(-duration)
    }

    public func filtered(_ samples: [HistorySample], now: Date) -> [HistorySample] {
        let start = startDate(now: now)
        return samples
            .filter { $0.timestamp >= start && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

public struct HistorySeries: Equatable, Sendable {
    public let samples: [HistorySample]
    public let temperatureSegments: [[HistorySample]]
    public let lifeSegments: [[HistorySample]]

    public var temperaturePointCount: Int {
        temperatureSegments.reduce(0) { $0 + $1.count }
    }

    public var lifePointCount: Int {
        lifeSegments.reduce(0) { $0 + $1.count }
    }

    public init(samples: [HistorySample], gapThreshold: TimeInterval) {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        self.samples = sorted
        self.temperatureSegments = Self.segments(
            in: sorted,
            gapThreshold: gapThreshold,
            value: { $0.temperatureCelsius }
        )
        self.lifeSegments = Self.segments(
            in: sorted,
            gapThreshold: gapThreshold,
            value: { $0.lifePercent }
        )
    }

    /// Median sample interval × 2.5, clamped to a sensible chart range.
    public static func automaticGapThreshold(for samples: [HistorySample]) -> TimeInterval {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > 1 else {
            return 300
        }

        var intervals: [TimeInterval] = []
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            let interval = next.timestamp.timeIntervalSince(previous.timestamp)
            if interval > 0 {
                intervals.append(interval)
            }
        }

        guard !intervals.isEmpty else {
            return 300
        }

        intervals.sort()
        let median = intervals[intervals.count / 2]
        return min(max(median * 2.5, 60), 3_600)
    }

    /// Downsamples a single contiguous segment for rendering while preserving
    /// its first and last points and the minimum/maximum value in each bucket.
    /// The model still retains every sample.
    public static func downsampled(
        _ samples: [HistorySample],
        maxPoints: Int
    ) -> [HistorySample] {
        downsampled(samples, maxPoints: maxPoints) { $0.temperatureCelsius }
    }

    public static func downsampled(
        _ samples: [HistorySample],
        maxPoints: Int,
        value: (HistorySample) -> Int?
    ) -> [HistorySample] {
        guard maxPoints > 2, samples.count > maxPoints else {
            return samples
        }

        let bucketCount = max(1, (maxPoints - 2) / 2)
        let bucketSize = max(
            1,
            Int(ceil(Double(samples.count) / Double(bucketCount)))
        )

        var result: [HistorySample] = []
        var index = 0

        while index < samples.count {
            let end = min(index + bucketSize, samples.count)
            let bucket = samples[index..<end]

            var minSample: HistorySample?
            var maxSample: HistorySample?
            var minValue = Int.max
            var maxValue = Int.min

            for sample in bucket {
                guard let sampleValue = value(sample) else { continue }
                if sampleValue < minValue {
                    minValue = sampleValue
                    minSample = sample
                }
                if sampleValue > maxValue {
                    maxValue = sampleValue
                    maxSample = sample
                }
            }

            if let minSample, let maxSample {
                let ordered: [HistorySample]
                if minSample.timestamp <= maxSample.timestamp {
                    ordered = [minSample, maxSample]
                } else {
                    ordered = [maxSample, minSample]
                }
                for sample in ordered where result.last?.timestamp != sample.timestamp {
                    result.append(sample)
                }
            }

            index = end
        }

        if let first = samples.first, result.first?.timestamp != first.timestamp {
            result.insert(first, at: 0)
        }
        if let last = samples.last, result.last?.timestamp != last.timestamp {
            result.append(last)
        }

        while result.count > maxPoints, result.count > 2 {
            result.remove(at: 1)
        }

        return result
    }

    private static func segments(
        in samples: [HistorySample],
        gapThreshold: TimeInterval,
        value: (HistorySample) -> Int?
    ) -> [[HistorySample]] {
        var result: [[HistorySample]] = []
        var current: [HistorySample] = []
        var previousTimestamp: Date?

        for sample in samples {
            if let previousTimestamp,
               sample.timestamp.timeIntervalSince(previousTimestamp) > gapThreshold,
               !current.isEmpty {
                result.append(current)
                current = []
            }

            previousTimestamp = sample.timestamp

            guard value(sample) != nil else {
                if !current.isEmpty {
                    result.append(current)
                    current = []
                }
                continue
            }

            current.append(sample)
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}

public struct HistoryChartView: View {
    private let samples: [HistorySample]
    private let now: Date
    private let warningCelsius: Int
    private let criticalCelsius: Int
    private let gapThreshold: TimeInterval?

    @StateObject private var state = HistoryChartState()

    public init(
        samples: [HistorySample],
        now: Date = Date(),
        warningCelsius: Int = 50,
        criticalCelsius: Int = 60,
        gapThreshold: TimeInterval? = nil
    ) {
        self.samples = samples
        self.now = now
        self.warningCelsius = warningCelsius
        self.criticalCelsius = criticalCelsius
        self.gapThreshold = gapThreshold
    }

    public var body: some View {
        content(series: series)
    }

    private var filteredSamples: [HistorySample] {
        state.window.filtered(samples, now: now)
    }

    private var series: HistorySeries {
        let filtered = filteredSamples
        let threshold = gapThreshold
            ?? HistorySeries.automaticGapThreshold(for: filtered)
        return HistorySeries(samples: filtered, gapThreshold: threshold)
    }

    private func content(series: HistorySeries) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Range", selection: $state.window) {
                    ForEach(HistoryWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }

            if series.samples.isEmpty {
                emptyState
            } else {
                temperatureChart(series)
                lifeChart(series)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func temperatureChart(_ series: HistorySeries) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Temperature")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(temperatureSummary(series))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(
                    Array(series.temperatureSegments.enumerated()),
                    id: \.offset
                ) { index, segment in
                    let points = HistorySeries.downsampled(
                        segment,
                        maxPoints: 600,
                        value: { $0.temperatureCelsius }
                    )
                    if points.count == 1, let sample = points.first {
                        PointMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Temperature", Double(sample.temperatureCelsius ?? 0))
                        )
                        .foregroundStyle(Theme.accent)
                        .symbolSize(18)
                    } else {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, sample in
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Temperature", Double(sample.temperatureCelsius ?? 0)),
                                series: .value("Segment", index)
                            )
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }

                RuleMark(y: .value("Warning", Double(warningCelsius)))
                    .foregroundStyle(Theme.caution.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                RuleMark(y: .value("Critical", Double(criticalCelsius)))
                    .foregroundStyle(Theme.bad.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXScale(domain: state.window.startDate(now: now)...now)
            .chartYScale(domain: temperatureDomain(series))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: axisDateFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 145)
        }
    }

    private func lifeChart(_ series: HistorySeries) -> some View {
        let latestLife = series.lifeSegments.last?.last?.lifePercent
        let tint = Theme.lifeColor(latestLife)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Life")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(latestLife.map { "Latest \($0)%" } ?? "No life samples")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(
                    Array(series.lifeSegments.enumerated()),
                    id: \.offset
                ) { index, segment in
                    let points = HistorySeries.downsampled(
                        segment,
                        maxPoints: 600,
                        value: { $0.lifePercent }
                    )
                    if points.count == 1, let sample = points.first {
                        PointMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Life", Double(sample.lifePercent ?? 0))
                        )
                        .foregroundStyle(tint)
                        .symbolSize(18)
                    } else {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, sample in
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("Life", Double(sample.lifePercent ?? 0)),
                                series: .value("Segment", index)
                            )
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                }
            }
            .chartXScale(domain: state.window.startDate(now: now)...now)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: axisDateFormat)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 145)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)

            Text("No history for this range")
                .font(.system(size: 13, weight: .semibold))

            Text("History appears after a successful refresh.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var axisDateFormat: Date.FormatStyle {
        let locale = Locale(identifier: "en_US")
        switch state.window {
        case .oneHour, .oneDay:
            return .dateTime.hour().minute().locale(locale)
        case .sevenDays, .thirtyDays:
            return .dateTime.month(.abbreviated).day().locale(locale)
        }
    }

    private func temperatureSummary(_ series: HistorySeries) -> String {
        guard let latest = series.temperatureSegments.last?.last?.temperatureCelsius else {
            return "No temperature samples"
        }
        return "Latest \(latest) °C · Warning \(warningCelsius) °C · Critical \(criticalCelsius) °C"
    }

    private func temperatureDomain(_ series: HistorySeries) -> ClosedRange<Double> {
        let values = series.samples.compactMap(\.temperatureCelsius).map(Double.init)
        let lower = min(
            values.min() ?? Double(warningCelsius),
            Double(warningCelsius),
            Double(criticalCelsius)
        ) - 5
        let upper = max(
            values.max() ?? Double(criticalCelsius),
            Double(warningCelsius),
            Double(criticalCelsius)
        ) + 5
        return lower...max(upper, lower + 10)
    }
}

@MainActor
private final class HistoryChartState: ObservableObject {
    @Published var window: HistoryWindow = .oneDay
}
