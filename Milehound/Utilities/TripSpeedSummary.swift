import CoreLocation
import Foundation

/// Speed read back from a stored route, without trusting `Trip.maxSpeedMps`.
///
/// Trips recorded before speeds were vetted carry maxima that no point ever reached — one bad fix
/// at the start of a drive was enough to claim 203 km/h. Nothing here writes: the stored field is
/// left exactly as it is and the honest number is derived from the points on every read.
enum TripSpeedSummary {
    /// A single sample cannot set the record. Bogus peaks are always one sample wide, because the
    /// fix after them lands back on the real route, so requiring a peak to last is enough to tell
    /// the two apart.
    static let minimumSustainedSamples = 3

    /// Speed at a point: the stored reading, or what the distance from the previous point implies
    /// when Core Location had none. Shared so the chart, the route coloring and the trip maximum
    /// all quote the same number.
    static func effectiveSpeedMps(at index: Int, in samples: [RouteSample]) -> Double? {
        let sample = samples[index]
        if let stored = sample.speedMps, RecordingMovementPolicy.isRecordableSpeed(stored) {
            return stored
        }
        guard index > 0 else { return nil }
        let previous = samples[index - 1]
        let delta = sample.location.distance(from: previous.location)
        let timeDelta = max(0.01, sample.timestamp.timeIntervalSince(previous.timestamp))
        let implied = delta / timeDelta
        return RecordingMovementPolicy.isRecordableSpeed(implied) ? implied : nil
    }

    static func speedsMps(in samples: [RouteSample]) -> [Double?] {
        samples.indices.map { effectiveSpeedMps(at: $0, in: samples) }
    }

    /// The fastest speed the route actually sustained, or nil when it never reported one.
    ///
    /// Implemented as the largest value that `minimumSustainedSamples` consecutive samples all
    /// reach — the maximum over sliding-window minima. A lone 203 km/h between two 10 km/h
    /// samples contributes 10; a real run of 120, 122, 121 contributes 120.
    static func maxSpeedMps(samples: [RouteSample]) -> Double? {
        let speeds = speedsMps(in: samples)
        guard !speeds.isEmpty else { return nil }
        guard speeds.count >= minimumSustainedSamples else {
            // Too short to corroborate anything, so there is no sustained speed to report.
            return nil
        }

        var best: Double?
        for start in 0...(speeds.count - minimumSustainedSamples) {
            let window = speeds[start..<(start + minimumSustainedSamples)]
            // One missing reading breaks the run: an unknown speed cannot vouch for a peak.
            guard let slowest = window.min(by: sortsBeforeTreatingNilAsSmallest), let slowest else {
                continue
            }
            if slowest > (best ?? 0) { best = slowest }
        }
        return best
    }

    static func maxSpeedMps(points: [TripPoint]) -> Double? {
        maxSpeedMps(samples: RouteDisplayPath.samples(from: points))
    }

    /// A stored maximum worth showing, or nil when it exceeds what a car can do. Used by the
    /// surfaces that must not load a trip's points — trip rows and statistics — where hiding a
    /// number the recorder should never have written beats displaying it.
    static func believableStoredMaxSpeedMps(_ storedMps: Double?) -> Double? {
        storedMps.flatMap { RecordingMovementPolicy.isRecordableSpeed($0) ? $0 : nil }
    }

    private static func sortsBeforeTreatingNilAsSmallest(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let rhs else { return false }
        guard let lhs else { return true }
        return lhs < rhs
    }
}
