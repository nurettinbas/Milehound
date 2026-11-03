import XCTest
@testable import Milehound

final class RecordingMovementPolicyTests: XCTestCase {
    func testSmallDeltaIsIgnored() {
        let decision = RecordingMovementPolicy.decision(delta: 1.5, timeDelta: 1, speed: 10)
        XCTAssertEqual(decision, .ignore)
    }

    func testStationaryJitterIsIgnored() {
        let decision = RecordingMovementPolicy.decision(delta: 3, timeDelta: 2, speed: 0.2)
        XCTAssertEqual(decision, .ignore)
    }

    func testNormalCitySegmentAccumulates() {
        let decision = RecordingMovementPolicy.decision(delta: 80, timeDelta: 5, speed: 16)
        XCTAssertEqual(decision, .accumulate)
    }

    func testTimeScaledSegmentAccumulates() {
        let decision = RecordingMovementPolicy.decision(delta: 400, timeDelta: 20, speed: 20)
        XCTAssertEqual(decision, .accumulate)
    }

    func testImpossibleJumpIsGapResume() {
        let decision = RecordingMovementPolicy.decision(delta: 800, timeDelta: 2, speed: 30)
        XCTAssertEqual(decision, .gapResume)
    }

    /// Same-timestamp batch fixes at trip start must not invent a gapResume via the 0.01 s floor.
    func testSameTimestampConvergenceDoesNotGapResume() {
        let decision = RecordingMovementPolicy.decision(delta: 7, timeDelta: 0, speed: 0)
        XCTAssertEqual(decision, .ignore)
        XCTAssertEqual(
            RecordingMovementPolicy.ignoreReason(delta: 7, timeDelta: 0, locationSpeedMps: 0),
            "convergence"
        )
    }

    func testSubHalfSecondConvergenceDoesNotGapResume() {
        let decision = RecordingMovementPolicy.decision(delta: 7, timeDelta: 0.2, speed: 0)
        XCTAssertEqual(decision, .ignore)
    }

    func testModerateGapAfterOutageAccumulatesInsteadOfSticking() {
        let decision = RecordingMovementPolicy.decision(delta: 600, timeDelta: 30, speed: 20)
        XCTAssertEqual(decision, .accumulate)
    }

    func testSparseCoastalGapAccumulatesDistance() {
        // 8 km in 10 min ≈ 13 m/s — real driving with sparse GPS; must count toward distance.
        let decision = RecordingMovementPolicy.decision(delta: 8000, timeDelta: 600, speed: 20)
        XCTAssertEqual(decision, .accumulate)
    }

    func testImpliedSpeedTooHighIsGapResume() {
        let decision = RecordingMovementPolicy.decision(delta: 400, timeDelta: 5, speed: 40)
        XCTAssertEqual(decision, .gapResume)
    }

    func testPlausibleRecordedSpeedBounds() {
        XCTAssertFalse(RecordingMovementPolicy.isPlausibleRecordedSpeed(0))
        XCTAssertFalse(RecordingMovementPolicy.isPlausibleRecordedSpeed(-1))
        XCTAssertTrue(RecordingMovementPolicy.isPlausibleRecordedSpeed(36.4)) // ~131 km/h
        XCTAssertFalse(RecordingMovementPolicy.isPlausibleRecordedSpeed(71))
    }

    func testSparseGapCountsDistanceButDoesNotDrawMapChord() {
        XCTAssertTrue(
            RecordingMovementPolicy.decision(delta: 8000, timeDelta: 600, speed: 20) == .accumulate
        )
        XCTAssertFalse(
            RecordingMovementPolicy.shouldDrawMapSegment(delta: 8000, timeDelta: 600, speed: 20)
        )
    }

    func testShortSegmentDrawsOnMap() {
        XCTAssertTrue(
            RecordingMovementPolicy.shouldDrawMapSegment(delta: 120, timeDelta: 8, speed: 16)
        )
    }

    func testEffectiveSpeedUsesImpliedWhenGPSSpeedInvalid() {
        let implied = RecordingMovementPolicy.effectiveSpeedMps(
            locationSpeedMps: -1,
            delta: 100,
            timeDelta: 5
        )
        XCTAssertEqual(implied ?? 0, 20, accuracy: 0.01)
    }

