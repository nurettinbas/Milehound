import XCTest
@testable import Milehound

final class LiveFollowPresentationTests: XCTestCase {
    private let container = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let source = CGRect(x: 16, y: 120, width: 358, height: 220)

    func testLerpRectEndpoints() {
        let mid = LiveFollowPresentation.lerpRect(from: source, to: container, progress: 0.5)
        XCTAssertEqual(mid.minX, 8, accuracy: 0.01)
        XCTAssertEqual(mid.minY, 60, accuracy: 0.01)
        XCTAssertEqual(mid.width, 374, accuracy: 0.01)
        XCTAssertEqual(mid.height, 532, accuracy: 0.01)

        XCTAssertEqual(
            LiveFollowPresentation.lerpRect(from: source, to: container, progress: 0),
            source
        )
        XCTAssertEqual(
            LiveFollowPresentation.lerpRect(from: source, to: container, progress: 1),
            container
        )
    }

    func testProgressClamped() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container)
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: -1),
            source
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: 2),
            settled
        )
    }

    func testHUDColumnWidthCapsTheCoverAndThePane() {
        XCTAssertEqual(
            LiveFollowPresentation.hudColumnWidth(containerWidth: 390, landscapeCover: false, fillsPane: false),
            LiveFollowPresentation.compactHUDWidthCap,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudColumnWidth(containerWidth: 320, landscapeCover: false, fillsPane: false),
            320 * 8 / 12,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudColumnWidth(containerWidth: 844, landscapeCover: true, fillsPane: false),
            LiveFollowPresentation.landscapeCoverHUDWidthCap,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudColumnWidth(containerWidth: 800, landscapeCover: false, fillsPane: true),
            LiveFollowPresentation.paneHUDWidthCap,
            accuracy: 0.01
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudColumnWidth(containerWidth: 360, landscapeCover: false, fillsPane: true),
            LiveFollowPresentation.compactHUDWidthCap,
            accuracy: 0.01
        )
    }

    func testSettledHUDRectCenteredBottom() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 112)
        XCTAssertEqual(settled.width, 390 * 8 / 12, accuracy: 0.01)
        XCTAssertEqual(settled.height, 112, accuracy: 0.01)
        XCTAssertEqual(settled.midX, container.midX, accuracy: 0.01)
        XCTAssertEqual(
            settled.maxY,
            container.maxY - LiveFollowPresentation.settledBottomPadding,
            accuracy: 0.01
        )
    }

    func testHUDRectEndpoints() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container)
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: 0),
            source
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: 1),
            settled
        )
    }

    func testSourceRectUsesAnchorWhenValid() {
        let anchor = RecordingCardAnchor(minX: 10, minY: 20, width: 300, height: 200)
        XCTAssertEqual(
            LiveFollowPresentation.sourceRect(from: anchor, fallbackContainer: container),
            CGRect(x: 10, y: 20, width: 300, height: 200)
        )
    }

    func testSourceRectFallsBackWhenAnchorEmpty() {
        let fallback = LiveFollowPresentation.sourceRect(
            from: RecordingCardAnchor(),
            fallbackContainer: container
        )
        XCTAssertGreaterThan(fallback.width, 1)
        XCTAssertGreaterThan(fallback.height, 1)
        XCTAssertTrue(container.contains(fallback.origin) || fallback.intersects(container))
    }

    func testReduceMotionStartsSettled() {
        XCTAssertEqual(LiveFollowPresentation.initialProgress(reduceMotion: true), 1)
        XCTAssertEqual(LiveFollowPresentation.initialProgress(reduceMotion: false), 0)
    }

    func testHeroSourcePrefersCarFrame() {
        let anchor = RecordingCardAnchor(
            minX: 10,
            minY: 20,
            width: 300,
            height: 200,
            carMinX: 40,
            carMinY: 60,
            carWidth: 100,
            carHeight: 50
        )
        XCTAssertEqual(
            LiveFollowPresentation.heroSourceRect(from: anchor, cardFallback: source),
            CGRect(x: 40, y: 60, width: 100, height: 50)
        )
    }

    func testHeroDestMatchesPuckCircleAtScreenCenter() {
        let size = CGSize(width: 390, height: 844)
        let dest3D = LiveFollowPresentation.heroDestCenter(in: size, uses3D: true)
        let dest2D = LiveFollowPresentation.heroDestCenter(in: size, uses3D: false)
        let expected = LiveFollowPresentation.puckCircleCenter(
            fromProjectedAnnotationPoint: CGPoint(x: 195, y: 422)
        )
        XCTAssertEqual(dest3D.x, expected.x, accuracy: 0.01)
        XCTAssertEqual(dest3D.y, expected.y, accuracy: 0.01)
        XCTAssertEqual(dest2D.x, dest3D.x, accuracy: 0.01)
        XCTAssertEqual(dest2D.y, dest3D.y, accuracy: 0.01)
        XCTAssertEqual(dest3D.x, 195, accuracy: 0.01)
    }

    /// The route tail ends at the coordinate, so the circle center must land there too —
    /// otherwise the trail enters the puck off-center (badly on a bend under 3D pitch).
    func testPuckCircleCenterSitsExactlyOnTheProjectedCoordinate() {
        let projected = CGPoint(x: 200, y: 500)
        let circle = LiveFollowPresentation.puckCircleCenter(fromProjectedAnnotationPoint: projected)
        XCTAssertEqual(circle.x, projected.x, accuracy: 0.01)
        XCTAssertEqual(circle.y, projected.y, accuracy: 0.01)
    }

    func testPuckAnnotationCenterOffsetCentersCircleOnCoordinate() {
        let offset = LiveFollowPresentation.puckAnnotationCenterOffset
        XCTAssertEqual(offset.x, 0, accuracy: 0.01)
        XCTAssertEqual(
            offset.y,
            LiveFollowPresentation.puckAnnotationFrameHeight / 2
                - LiveFollowPresentation.puckCircleSize / 2,
            accuracy: 0.01
        )
        // Chevron hangs below the coordinate, behind the vehicle.
        XCTAssertGreaterThan(offset.y, 0)
    }

    func testPuckRotationIsIdentityWhenMapAlreadyFacesTravel() {
        XCTAssertEqual(
            LiveFollowPresentation.puckRotationRadians(
                travelHeadingDegrees: 90,
                mapHeadingDegrees: 90
            ),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LiveFollowPresentation.puckRotationRadians(
                travelHeadingDegrees: 0,
                mapHeadingDegrees: 0
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testPuckRotationOnNorthUpOverviewFacesTravel() {
        // Artwork is drawn screen-up. Eastbound on a north-up map needs +90°
        // (clockwise in UIKit) so the chevron's sharp tip points along the road.
        let east = LiveFollowPresentation.puckRotationRadians(
            travelHeadingDegrees: 90,
            mapHeadingDegrees: 0
        )
        XCTAssertEqual(east, .pi / 2, accuracy: 0.0001)

        let west = LiveFollowPresentation.puckRotationRadians(
            travelHeadingDegrees: 270,
            mapHeadingDegrees: 0
        )
        XCTAssertEqual(west, -.pi / 2, accuracy: 0.0001)

        let wrap = LiveFollowPresentation.puckRotationRadians(
            travelHeadingDegrees: 10,
            mapHeadingDegrees: 350
        )
        XCTAssertEqual(wrap, 20 * .pi / 180, accuracy: 0.0001)
    }

    func testHeroFlightArcEndpointsAndBulge() {
        let from = CGPoint(x: 195, y: 160)
        let to = CGPoint(x: 195, y: 540)
        XCTAssertEqual(
            LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: 0),
            from
        )
        XCTAssertEqual(
            LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: 1),
            to
        )
        let midArc = LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: 0.5)
        let midStraight = LiveFollowPresentation.lerpPoint(from: from, to: to, progress: 0.5)
        // Side-sweep must leave the vertical chord by a readable amount.
        XCTAssertGreaterThan(abs(midArc.x - midStraight.x), 40)
        XCTAssertLessThan(midArc.x, midStraight.x) // bows leading / left
        XCTAssertLessThan(midArc.y, midStraight.y) // slight upward peak before descent
    }

    func testCloseHudExpandsAtBottomThenRises() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 112)
        let start = LiveFollowPresentation.closeHudRect(
            source: source,
            settled: settled,
            expandProgress: 0,
            riseProgress: 0
        )
        XCTAssertEqual(start, settled)

        let expanded = LiveFollowPresentation.closeHudRect(
            source: source,
            settled: settled,
            expandProgress: 1,
            riseProgress: 0
        )
        XCTAssertEqual(expanded.width, source.width, accuracy: 0.01)
        XCTAssertEqual(expanded.height, source.height, accuracy: 0.01)
        XCTAssertEqual(expanded.maxY, settled.maxY, accuracy: 0.01)

        let risen = LiveFollowPresentation.closeHudRect(
            source: source,
            settled: settled,
            expandProgress: 1,
            riseProgress: 1
        )
        XCTAssertEqual(risen, source)
    }

    func testHeroSourceFallsBackWhenCarFrameMissing() {
        let fallback = LiveFollowPresentation.heroSourceRect(
            from: RecordingCardAnchor(minX: 10, minY: 20, width: 300, height: 200),
            cardFallback: source
        )
        XCTAssertGreaterThan(fallback.width, 1)
        XCTAssertGreaterThan(fallback.height, 1)
        XCTAssertEqual(fallback.midX, source.midX, accuracy: 0.01)
        XCTAssertGreaterThan(fallback.minY, source.minY)
    }

    func testExpandedAtBottomPinsMaxY() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 112)
        let expanded = LiveFollowPresentation.expandedAtBottomRect(source: source, settled: settled)
        XCTAssertEqual(expanded.width, source.width, accuracy: 0.01)
        XCTAssertEqual(expanded.height, source.height, accuracy: 0.01)
        XCTAssertEqual(expanded.maxY, settled.maxY, accuracy: 0.01)
        XCTAssertEqual(expanded.midX, settled.midX, accuracy: 0.01)
    }

    func testQuadraticBezierEndpoints() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 100)
        let control = CGPoint(x: 0, y: 100)
        XCTAssertEqual(
            LiveFollowPresentation.quadraticBezier(from: from, control: control, to: to, progress: 0),
            from
        )
        XCTAssertEqual(
            LiveFollowPresentation.quadraticBezier(from: from, control: control, to: to, progress: 1),
            to
        )
        let mid = LiveFollowPresentation.quadraticBezier(
            from: from,
            control: control,
            to: to,
            progress: 0.5
        )
        XCTAssertEqual(mid.x, 25, accuracy: 0.01)
        XCTAssertEqual(mid.y, 75, accuracy: 0.01)
    }

    func testCloseHudClampsOutOfRangeProgress() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 112)
        XCTAssertEqual(
            LiveFollowPresentation.closeHudRect(
                source: source,
                settled: settled,
                expandProgress: -1,
                riseProgress: -2
            ),
            settled
        )
        XCTAssertEqual(
            LiveFollowPresentation.closeHudRect(
                source: source,
                settled: settled,
                expandProgress: 4,
                riseProgress: 9
            ),
            source
        )
    }

    func testRecordingCardAnchorCarFrameGate() {
        var anchor = RecordingCardAnchor(minX: 10, minY: 20, width: 300, height: 180)
        XCTAssertFalse(anchor.hasCarFrame)
        XCTAssertEqual(anchor.rect, CGRect(x: 10, y: 20, width: 300, height: 180))

        anchor.carMinX = 40
        anchor.carMinY = 60
        anchor.carWidth = 1
        anchor.carHeight = 50
        XCTAssertFalse(anchor.hasCarFrame)

        anchor.carWidth = 80
        XCTAssertTrue(anchor.hasCarFrame)
        XCTAssertEqual(anchor.carRect, CGRect(x: 40, y: 60, width: 80, height: 50))
    }
}
