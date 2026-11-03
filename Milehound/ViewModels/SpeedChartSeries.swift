import CoreGraphics
import CoreLocation
import Foundation

/// Turns a stored route into the series the speed chart draws.
///
/// Pure and free of SwiftData so it can be tested directly, in the same spirit as
/// `RouteDisplayPath`. Three things it deliberately does differently from plotting the raw
/// readings:
///
/// 1. Reduces by averaging buckets rather than by picking every Nth reading. Striding a noisy
///    1 Hz GPS signal keeps lone spikes and throws away the neighbours that would have balanced
///    them, so the line looked far more jagged than the drive was.
/// 2. Draws a standstill as zero instead of as missing data. The recorder stores no points while
///    the car sits at a light, and because the chart's x axis is time that left a hole — a stop
///    read as "no recording" rather than "not moving".
/// 3. Never averages or smooths across a real recording gap, which would quietly erase the stop
///    sitting inside it.
enum SpeedChartSeries {
    struct Sample: Equatable, Sendable {
        let date: Date
        let speedKmh: Double
    }

    struct Series: Equatable, Sendable {
        var samples: [Sample] = []
        /// Typical spacing of the emitted samples; the canvas scales its own gap threshold off it.
        var medianIntervalSeconds: TimeInterval = 0
    }

    /// Budget for the samples that represent driving, so a 10.000-point trip costs the same to
    /// draw as a short one. Standstill fill is added on top and is bounded by trip duration.
    static let maxDrivingSamples = 600

    /// Rank filter width. Three is enough to drop a single-reading spike while leaving a genuine
    /// acceleration untouched.
    static let smoothingWindow = 3

    /// Same threshold the canvas uses to break its line, so the two agree on what a gap is.
    static let minimumGapSeconds: TimeInterval = 90
    static let gapIntervalMultiple: Double = 6

    /// GPS wanders while parked, so "did not move" cannot mean zero.
    static let parkedDriftMeters: CLLocationDistance = 60

    /// Past this, a standstill is not a pause in a drive any more — typically the seam of a merged
    /// trip — and drawing an hours-long zero line would misrepresent it. The break stays.
    static let maximumDrawnStopSeconds: TimeInterval = 45 * 60

    static func build(samples: [RouteSample]) -> Series {
        let readings = readings(from: samples)
        guard readings.count >= 2 else {
            return Series(
                samples: readings.map { Sample(date: $0.date, speedKmh: $0.speedMps * 3.6) },
                medianIntervalSeconds: 0
            )
        }

        let gapSeconds = gapThresholdSeconds(for: readings)
        let runs = split(readings, gapSeconds: gapSeconds)
        let totalCount = readings.count

        var output: [Sample] = []
        for (index, run) in runs.enumerated() {
            if index > 0 {
                output.append(
                    contentsOf: standstillFill(
                        between: runs[index - 1],
                        and: run,
                        gapSeconds: gapSeconds
                    )
                )
            }

            let budget = max(2, Int((Double(maxDrivingSamples * run.count) / Double(totalCount)).rounded()))
            let reduced = bucketed(smoothed(run), into: budget)
            output.append(contentsOf: reduced.map { Sample(date: $0.date, speedKmh: $0.speedMps * 3.6) })
        }

        return Series(
            samples: output,
            medianIntervalSeconds: median(of: intervals(of: output.map(\.date))) ?? 0
        )
    }

    static func gapBreakSeconds(medianIntervalSeconds: TimeInterval) -> TimeInterval {
        max(minimumGapSeconds, medianIntervalSeconds * gapIntervalMultiple)
    }

    /// Reveal walks sample index, not clock time. Crossing a recording gap must stay on the
    /// floor — a speed lerp would draw a diagonal through the hole.
    static func revealedSamples(
        from samples: [(date: Date, speedKmh: Double)],
        progress: Double,
        gapBreakSeconds: TimeInterval
    ) -> [(date: Date, speedKmh: Double)] {
        guard samples.count >= 2 else { return samples }

        let clamped = min(1, max(0, progress))
        if clamped <= 0 { return [samples[0]] }
        if clamped >= 1 { return samples }

        let segmentCount = samples.count - 1
        let exact = Double(segmentCount) * clamped
        let index = min(segmentCount - 1, Int(exact))
        let fraction = exact - Double(index)
        var result = Array(samples.prefix(index + 1))
        let start = samples[index]
        let end = samples[index + 1]
        let startTime = start.date.timeIntervalSince1970
        let endTime = end.date.timeIntervalSince1970
        let span = endTime - startTime
        result.append((
            date: Date(timeIntervalSince1970: startTime + span * fraction),
            speedKmh: span > gapBreakSeconds
                ? 0
                : start.speedKmh + (end.speedKmh - start.speedKmh) * fraction
        ))
        return result
    }

