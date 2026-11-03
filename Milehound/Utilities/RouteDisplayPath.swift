import CoreLocation
import Foundation

/// A recorded point reduced to the values drawing needs — keeps `RouteDisplayPath` free of
/// SwiftData so it can be unit tested without a model container.
struct RouteSample: Equatable {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let speedMps: Double?

    init(coordinate: CLLocationCoordinate2D, timestamp: Date, speedMps: Double?) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.speedMps = speedMps
    }

    var location: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func == (lhs: RouteSample, rhs: RouteSample) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.timestamp == rhs.timestamp
            && lhs.speedMps == rhs.speedMps
    }
}

/// Turns stored trip points into drawable polyline pieces.
///
/// Stored points are never modified — this is purely a read-path transform. Two jobs:
///
/// 1. Bound how many points reach MapKit/Canvas, without ever introducing a chord long
///    enough to be mistaken for a GPS gap.
/// 2. Decide where the route genuinely breaks (teleports, signal loss) versus where a long
///    straight chord is legitimate.
enum RouteDisplayPath {
    /// Upper bound on points handed to the renderer for one route.
    static let maxDisplayPoints = 1500

    /// Deviation budget when decimating; well below map pixel size at trip-fitting zoom.
    static let decimationToleranceMeters: Double = 3

    /// Assumed on-screen width of a trip-fitting map when deriving scale-based tolerance.
    static let overviewTargetPixels: Double = 400

    /// Longest chord drawn for a densely recorded route. Beyond this the actual path is
    /// unknown (tunnel, signal loss) so the route breaks instead of inventing a straight line.
    static let baseChordLimitMeters: CLLocationDistance = 450

    /// Median spacing above this means the stored points are already a simplified polyline
    /// rather than a raw recording. Live recording samples every few meters, so a healthy
    /// trip never lands here.
    static let sparseRouteMedianSpacingMeters: CLLocationDistance = 60

    /// How many spacings on each side of a chord are used to judge how densely that stretch of
    /// the route was recorded.
    static let densityWindowRadius = 12

    /// Test seam: increments every time `displaySegments` runs. Reveal must not bump this.
    nonisolated(unsafe) static var testDisplaySegmentsInvocations = 0

    static func samples(from points: [TripPoint]) -> [RouteSample] {
        points.map {
            RouteSample(coordinate: $0.coordinate, timestamp: $0.timestamp, speedMps: $0.speedMps)
        }
    }

    /// Drawable pieces for a stored route, decimated for cost and split only on real gaps.
    static func displaySegments(samples: [RouteSample]) -> [[RouteSample]] {
        testDisplaySegmentsInvocations += 1
        guard samples.count >= 2 else {
            return samples.isEmpty ? [] : [samples]
        }

        let display = decimate(
            samples: samples,
            maxCount: maxDisplayPoints,
            chordCapMeters: baseChordLimitMeters
        )
        return split(samples: display, chordLimits: chordLimitsMeters(samples: display))
    }

    /// Flattened drawable coordinates — for callers that want one path per piece.
    static func displaySegmentCoordinates(samples: [RouteSample]) -> [[CLLocationCoordinate2D]] {
        displaySegments(samples: samples).map { $0.map(\.coordinate) }
    }

    /// Privacy-clipped drawable pieces for a stored trip. Clipping happens before decimation
    /// so the trimmed ends never reappear as display points.
    /// Share card uses the same clip-then-decimate order via `TripShareRoutePrep`.
    static func displaySegmentCoordinates(
        trip: Trip,
        privacyRadiusMeters: Double,
        places: [SavedPlace]
    ) -> [[CLLocationCoordinate2D]] {
        let samples = samples(from: trip.sortedPoints)
        let range = RoutePrivacyClipper.clippedRange(
            samples.map(\.coordinate),
            privacyRadiusMeters: privacyRadiusMeters,
            places: places.map(RoutePrivacyPlace.init)
        )
        return displaySegmentCoordinates(samples: Array(samples[range]))
    }

