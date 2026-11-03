import CoreLocation
import XCTest
@testable import Milehound

final class TripSpeedProfileTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 38.42, longitude: 27.14)

    func testSteadyNinetyReportsCruiseNearNinety() {
        let speeds = Array(repeating: 90.0 / 3.6, count: 121)
        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 90, accuracy: 0.5)
        XCTAssertEqual(profile.cruiseDurationSeconds, 120, accuracy: 0.5)
        XCTAssertEqual(profile.stopDurationSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(profile.mostCommonSpeedKmh ?? 0, 92.5, accuracy: 0.001)
        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 90, accuracy: 0.5)
        XCTAssertEqual(profile.p90SpeedKmh ?? 0, 90, accuracy: 0.5)
    }

    func testStopThenCruiseCountsStopTimeSeparately() {
        var speeds = Array(repeating: 0.5, count: 31) // 30 s stopped
        speeds += Array(repeating: 50.0 / 3.6, count: 91) // 90 s at ~50 km/h

        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.stopDurationSeconds, 30, accuracy: 1)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 50, accuracy: 1)
        XCTAssertGreaterThan(profile.cruiseDurationSeconds, 60)
        XCTAssertEqual(profile.mostCommonSpeedKmh ?? 0, 52.5, accuracy: 0.001)
        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 50, accuracy: 1)
    }

    /// Cruise is distance / moving time, so any real stop makes it higher than the overall
    /// average (distance / clock time).
    func testCruiseExceedsOverallAverageWhenThereAreStops() {
        var speeds = Array(repeating: 0.2, count: 301) // 5 minutes stopped
        speeds += Array(repeating: 40.0 / 3.6, count: 3_601) // 1 hour at 40 km/h

        let route = samples(speedsMps: speeds)
        let profile = TripSpeedProfile.compute(samples: route)

        let clockSeconds = route.last!.timestamp.timeIntervalSince(route.first!.timestamp)
        let totalMeters = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            partial + pair.0.location.distance(from: pair.1.location)
        }
        let overallKmh = totalMeters * 3.6 / clockSeconds

        XCTAssertEqual(profile.stopDurationSeconds, 300, accuracy: 2)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 40, accuracy: 1)
        XCTAssertGreaterThan(profile.cruiseSpeedKmh ?? 0, overallKmh)
    }

    func testSingleSpikeDoesNotStealCruise() {
        var speeds = Array(repeating: 50.0 / 3.6, count: 121)
        speeds[60] = 56.4 // 203 km/h for one second — not recordable

        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 50, accuracy: 1)
    }

    func testLongRecordingGapIsNotCountedAsStop() {
        let first = samples(speedsMps: Array(repeating: 40.0 / 3.6, count: 61))
        let gapStart = start.addingTimeInterval(60)
        let afterGap = samples(
            speedsMps: Array(repeating: 40.0 / 3.6, count: 61),
            startAt: gapStart.addingTimeInterval(2 * 3_600)
        )
        let profile = TripSpeedProfile.compute(samples: first + afterGap)

        XCTAssertEqual(profile.stopDurationSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 40, accuracy: 1)
    }

    /// Parking stops write no points for minutes. That quiet gap must count as stop time, not
    /// be dropped as a "recording seam" just because it exceeds 90 seconds.
    func testMultiMinuteStationaryGapCountsAsStop() {
        let moving = samples(speedsMps: Array(repeating: 50.0 / 3.6, count: 61))
        let last = moving[moving.count - 1]
        let waited: TimeInterval = 5 * 60 + 58
        let afterDwell = RouteSample(
            coordinate: last.coordinate,
            timestamp: last.timestamp.addingTimeInterval(waited),
            speedMps: 40.0 / 3.6
        )

        let profile = TripSpeedProfile.compute(samples: moving + [afterDwell])

        XCTAssertEqual(profile.stopDurationSeconds, waited, accuracy: 1)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 50, accuracy: 1)
    }

    /// GPS wanders tens of metres while the car sits. Implied speed is still a crawl, so the
    /// whole wait is stop time — a 60 m hard cap used to throw those minutes away.
    func testStationaryGapWithGPSWanderStillCountsAsStop() {
        let moving = samples(speedsMps: Array(repeating: 50.0 / 3.6, count: 61))
        let last = moving[moving.count - 1]
        let waited: TimeInterval = 4 * 60
        let drifted = offset(from: last.coordinate, metersEast: 80)
        let afterDwell = RouteSample(
            coordinate: drifted,
            timestamp: last.timestamp.addingTimeInterval(waited),
            speedMps: 15.0 / 3.6
        )

        let profile = TripSpeedProfile.compute(samples: moving + [afterDwell])

        XCTAssertEqual(profile.stopDurationSeconds, waited, accuracy: 1)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 50, accuracy: 1)
    }

    /// A long chord at a real driving speed is compressed recording (straight highway), not a
    /// seam. Discarding it used to erase both the minutes and the speed band.
    func testLongPlausibleMovingChordCountsAsMoving() {
        let first = RouteSample(coordinate: origin, timestamp: start, speedMps: 68.0 / 3.6)
        let rest = samples(
            speedsMps: Array(repeating: 68.0 / 3.6, count: 61),
            startAt: start.addingTimeInterval(24),
            startFrom: offset(from: origin, metersEast: (68.0 / 3.6) * 24)
        )
        let profile = TripSpeedProfile.compute(samples: [first] + rest)

        XCTAssertEqual(profile.stopDurationSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 68, accuracy: 2)
        XCTAssertGreaterThan(profile.cruiseDurationSeconds, 60)
    }

    /// The recorder writes no points while the car sits at a light. The next reading is the
    /// pull-away speed — that must not claim the whole wait as moving time.
    func testStationaryGapBeforePullawayCountsAsStopNotMoving() {
        let moving = samples(speedsMps: Array(repeating: 50.0 / 3.6, count: 91))
        let last = moving[moving.count - 1]
        let afterDwell = RouteSample(
            coordinate: last.coordinate,
            timestamp: last.timestamp.addingTimeInterval(40),
            speedMps: 15.0 / 3.6
        )

        let profile = TripSpeedProfile.compute(samples: moving + [afterDwell])

        XCTAssertEqual(profile.stopDurationSeconds, 40, accuracy: 1)
        XCTAssertEqual(profile.cruiseSpeedKmh ?? 0, 50, accuracy: 1)
    }

    func testTooLittleMovingTimeReportsNoCruise() {
        let speeds = Array(repeating: 40.0 / 3.6, count: 31) // 30 s moving
        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertNil(profile.cruiseSpeedKmh)
        XCTAssertNil(profile.mostCommonSpeedKmh)
        XCTAssertNil(profile.medianSpeedKmh)
        XCTAssertNil(profile.p90SpeedKmh)
        XCTAssertEqual(profile.cruiseDurationSeconds, 0, accuracy: 0.001)
    }

    func testSteadySpeedMedianMatchesP90() {
        let speeds = Array(repeating: 50.0 / 3.6, count: 121)
        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 50, accuracy: 0.5)
        XCTAssertEqual(profile.p90SpeedKmh ?? 0, 50, accuracy: 0.5)
    }

    func testEmptyRouteReportsEmpty() {
        XCTAssertEqual(TripSpeedProfile.compute(samples: []), .empty)
        XCTAssertEqual(
            TripSpeedProfile.compute(samples: samples(speedsMps: [10])),
            .empty
        )
    }

    /// Neighbour blending: a minute spread around 50 beats a tighter but shorter 68 cluster.
    func testMostCommonBlendsNeighbouringBuckets() {
        var speeds = Array(repeating: 48.0 / 3.6, count: 21)
        speeds += Array(repeating: 52.0 / 3.6, count: 20)
        speeds += Array(repeating: 56.0 / 3.6, count: 20)
        speeds += Array(repeating: 68.0 / 3.6, count: 41)

        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.mostCommonSpeedKmh ?? 0, 52.5, accuracy: 0.001)
        // 20+20+20+40 s; the 50th percentile lands in the 56 km/h slice
        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 56, accuracy: 1)
    }

    /// Crawl time must not steal the mode — 12 km/h in a queue is not “most common” on a 50 trip.
    func testMostCommonIgnoresCrawlEvenWhenItLastsLonger() {
        var speeds = Array(repeating: 12.0 / 3.6, count: 121) // 2 min creeping
        speeds += Array(repeating: 50.0 / 3.6, count: 91) // 90 s at 50

        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.mostCommonSpeedKmh ?? 0, 52.5, accuracy: 0.001)
        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 12, accuracy: 1)
        XCTAssertGreaterThan(profile.mostCommonSpeedKmh ?? 0, profile.cruiseSpeedKmh ?? 0)
    }

    func testMostCommonFallsBackToCrawlWhenTheTripNeverDrove() {
        let speeds = Array(repeating: 12.0 / 3.6, count: 121)
        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.mostCommonSpeedKmh ?? 0, 12.5, accuracy: 0.001)
        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 12, accuracy: 1)
    }

    /// Mode follows the tight highway cluster; median sits in the slower half of moving time.
    func testMedianIsLowerThanModeOnCityThenHighway() {
        var speeds = Array(repeating: 35.0 / 3.6, count: 51)
        speeds += Array(repeating: 45.0 / 3.6, count: 50)
        speeds += Array(repeating: 68.0 / 3.6, count: 81)

        let profile = TripSpeedProfile.compute(samples: samples(speedsMps: speeds))

        XCTAssertEqual(profile.mostCommonSpeedKmh ?? 0, 67.5, accuracy: 0.001)
        XCTAssertEqual(profile.medianSpeedKmh ?? 0, 45, accuracy: 1)
        XCTAssertEqual(profile.p90SpeedKmh ?? 0, 68, accuracy: 1)
        XCTAssertLessThan(profile.medianSpeedKmh ?? 0, profile.mostCommonSpeedKmh ?? 0)
        XCTAssertGreaterThanOrEqual(profile.p90SpeedKmh ?? 0, profile.medianSpeedKmh ?? 0)
        XCTAssertLessThanOrEqual(profile.p90SpeedKmh ?? 0, 68.5)
    }

    /// Samples one second apart, each moving the distance its speed implies.
    private func samples(
        speedsMps: [Double],
        storeSpeeds: Bool = true,
        startAt: Date? = nil,
        startFrom: CLLocationCoordinate2D? = nil
    ) -> [RouteSample] {
        let originTime = startAt ?? start
        let from = startFrom ?? origin
        var travelled = 0.0
        return speedsMps.enumerated().map { index, speed in
            if index > 0 { travelled += speed }
            return RouteSample(
                coordinate: offset(from: from, metersEast: travelled),
                timestamp: originTime.addingTimeInterval(Double(index)),
                speedMps: storeSpeeds ? speed : nil
            )
        }
    }

    private func offset(from coordinate: CLLocationCoordinate2D, metersEast: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude + metersEast / metersPerDegreeLongitude
        )
    }
}
