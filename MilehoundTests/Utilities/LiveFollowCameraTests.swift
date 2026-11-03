import CoreLocation
import XCTest
@testable import Milehound

final class LiveFollowCameraTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 5_000)
    private let frame: TimeInterval = 1.0 / 60.0

    func testLowSpeedHoldsHeading() {
        var camera = LiveFollowCamera()
        let moving = location(lat: 41.0, lon: 29.0, speedMps: 15, course: 90, courseAccuracy: 5)
        camera.ingest(location: moving, isPaused: false, now: baseDate)
        XCTAssertTrue(camera.tick(dt: frame, now: baseDate))
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)

        let crawling = location(lat: 41.0001, lon: 29.0, speedMps: 1, course: 180, courseAccuracy: 5)
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: crawling, isPaused: false, now: later)
        XCTAssertTrue(camera.tick(dt: frame, now: later))
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)
    }

    func testBadCourseAccuracyFollowsPathBearing() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 8)
        camera.ingest(location: good, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)

        // 22 m due north with an untrusted course: the path is the only honest heading.
        let badCourse = location(
            lat: 41.0002,
            lon: 29.0,
            speedMps: 20,
            course: 200,
            courseAccuracy: -1
        )
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: badCourse, isPaused: false, now: later)
        XCTAssertEqual(camera.vehicleHeadingDegrees, 45, accuracy: 0.01)
        var now = later
        for _ in 0..<60 {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
        }
        XCTAssertLessThan(camera.vehicleHeadingDegrees, 5)
        XCTAssertLessThan(camera.headingDegrees, 45)
    }

    func testBadCourseWithTinyMoveHoldsHeading() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 8)
        camera.ingest(location: good, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        // ~1 m of jitter is not a direction of travel.
        let jitter = location(
            lat: 41.00001,
            lon: 29.0,
            speedMps: 20,
            course: -1,
            courseAccuracy: -1,
            timestamp: baseDate.addingTimeInterval(1)
        )
        camera.ingest(location: jitter, isPaused: false, now: baseDate.addingTimeInterval(1))
        _ = camera.tick(dt: frame, now: baseDate.addingTimeInterval(1))
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)
    }

    /// Simulator and urban GPS often omit `course`. The puck used to keep the first heading
    /// forever and dead-reckon straight off the road after the first turn.
    func testRightAngleTurnWithoutCourseStaysOnTrail() {
        var camera = LiveFollowCamera()
        let speed = 11.0
        let stepDegrees = speed / 111_320.0
        var fixes: [CLLocationCoordinate2D] = (0..<8).map {
            CLLocationCoordinate2D(latitude: 41.0 + Double($0) * stepDegrees, longitude: 29.0)
        }
        let corner = fixes.last!
        let lonStep = speed / (111_320.0 * cos(41.0 * .pi / 180))
        fixes += (1...12).map {
            CLLocationCoordinate2D(latitude: corner.latitude, longitude: corner.longitude - Double($0) * lonStep)
        }

        var now = baseDate
        var worstAfterTurn = 0.0
        for (index, fix) in fixes.enumerated() {
            let stamp = baseDate.addingTimeInterval(Double(index))
            let sample = CLLocation(
                coordinate: fix,
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: -1,
                courseAccuracy: -1,
                speed: speed,
                speedAccuracy: -1,
                timestamp: stamp
            )
            for _ in 0..<60 {
                camera.ingest(location: sample, isPaused: false, now: now)
                _ = camera.tick(dt: frame, now: now)
                now = now.addingTimeInterval(frame)
            }
            if index >= 11, let center = camera.center {
                // West leg: distance from the road (constant latitude) in metres.
                worstAfterTurn = max(worstAfterTurn, abs(center.latitude - corner.latitude) * 111_320)
            }
        }
        XCTAssertLessThan(worstAfterTurn, 3, "puck must settle back onto the new road")
        XCTAssertEqual(camera.vehicleHeadingDegrees, 270, accuracy: 10)
    }

    func testWrongHeadingCannotRunAwayFromGPS() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 11, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        // Fixes keep landing on the start point while the stale heading says north.
        var now = baseDate
        for second in 1...10 {
            let stamp = baseDate.addingTimeInterval(Double(second))
            let still = location(
                lat: 41.0,
                lon: 29.0,
                speedMps: 11,
                course: -1,
                courseAccuracy: -1,
                timestamp: stamp
            )
            for _ in 0..<60 {
                camera.ingest(location: still, isPaused: false, now: now)
                _ = camera.tick(dt: frame, now: now)
                now = now.addingTimeInterval(frame)
            }
        }
        let drift = CLLocation(latitude: 41.0, longitude: 29.0).distance(from: CLLocation(
            latitude: camera.center?.latitude ?? 0,
            longitude: camera.center?.longitude ?? 0
        ))
        XCTAssertLessThan(drift, 20)
    }

    func testPauseFreezesCameraUpdates() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 18, course: 10, courseAccuracy: 4)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        let frozenHeading = camera.headingDegrees
        let frozenLat = camera.center?.latitude

        let next = location(lat: 41.01, lon: 29.01, speedMps: 18, course: 90, courseAccuracy: 4)
        camera.ingest(location: next, isPaused: true, now: baseDate.addingTimeInterval(0.3))
        XCTAssertFalse(camera.tick(dt: frame, now: baseDate.addingTimeInterval(0.3)))
        XCTAssertTrue(camera.isFrozen)
        XCTAssertEqual(camera.headingDegrees, frozenHeading, accuracy: 0.01)
        XCTAssertEqual(camera.center?.latitude, frozenLat)
    }

    func testTargetHeadingEasesOnCourseJump() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let second = location(lat: 41.0003, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        let t1 = baseDate.addingTimeInterval(1)
        camera.ingest(location: second, isPaused: false, now: t1)
        _ = camera.tick(dt: frame, now: t1)
        // Target eases — published heading should not lunge toward 90 immediately.
        XCTAssertLessThan(camera.headingDegrees, 40)
    }

    func testBearingDegreesEast() {
        let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let east = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.001)
        XCTAssertEqual(
            LiveFollowCamera.bearingDegrees(from: origin, to: east),
            90,
            accuracy: 2
        )
    }

    func testHeadingApproachesTargetOverTicks() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.headingDegrees, 0, accuracy: 0.01)

        let second = location(lat: 41.0003, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        let t1 = baseDate.addingTimeInterval(1)
        camera.ingest(location: second, isPaused: false, now: t1)

        var previous = camera.headingDegrees
        for step in 1...12 {
            let now = t1.addingTimeInterval(Double(step) * frame)
            XCTAssertTrue(camera.tick(dt: frame, now: now))
            XCTAssertGreaterThanOrEqual(camera.headingDegrees, previous - 0.001)
            previous = camera.headingDegrees
        }
        XCTAssertGreaterThan(camera.headingDegrees, 3)
        XCTAssertLessThan(camera.headingDegrees, 90)
    }

    func testOneHzGPSWithDisplayTicksIsMonotonic() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )

        var lastLat = camera.center?.latitude ?? -1
        for second in 0..<3 {
            let fixAt = baseDate.addingTimeInterval(Double(second))
            let lat = 41.0 + Double(second) * 0.0002
            camera.ingest(
                location: location(lat: lat, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
                isPaused: false,
                now: fixAt
            )
            for frameIndex in 0..<60 {
                let now = fixAt.addingTimeInterval(Double(frameIndex) * frame)
                XCTAssertTrue(camera.tick(dt: frame, now: now))
                let current = camera.center?.latitude ?? -1
                XCTAssertGreaterThanOrEqual(current, lastLat - 0.000_000_1)
                lastLat = current
            }
        }
    }

    func testDoesNotRewindWhenNextFixLagsDeadReckon() {
        var camera = LiveFollowCamera()
        let start = location(
            lat: 41.0,
            lon: 29.0,
            speedMps: 20,
            course: 0,
            courseAccuracy: 5,
            timestamp: baseDate
        )
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        var now = baseDate
        for _ in 0..<60 {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
        }
        let ahead = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(ahead, 41.0)

        let stale = location(
            lat: 41.00004,
            lon: 29.0,
            speedMps: 20,
            course: 0,
            courseAccuracy: 5,
            timestamp: now
        )
        camera.ingest(location: stale, isPaused: false, now: now)
        _ = camera.tick(dt: frame, now: now.addingTimeInterval(frame))
        XCTAssertGreaterThanOrEqual(camera.center?.latitude ?? -1, ahead - 0.000_000_1)
    }

    func testCoastStaysAheadOfLastFixSoTrailDoesNotLeadThePuck() {
        var camera = LiveFollowCamera()
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        // Half a GPS interval later the published center must sit *ahead* of the
        // last fix. Aiming at the raw GPS parks the puck a whole second behind
        // reality and the breadcrumb trail draws out in front of the vehicle.
        var now = baseDate
        for _ in 0..<30 {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
        }
        let expected = LiveFollowCamera.coordinate(
            from: CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            headingDegrees: 0,
            distanceMeters: 20 * 0.5
        )
        XCTAssertEqual(camera.center?.latitude ?? 0, expected.latitude, accuracy: 0.000_08)
        XCTAssertGreaterThan(camera.center?.latitude ?? 0, 41.0)
    }

    func testResolvedSpeedFallsBackToImpliedWhenGPSSpeedMissing() {
        let previous = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let next = location(
            lat: 41.0003,
            lon: 29.0,
            speedMps: -1,
            course: -1,
            courseAccuracy: -1,
            timestamp: baseDate.addingTimeInterval(1)
        )
        let speed = LiveFollowCamera.resolvedSpeedMps(
            location: next,
            previousCoordinate: previous,
            previousStamp: baseDate
        )
        XCTAssertGreaterThan(speed, 25)
        XCTAssertLessThan(speed, 40)
    }

    func testInvalidGPSSpeedStillAdvancesBetweenFixes() {
        var camera = LiveFollowCamera()
        let first = location(
            lat: 41.0,
            lon: 29.0,
            speedMps: -1,
            course: -1,
            courseAccuracy: -1,
            timestamp: baseDate
        )
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let secondStamp = baseDate.addingTimeInterval(1)
        let second = location(
            lat: 41.0003,
            lon: 29.0,
            speedMps: -1,
            course: -1,
            courseAccuracy: -1,
            timestamp: secondStamp
        )
        camera.ingest(location: second, isPaused: false, now: secondStamp)
        _ = camera.tick(dt: frame, now: secondStamp)
        let afterSecond = camera.center?.latitude ?? -1

        var now = secondStamp
        for _ in 0..<45 {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
        }
        XCTAssertGreaterThan(camera.center?.latitude ?? -1, afterSecond + 0.00003)
    }

    /// The fresh window must comfortably cover a ~1 Hz fix interval, otherwise the
    /// puck stalls between every sample — that reads as a 1 Hz hitch on screen.
    func testCoastSpansAFullSecondWithoutStalling() {
        var camera = LiveFollowCamera()
        let fix = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: fix, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        var now = baseDate
        var previous = camera.center?.latitude ?? -1
        for _ in 0..<60 {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
            let current = camera.center?.latitude ?? -1
            XCTAssertGreaterThan(current, previous, "puck must advance on every frame")
            previous = current
        }
    }

    func testStaleFixBleedsCoastOffAndSettles() {
        var camera = LiveFollowCamera()
        let fix = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: fix, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        var now = baseDate
        for _ in 0..<(60 * 15) {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
        }
        let settled = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(settled, 41.0)

        for _ in 0..<120 {
            now = now.addingTimeInterval(frame)
            _ = camera.tick(dt: frame, now: now)
        }
        XCTAssertEqual(camera.center?.latitude ?? -1, settled, accuracy: 0.000_001)
    }

    func testForceRecenterUpdatesImmediately() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 30, courseAccuracy: 5)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let jumped = location(lat: 42.0, lon: 30.0, speedMps: 16, course: 120, courseAccuracy: 5)
        camera.forceRecenter(location: jumped, now: baseDate.addingTimeInterval(0.05))
        XCTAssertEqual(camera.center?.latitude ?? -1, 42.0, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 120, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
    }

    func testSmoothedHeadingTakesShortestArc() {
        let blended = LiveFollowCamera.smoothedHeading(from: 350, toward: 10, factor: 0.5)
        XCTAssertEqual(blended, 0, accuracy: 0.01)
    }

    func testHeadingWrapsShortestArcAcrossNorth() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 350, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)

        camera.ingest(
            location: location(lat: 41.0001, lon: 29.0, speedMps: 20, course: 10, courseAccuracy: 5),
            isPaused: false,
            now: baseDate.addingTimeInterval(1)
        )
        for step in 1...180 {
            _ = camera.tick(
                dt: frame,
                now: baseDate.addingTimeInterval(1 + Double(step) * frame)
            )
            let heading = camera.headingDegrees
            XCTAssertFalse(heading > 90 && heading < 270, "Should not take the long arc")
        }
        let delta = min(
            abs(camera.headingDegrees - 10),
            360 - abs(camera.headingDegrees - 10)
        )
        XCTAssertLessThan(delta, 25)
    }

    func testPoseCentersOnVehicleIn3D() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        guard let pose = camera.pose else {
            return XCTFail("expected pose")
        }
        XCTAssertEqual(pose.center.latitude, 41.0, accuracy: 0.00001)
        XCTAssertEqual(pose.center.longitude, 29.0, accuracy: 0.00001)
        XCTAssertEqual(pose.pitchDegrees, LiveFollowCamera.pitch3D, accuracy: 0.5)
        XCTAssertEqual(
            pose.distanceMeters,
            LiveFollowCamera.followDistance(uses3D: true, speedMps: 20),
            accuracy: 1
        )
    }

    func testFollowDistanceGrowsWithSpeedAndCaps() {
        let parked = LiveFollowCamera.followDistance(uses3D: true, speedMps: 0)
        let motorway = LiveFollowCamera.followDistance(uses3D: true, speedMps: 28)
        XCTAssertEqual(parked, LiveFollowCamera.distance3D, accuracy: 0.01)
        XCTAssertGreaterThan(motorway, parked * 1.5)
        XCTAssertLessThanOrEqual(motorway, LiveFollowCamera.distanceCap3D)
        XCTAssertEqual(
            LiveFollowCamera.followDistance(uses3D: true, speedMps: 500),
            LiveFollowCamera.distanceCap3D,
            accuracy: 0.01
        )
        XCTAssertGreaterThan(
            LiveFollowCamera.followDistance(uses3D: false, speedMps: 28),
            LiveFollowCamera.followDistance(uses3D: true, speedMps: 28)
        )
    }

    func testPoseFlattensIn2D() {
        var camera = LiveFollowCamera()
        camera.uses3D = false
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        guard let pose = camera.pose else {
            return XCTFail("expected pose")
        }
        XCTAssertEqual(pose.pitchDegrees, 0, accuracy: 0.5)
        XCTAssertEqual(
            pose.distanceMeters,
            LiveFollowCamera.followDistance(uses3D: false, speedMps: 20),
            accuracy: 1
        )
        XCTAssertEqual(pose.center.latitude, 41.0, accuracy: 0.00001)
        XCTAssertEqual(pose.center.longitude, 29.0, accuracy: 0.00001)
    }

    func testSnapDimensionModeJumpsWithoutLerp() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, LiveFollowCamera.pitch3D, accuracy: 0.5)

        camera.uses3D = false
        camera.snapDimensionMode()
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, LiveFollowCamera.pitch2D, accuracy: 0.01)
        XCTAssertEqual(
            camera.pose?.distanceMeters ?? -1,
            LiveFollowCamera.followDistance(uses3D: false, speedMps: 20),
            accuracy: 0.01
        )
    }

    func testModeLerpBlendsPitchWhenSwitching2D3D() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, LiveFollowCamera.pitch3D, accuracy: 0.5)

        camera.uses3D = false
        _ = camera.tick(dt: frame, now: baseDate.addingTimeInterval(frame))
        let mid = camera.pose?.pitchDegrees ?? -1
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, LiveFollowCamera.pitch3D)

        for step in 1...90 {
            _ = camera.tick(dt: frame, now: baseDate.addingTimeInterval(Double(step) * frame))
        }
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, 0, accuracy: 1)
    }

    func testLookAheadCoordinateNorth() {
        let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let ahead = LiveFollowCamera.coordinate(from: origin, headingDegrees: 0, distanceMeters: 100)
        XCTAssertGreaterThan(ahead.latitude, origin.latitude)
        XCTAssertEqual(ahead.longitude, origin.longitude, accuracy: 0.0002)
    }

    func testPoseNilUntilFirstUpdate() {
        let camera = LiveFollowCamera()
        XCTAssertNil(camera.pose)
        XCTAssertNil(camera.center)
    }

    func testResetClearsPoseAndHeading() {
        var camera = LiveFollowCamera()
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertNotNil(camera.pose)

        camera.reset()
        XCTAssertNil(camera.center)
        XCTAssertNil(camera.pose)
        XCTAssertEqual(camera.headingDegrees, 0, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
    }

    func testResumeAfterPauseUnfreezesAndUpdates() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 18, course: 10, courseAccuracy: 4)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        camera.ingest(
            location: location(lat: 41.01, lon: 29.01, speedMps: 18, course: 90, courseAccuracy: 4),
            isPaused: true,
            now: baseDate.addingTimeInterval(0.3)
        )
        XCTAssertTrue(camera.isFrozen)

        let resumed = location(lat: 41.02, lon: 29.02, speedMps: 18, course: 90, courseAccuracy: 4)
        let later = baseDate.addingTimeInterval(0.6)
        camera.ingest(location: resumed, isPaused: false, now: later)
        XCTAssertTrue(camera.tick(dt: frame, now: later))
        XCTAssertFalse(camera.isFrozen)
        XCTAssertEqual(camera.center?.latitude ?? -1, 41.02, accuracy: 0.0001)
    }

    func testNegativeCourseKeepsPuckBetweenFixes() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 5)
        camera.ingest(location: good, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let unavailable = location(
            lat: 41.0002,
            lon: 29.0,
            speedMps: 20,
            course: -1,
            courseAccuracy: 5
        )
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: unavailable, isPaused: false, now: later)
        _ = camera.tick(dt: frame, now: later)
        XCTAssertLessThanOrEqual(camera.headingDegrees, 45)
        XCTAssertGreaterThan(camera.headingDegrees, 40, "camera eases toward the path, no lunge")
        let lat = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(lat, 41.0)
        XCTAssertLessThanOrEqual(lat, 41.0002)
    }

    func testReingestSameFixDoesNotResetDeadReckon() {
        var camera = LiveFollowCamera()
        let fix = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: fix, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        let afterFirst = camera.center?.latitude ?? -1

        for step in 1...30 {
            let now = baseDate.addingTimeInterval(Double(step) * frame)
            camera.ingest(location: fix, isPaused: false, now: now)
            _ = camera.tick(dt: frame, now: now)
        }
        let afterReplay = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(afterReplay, afterFirst)
    }

    func testPublishedCenterEasesTowardNewFix() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 0.2, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)

        let jumped = location(lat: 41.01, lon: 29.0, speedMps: 0.2, course: 0, courseAccuracy: 5)
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: jumped, isPaused: false, now: later)
        _ = camera.tick(dt: frame, now: later)
        let mid = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(mid, 41.0)
        XCTAssertLessThan(mid, 41.01)
    }

    func testForceRecenterAtLowSpeedKeepsHeading() {
        var camera = LiveFollowCamera()
        let moving = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 30, courseAccuracy: 5)
        camera.ingest(location: moving, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let crawling = location(lat: 42.0, lon: 30.0, speedMps: 0.5, course: 200, courseAccuracy: 5)
        camera.forceRecenter(location: crawling, now: baseDate.addingTimeInterval(0.05))
        XCTAssertEqual(camera.center?.latitude ?? -1, 42.0, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 30, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
    }

    func testReduceMotionSnapsToTarget() {
        var camera = LiveFollowCamera()
        camera.reduceMotion = true
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        camera.ingest(
            location: location(lat: 41.01, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5),
            isPaused: false,
            now: baseDate.addingTimeInterval(1)
        )
        XCTAssertTrue(camera.tick(dt: frame, now: baseDate.addingTimeInterval(1)))
        XCTAssertEqual(camera.center?.latitude ?? -1, 41.01, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)
    }

    func testNormalizedHeadingWraps() {
        XCTAssertEqual(LiveFollowCamera.normalizedHeading(360), 0, accuracy: 0.01)
        XCTAssertEqual(LiveFollowCamera.normalizedHeading(-90), 270, accuracy: 0.01)
        XCTAssertEqual(LiveFollowCamera.normalizedHeading(450), 90, accuracy: 0.01)
    }

    @MainActor
    func testSessionTickContinuesWhenNotFollowing() {
        let session = LiveFollowSession()
        session.openSettled = true
        session.isFollowing = false
        session.isPaused = false
        var poseWrites = 0
        session.onPoseWrite = { _, _ in poseWrites += 1 }

        let start = location(lat: 41.0, lon: 29.0, speedMps: 15, course: 0, courseAccuracy: 5)
        session.ingest(location: start, isPaused: false, now: baseDate)
        XCTAssertTrue(session.tick(dt: frame, now: baseDate))
        let firstWrites = poseWrites
        XCTAssertGreaterThan(firstWrites, 0)

        let later = baseDate.addingTimeInterval(1)
        let next = location(
            lat: 41.001,
            lon: 29.0,
            speedMps: 15,
            course: 0,
            courseAccuracy: 5,
            timestamp: later
        )
        session.ingest(location: next, isPaused: false, now: later)
        XCTAssertTrue(session.tick(dt: frame, now: later))
        XCTAssertGreaterThan(poseWrites, firstWrites)
        XCTAssertNotNil(session.vehicleCoordinate)
    }

    @MainActor
    func testSessionRouteIsEmptyUntilRecordingServiceIsBound() {
        let session = LiveFollowSession()
        XCTAssertEqual(session.routeVersion, 0)
        XCTAssertTrue(session.routeSegments.isEmpty)
    }

    @MainActor
    func testHandleDisplayTickAdvancesWithoutOpenSettled() {
        let session = LiveFollowSession()
        session.openSettled = false
        session.isFollowing = true
        session.isPaused = false
        var poseWrites = 0
        session.onPoseWrite = { _, _ in poseWrites += 1 }

        let start = location(lat: 41.0, lon: 29.0, speedMps: 12, course: 90, courseAccuracy: 5)
        session.ingest(location: start, isPaused: false, now: baseDate)
        session.handleDisplayTick(dt: frame, now: baseDate)
        XCTAssertGreaterThan(poseWrites, 0)
    }

    /// The open hero lasts ~1 s. At motorway speed that is tens of metres — if the
    /// map camera froze for that window while the pose kept ticking, the curved
    /// flight would land on empty road with the trail already gone ahead.
    @MainActor
    func testMotorwayOpenWindowMovesTensOfMetresWhileUnsettled() {
        let session = LiveFollowSession()
        session.openSettled = false
        session.isFollowing = true
        session.isPaused = false
        let highway = location(lat: 41.0, lon: 29.0, speedMps: 33, course: 0, courseAccuracy: 5)
        session.ingest(location: highway, isPaused: false, now: baseDate)

        var now = baseDate
        for _ in 0..<63 {
            now = now.addingTimeInterval(frame)
            session.handleDisplayTick(dt: frame, now: now)
        }
        let travelled = CLLocation(latitude: 41.0, longitude: 29.0)
            .distance(from: CLLocation(
                latitude: session.vehicleCoordinate?.latitude ?? 41.0,
                longitude: session.vehicleCoordinate?.longitude ?? 29.0
            ))
        XCTAssertGreaterThan(travelled, 25)
        XCTAssertLessThan(travelled, 50)
    }

    func testVisuallySamePoseIgnoresSubPixelDeltas() {
        let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let pose = LiveFollowCamera.Pose(
            center: origin,
            headingDegrees: 90,
            distanceMeters: 220,
            pitchDegrees: 62
        )
        XCTAssertTrue(pose.isVisuallySame(as: pose))

        let nudged = LiveFollowCamera.coordinate(from: origin, headingDegrees: 0, distanceMeters: 0.01)
        XCTAssertTrue(pose.isVisuallySame(as: copy(pose, center: nudged)))
        XCTAssertTrue(pose.isVisuallySame(as: copy(pose, headingDegrees: 90.005)))
        XCTAssertTrue(pose.isVisuallySame(as: copy(pose, distanceMeters: 220.05)))
        XCTAssertTrue(pose.isVisuallySame(as: copy(pose, pitchDegrees: 62.005)))
    }

    func testVisuallySamePoseRejectsVisibleDeltas() {
        let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let pose = LiveFollowCamera.Pose(
            center: origin,
            headingDegrees: 90,
            distanceMeters: 220,
            pitchDegrees: 62
        )
        let moved = LiveFollowCamera.coordinate(from: origin, headingDegrees: 0, distanceMeters: 1)
        XCTAssertFalse(pose.isVisuallySame(as: copy(pose, center: moved)))
        XCTAssertFalse(pose.isVisuallySame(as: copy(pose, headingDegrees: 90.5)))
        XCTAssertFalse(pose.isVisuallySame(as: copy(pose, distanceMeters: 221)))
        XCTAssertFalse(pose.isVisuallySame(as: copy(pose, pitchDegrees: 63)))
    }

    func testVisuallySamePoseWrapsHeading() {
        let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let nearNorth = LiveFollowCamera.Pose(
            center: origin,
            headingDegrees: 359.999,
            distanceMeters: 220,
            pitchDegrees: 62
        )
        XCTAssertTrue(nearNorth.isVisuallySame(as: copy(nearNorth, headingDegrees: 0)))
        XCTAssertFalse(nearNorth.isVisuallySame(as: copy(nearNorth, headingDegrees: 1)))
    }

    func testMotorwayTicksAreNeverVisuallySame() throws {
        var camera = LiveFollowCamera()
        let speedMps = 30.0
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: speedMps, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        XCTAssertTrue(camera.tick(dt: frame, now: baseDate))
        var previous = try XCTUnwrap(camera.pose)

        for step in 1...45 {
            let now = baseDate.addingTimeInterval(Double(step) * frame)
            XCTAssertTrue(camera.tick(dt: frame, now: now))
            let pose = try XCTUnwrap(camera.pose)
            XCTAssertFalse(
                previous.isVisuallySame(as: pose),
                "frame \(step) was sub-pixel; a moving follow frame must still write the camera"
            )
            previous = pose
        }
    }

    private func copy(
        _ pose: LiveFollowCamera.Pose,
        center: CLLocationCoordinate2D? = nil,
        headingDegrees: CLLocationDirection? = nil,
        distanceMeters: CLLocationDistance? = nil,
        pitchDegrees: Double? = nil
    ) -> LiveFollowCamera.Pose {
        LiveFollowCamera.Pose(
            center: center ?? pose.center,
            headingDegrees: headingDegrees ?? pose.headingDegrees,
            distanceMeters: distanceMeters ?? pose.distanceMeters,
            pitchDegrees: pitchDegrees ?? pose.pitchDegrees
        )
    }

    private func location(
        lat: Double,
        lon: Double,
        speedMps: Double,
        course: Double,
        courseAccuracy: Double,
        timestamp: Date? = nil
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speedMps,
            speedAccuracy: 1,
            timestamp: timestamp ?? baseDate
        )
    }
}
