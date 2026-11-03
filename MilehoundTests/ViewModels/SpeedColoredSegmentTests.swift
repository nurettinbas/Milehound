import CoreLocation
import XCTest
@testable import Milehound

@MainActor
final class SpeedColoredSegmentTests: XCTestCase {
    func testHysteresisKeepsOscillatingSpeedAsOneSegment() {
        // Speeds that cross 50 km/h without clearing the ±5 km/h hysteresis band.
        var samples: [RouteSample] = []
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<40 {
            let kmh = index.isMultiple(of: 2) ? 48.0 : 52.0
            samples.append(
                RouteSample(
                    coordinate: CLLocationCoordinate2D(
                        latitude: 41.0 + Double(index) * 0.0002,
                        longitude: 29.0
                    ),
                    timestamp: start.addingTimeInterval(Double(index) * 2),
                    speedMps: kmh / 3.6
                )
            )
        }

        let segments = SpeedColoredSegmentBuilder.build(pieces: [samples])
        XCTAssertEqual(segments.count, 1)
        if let color = segments.first?.color {
            XCTAssertEqual(String(describing: color), String(describing: SpeedBand.slow.color))
        } else {
            XCTFail("expected a colored segment")
        }
    }

    func testSegmentCountStaysUnderBudgetForNoisyLongRoute() {
        let samples = noisySpeedRoute(count: 20_000)
        let segments = SpeedColoredSegmentBuilder.build(pieces: [samples])
        XCTAssertLessThanOrEqual(segments.count, SpeedColoredSegmentBuilder.maxColorSegments)
    }

    func testMergingPreservesGeometry() {
        let samples = alternatingBandRoute(count: 200)
        let pieces = [samples]
        let segments = SpeedColoredSegmentBuilder.build(pieces: pieces)

        let rebuilt = flattenCoordinates(segments)
        let original = samples.map(\.coordinate)
        XCTAssertEqual(rebuilt.count, original.count)
        for (lhs, rhs) in zip(rebuilt, original) {
            XCTAssertEqual(lhs.latitude, rhs.latitude, accuracy: 1e-12)
            XCTAssertEqual(lhs.longitude, rhs.longitude, accuracy: 1e-12)
        }
    }

    func testGapsAreNeverBridgedByMerge() {
        let left = straight(count: 30, speedKmh: 40, lonOffset: 0)
        let right = straight(count: 30, speedKmh: 40, lonOffset: 0.05) // far away — a real gap
        let segments = SpeedColoredSegmentBuilder.build(pieces: [left, right])

        // Two pieces must remain at least two separate drawable segments.
        XCTAssertGreaterThanOrEqual(segments.count, 2)
        let seam = segments[0].coordinates.last!
        let next = segments[1].coordinates.first!
        let distance = CLLocation(latitude: seam.latitude, longitude: seam.longitude)
            .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
        XCTAssertGreaterThan(distance, 1_000)
    }

    func testMixedSpeedsStillProduceMultipleColors() {
        var samples: [RouteSample] = []
        samples.append(contentsOf: straight(count: 40, speedKmh: 30, lonOffset: 0))
        samples.append(contentsOf: straight(count: 40, speedKmh: 70, lonOffset: 0.004, continueFrom: samples.last))
        samples.append(contentsOf: straight(count: 40, speedKmh: 110, lonOffset: 0.008, continueFrom: samples.last))

        let segments = SpeedColoredSegmentBuilder.build(pieces: [samples])
        let colors = Set(segments.map { String(describing: $0.color) })
        XCTAssertGreaterThanOrEqual(colors.count, 2)
    }

    func testSpeedBandHysteresisTransitions() {
        var band = SpeedBand.slow
        band.update(kmh: 52) // still inside hysteresis
        XCTAssertEqual(band, .slow)
        band.update(kmh: 56)
        XCTAssertEqual(band, .medium)
        band.update(kmh: 48) // still inside hysteresis around 50
        XCTAssertEqual(band, .medium)
        band.update(kmh: 44)
        XCTAssertEqual(band, .slow)
    }

    private func flattenCoordinates(_ segments: [SpeedColoredSegment]) -> [CLLocationCoordinate2D] {
        guard let first = segments.first else { return [] }
        var coords = first.coordinates
        for segment in segments.dropFirst() {
            // Color joins overlap on a two-point chord [A, B].
            if coords.count >= 2, segment.coordinates.count >= 2,
               abs(coords[coords.count - 2].latitude - segment.coordinates[0].latitude) < 1e-12,
               abs(coords[coords.count - 2].longitude - segment.coordinates[0].longitude) < 1e-12,
               abs(coords[coords.count - 1].latitude - segment.coordinates[1].latitude) < 1e-12,
               abs(coords[coords.count - 1].longitude - segment.coordinates[1].longitude) < 1e-12 {
                coords.append(contentsOf: segment.coordinates.dropFirst(2))
            } else if let last = coords.last,
                      let next = segment.coordinates.first,
                      abs(last.latitude - next.latitude) < 1e-12,
                      abs(last.longitude - next.longitude) < 1e-12 {
                coords.append(contentsOf: segment.coordinates.dropFirst())
            } else {
                coords.append(contentsOf: segment.coordinates)
            }
        }
        return coords
    }

    private func noisySpeedRoute(count: Int) -> [RouteSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            // Alternate around every threshold so a naive builder would explode.
            let kmh: Double
            switch index % 6 {
            case 0: kmh = 45
            case 1: kmh = 55
            case 2: kmh = 85
            case 3: kmh = 95
            case 4: kmh = 48
            default: kmh = 92
            }
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: 41.0 + Double(index) * 0.00005,
                    longitude: 29.0 + Double(index) * 0.00005
                ),
                timestamp: start.addingTimeInterval(Double(index)),
                speedMps: kmh / 3.6
            )
        }
    }

    private func alternatingBandRoute(count: Int) -> [RouteSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            let kmh = index % 20 < 10 ? 30.0 : 100.0
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: 41.0 + Double(index) * 0.0001,
                    longitude: 29.0
                ),
                timestamp: start.addingTimeInterval(Double(index) * 2),
                speedMps: kmh / 3.6
            )
        }
    }

    private func straight(
        count: Int,
        speedKmh: Double,
        lonOffset: Double,
        continueFrom previous: RouteSample? = nil
    ) -> [RouteSample] {
        let start = previous?.timestamp.addingTimeInterval(2) ?? Date(timeIntervalSince1970: 1_700_000_000)
        let baseLat = previous?.coordinate.latitude ?? 41.0
        let baseLon = previous?.coordinate.longitude ?? (29.0 + lonOffset)
        let startIndex = previous == nil ? 0 : 1
        return (startIndex..<(startIndex + count)).map { index in
            RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: baseLat + Double(index) * 0.00015,
                    longitude: baseLon
                ),
                timestamp: start.addingTimeInterval(Double(index) * 2),
                speedMps: speedKmh / 3.6
            )
        }
    }
}
