import CoreLocation
import Foundation

/// Speed profile for a stored route.
///
/// - **Cruise:** mean speed while moving (`moving metres / moving seconds`) — above overall
///   average whenever there was real stop time.
/// - **Most common:** mode of *driving* speed — the ±5 km/h band with the most time at or
///   above `drivingSpeedKmh`. Crawl / queue time (5–20 km/h) is still moving for cruise and
///   median, but it is not “the speed I drove most”; that band used to beat a spread-out
///   highway cluster and report 12 km/h on a 50 km/h trip.
/// - **Median:** speed that splits moving time in half — half the drive was slower, half faster.
///   On a city-then-highway trip this sits below the mode, which follows the tight highway cluster.
/// - **P90:** speed below which 90% of moving time was spent — “upper pace” without max spikes.
/// - **Stop:** every interval whose implied speed is below the moving threshold, including
///   multi-minute stands where the recorder wrote no points. GPS wander while parked is still
///   a stop; only merge-length gaps and physical teleports are ignored.
enum TripSpeedProfile {
    /// Below this, the car counts as stopped rather than moving.
    static let movingSpeedKmh: Double = TripMotionThresholds.movingSpeedKmh
    /// Below this, time counts as moving but not toward “most common” (queue / crawl).
    static let drivingSpeedKmh: Double = 20
    /// Bucket width for modal speeds (±2.5 around the reported midpoint).
    static let bucketWidthKmh: Double = 5
    /// Cap for a single no-points standstill (matches the chart’s drawn-stop ceiling).
    static let maximumStopGapSeconds: TimeInterval = TripMotionThresholds.maximumStopGapSeconds
    /// Not enough moving time to report cruise / modal speeds.
    static let minimumMovingSecondsForCruise: TimeInterval = 60

    struct Result: Equatable, Sendable {
        /// Mean speed while moving: moving metres / moving seconds.
        var cruiseSpeedKmh: Double?
        /// Seconds classified as moving — period weight for stats.
        var cruiseDurationSeconds: TimeInterval
        /// Seconds spent stopped (slow intervals + no-points standstills).
        var stopDurationSeconds: TimeInterval
        /// Midpoint of the ±5 km/h driving band with the most time (crawl excluded).
        var mostCommonSpeedKmh: Double?
        /// Time-weighted median speed while moving.
        var medianSpeedKmh: Double?
        /// Time-weighted 90th percentile speed while moving.
        var p90SpeedKmh: Double?

        static let empty = Result(
            cruiseSpeedKmh: nil,
            cruiseDurationSeconds: 0,
            stopDurationSeconds: 0,
            mostCommonSpeedKmh: nil,
            medianSpeedKmh: nil,
            p90SpeedKmh: nil
        )
    }

    private struct SpeedSlice {
        var seconds: TimeInterval
        var kmh: Double
    }

    static func compute(samples: [RouteSample]) -> Result {
        guard samples.count >= 2 else { return .empty }

        var stopSeconds: TimeInterval = 0
        var movingSeconds: TimeInterval = 0
        var movingMeters: Double = 0
        var drivingBucketSeconds: [Int: TimeInterval] = [:]
        var movingBucketSeconds: [Int: TimeInterval] = [:]
        var movingSlices: [SpeedSlice] = []

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let dt = current.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { continue }

            // Hours-long holes are merged-trip seams, not a pause in this drive.
            if dt > maximumStopGapSeconds {
                continue
            }

            let distance = current.location.distance(from: previous.location)
            let impliedMps = distance / dt
            let impliedKmh = impliedMps * 3.6

            // Classify the interval by how far the car actually went. A 5-minute light with
            // 80 m of GPS wander is still a stop; the old 60 m cap threw those minutes away.
            if impliedKmh < movingSpeedKmh {
                stopSeconds += dt
                continue
            }

            // Instantaneous GPS at the end of a dwell is not how the interval was spent.
            let sampleMps = TripSpeedSummary.effectiveSpeedMps(at: index, in: samples)
            let motionMps = sampleMps.map { min($0, impliedMps) } ?? impliedMps
            let kmh = motionMps * 3.6

            if kmh < movingSpeedKmh {
                stopSeconds += dt
                continue
            }
            // Teleports / unrecordable spikes are neither cruise nor stop.
            guard RecordingMovementPolicy.isRecordableSpeed(motionMps) else {
                continue
            }

            movingSeconds += dt
            movingMeters += distance
            movingSlices.append(SpeedSlice(seconds: dt, kmh: kmh))
            let bucket = Int(floor(kmh / bucketWidthKmh))
            movingBucketSeconds[bucket, default: 0] += dt
            // Queue / GPS-creep clusters at 8–15 km/h; that is not the trip's pace.
            if kmh >= drivingSpeedKmh {
                drivingBucketSeconds[bucket, default: 0] += dt
            }
        }