    /// How long each chord may be before it counts as a gap — one limit per consecutive pair.
    ///
    /// Densely recorded stretches keep the conservative limit. Stretches whose stored points are
    /// already a simplified polyline get no distance cap: Douglas-Peucker only drops points
    /// that sit within a few meters of the chord, so drawing those chords is accurate — and
    /// implausible-speed teleports are still caught by `RecordingMovementPolicy`.
    ///
    /// The density is measured locally rather than over the whole route, because a merged trip
    /// mixes both kinds. Judged as a whole, a densely recorded leg outvotes a sparse legacy one,
    /// and the sparse leg's legitimate long chords suddenly read as gaps — the merged trip falls
    /// apart on the map even though every point survived the merge.
    static func chordLimitsMeters(samples: [RouteSample]) -> [CLLocationDistance] {
        let spacings = spacingsMeters(samples: samples)
        return spacings.indices.map { index in
            let window = spacings[
                max(spacings.startIndex, index - densityWindowRadius)
                    ..< min(spacings.endIndex, index + densityWindowRadius + 1)
            ]
            let local = median(of: Array(window)) ?? 0
            return local > sparseRouteMedianSpacingMeters ? .infinity : baseChordLimitMeters
        }
    }

    static func spacingsMeters(samples: [RouteSample]) -> [CLLocationDistance] {
        guard samples.count >= 2 else { return [] }
        return (1..<samples.count).map { index in
            samples[index].location.distance(from: samples[index - 1].location)
        }
    }

    /// Douglas-Peucker reduction that then re-inserts points wherever the surviving chord
    /// would exceed `chordCapMeters`, so decimation can never manufacture a false gap.
    ///
    /// Tolerance starts at `decimationToleranceMeters` and rises toward one on-screen pixel
    /// (derived from the route bounding box) when the result still exceeds `maxCount`. Chord
    /// re-insertion is never skipped — a false long gap is worse than a few extra points.
    static func decimate(
        samples: [RouteSample],
        maxCount: Int = maxDisplayPoints,
        chordCapMeters: CLLocationDistance = baseChordLimitMeters
    ) -> [RouteSample] {
        guard samples.count > maxCount, samples.count > 2 else { return samples }

        let pixelTolerance = scaleToleranceMeters(samples: samples, pixels: overviewTargetPixels)
        var tolerance = max(decimationToleranceMeters, pixelTolerance / 2)

        var result = decimateOnce(
            samples: samples,
            toleranceMeters: tolerance,
            chordCapMeters: chordCapMeters
        )

        while result.count > maxCount && tolerance < pixelTolerance - 0.01 {
            tolerance = min(pixelTolerance, tolerance * 1.5)
            result = decimateOnce(
                samples: samples,
                toleranceMeters: tolerance,
                chordCapMeters: chordCapMeters
            )
        }

        if result.count > maxCount {
            result = enforceBudget(
                samples: result,
                maxCount: maxCount,
                chordCapMeters: chordCapMeters
            )
        }

        guard result.count < samples.count else { return samples }
        return result
    }

    /// Half-pixel / full-pixel tolerance from the route's geographic span.
    /// Always at least `decimationToleranceMeters` so short trips stay crisp.
    static func scaleToleranceMeters(
        samples: [RouteSample],
        pixels: Double = overviewTargetPixels
    ) -> Double {
        guard samples.count >= 2, pixels > 0 else { return decimationToleranceMeters }
        var minLat = samples[0].coordinate.latitude
        var maxLat = minLat
        var minLon = samples[0].coordinate.longitude
        var maxLon = minLon
        for sample in samples.dropFirst() {
            minLat = min(minLat, sample.coordinate.latitude)
            maxLat = max(maxLat, sample.coordinate.latitude)
            minLon = min(minLon, sample.coordinate.longitude)
            maxLon = max(maxLon, sample.coordinate.longitude)
        }
        let midLat = (minLat + maxLat) / 2
        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(midLat * .pi / 180)
        let diagonal = hypot(
            (maxLat - minLat) * metersPerDegreeLatitude,
            (maxLon - minLon) * metersPerDegreeLongitude
        )
        return max(decimationToleranceMeters, diagonal / pixels)
    }

    /// Maximum perpendicular distance from every original sample to the decimated polyline.
    static func maxDeviationMeters(
        original: [RouteSample],
        decimated: [RouteSample]
    ) -> Double {
        guard original.count >= 2, decimated.count >= 2 else { return 0 }
        let referenceLatitude = original[original.count / 2].coordinate.latitude
        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(referenceLatitude * .pi / 180)

        func project(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                coordinate.longitude * metersPerDegreeLongitude,
                coordinate.latitude * metersPerDegreeLatitude
            )
        }

