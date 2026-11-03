import CoreLocation
import XCTest
@testable import Milehound

final class TripSpeedSummaryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 38.42, longitude: 27.14)

    /// The reported bug, reproduced from the read side: a trip whose stored points carry one
    /// 203 km/h reading among ordinary city speeds must not claim 203 km/h.
    func testSingleSampleSpikeDoesNotSetTheMaximum() {
        var speeds = Array(repeating: 10.0, count: 40)
        speeds[7] = 56.4 // 203 km/h

        let derived = TripSpeedSummary.maxSpeedMps(samples: samples(speedsMps: speeds))

        XCTAssertEqual(derived ?? 0, 10, accuracy: 0.001)
    }

    func testSustainedPeakSetsTheMaximum() {
        var speeds = Array(repeating: 10.0, count: 40)
        speeds[20...23] = [33, 34, 33.5, 33]

        let derived = TripSpeedSummary.maxSpeedMps(samples: samples(speedsMps: speeds))

        XCTAssertEqual(derived ?? 0, 33, accuracy: 0.001)
    }

    /// Two samples cannot corroborate each other, so a two-sample trip reports nothing rather
    /// than trusting whichever reading happens to be higher.
    func testTooFewSamplesReportNoMaximum() {
        XCTAssertNil(TripSpeedSummary.maxSpeedMps(samples: samples(speedsMps: [10, 56.4])))
        XCTAssertNil(TripSpeedSummary.maxSpeedMps(samples: []))
    }

    /// A run of readings above what a car can do is noise however long it lasts. Each is dropped
    /// before the sustained check runs, and a window containing one is skipped rather than
    /// averaged — an unknown reading cannot vouch for a peak.
    func testReadingsAboveTheCeilingAreNotSpeeds() {
        let speeds = Array(repeating: 10.0, count: 5)
            + Array(repeating: 80.0, count: 3)
            + Array(repeating: 10.0, count: 5)

        let derived = TripSpeedSummary.maxSpeedMps(samples: samples(speedsMps: speeds))

        XCTAssertEqual(derived ?? 0, 10, accuracy: 0.001)
    }

    /// Stored speed missing (Core Location reported -1) falls back to what the distance implies.
    func testMissingStoredSpeedFallsBackToImpliedSpeed() {
        let route = samples(speedsMps: [14, 14, 14], storeSpeeds: false)

        let speed = TripSpeedSummary.effectiveSpeedMps(at: 1, in: route)

        XCTAssertEqual(speed ?? 0, 14, accuracy: 0.5)
    }

    func testFirstSampleHasNoImpliedSpeedToFallBackOn() {
        let route = samples(speedsMps: [14, 14, 14], storeSpeeds: false)

        XCTAssertNil(TripSpeedSummary.effectiveSpeedMps(at: 0, in: route))
    }

    func testStoredMaximumIsHiddenWhenNoCarCouldHaveDoneIt() {
        XCTAssertNil(TripSpeedSummary.believableStoredMaxSpeedMps(56.4))
        XCTAssertNil(TripSpeedSummary.believableStoredMaxSpeedMps(nil))
        XCTAssertNil(TripSpeedSummary.believableStoredMaxSpeedMps(0))
        XCTAssertEqual(TripSpeedSummary.believableStoredMaxSpeedMps(23.3) ?? 0, 23.3, accuracy: 0.001)
    }

    /// Samples one second apart, each moving the distance its speed implies.
    private func samples(speedsMps: [Double], storeSpeeds: Bool = true) -> [RouteSample] {
        let metersPerDegreeLongitude = 111_320 * cos(origin.latitude * .pi / 180)
        var travelled = 0.0
        return speedsMps.enumerated().map { index, speed in
            if index > 0 { travelled += speed }
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: origin.latitude,
                    longitude: origin.longitude + travelled / metersPerDegreeLongitude
                ),
                timestamp: start.addingTimeInterval(Double(index)),
                speedMps: storeSpeeds ? speed : nil
            )
        }
    }
}