        let modeBuckets = drivingTime(in: drivingBucketSeconds) >= minimumMovingSecondsForCruise
            ? drivingBucketSeconds
            : movingBucketSeconds
        let mostCommon = smoothedWinningBucket(modeBuckets)
            .map { bucketMidpointKmh($0) }
        let median = timeWeightedPercentileKmh(movingSlices, percentile: 0.5)
        let p90 = timeWeightedPercentileKmh(movingSlices, percentile: 0.9)

        guard movingSeconds >= minimumMovingSecondsForCruise, movingMeters > 0 else {
            return Result(
                cruiseSpeedKmh: nil,
                cruiseDurationSeconds: 0,
                stopDurationSeconds: stopSeconds,
                mostCommonSpeedKmh: nil,
                medianSpeedKmh: nil,
                p90SpeedKmh: nil
            )
        }

        return Result(
            cruiseSpeedKmh: movingMeters * 3.6 / movingSeconds,
            cruiseDurationSeconds: movingSeconds,
            stopDurationSeconds: stopSeconds,
            mostCommonSpeedKmh: mostCommon,
            medianSpeedKmh: median,
            p90SpeedKmh: p90
        )
    }

    static func compute(points: [TripPoint]) -> Result {
        compute(samples: RouteDisplayPath.samples(from: points))
    }

    private static func drivingTime(in buckets: [Int: TimeInterval]) -> TimeInterval {
        buckets.values.reduce(0, +)
    }

    private static func bucketMidpointKmh(_ bucket: Int) -> Double {
        (Double(bucket) + 0.5) * bucketWidthKmh
    }

    /// Speed at `percentile` of moving time (0…1): sort intervals by speed and walk until that
    /// fraction of moving seconds has been seen. Median uses 0.5; P90 uses 0.9.
    private static func timeWeightedPercentileKmh(
        _ slices: [SpeedSlice],
        percentile: Double
    ) -> Double? {
        let total = slices.reduce(0.0) { $0 + $1.seconds }
        guard total > 0 else { return nil }

        let ordered = slices.sorted { $0.kmh < $1.kmh }
        let target = total * min(1, max(0, percentile))
        var seen: TimeInterval = 0
        for slice in ordered {
            seen += slice.seconds
            if seen >= target {
                return slice.kmh
            }
        }
        return ordered.last?.kmh
    }

    /// Peak of a 3-bucket moving sum so a steady ~50 split across 45 / 50 / 55 still wins
    /// against a tighter but shorter cluster at a single highway reading. Only buckets that
    /// themselves have time can win — otherwise an empty neighbour inherits the mass and
    /// reports 57.5 for a trip that never left 50.
    private static func smoothedWinningBucket(_ bucketSeconds: [Int: TimeInterval]) -> Int? {
        var winner: Int?
        var best: TimeInterval = 0
        for bucket in bucketSeconds.keys {
            let weight = (bucketSeconds[bucket - 1] ?? 0)
                + (bucketSeconds[bucket] ?? 0)
                + (bucketSeconds[bucket + 1] ?? 0)
            if weight > best || (weight == best && bucket > (winner ?? .min)) {
                best = weight
                winner = bucket
            }
        }
        return best > 0 ? winner : nil
    }
}
