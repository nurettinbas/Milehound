import CoreLocation
import Foundation

/// Shared moving / merge-gap numbers for speed profile and estimated fuel.
/// Stop *duration* can still include long standstills; fuel grades ambiguous gaps by evidence.
enum TripMotionThresholds {
    static let movingSpeedKmh: Double = 5
    static let maximumStopGapSeconds: TimeInterval = 45 * 60
    static let minimumAccelIntervalSeconds: TimeInterval = 0.8
    /// Sparse samples cannot support Δv/Δt; treat as steady cruise.
    static let maximumAccelIntervalSeconds: TimeInterval = 15
    static let maximumAbsAccelerationMps2: Double = 3.5
}

/// One GPS segment after filtering teleports, merge seams, and noisy acceleration.
struct TripFuelInterval: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Implied or motion speed is below the moving threshold.
        case observedStop
        /// Believable moving sample.
        case moving
        /// Merge seam or pause with no trustworthy motion evidence — not fuel.
        case unobserved
        /// Physically impossible jump.
        case teleport
    }

    var dt: TimeInterval
    var distanceMeters: Double
    var speedMps: Double
    var accelerationMps2: Double
    /// 0…1 support that a low-speed interval is observed traffic rather than a GPS/parking gap.
    var evidenceWeight: Double
    var kind: Kind
    var startedAt: Date
    /// False when |Δv/Δt| exceeded the physical cap — not a hard-accel event.
    var accelerationAvailable: Bool = true
}

/// GPS motion prepared for the relative fuel model. Pure and free of SwiftData.
enum TripFuelMotionTimeline {
    struct Result: Equatable, Sendable {
        var intervals: [TripFuelInterval]
        var observedMovingMeters: Double
        var observedStopSeconds: TimeInterval
        var unobservedSeconds: TimeInterval
        /// 0…1. Low when the trace is sparse, teleports, or disagrees with stored distance.
        var confidence: Double

        static let empty = Result(
            intervals: [],
            observedMovingMeters: 0,
            observedStopSeconds: 0,
            unobservedSeconds: 0,
            confidence: 0
        )
    }

    struct ExcludedStop: Equatable, Sendable {
        var startedAt: Date
        var duration: TimeInterval

        var end: Date { startedAt.addingTimeInterval(duration) }

        func contains(_ date: Date) -> Bool {
            date >= startedAt && date <= end
        }
    }

    /// Probability the engine is still on during a GPS-confirmed stop run.
    /// Short lights are likely idling; long gaps look more like parking. A Stop pin is not engine-off.
    static func engineOnProbability(forRunDuration duration: TimeInterval) -> Double {
        let dt = max(0, duration)
        if dt <= 120 { return 0.85 }
        if dt <= 600 {
            let t = (dt - 120) / (600 - 120)
            return 0.85 + t * (0.65 - 0.85)
        }
        if dt <= 45 * 60 {
            let t = (dt - 600) / (45 * 60 - 600)
            return 0.65 + t * (0.20 - 0.65)
        }
        return 0.20
    }

    /// Evidence-weighted idle seconds for a consecutive stop run.
    static func idleCreditSeconds(forRunDuration duration: TimeInterval) -> TimeInterval {
        max(0, duration) * engineOnProbability(forRunDuration: duration)
    }

