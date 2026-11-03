import XCTest
@testable import Milehound

final class VehiclePhotoCaptureHandoffTests: XCTestCase {
    func testLibraryMapsToGalleryOverlay() {
        XCTAssertEqual(
            VehiclePhotoCaptureHandoff.pendingMode(after: .library),
            .gallery
        )
    }

    func testCameraMapsToCameraOverlay() {
        XCTAssertEqual(
            VehiclePhotoCaptureHandoff.pendingMode(after: .camera),
            .camera
        )
    }

    func testCancelClearsPendingMode() {
        XCTAssertNil(VehiclePhotoCaptureHandoff.pendingMode(after: .cancel))
    }

    func testSheetRouteIDIsStableFlowIdentity() {
        XCTAssertEqual(VehiclePhotoSheetRoute.flow.id, "vehicle-photo-flow")
    }

    func testSourceDetentHeightDependsOnCamera() {
        XCTAssertEqual(VehiclePhotoFlowDetents.sourceHeight(cameraAvailable: true), 340)
        XCTAssertEqual(VehiclePhotoFlowDetents.sourceHeight(cameraAvailable: false), 280)
    }

    func testCaptureFractionIsSeventyTwoPercent() {
        XCTAssertEqual(VehiclePhotoFlowDetents.captureFraction, 0.72, accuracy: 0.0001)
    }
}
