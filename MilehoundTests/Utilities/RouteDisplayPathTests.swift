import CoreLocation
import XCTest
@testable import Milehound

final class RouteDisplayPathTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 38.42, longitude: 27.14)

    /// Straight eastward run of `count` samples spaced `spacingMeters` apart at ~50 km/h.
    private func route(
        count: Int,
        spacingMeters: Double,
        startingAt start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        from base: CLLocationCoordinate2D? = nil
    ) -> [RouteSample] {
        let anchor = base ?? origin
        let metersPerDegreeLongitude = 111_320 * cos(anchor.latitude * .pi / 180)
        let speedMps: Double = 14
        return (0..<count).map { index in
            let offset = Double(index) * spacingMeters
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude,
                    longitude: anchor.longitude + offset / metersPerDegreeLongitude
                ),
                timestamp: start.addingTimeInterval(offset / speedMps),
                speedMps: speedMps
            )
        }
    }

    func testDenseRouteWithOneTeleportSplitsInTwo() {
        var samples = route(count: 200, spacingMeters: 12)
        let last = samples[samples.count - 1]
        // 40 km away one second later: impossible, so the route must break here.
        let jumped = CLLocationCoordinate2D(
            latitude: last.coordinate.latitude + 0.36,
            longitude: last.coordinate.longitude
        )
        samples.append(
            RouteSample(coordinate: jumped, timestamp: last.timestamp.addingTimeInterval(1), speedMps: 14)
        )
        samples.append(contentsOf: route(count: 120, spacingMeters: 12, startingAt: last.timestamp.addingTimeInterval(2), from: jumped))

        let pieces = RouteDisplayPath.displaySegments(samples: samples)

        XCTAssertEqual(pieces.count, 2)
    }

    func testDenseRouteWithoutGapsStaysOnePiece() {
        let pieces = RouteDisplayPath.displaySegments(samples: route(count: 500, spacingMeters: 14))
        XCTAssertEqual(pieces.count, 1)
    }

    /// The regression that produced the reported broken maps: an already-simplified legacy trip
    /// (about 5 points per km) must still draw as one continuous line.
    func testSparseLegacyRouteStaysOnePiece() {
        let samples = route(count: 143, spacingMeters: 180)
        XCTAssertEqual(RouteDisplayPath.displaySegments(samples: samples).count, 1)
    }

    func testChordLimitRelaxesOnlyForSparseRoutes() {
        let dense = RouteDisplayPath.chordLimitsMeters(samples: route(count: 100, spacingMeters: 12))
        XCTAssertEqual(dense.count, 99)
        XCTAssertTrue(dense.allSatisfy { $0 == RouteDisplayPath.baseChordLimitMeters })

        let sparse = RouteDisplayPath.chordLimitsMeters(samples: route(count: 100, spacingMeters: 180))
        XCTAssertTrue(sparse.allSatisfy { !$0.isFinite })
    }

    /// Merging an already-simplified legacy trip onto a densely recorded one used to break the
    /// legacy leg apart: judged over the whole route, the dense leg's spacing won the vote and
    /// the legacy leg's legitimate long chords were treated as gaps.
    func testMergedSparseAndDenseLegsAreJudgedSeparately() throws {
        let sparse = route(count: 60, spacingMeters: 700)
        let seam = sparse[sparse.count - 1]
        let dense = route(
            count: 600,
            spacingMeters: 12,
            startingAt: seam.timestamp.addingTimeInterval(1),
            from: seam.coordinate
        )

        let pieces = RouteDisplayPath.displaySegments(samples: sparse + dense)

        XCTAssertEqual(try XCTUnwrap(pieces.first).count, sparse.count)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.count }, sparse.count + dense.count)
    }

    func testDecimateStaysWithinBudgetAndKeepsEnds() {
        let samples = route(count: 6000, spacingMeters: 12)
        let decimated = RouteDisplayPath.decimate(samples: samples)

        XCTAssertLessThanOrEqual(decimated.count, RouteDisplayPath.maxDisplayPoints)
        XCTAssertEqual(decimated.first, samples.first)
        XCTAssertEqual(decimated.last, samples.last)
    }

    func testDecimateNeverLeavesAChordAboveTheLimit() {
        let samples = route(count: 6000, spacingMeters: 12)
        let decimated = RouteDisplayPath.decimate(samples: samples)

        let longest = RouteDisplayPath.spacingsMeters(samples: decimated).max() ?? 0
        XCTAssertLessThanOrEqual(longest, RouteDisplayPath.baseChordLimitMeters)
    }

    func testDecimatedLongRouteStillDrawsAsOnePiece() {
        let pieces = RouteDisplayPath.displaySegments(samples: route(count: 6000, spacingMeters: 12))
        XCTAssertEqual(pieces.count, 1)
    }

    func testEmptyAndSinglePointInputsAreSafe() {
        XCTAssertTrue(RouteDisplayPath.displaySegments(samples: []).isEmpty)
        XCTAssertEqual(RouteDisplayPath.displaySegments(samples: route(count: 1, spacingMeters: 12)).count, 1)
        XCTAssertTrue(RouteDisplayPath.spacingsMeters(samples: []).isEmpty)
        XCTAssertEqual(RouteDisplayPath.decimate(samples: []).count, 0)
    }

    /// Sinusoidal route — every original point must stay within the decimation tolerance of the
    /// surviving polyline. This is the regression for "does thinning straighten curves?".
    func testDecimatePreservesShapeOnCurvyRoute() {
        let samples = curvyRoute(count: 4_000, wavelengthMeters: 80, amplitudeMeters: 25)
        let decimated = RouteDisplayPath.decimate(samples: samples)
        let tolerance = RouteDisplayPath.scaleToleranceMeters(samples: samples)
        let deviation = RouteDisplayPath.maxDeviationMeters(original: samples, decimated: decimated)
        XCTAssertLessThanOrEqual(deviation, tolerance + 0.5)
    }

    func testDecimateStaysWithinBudgetOnCurvyRoute() {
        let samples = curvyRoute(count: 8_000, wavelengthMeters: 60, amplitudeMeters: 20)
        let decimated = RouteDisplayPath.decimate(samples: samples)
        XCTAssertLessThanOrEqual(decimated.count, RouteDisplayPath.maxDisplayPoints)
        XCTAssertEqual(decimated.first, samples.first)
        XCTAssertEqual(decimated.last, samples.last)
    }

    /// A tight roundabout must keep enough vertices that the simplified ring still encloses
    /// most of the original area — not collapse to a chord across the circle.
    func testRoundaboutSurvivesDecimation() {
        let samples = roundabout(radiusMeters: 18, pointCount: 120)
        let decimated = RouteDisplayPath.decimate(
            samples: samples,
            maxCount: 40,
            chordCapMeters: RouteDisplayPath.baseChordLimitMeters
        )
        XCTAssertGreaterThan(decimated.count, 8)
        let originalSpan = boundingSpanMeters(samples)
        let simplifiedSpan = boundingSpanMeters(decimated)
        XCTAssertGreaterThan(simplifiedSpan, originalSpan * 0.7)
    }

    private func curvyRoute(
        count: Int,
        wavelengthMeters: Double,
        amplitudeMeters: Double,
        startingAt start: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> [RouteSample] {
        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(origin.latitude * .pi / 180)
        let stepMeters = 8.0
        let speedMps = 14.0
        return (0..<count).map { index in
            let along = Double(index) * stepMeters
            let lateral = sin(along / wavelengthMeters * 2 * .pi) * amplitudeMeters
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: origin.latitude + lateral / metersPerDegreeLatitude,
                    longitude: origin.longitude + along / metersPerDegreeLongitude
                ),
                timestamp: start.addingTimeInterval(along / speedMps),
                speedMps: speedMps
            )
        }
    }

    private func roundabout(
        radiusMeters: Double,
        pointCount: Int,
        startingAt start: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> [RouteSample] {
        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(origin.latitude * .pi / 180)
        return (0..<pointCount).map { index in
            let angle = Double(index) / Double(pointCount) * 2 * .pi
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: origin.latitude + (sin(angle) * radiusMeters) / metersPerDegreeLatitude,
                    longitude: origin.longitude + (cos(angle) * radiusMeters) / metersPerDegreeLongitude
                ),
                timestamp: start.addingTimeInterval(Double(index)),
                speedMps: 8
            )
        }
    }

    private func boundingSpanMeters(_ samples: [RouteSample]) -> Double {
        guard let first = samples.first else { return 0 }
        var minLat = first.coordinate.latitude
        var maxLat = minLat
        var minLon = first.coordinate.longitude
        var maxLon = minLon
        for sample in samples.dropFirst() {
            minLat = min(minLat, sample.coordinate.latitude)
            maxLat = max(maxLat, sample.coordinate.latitude)
            minLon = min(minLon, sample.coordinate.longitude)
            maxLon = max(maxLon, sample.coordinate.longitude)
        }
        let midLat = (minLat + maxLat) / 2
        return hypot(
            (maxLat - minLat) * 111_132,
            (maxLon - minLon) * 111_320 * cos(midLat * .pi / 180)
        )
    }
}