        let poly = decimated.map { project($0.coordinate) }
        var maxDistance = 0.0
        for sample in original {
            let point = project(sample.coordinate)
            var best = Double.greatestFiniteMagnitude
            for index in 1..<poly.count {
                let start = poly[index - 1]
                let end = poly[index]
                let dx = end.x - start.x
                let dy = end.y - start.y
                if dx == 0 && dy == 0 {
                    best = min(best, hypot(point.x - start.x, point.y - start.y))
                    continue
                }
                let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
                best = min(best, hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy)))
            }
            maxDistance = max(maxDistance, best)
        }
        return maxDistance
    }

    private static func decimateOnce(
        samples: [RouteSample],
        toleranceMeters: Double,
        chordCapMeters: CLLocationDistance
    ) -> [RouteSample] {
        let kept = DistanceCalculator.simplifiedIndices(
            coordinates: samples.map(\.coordinate),
            toleranceMeters: toleranceMeters
        )
        guard kept.count >= 2 else { return samples }
        let restored = reinsertIndices(
            keeping: kept,
            in: samples,
            chordCapMeters: chordCapMeters
        )
        return restored.map { samples[$0] }
    }

    /// Evenly thins an already-decimated path while still re-inserting for the chord cap.
    /// May still exceed `maxCount` when the chord cap forces denser sampling — that is intentional.
    private static func enforceBudget(
        samples: [RouteSample],
        maxCount: Int,
        chordCapMeters: CLLocationDistance
    ) -> [RouteSample] {
        guard samples.count > maxCount, maxCount >= 2 else { return samples }

        var kept: [Int] = [0]
        let inner = maxCount - 2
        if inner > 0 {
            for step in 1...inner {
                let index = Int((Double(step) * Double(samples.count - 1) / Double(maxCount - 1)).rounded())
                if index > kept[kept.count - 1], index < samples.count - 1 {
                    kept.append(index)
                }
            }
        }
        if kept[kept.count - 1] != samples.count - 1 {
            kept.append(samples.count - 1)
        }

        let restored = reinsertIndices(
            keeping: kept,
            in: samples,
            chordCapMeters: chordCapMeters
        )
        return restored.map { samples[$0] }
    }

    private static func reinsertIndices(
        keeping kept: [Int],
        in samples: [RouteSample],
        chordCapMeters: CLLocationDistance
    ) -> [Int] {
        guard chordCapMeters.isFinite else { return kept }

        var result: [Int] = [kept[0]]
        var anchor = kept[0]

        for target in kept.dropFirst() {
            if target > anchor + 1 {
                for candidate in (anchor + 1)..<target {
                    let next = candidate + 1
                    let anchorToNext = samples[next].location.distance(from: samples[anchor].location)
                    if anchorToNext > chordCapMeters {
                        result.append(candidate)
                        anchor = candidate
                    }
                }
            }
            result.append(target)
            anchor = target
        }

        return result
    }

    /// Splits on implausible movement (teleport / stationary jitter) and on chords longer than
    /// the limit `chordLimits` gives for that pair.
    static func split(
        samples: [RouteSample],
        chordLimits: [CLLocationDistance]
    ) -> [[RouteSample]] {
        guard samples.count >= 2 else {
            return samples.isEmpty ? [] : [samples]
        }

        var segments: [[RouteSample]] = []
        var current: [RouteSample] = [samples[0]]

        for index in 1..<samples.count {
            let limit = index <= chordLimits.count ? chordLimits[index - 1] : baseChordLimitMeters
            if shouldConnect(samples[index - 1], samples[index], chordLimitMeters: limit) {
                current.append(samples[index])
                continue
            }
            if current.count >= 2 { segments.append(current) }
            current = [samples[index]]
        }

        if current.count >= 2 { segments.append(current) }
        return segments
    }

    static func shouldConnect(
        _ previous: RouteSample,
        _ current: RouteSample,
        chordLimitMeters: CLLocationDistance
    ) -> Bool {
        let delta = current.location.distance(from: previous.location)
        let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
        let speed = RecordingMovementPolicy.effectiveSpeedMps(
            locationSpeedMps: current.speedMps ?? -1,
            delta: delta,
            timeDelta: timeDelta
        ) ?? 0
        return RecordingMovementPolicy.shouldDrawMapSegment(
            delta: delta,
            timeDelta: timeDelta,
            speed: speed,
            chordLimitMeters: chordLimitMeters
        )
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
