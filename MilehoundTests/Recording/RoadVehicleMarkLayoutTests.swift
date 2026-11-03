import UIKit
import XCTest
@testable import Milehound

final class RoadVehicleMarkLayoutTests: XCTestCase {
    func testSymbolPlacementMatchesHistoricalFormula() {
        let metrics = MilehoundRoadSceneMetrics.regular
        let roadTop: CGFloat = 50
        let bounce: CGFloat = 1.2
        let placement = MilehoundRoadVehicleMarkLayout.placement(
            kind: .symbol,
            metrics: metrics,
            roadTop: roadTop,
            bounce: bounce
        )
        XCTAssertEqual(placement.size, metrics.carSize)
        XCTAssertEqual(placement.centerY, roadTop - metrics.carSize * 0.35 + bounce, accuracy: 0.001)
    }

    func testCutoutPlacementKeepsLargePhotoSizeAndHistoricalY() {
        let metrics = MilehoundRoadSceneMetrics.regular
        let roadTop: CGFloat = 50
        let bounce: CGFloat = 0
        let placement = MilehoundRoadVehicleMarkLayout.placement(
            kind: .cutoutPhoto,
            metrics: metrics,
            roadTop: roadTop,
            bounce: bounce
        )
        let expectedSize = min(metrics.carSize * 3.0, metrics.sceneHeight * 1.18)
        XCTAssertEqual(placement.size, expectedSize)
        XCTAssertEqual(placement.centerY, roadTop - metrics.carSize * 0.35 + bounce, accuracy: 0.001)
    }

    func testOpaquePlacementKeepsFullSizeOnRoad() {
        let metrics = MilehoundRoadSceneMetrics.regular
        let frameHeight = MilehoundRoadVehicleMarkLayout.sceneFrameHeight(for: metrics)
        let roadTop = frameHeight - metrics.roadHeight
        let bounce: CGFloat = 0
        let cutout = MilehoundRoadVehicleMarkLayout.placement(
            kind: .cutoutPhoto,
            metrics: metrics,
            roadTop: roadTop,
            bounce: bounce
        )
        let opaque = MilehoundRoadVehicleMarkLayout.placement(
            kind: .opaquePhoto,
            metrics: metrics,
            roadTop: roadTop,
            bounce: bounce
        )
        let expectedSize = min(metrics.carSize * 1.65, metrics.sceneHeight * 0.72)
        XCTAssertEqual(opaque.size, expectedSize, accuracy: 0.001)
        XCTAssertLessThan(opaque.size, cutout.size)

        let bottomY = opaque.centerY + opaque.size * 0.5
        XCTAssertEqual(
            bottomY,
            roadTop + MilehoundRoadVehicleMarkLayout.opaqueRoadOverlap,
            accuracy: 0.001
        )
    }

    func testSceneFrameHeightAddsChromeSoBadgeFitsAboveFullOpaquePlate() {
        let metrics = MilehoundRoadSceneMetrics.compact
        let frameHeight = MilehoundRoadVehicleMarkLayout.sceneFrameHeight(for: metrics)
        XCTAssertGreaterThan(frameHeight, metrics.sceneHeight)

        let roadTop = frameHeight - metrics.roadHeight
        let bounce = -MilehoundRoadVehicleMarkLayout.bounceAmplitude
        let opaque = MilehoundRoadVehicleMarkLayout.placement(
            kind: .opaquePhoto,
            metrics: metrics,
            roadTop: roadTop,
            bounce: bounce
        )
        let expectedSize = min(metrics.carSize * 1.65, metrics.sceneHeight * 0.72)
        XCTAssertEqual(opaque.size, expectedSize, accuracy: 0.001)

        let diameter = max(15 as CGFloat, metrics.carSize * 0.68)
        let badgeOffsetY = RecordingVehicleServiceBadgeLayout.offsetY(
            for: metrics.carSize,
            markSize: opaque.size
        )
        let badgeTop = opaque.centerY + badgeOffsetY - diameter * 0.5
        XCTAssertGreaterThanOrEqual(badgeTop, 0, "badge sits above mark inside expanded frame")
    }

    func testServiceBadgeLiftsAboveLargeCutoutPhotoWithoutClipping() {
        let metrics = MilehoundRoadSceneMetrics.compact
        let frameHeight = MilehoundRoadVehicleMarkLayout.sceneFrameHeight(for: metrics)
        let roadTop = frameHeight - metrics.roadHeight
        let cutout = MilehoundRoadVehicleMarkLayout.placement(
            kind: .cutoutPhoto,
            metrics: metrics,
            roadTop: roadTop,
            bounce: MilehoundRoadVehicleMarkLayout.bounceAmplitude
        )
        let diameter = max(15 as CGFloat, metrics.carSize * 0.68)
        let symbolOffset = RecordingVehicleServiceBadgeLayout.offsetY(
            for: metrics.carSize,
            markSize: metrics.carSize
        )
        let photoOffset = RecordingVehicleServiceBadgeLayout.offsetY(
            for: metrics.carSize,
            markSize: cutout.size
        )
        XCTAssertLessThan(photoOffset, symbolOffset, "large photos lift the wrench above the mark")

        let badgeTop = cutout.centerY + photoOffset - diameter * 0.5
        XCTAssertGreaterThanOrEqual(badgeTop, 0, "lifted badge stays inside chrome headroom")

        let markTop = cutout.centerY - cutout.size * 0.5
        let badgeCenterY = cutout.centerY + photoOffset
        XCTAssertLessThanOrEqual(badgeCenterY, markTop + 1, "badge sits on/above the photo, not on the body")
    }

    func testKindHelperMapsPhotoFlags() {
        XCTAssertEqual(MilehoundRoadVehicleMarkLayout.kind(hasPhoto: false, isCutout: true), .symbol)
        XCTAssertEqual(MilehoundRoadVehicleMarkLayout.kind(hasPhoto: true, isCutout: true), .cutoutPhoto)
        XCTAssertEqual(MilehoundRoadVehicleMarkLayout.kind(hasPhoto: true, isCutout: false), .opaquePhoto)
    }

    func testClassifierMarksSolidImageAsOpaquePlate() {
        let solid = makeSolidColorImage(width: 64, height: 64, color: .systemBlue)
        XCTAssertFalse(VehiclePhotoStore.isRoadCutoutMark(solid))
    }

    func testClassifierMarksTransparentEllipseAsCutout() {
        let cutout = makeTransparentEllipse(size: 64)
        XCTAssertTrue(VehiclePhotoStore.isRoadCutoutMark(cutout))
    }

    private func makeSolidColorImage(width: CGFloat, height: CGFloat, color: UIColor) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            color.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeTransparentEllipse(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.systemBlue.setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: size * 0.2, y: size * 0.2, width: size * 0.6, height: size * 0.6)
            )
        }
    }
}
