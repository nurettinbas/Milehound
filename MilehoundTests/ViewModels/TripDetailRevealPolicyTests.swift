import CoreLocation
import XCTest
@testable import Milehound

final class TripDetailRevealPolicyTests: XCTestCase {
    func testAnyRouteLengthAnimatesOnFirstOpen() {
        for pointCount in [10, 300, 350, 1500, 2000] {
            let plan = TripDetailRevealPolicy.animationPlan(
                pointCount: pointCount,
                reduceMotion: false
            )
            XCTAssertTrue(plan.shouldAnimate, "pointCount \(pointCount) should animate")
            XCTAssertEqual(plan.tickCount, 12)
            XCTAssertEqual(plan.stepSleepMilliseconds, 40)
            XCTAssertTrue(plan.useCheapMapDuringReveal)
        }
    }

    func testReduceMotionSkipsAnimation() {
        let plan = TripDetailRevealPolicy.animationPlan(pointCount: 10, reduceMotion: true)
        XCTAssertFalse(plan.shouldAnimate)
        XCTAssertEqual(plan.tickCount, 0)
        XCTAssertTrue(plan.useCheapMapDuringReveal)
    }

    func testQuantizedProgressSteps() {
        let progress = TripDetailRevealPolicy.quantizedProgress(rawProgress: 0.9, tick: 8, tickCount: 16)
        XCTAssertEqual(progress, 0.5, accuracy: 0.0001)
    }

    func testMidRevealUsesFallbackOnly() {
        let path = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.02),
            CLLocationCoordinate2D(latitude: 41.03, longitude: 29.03)
        ]
        let colored = [
            SpeedColoredSegment(id: 0, coordinates: path, band: .slow)
        ]
        let fallback = RoutePathReveal.prefix(path, progress: 0.5)
        let stroke = TripDetailRevealOverlays.stroke(
            progress: 0.5,
            coloredSegments: colored,
            fallbackCoordinates: fallback
        )
        XCTAssertTrue(stroke.revealedItems.isEmpty)
        XCTAssertFalse(stroke.drawCasing)
        XCTAssertGreaterThanOrEqual(stroke.revealedFallback.count, 2)
        XCTAssertLessThan(stroke.revealedFallback.count, path.count)
    }

    func testSettledRevealUsesColoredSegmentsAndCasing() {
        let path = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.02)
        ]
        let colored = [
            SpeedColoredSegment(id: 0, coordinates: Array(path.prefix(2)), band: .slow),
            SpeedColoredSegment(id: 1, coordinates: Array(path.suffix(2)), band: .medium)
        ]
        let stroke = TripDetailRevealOverlays.stroke(
            progress: 1,
            coloredSegments: colored,
            fallbackCoordinates: path
        )
        XCTAssertEqual(stroke.revealedItems.count, 2)
        XCTAssertTrue(stroke.drawCasing)
        XCTAssertTrue(stroke.revealedFallback.isEmpty)
    }

    func testSettledWithoutColorsFallsBackToSolid() {
        let path = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        ]
        let stroke = TripDetailRevealOverlays.stroke(
            progress: 1,
            coloredSegments: [],
            fallbackCoordinates: path
        )
        XCTAssertTrue(stroke.revealedItems.isEmpty)
        XCTAssertEqual(stroke.revealedFallback.count, 2)
        XCTAssertTrue(stroke.drawCasing)
    }
}
