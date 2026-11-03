import CoreLocation
import Foundation

enum RecordingMovementPolicy {
    enum Decision: Equatable {
        /// Jitter / stationary — ignore completely.
        case ignore
        /// Plausible movement — add distance and optionally a point.
        case accumulate
        /// Impossible GPS jump — advance anchor and record a point, but do not add distance.
        case gapResume
    }

    static let minimumDistanceSampleMeters: CLLocationDistance = 2
    static let stationarySpeedMps: Double = 0.5
    static let stationaryDistanceMeters: CLLocationDistance = 5
    /// Above this a jump between two fixes is physically impossible, so it is signal loss rather
    /// than movement. Deliberately generous — it guards gap detection, not the speedometer.
    static let maximumPlausibleSpeedMps: Double = 70
    /// Do not draw a map chord longer than this (sparse GPS may still count distance).
    static let mapMaxChordMeters: CLLocationDistance = 450
    /// Same-timestamp / sub-second batch fixes at trip start look like teleports once
    /// `timeDelta` is floored to 0.01 s (7 m → 700 m/s → gapResume). Treat as convergence.
    static let minimumMovementTimeDeltaSeconds: TimeInterval = 0.5

    // MARK: - Speed trust

    /// Fastest speed worth writing down for a car. Separate from `maximumPlausibleSpeedMps`,
    /// which answers a different question: 203 km/h is a believable *jump* between two bad fixes
    /// but not a believable *speed*, and a trip once recorded 203 km/h that never happened.
    static let maximumRecordedSpeedMps: Double = 50

    /// Core Location's own estimate of how wrong `speed` may be. A good fix reports well under
    /// 1 m/s; a converging one reports several, which is exactly the trip-start spike.
    static let maximumSpeedAccuracyMps: Double = 3

    /// A fix this uncertain about *where* it is cannot be trusted about how fast it is moving.
    /// Only the speed is discarded — the position is still stored, because dropping points is
    /// what makes routes look broken.
    static let maximumSpeedFixAccuracyMeters: CLLocationDistance = 65

    /// Recording start replays the last cached fix, which may be two minutes old and still
    /// carry the speed of an earlier drive.
    static let maximumSpeedFixAgeSeconds: TimeInterval = 5

    /// Roughly 0-100 km/h in 3.5 s: quicker than any car this app will see, so anything above
    /// is the GPS changing its mind rather than the driver accelerating.
    static let maximumAccelerationMps2: Double = 8

    /// Whether a speed is worth writing onto a point or into a trip's maximum.
    static func isRecordableSpeed(_ speedMps: Double) -> Bool {
        speedMps > 0 && speedMps <= maximumRecordedSpeedMps
    }

    /// Core Location's reported speed, or nil when it cannot be trusted.
    ///
    /// Pass `speedAccuracyMps` straight from `CLLocation.speedAccuracy`, where a negative value
    /// means the speed is invalid.
    static func trustedGPSSpeedMps(
        reportedMps: Double,
        speedAccuracyMps: Double,
        horizontalAccuracyMeters: CLLocationDistance,
        fixAgeSeconds: TimeInterval
    ) -> Double? {
        guard reportedMps >= 0, reportedMps <= maximumRecordedSpeedMps else { return nil }
        guard speedAccuracyMps >= 0, speedAccuracyMps <= maximumSpeedAccuracyMps else { return nil }
        guard horizontalAccuracyMeters >= 0,
              horizontalAccuracyMeters <= maximumSpeedFixAccuracyMeters else { return nil }
        guard fixAgeSeconds <= maximumSpeedFixAgeSeconds else { return nil }
        return reportedMps
    }

    /// Whether going from `previousMps` to `currentMps` in `timeDelta` is something a car can do.
    /// With no previous speed there is nothing to compare against, so the sample is allowed.
    static func isPlausibleAcceleration(
        from previousMps: Double?,
        to currentMps: Double,
        timeDelta: TimeInterval
    ) -> Bool {
        guard let previousMps else { return true }
        let safeTime = max(0.01, timeDelta)
        return abs(currentMps - previousMps) / safeTime <= maximumAccelerationMps2
    }

    /// Which gate rejected a speed, for the developer log. Nil when the speed was accepted.
    static func speedRejectionReason(
        reportedMps: Double,
        speedAccuracyMps: Double,
        horizontalAccuracyMeters: CLLocationDistance,
        fixAgeSeconds: TimeInterval
    ) -> String? {
        if reportedMps < 0 { return "no_gps_speed" }
        if reportedMps > maximumRecordedSpeedMps { return "over_ceiling" }
        if speedAccuracyMps < 0 { return "speed_invalid" }
        if speedAccuracyMps > maximumSpeedAccuracyMps { return "speed_uncertain" }
        if horizontalAccuracyMeters < 0 || horizontalAccuracyMeters > maximumSpeedFixAccuracyMeters {
            return "fix_uncertain"
        }
        if fixAgeSeconds > maximumSpeedFixAgeSeconds { return "fix_stale" }
        return nil
    }

    static func decision(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        speed: Double
    ) -> Decision {
        decision(delta: delta, timeDelta: timeDelta, locationSpeedMps: speed)
    }

    static func decision(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        locationSpeedMps: Double
    ) -> Decision {
        guard delta >= minimumDistanceSampleMeters else { return .ignore }
        // GPS convergence batches often share a timestamp; do not invent a gapResume.
        guard timeDelta >= minimumMovementTimeDeltaSeconds else { return .ignore }

        let safeTimeDelta = max(0.01, timeDelta)
        let impliedSpeedMps = delta / safeTimeDelta
        let movementSpeedMps = locationSpeedMps > 0 ? locationSpeedMps : impliedSpeedMps

        if movementSpeedMps < stationarySpeedMps, delta < stationaryDistanceMeters {
            return .ignore
        }

        if impliedSpeedMps > maximumPlausibleSpeedMps {
            return .gapResume
        }
        return .accumulate
    }

    static func isPlausibleRecordedSpeed(_ speedMps: Double) -> Bool {
        speedMps > 0 && speedMps <= maximumPlausibleSpeedMps
    }

    /// Prefer GPS speed; fall back to distance / time when Core Location reports invalid speed (-1).
    static func effectiveSpeedMps(
        locationSpeedMps: Double,
        delta: CLLocationDistance,
        timeDelta: TimeInterval
    ) -> Double? {
        if isPlausibleRecordedSpeed(locationSpeedMps) {
            return locationSpeedMps
        }
        let safeTime = max(0.01, timeDelta)
        let implied = delta / safeTime
        if isPlausibleRecordedSpeed(implied) {
            return implied
        }
        return nil
    }

    /// Whether map should connect two stored points (distance may still accumulate for longer sparse gaps).
    ///
    /// `chordLimitMeters` is relaxed by `RouteDisplayPath` for routes whose stored points are
    /// already a simplified polyline, where long chords are geometrically accurate.
    static func shouldDrawMapSegment(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        speed: Double,
        chordLimitMeters: CLLocationDistance = mapMaxChordMeters
    ) -> Bool {
        guard decision(delta: delta, timeDelta: timeDelta, speed: speed) == .accumulate else {
            return false
        }
        return delta <= chordLimitMeters
    }
}
