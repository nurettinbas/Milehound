import CoreLocation
import XCTest
@testable import Milehound

final class LiveFollowMapViewTests: XCTestCase {
    /// ~12 m north of `lat` — dense enough that RouteDisplayPath keeps the chord.
    private func north(_ lat: Double, steps: Int, lon: Double = 29.0) -> [CLLocationCoordinate2D] {
        (0..<steps).map { index in
            CLLocationCoordinate2D(
                latitude: lat + Double(index) * 0.000108,
                longitude: lon
            )
        }
    }

    func testPolylineSegmentsDropsEmptyPieces() {
        let single = [CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)]
        XCTAssertTrue(LiveFollowMapView.polylineSegments(from: [single]).isEmpty)
        XCTAssertTrue(LiveFollowMapView.polylineSegments(from: [[]]).isEmpty)
        XCTAssertTrue(LiveFollowMapView.polylineSegments(from: []).isEmpty)
    }

    func testPolylineSegmentsKeepsDrawableRun() {
        let run = north(41.0, steps: 3)
        let segments = LiveFollowMapView.polylineSegments(from: [run])
        XCTAssertEqual(segments.count, 1)
        guard let first = segments.first else { return }
        XCTAssertGreaterThanOrEqual(first.coordinates.count, 2)
        XCTAssertEqual(first.id, "live-0-0")
    }

    func testPolylineSegmentsPreservesGapSplitRuns() {
        let first = north(41.0, steps: 2)
        let second = north(41.5, steps: 2, lon: 29.4)
        let segments = LiveFollowMapView.polylineSegments(from: [first, second])
        XCTAssertEqual(segments.count, 2)
        guard segments.count == 2 else { return }
        XCTAssertEqual(segments[0].id, "live-0-0")
        XCTAssertEqual(segments[1].id, "live-1-0")
        XCTAssertGreaterThanOrEqual(segments[0].coordinates.count, 2)
        XCTAssertGreaterThanOrEqual(segments[1].coordinates.count, 2)
    }
}
