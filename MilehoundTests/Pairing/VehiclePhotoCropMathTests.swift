import UIKit
import XCTest
@testable import Milehound

final class VehiclePhotoCropMathTests: XCTestCase {
    func testCoverScaleFillsCrop() {
        let scale = VehiclePhotoCropMath.coverScale(imageSize: CGSize(width: 400, height: 200), cropSide: 100)
        XCTAssertEqual(scale, 0.5, accuracy: 0.0001)
    }

    func testOffsetClampKeepsCoverage() {
        let draw = CGSize(width: 200, height: 200)
        let clamped = VehiclePhotoCropMath.clampedOffset(
            CGSize(width: 500, height: -500),
            drawSize: draw,
            cropSide: 100
        )
        XCTAssertEqual(clamped.width, 50, accuracy: 0.001)
        XCTAssertEqual(clamped.height, -50, accuracy: 0.001)
    }

    func testRenderSquareProducesExpectedSize() {
        let image = makeImage(width: 400, height: 300)
        let rendered = VehiclePhotoCropMath.renderSquare(
            image: image,
            cropSide: 200,
            userScale: 1.2,
            offset: .zero,
            outputSide: 256
        )
        XCTAssertEqual(rendered?.size.width, 256)
        XCTAssertEqual(rendered?.size.height, 256)
        XCTAssertEqual(rendered?.scale, 1)
    }

    func testZoomRangeIsCenteredOnDefaultCover() {
        let mid =
            (VehiclePhotoCropMath.minUserScale + VehiclePhotoCropMath.maxUserScale) / 2
        XCTAssertEqual(mid, VehiclePhotoCropMath.defaultUserScale, accuracy: 0.0001)
        XCTAssertLessThan(VehiclePhotoCropMath.minUserScale, 1)
        XCTAssertGreaterThan(VehiclePhotoCropMath.maxUserScale, 1)
    }

    func testDrawSizeAllowsZoomOutBelowCover() {
        let imageSize = CGSize(width: 400, height: 300)
        let crop: CGFloat = 200
        let cover = VehiclePhotoCropMath.drawSize(imageSize: imageSize, cropSide: crop, userScale: 1)
        let out = VehiclePhotoCropMath.drawSize(imageSize: imageSize, cropSide: crop, userScale: 0.5)
        XCTAssertLessThan(out.width, cover.width)
        XCTAssertLessThan(out.height, cover.height)
    }

    func testRotateRightSwapsAspect() {
        let image = makeImage(width: 400, height: 200)
        let rotated = VehiclePhotoCropMath.applying(.rotateRight, to: image)
        XCTAssertEqual(rotated.size.width, 200, accuracy: 1)
        XCTAssertEqual(rotated.size.height, 400, accuracy: 1)
    }

    func testFlipHorizontalKeepsSize() {
        let image = makeImage(width: 120, height: 80)
        let flipped = VehiclePhotoCropMath.applying(.flipHorizontal, to: image)
        XCTAssertEqual(flipped.size.width, 120, accuracy: 0.5)
        XCTAssertEqual(flipped.size.height, 80, accuracy: 0.5)
    }

    func testPrepareForCropDownscalesHugeImages() {
        let huge = makeImage(width: 4000, height: 3000)
        let prepared = VehiclePhotoCropMath.prepareForCrop(huge, maxEdge: 1024)
        let longest = max(prepared.size.width, prepared.size.height)
        XCTAssertLessThanOrEqual(longest, 1024 + 1)
    }

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