    static func build(
        samples: [RouteSample],
        storedDistanceMeters: Double,
        excludedStops: [ExcludedStop] = []
    ) -> Result {
        guard samples.count >= 2 else { return .empty }

        var draft: [TripFuelInterval] = []
        draft.reserveCapacity(samples.count - 1)

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let dt = current.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { continue }

            if dt > TripMotionThresholds.maximumStopGapSeconds {
                draft.append(
                    TripFuelInterval(
                        dt: dt,
                        distanceMeters: 0,
                        speedMps: 0,
                        accelerationMps2: 0,
                        evidenceWeight: 0,
                        kind: .unobserved,
                        startedAt: previous.timestamp
                    )
                )
                continue
            }

            let distance = current.location.distance(from: previous.location)
            let impliedMps = distance / dt
            if impliedMps > 70 {
                draft.append(
                    TripFuelInterval(
                        dt: dt,
                        distanceMeters: 0,
                        speedMps: 0,
                        accelerationMps2: 0,
                        evidenceWeight: 0,
                        kind: .teleport,
                        startedAt: previous.timestamp
                    )
                )
                continue
            }

            let midpoint = previous.timestamp.addingTimeInterval(dt / 2)
            if excludedStops.contains(where: { $0.contains(midpoint) }) {
                draft.append(
                    TripFuelInterval(
                        dt: dt,
                        distanceMeters: distance,
                        speedMps: min(impliedMps, TripMotionThresholds.movingSpeedKmh / 3.6),
                        accelerationMps2: 0,
                        evidenceWeight: 0,
                        kind: .unobserved,
                        startedAt: previous.timestamp
                    )
                )
                continue
            }

            let impliedKmh = impliedMps * 3.6
            if impliedKmh < TripMotionThresholds.movingSpeedKmh {
                draft.append(
                    TripFuelInterval(
                        dt: dt,
                        distanceMeters: distance,
                        speedMps: impliedMps,
                        accelerationMps2: 0,
                        evidenceWeight: 1,
                        kind: .observedStop,
                        startedAt: previous.timestamp
                    )
                )
                continue
            }

            let sampleMps = TripSpeedSummary.effectiveSpeedMps(at: index, in: samples)
            let motionMps = sampleMps.map { min($0, impliedMps) } ?? impliedMps
            let kmh = motionMps * 3.6
            if kmh < TripMotionThresholds.movingSpeedKmh {
                draft.append(
                    TripFuelInterval(
                        dt: dt,
                        distanceMeters: distance,
                        speedMps: motionMps,
                        accelerationMps2: 0,
                        evidenceWeight: 1,
                        kind: .observedStop,
                        startedAt: previous.timestamp
                    )
                )
                continue
            }

            guard RecordingMovementPolicy.isRecordableSpeed(motionMps) else {
                draft.append(
                    TripFuelInterval(
                        dt: dt,
                        distanceMeters: 0,
                        speedMps: 0,
                        accelerationMps2: 0,
                        evidenceWeight: 0,
                        kind: .teleport,
                        startedAt: previous.timestamp
                    )
                )
                continue
            }

            draft.append(
                TripFuelInterval(
                    dt: dt,
                    distanceMeters: distance,
                    speedMps: motionMps,
                    accelerationMps2: 0,
                    evidenceWeight: 1,
                    kind: .moving,
                    startedAt: previous.timestamp
                )
            )
        }

