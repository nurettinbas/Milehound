import CoreLocation
import XCTest
@testable import Milehound

final class SpeedChartSeriesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 38.42, longitude: 27.14)

    func testShortTripIsPlottedSampleForSample() {
        let series = SpeedChartSeries.build(samples: drive(speedsMps: Array(repeating: 14.0, count: 50)))

        XCTAssertEqual(series.samples.count, 50)
        XCTAssertEqual(series.medianIntervalSeconds, 1, accuracy: 0.001)
    }

    func testLongTripIsReducedToTheDrivingBudget() {
        let series = SpeedChartSeries.build(samples: drive(speedsMps: Array(repeating: 14.0, count: 6000)))

        XCTAssertLessThanOrEqual(series.samples.count, SpeedChartSeries.maxDrivingSamples)
        XCTAssertGreaterThan(series.samples.count, SpeedChartSeries.maxDrivingSamples / 2)
    }

    /// Averaging buckets keeps the shape of a ramp, unlike striding, which reproduces whichever
    /// readings happen to land on the stride.
    func testBucketingKeepsTheShapeOfARamp() {
        let ramp = (0..<2000).map { 5 + Double($0) * 0.015 }
        let series = SpeedChartSeries.build(samples: drive(speedsMps: ramp))

        XCTAssertEqual(series.samples.first?.speedKmh ?? 0, 5 * 3.6, accuracy: 3)
        XCTAssertEqual(series.samples.last?.speedKmh ?? 0, 35 * 3.6, accuracy: 3)
        XCTAssertTrue(
            zip(series.samples, series.samples.dropFirst())
                .allSatisfy { $0.speedKmh <= $1.speedKmh + 0.001 },
            "a monotonic ramp must stay monotonic after bucketing"
        )
    }

    /// The rank filter drops a lone spike that survived recording, so the drawn line does not
    /// shoot up for one reading.
    func testSmoothingRemovesALoneSpike() {
        var speeds = Array(repeating: 10.0, count: 60)
        speeds[30] = 40

        let series = SpeedChartSeries.build(samples: drive(speedsMps: speeds))

        XCTAssertEqual(series.samples.map(\.speedKmh).max() ?? 0, 10 * 3.6, accuracy: 0.001)
    }

    /// A traffic light stores no points at all, which used to read as missing data. It must now
    /// draw as a floor at zero, continuously enough that the canvas does not break the line.
    func testStandstillGapIsDrawnAsZero() {
        let series = SpeedChartSeries.build(samples: driveThenWaitThenDrive(waitSeconds: 600, movedMeters: 0))

        let zeros = series.samples.filter { $0.speedKmh == 0 }
        XCTAssertFalse(zeros.isEmpty)

        let breakThreshold = max(90, series.medianIntervalSeconds * SpeedChartSeries.gapIntervalMultiple)
        let widestGap = zip(series.samples, series.samples.dropFirst())
            .map { $1.date.timeIntervalSince($0.date) }
            .max() ?? 0
        XCTAssertLessThanOrEqual(widestGap, breakThreshold)
    }

    /// A gap the vehicle drove through is lost signal, not a stop, so inventing a floor at zero
    /// there would be a lie. The break stays.
    func testGapWhereVehicleMovedIsLeftAsAGap() {
        let series = SpeedChartSeries.build(samples: driveThenWaitThenDrive(waitSeconds: 600, movedMeters: 4000))

        XCTAssertTrue(series.samples.allSatisfy { $0.speedKmh > 0 })
    }

    /// Hours apart is a merged trip's seam rather than a pause in one drive, and drawing an
    /// hours-long zero line would misrepresent it.
    func testVeryLongStandstillStaysABreak() {
        let series = SpeedChartSeries.build(samples: driveThenWaitThenDrive(waitSeconds: 5 * 3600, movedMeters: 0))

        XCTAssertTrue(series.samples.allSatisfy { $0.speedKmh > 0 })
    }

    /// Averaging must not reach across a gap: the readings either side belong to different legs.
    func testBucketsDoNotAverageAcrossAGap() {
        let before = drive(speedsMps: Array(repeating: 5.0, count: 900))
        let last = before[before.count - 1]
        let after = drive(
            speedsMps: Array(repeating: 30.0, count: 900),
            from: last.coordinate,
            startingAt: last.timestamp.addingTimeInterval(4000)
        )

        let series = SpeedChartSeries.build(samples: before + after)
        let plotted = series.samples.map(\.speedKmh)

        XCTAssertEqual(plotted.min() ?? 0, 5 * 3.6, accuracy: 0.5)
        XCTAssertEqual(plotted.max() ?? 0, 30 * 3.6, accuracy: 0.5)
        // Nothing in between: an averaged bucket straddling the seam would land around 63 km/h.
        XCTAssertFalse(plotted.contains { $0 > 5 * 3.6 + 1 && $0 < 30 * 3.6 - 1 })
    }

    func testEmptyAndSingleSampleInputsAreSafe() {
        XCTAssertTrue(SpeedChartSeries.build(samples: []).samples.isEmpty)
        XCTAssertEqual(SpeedChartSeries.build(samples: drive(speedsMps: [14])).samples.count, 1)
    }

    /// A merge seam or lost-signal hole must not leave a dashed chart: the stroke drops to
    /// y=0, runs along the floor, then climbs the next leg.
    func testRecordingGapIsBridgedAlongTheBaseline() {
        let samples = [
            (date: start, speedKmh: 50.0),
            (date: start.addingTimeInterval(10), speedKmh: 60.0),
            (date: start.addingTimeInterval(4000), speedKmh: 40.0)
        ]

        let points = SpeedChartSeries.strokePoints(
            samples: samples,
            gapBreakSeconds: 90,
            project: { date, speed in
                CGPoint(x: date.timeIntervalSince(start), y: speed)
            },
            baselineY: 0
        )

        XCTAssertEqual(points, [
            CGPoint(x: 0, y: 50),
            CGPoint(x: 10, y: 60),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 4000, y: 0),
            CGPoint(x: 4000, y: 40)
        ])
    }

    func testCloseSamplesAreNotBridged() {
        let samples = [
            (date: start, speedKmh: 20.0),
            (date: start.addingTimeInterval(5), speedKmh: 30.0)
        ]

        let points = SpeedChartSeries.strokePoints(
            samples: samples,
            gapBreakSeconds: 90,
            project: { date, speed in
                CGPoint(x: date.timeIntervalSince(start), y: speed)
            },
            baselineY: 0
        )

        XCTAssertEqual(points, [
            CGPoint(x: 0, y: 20),
            CGPoint(x: 5, y: 30)
        ])
    }

    func testRevealAcrossAGapStaysOnTheFloor() {
        let samples = [
            (date: start, speedKmh: 50.0),
            (date: start.addingTimeInterval(4000), speedKmh: 40.0)
        ]

        let revealed = SpeedChartSeries.revealedSamples(
            from: samples,
            progress: 0.5,
            gapBreakSeconds: 90
        )

        XCTAssertEqual(revealed.count, 2)
        XCTAssertEqual(revealed[1].speedKmh, 0, accuracy: 0.001)
        XCTAssertEqual(revealed[1].date.timeIntervalSince(start), 2000, accuracy: 0.001)
    }

    func testRevealAcrossDrivingInterpolatesSpeed() {
        let samples = [
            (date: start, speedKmh: 0.0),
            (date: start.addingTimeInterval(10), speedKmh: 50.0)
        ]

        let revealed = SpeedChartSeries.revealedSamples(
            from: samples,
            progress: 0.5,
            gapBreakSeconds: 90
        )

        XCTAssertEqual(revealed[1].speedKmh, 25, accuracy: 0.001)
    }

    // MARK: - Fixtures

    /// One sample per second, each moving the distance its speed implies.
    private func drive(
        speedsMps: [Double],
        from base: CLLocationCoordinate2D? = nil,
        startingAt origin: Date? = nil
    ) -> [RouteSample] {
        let anchor = base ?? self.origin
        let begin = origin ?? start
        let metersPerDegreeLongitude = 111_320 * cos(anchor.latitude * .pi / 180)
        var travelled = 0.0
        return speedsMps.enumerated().map { index, speed in
            if index > 0 { travelled += speed }
            return RouteSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude,
                    longitude: anchor.longitude + travelled / metersPerDegreeLongitude
                ),
                timestamp: begin.addingTimeInterval(Double(index)),
                speedMps: speed
            )
        }
    }

    /// Two legs with nothing recorded in between — the vehicle either waited there or covered
    /// `movedMeters` unrecorded.
    private func driveThenWaitThenDrive(
        waitSeconds: TimeInterval,
        movedMeters: Double
    ) -> [RouteSample] {
        let before = drive(speedsMps: Array(repeating: 12.0, count: 120))
        let last = before[before.count - 1]
        let metersPerDegreeLatitude = 111_000.0
        let resumeCoordinate = CLLocationCoordinate2D(
            latitude: last.coordinate.latitude + movedMeters / metersPerDegreeLatitude,
            longitude: last.coordinate.longitude
        )
        let after = drive(
            speedsMps: Array(repeating: 12.0, count: 120),
            from: resumeCoordinate,
            startingAt: last.timestamp.addingTimeInterval(waitSeconds)
        )
        return before + after
    }
}
