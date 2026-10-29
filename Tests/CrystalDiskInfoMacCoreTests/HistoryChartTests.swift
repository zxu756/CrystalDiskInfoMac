import Testing
import Foundation
import SwiftUI
@testable import CrystalDiskInfoMacCore

struct HistoryChartTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(
        at timestamp: Date,
        temperature: Int? = 40,
        life: Int? = 95,
        health: HealthStatus = .good
    ) -> HistorySample {
        HistorySample(
            timestamp: timestamp,
            health: health,
            temperatureCelsius: temperature,
            lifePercent: life,
            powerOnHours: 100
        )
    }

    @Test func rangeFilteringUsesInclusiveBoundariesAndExcludesFuture() {
        let samples = [
            sample(at: now.addingTimeInterval(-3_601)),
            sample(at: now.addingTimeInterval(-3_600)),
            sample(at: now.addingTimeInterval(-1_800)),
            sample(at: now),
            sample(at: now.addingTimeInterval(60))
        ]

        let hour = HistoryWindow.oneHour.filtered(samples, now: now)
        #expect(hour.map(\.timestamp) == [
            now.addingTimeInterval(-3_600),
            now.addingTimeInterval(-1_800),
            now
        ])

        let day = HistoryWindow.oneDay.filtered(samples, now: now)
        #expect(day.count == 4)
        #expect(day.last?.timestamp == now)
    }

    @Test func seriesCountsSkipMissingMetrics() {
        let samples = [
            sample(at: now.addingTimeInterval(-180), temperature: 40, life: 95),
            sample(at: now.addingTimeInterval(-120), temperature: nil, life: 94),
            sample(at: now.addingTimeInterval(-60), temperature: 42, life: nil),
            sample(at: now, temperature: 43, life: 92)
        ]

        let series = HistorySeries(samples: samples, gapThreshold: 300)

        #expect(series.temperaturePointCount == 3)
        #expect(series.lifePointCount == 3)
        #expect(
            series.temperatureSegments.flatMap { $0 }.compactMap(\.temperatureCelsius)
                == [40, 42, 43]
        )
        #expect(
            series.lifeSegments.flatMap { $0 }.compactMap(\.lifePercent)
                == [95, 94, 92]
        )
    }

    @Test func missingSamplesRemainGaps() {
        let samples = [
            sample(at: now.addingTimeInterval(-660), temperature: 40, life: 95),
            sample(at: now.addingTimeInterval(-600), temperature: 41, life: 95),
            sample(at: now.addingTimeInterval(-60), temperature: 42, life: 94),
            sample(at: now, temperature: 43, life: 94)
        ]

        let series = HistorySeries(samples: samples, gapThreshold: 300)

        #expect(series.temperatureSegments.count == 2)
        #expect(series.temperatureSegments.map(\.count) == [2, 2])
        #expect(series.lifeSegments.count == 2)
        #expect(series.lifeSegments.map(\.count) == [2, 2])
        #expect(series.temperaturePointCount == 4)
    }

    @Test func nilMetricBreaksOnlyItsOwnSegment() {
        let samples = [
            sample(at: now.addingTimeInterval(-120), temperature: 40, life: 95),
            sample(at: now.addingTimeInterval(-60), temperature: nil, life: 95),
            sample(at: now, temperature: 42, life: 95)
        ]

        let series = HistorySeries(samples: samples, gapThreshold: 300)

        #expect(series.temperatureSegments.count == 2)
        #expect(series.temperatureSegments.map(\.count) == [1, 1])
        #expect(series.lifeSegments.count == 1)
        #expect(series.lifeSegments[0].count == 3)
    }

    @Test func emptyHistoryProducesNoSeries() {
        #expect(HistoryWindow.oneDay.filtered([], now: now).isEmpty)

        let series = HistorySeries(samples: [], gapThreshold: 300)
        #expect(series.samples.isEmpty)
        #expect(series.temperatureSegments.isEmpty)
        #expect(series.lifeSegments.isEmpty)
        #expect(series.temperaturePointCount == 0)
        #expect(series.lifePointCount == 0)
    }

    @Test func thirtyDayOneMinuteHistoryIsNotTruncated() {
        let samples = (0..<43_200).map { index in
            sample(
                at: now.addingTimeInterval(-Double(43_199 - index) * 60),
                temperature: 36,
                life: 95
            )
        }

        let filtered = HistoryWindow.thirtyDays.filtered(samples, now: now)
        #expect(filtered.count == 43_200)

        let series = HistorySeries(samples: filtered, gapThreshold: 150)
        #expect(series.temperaturePointCount == 43_200)
        #expect(series.lifePointCount == 43_200)
        #expect(series.temperatureSegments.count == 1)
        #expect(series.lifeSegments.count == 1)
    }

    @Test func automaticGapThresholdAdaptsToCadence() {
        let oneMinute = (0..<10).map {
            sample(at: now.addingTimeInterval(-Double($0) * 60))
        }

        #expect(HistorySeries.automaticGapThreshold(for: oneMinute) == 150)
        #expect(HistorySeries.automaticGapThreshold(for: []) == 300)
        #expect(HistorySeries.automaticGapThreshold(for: [sample(at: now)]) == 300)
    }

    @MainActor
    @Test func historyChartRendersWithSamples() {
        let samples = (0..<24).map { index in
            sample(
                at: now.addingTimeInterval(-Double(23 - index) * 300),
                temperature: 36 + index % 3,
                life: 95
            )
        }

        let renderer = ImageRenderer(
            content: HistoryChartView(
                samples: samples,
                now: now,
                warningCelsius: 50,
                criticalCelsius: 60,
                gapThreshold: 900
            )
        )
        renderer.proposedSize = .init(width: 900, height: 420)

        #expect(renderer.nsImage != nil)
    }

    @MainActor
    @Test func historyChartRendersEmptyState() {
        let renderer = ImageRenderer(
            content: HistoryChartView(samples: [], now: now)
        )
        renderer.proposedSize = .init(width: 900, height: 420)

        #expect(renderer.nsImage != nil)
    }
}