        let evidenced = contextualizeStopEvidence(draft)
        let smoothed = smoothedAccelerations(evidenced)
        return summarize(smoothed, storedDistanceMeters: storedDistanceMeters)
    }

    static func build(
        points: [TripPoint],
        storedDistanceMeters: Double,
        excludedStops: [ExcludedStop] = []
    ) -> Result {
        build(
            samples: RouteDisplayPath.samples(from: points),
            storedDistanceMeters: storedDistanceMeters,
            excludedStops: excludedStops
        )
    }

    // MARK: - Smoothing

    /// Dense fixes are direct stop evidence. A sparse low-speed interval is ambiguous, so its
    /// support falls smoothly with duration and rises when moving intervals bound the stop run.
    /// There is intentionally no fixed "after N minutes discard everything" rule.
    private static func contextualizeStopEvidence(
        _ intervals: [TripFuelInterval]
    ) -> [TripFuelInterval] {
        var result = intervals
        var index = 0
        while index < result.count {
            guard result[index].kind == .observedStop else {
                index += 1
                continue
            }

            let start = index
            while index + 1 < result.count, result[index + 1].kind == .observedStop {
                index += 1
            }
            let end = index
            let movingBefore = start > 0 && result[start - 1].kind == .moving
            let movingAfter = end + 1 < result.count && result[end + 1].kind == .moving
            let contextWeight: Double
            switch (movingBefore, movingAfter) {
            case (true, true): contextWeight = 1
            case (true, false), (false, true): contextWeight = 0.65
            case (false, false): contextWeight = 0.25
            }

            for stopIndex in start...end {
                let dt = result[stopIndex].dt
                if dt <= TripMotionThresholds.maximumAccelIntervalSeconds {
                    result[stopIndex].evidenceWeight = 1
                } else {
                    // ≈90% at 5:50, 6% at 20 min, then asymptotically approaches zero.
                    let scaled = dt / (10 * 60)
                    let squared = scaled * scaled
                    let durationWeight = 1 / (1 + squared * squared)
                    result[stopIndex].evidenceWeight = contextWeight * durationWeight
                }
            }
            index += 1
        }
        return result
    }

    private static func smoothedAccelerations(_ intervals: [TripFuelInterval]) -> [TripFuelInterval] {
        guard !intervals.isEmpty else { return intervals }

        var speeds = intervals.map(\.speedMps)
        if speeds.count >= 3 {
            var median = speeds
            for index in 1..<(speeds.count - 1) {
                let window = [speeds[index - 1], speeds[index], speeds[index + 1]].sorted()
                let mid = window[1]
                let deviations = window.map { abs($0 - mid) }.sorted()
                let mad = deviations[1]
                if mad > 0, abs(speeds[index] - mid) > 3 * mad {
                    median[index] = mid
                } else {
                    median[index] = mid
                }
            }
            speeds = median
        }

        var result = intervals
        var previousMovingSpeed: Double?
        for index in result.indices {
            var interval = result[index]
            interval.speedMps = speeds[index]
            if interval.kind == .moving {
                let dt = interval.dt
                if dt >= TripMotionThresholds.minimumAccelIntervalSeconds,
                   dt <= TripMotionThresholds.maximumAccelIntervalSeconds,
                   let previousMovingSpeed {
                    let raw = (interval.speedMps - previousMovingSpeed) / dt
                    let cap = TripMotionThresholds.maximumAbsAccelerationMps2
                    if abs(raw) > cap {
                        interval.accelerationMps2 = 0
                        interval.accelerationAvailable = false
                    } else {
                        interval.accelerationMps2 = raw
                        interval.accelerationAvailable = true
                    }
                } else {
                    interval.accelerationMps2 = 0
                    interval.accelerationAvailable = false
                }
                previousMovingSpeed = interval.speedMps
            } else if interval.kind != .observedStop {
                previousMovingSpeed = nil
            }
            result[index] = interval
        }
        return result
    }

    private static func summarize(
        _ intervals: [TripFuelInterval],
        storedDistanceMeters: Double
    ) -> Result {
        var movingMeters = 0.0
        var stopSeconds: TimeInterval = 0
        var unobservedSeconds: TimeInterval = 0
        var teleportCount = 0
        var usableSeconds: TimeInterval = 0
        var stopRunDuration: TimeInterval = 0

        func flushStopRun() {
            guard stopRunDuration > 0 else { return }
            stopSeconds += idleCreditSeconds(forRunDuration: stopRunDuration)
            stopRunDuration = 0
        }

        for interval in intervals {
            switch interval.kind {
            case .moving:
                flushStopRun()
                movingMeters += interval.distanceMeters
                usableSeconds += interval.dt
            case .observedStop:
                let supportedSeconds = interval.dt * interval.evidenceWeight
                usableSeconds += supportedSeconds
                unobservedSeconds += interval.dt - supportedSeconds
                stopRunDuration += supportedSeconds
            case .unobserved:
                flushStopRun()
                unobservedSeconds += interval.dt
            case .teleport:
                flushStopRun()
                teleportCount += 1
            }
        }
        flushStopRun()

        let stored = max(0, storedDistanceMeters)
        let distanceAgreement: Double
        if stored <= 1 || movingMeters <= 1 {
            distanceAgreement = stored > 1 && movingMeters <= 1 ? 0.15 : 1
        } else {
            distanceAgreement = min(movingMeters, stored) / max(movingMeters, stored)
        }

        let accounted = usableSeconds + unobservedSeconds
        let coverage = accounted > 0 ? usableSeconds / accounted : 0
        let teleportPenalty = min(0.4, Double(teleportCount) * 0.08)
        let sampleFactor = intervals.count >= 8 ? 1.0 : Double(intervals.count) / 8.0
        let confidence = min(
            1,
            max(0, distanceAgreement * (0.45 + 0.55 * coverage) * sampleFactor - teleportPenalty)
        )

        return Result(
            intervals: intervals,
            observedMovingMeters: movingMeters,
            observedStopSeconds: stopSeconds,
            unobservedSeconds: unobservedSeconds,
            confidence: confidence
        )
    }
}
