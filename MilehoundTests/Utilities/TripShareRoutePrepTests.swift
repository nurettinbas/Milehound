import CoreLocation
import XCTest
@testable import Milehound

final class TripShareRoutePrepTests: XCTestCase {
    func testPrivacyRadiusClipsEndsAndChartUsesClippedSamples() {
        let points = straightRoutePoints(count: 80, spacingMeters: 40)
        let prep = TripShareRoutePrep.prepare(
            points: points,
            privacyRadiusMeters: 500,
            places: []
        )

        XCTAssertLessThan(prep.clippedPoints.count, points.count)
        XCTAssertGreaterThanOrEqual(prep.clippedPoints.count, 2)

        let start = CLLocation(
            latitude: points[0].latitude,
            longitude: points[0].longitude
        )
        let clippedStart = CLLocation(
            latitude: prep.clippedPoints[0].latitude,
            longitude: prep.clippedPoints[0].longitude
        )
        XCTAssertGreaterThan(clippedStart.distance(from: start), 400)

        // Chart must not extend past the clipped geometry's timestamps.
        if let firstChart = prep.chartSeries.samples.first,
           let lastChart = prep.chartSeries.samples.last,
           let firstClipped = prep.clippedPoints.first,
           let lastClipped = prep.clippedPoints.last {
            XCTAssertGreaterThanOrEqual(firstChart.date, firstClipped.timestamp)
            XCTAssertLessThanOrEqual(lastChart.date, lastClipped.timestamp)
        } else {
            XCTFail("expected clipped chart samples")
        }
    }

    func testZeroPrivacyRadiusKeepsFullPath() {
        let points = straightRoutePoints(count: 40, spacingMeters: 40)
        let prep = TripShareRoutePrep.prepare(
            points: points,
            privacyRadiusMeters: 0,
            places: []
        )

        XCTAssertEqual(prep.clippedPoints.count, points.count)
        XCTAssertEqual(prep.start?.latitude, points.first?.latitude)
        XCTAssertEqual(prep.end?.latitude, points.last?.latitude)
    }

    func testMapStrokesMatchSpeedColoredSegmentBuilder() {
        let points = straightRoutePoints(count: 60, spacingMeters: 30, speedMps: 20)
        let prep = TripShareRoutePrep.prepare(
            points: points,
            privacyRadiusMeters: 200,
            places: []
        )

        let samples = points.map {
            RouteSample(
                coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                timestamp: $0.timestamp,
                speedMps: $0.speedMps
            )
        }
        let range = RoutePrivacyClipper.clippedRange(
            samples.map(\.coordinate),
            privacyRadiusMeters: 200,
            places: [RoutePrivacyPlace]()
        )
        let clipped = Array(samples[range])
        let pieces = RouteDisplayPath.displaySegments(samples: clipped)
        let expected = SpeedColoredSegmentBuilder.build(pieces: pieces)

        XCTAssertEqual(prep.strokes.count, expected.count)
        for (stroke, segment) in zip(prep.strokes, expected) {
            XCTAssertEqual(stroke.bandRawValue, segment.band.rawValue)
            XCTAssertEqual(stroke.coordinates.count, segment.coordinates.count)
            if let s = stroke.coordinates.first, let e = segment.coordinates.first {
                XCTAssertEqual(s.latitude, e.latitude, accuracy: 1e-12)
                XCTAssertEqual(s.longitude, e.longitude, accuracy: 1e-12)
            }
        }
    }

    func testChartAndMapShareSameClippedEndpoints() {
        let points = straightRoutePoints(count: 100, spacingMeters: 50)
        let home = TripShareRoutePrep.Place(
            latitude: points[0].latitude,
            longitude: points[0].longitude,
            radiusMeters: 800,
            expandsClipRadius: true
        )
        let prep = TripShareRoutePrep.prepare(
            points: points,
            privacyRadiusMeters: 500,
            places: [home]
        )

        guard let start = prep.start, let end = prep.end else {
            XCTFail("expected clipped endpoints")
            return
        }
        XCTAssertFalse(prep.strokes.isEmpty)

        let strokeCoords = prep.strokes.flatMap(\.coordinates)
        XCTAssertEqual(strokeCoords.first?.latitude ?? 0, start.latitude, accuracy: 1e-12)
        XCTAssertEqual(strokeCoords.first?.longitude ?? 0, start.longitude, accuracy: 1e-12)
        XCTAssertEqual(strokeCoords.last?.latitude ?? 0, end.latitude, accuracy: 1e-12)
        XCTAssertEqual(strokeCoords.last?.longitude ?? 0, end.longitude, accuracy: 1e-12)
    }

    // MARK: - Fixtures

    private func straightRoutePoints(
        count: Int,
        spacingMeters: Double,
        speedMps: Double = 14
    ) -> [TripShareRoutePrep.Point] {
        // ~111_320 m per degree latitude.
        let latStep = spacingMeters / 111_320
        let start = Date(timeIntervalSince1970: 1_720_000_000)
        return (0..<count).map { index in
            TripShareRoutePrep.Point(
                latitude: 41.0 + Double(index) * latStep,
                longitude: 29.0,
                timestamp: start.addingTimeInterval(Double(index) * 2),
                speedMps: speedMps
            )
        }
    }
}