    /// A recording gap is a valley at zero, not a hole: drop to the baseline, run along it,
    /// then climb back so the stroke stays one line.
    static func strokePoints(
        samples: [(date: Date, speedKmh: Double)],
        gapBreakSeconds: TimeInterval,
        project: (_ date: Date, _ speedKmh: Double) -> CGPoint,
        baselineY: CGFloat
    ) -> [CGPoint] {
        guard let first = samples.first else { return [] }

        var points = [project(first.date, first.speedKmh)]
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let sample = samples[index]
            let projected = project(sample.date, sample.speedKmh)
            if sample.date.timeIntervalSince(previous.date) > gapBreakSeconds {
                points.append(CGPoint(x: points[points.count - 1].x, y: baselineY))
                points.append(CGPoint(x: projected.x, y: baselineY))
            }
            points.append(projected)
        }
        return points
    }

    // MARK: - Stages

    private struct Reading {
        let date: Date
        let coordinate: CLLocationCoordinate2D
        let speedMps: Double
    }

    /// Readings whose speed is unknown are left out rather than drawn as zero: an unrecorded
    /// speed is not the same claim as a stationary car.
    private static func readings(from samples: [RouteSample]) -> [Reading] {
        samples.indices.compactMap { index in
            guard let speed = TripSpeedSummary.effectiveSpeedMps(at: index, in: samples) else {
                return nil
            }
            return Reading(
                date: samples[index].timestamp,
                coordinate: samples[index].coordinate,
                speedMps: speed
            )
        }
    }

    private static func gapThresholdSeconds(for readings: [Reading]) -> TimeInterval {
        let typical = median(of: intervals(of: readings.map(\.date))) ?? 0
        return max(minimumGapSeconds, typical * gapIntervalMultiple)
    }

    private static func split(_ readings: [Reading], gapSeconds: TimeInterval) -> [[Reading]] {
        var runs: [[Reading]] = []
        var current: [Reading] = [readings[0]]

        for reading in readings.dropFirst() {
            if reading.date.timeIntervalSince(current[current.count - 1].date) > gapSeconds {
                runs.append(current)
                current = [reading]
            } else {
                current.append(reading)
            }
        }
        runs.append(current)
        return runs
    }

    /// Zero-speed samples covering the pause between two runs, or nothing when the car clearly
    /// moved while the recorder was not looking.
    ///
    /// Spaced at half the gap threshold so the canvas reads them as one continuous line rather
    /// than breaking between them.
    private static func standstillFill(
        between previous: [Reading],
        and next: [Reading],
        gapSeconds: TimeInterval
    ) -> [Sample] {
        guard let from = previous.last, let to = next.first else { return [] }

        let waited = to.date.timeIntervalSince(from.date)
        guard waited <= maximumDrawnStopSeconds else { return [] }

        let here = CLLocation(latitude: from.coordinate.latitude, longitude: from.coordinate.longitude)
        let there = CLLocation(latitude: to.coordinate.latitude, longitude: to.coordinate.longitude)
        guard here.distance(from: there) <= parkedDriftMeters else { return [] }

        let step = max(1, gapSeconds / 2)
        var filled: [Sample] = []
        var offset = step
        while offset < waited {
            filled.append(Sample(date: from.date.addingTimeInterval(offset), speedKmh: 0))
            offset += step
        }
        // Even a pause shorter than one step needs its floor drawn.
        if filled.isEmpty {
            filled.append(Sample(date: from.date.addingTimeInterval(waited / 2), speedKmh: 0))
        }
        return filled
    }

    private static func smoothed(_ run: [Reading]) -> [Reading] {
        guard run.count > smoothingWindow else { return run }

        let radius = smoothingWindow / 2
        return run.indices.map { index in
            let lower = index - radius
            let upper = index + radius
            guard lower >= 0, upper < run.count else { return run[index] }
            let window = run[lower...upper].map(\.speedMps).sorted()
            return Reading(
                date: run[index].date,
                coordinate: run[index].coordinate,
                speedMps: window[window.count / 2]
            )
        }
    }

    /// Averages contiguous readings into at most `budget` buckets, keeping every reading's
    /// contribution instead of discarding two thirds of them.
    private static func bucketed(_ run: [Reading], into budget: Int) -> [Reading] {
        guard run.count > budget, budget >= 2 else { return run }

        var result: [Reading] = []
        result.reserveCapacity(budget)

        for bucket in 0..<budget {
            let lower = run.count * bucket / budget
            let upper = run.count * (bucket + 1) / budget
            guard lower < upper else { continue }

            let slice = run[lower..<upper]
            let meanSpeed = slice.reduce(0) { $0 + $1.speedMps } / Double(slice.count)
            let meanTime = slice.reduce(0.0) { $0 + $1.date.timeIntervalSince1970 } / Double(slice.count)
            result.append(
                Reading(
                    date: Date(timeIntervalSince1970: meanTime),
                    coordinate: slice[slice.startIndex].coordinate,
                    speedMps: meanSpeed
                )
            )
        }
        return result
    }

    // MARK: - Helpers

    private static func intervals(of dates: [Date]) -> [TimeInterval] {
        guard dates.count >= 2 else { return [] }
        return (1..<dates.count)
            .map { dates[$0].timeIntervalSince(dates[$0 - 1]) }
            .filter { $0 > 0 }
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