    // MARK: - Speed trust

    /// A clean fix on the motorway: every gate passes and the reading is used as reported.
    func testTrustedSpeedAcceptsAGoodFix() {
        XCTAssertEqual(
            trusted(reported: 33, speedAccuracy: 0.6, horizontalAccuracy: 8, age: 0.4) ?? 0,
            33,
            accuracy: 0.001
        )
    }

    /// Core Location signals an unusable speed with a negative accuracy, which the old code never
    /// looked at.
    func testTrustedSpeedRejectsInvalidSpeedAccuracy() {
        XCTAssertNil(trusted(reported: 30, speedAccuracy: -1, horizontalAccuracy: 8, age: 0.4))
        XCTAssertEqual(
            RecordingMovementPolicy.speedRejectionReason(
                reportedMps: 30,
                speedAccuracyMps: -1,
                horizontalAccuracyMeters: 8,
                fixAgeSeconds: 0.4
            ),
            "speed_invalid"
        )
    }

    func testTrustedSpeedRejectsUncertainSpeed() {
        XCTAssertNil(trusted(reported: 30, speedAccuracy: 9, horizontalAccuracy: 8, age: 0.4))
    }

    /// The position is still stored elsewhere; only the speed of a vague fix is thrown away.
    func testTrustedSpeedRejectsUncertainPosition() {
        XCTAssertNil(trusted(reported: 30, speedAccuracy: 0.5, horizontalAccuracy: 180, age: 0.4))
    }

    /// Recording start replays the last cached fix, which may still carry an earlier drive's speed.
    func testTrustedSpeedRejectsStaleFix() {
        XCTAssertNil(trusted(reported: 30, speedAccuracy: 0.5, horizontalAccuracy: 8, age: 90))
        XCTAssertEqual(
            RecordingMovementPolicy.speedRejectionReason(
                reportedMps: 30,
                speedAccuracyMps: 0.5,
                horizontalAccuracyMeters: 8,
                fixAgeSeconds: 90
            ),
            "fix_stale"
        )
    }

    /// 203 km/h passes the teleport check (70 m/s) but is not a speed a car in this app reaches.
    func testTrustedSpeedRejectsTheReportedPhantom() {
        XCTAssertTrue(RecordingMovementPolicy.isPlausibleRecordedSpeed(56.4))
        XCTAssertFalse(RecordingMovementPolicy.isRecordableSpeed(56.4))
        XCTAssertNil(trusted(reported: 56.4, speedAccuracy: 0.5, horizontalAccuracy: 8, age: 0.4))
    }

    func testAccelerationLimitRejectsAnImpossibleJump() {
        XCTAssertFalse(
            RecordingMovementPolicy.isPlausibleAcceleration(from: 10, to: 45, timeDelta: 1)
        )
        XCTAssertTrue(
            RecordingMovementPolicy.isPlausibleAcceleration(from: 10, to: 14, timeDelta: 1)
        )
    }

    /// A long wait loosens the limit on its own, so pulling away from a light after two minutes
    /// parked is never mistaken for noise.
    func testAccelerationLimitAllowsPullingAwayAfterALongStop() {
        XCTAssertTrue(
            RecordingMovementPolicy.isPlausibleAcceleration(from: 0, to: 14, timeDelta: 120)
        )
    }

    func testAccelerationLimitAllowsTheFirstSampleOfATrip() {
        XCTAssertTrue(
            RecordingMovementPolicy.isPlausibleAcceleration(from: nil, to: 40, timeDelta: 1)
        )
    }

    private func trusted(
        reported: Double,
        speedAccuracy: Double,
        horizontalAccuracy: Double,
        age: TimeInterval
    ) -> Double? {
        RecordingMovementPolicy.trustedGPSSpeedMps(
            reportedMps: reported,
            speedAccuracyMps: speedAccuracy,
            horizontalAccuracyMeters: horizontalAccuracy,
            fixAgeSeconds: age
        )
    }
}
