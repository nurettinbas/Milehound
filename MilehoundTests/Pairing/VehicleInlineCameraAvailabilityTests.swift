import XCTest
@testable import Milehound

final class VehicleInlineCameraAvailabilityTests: XCTestCase {
    func testBackCameraAloneIsAvailable() {
        XCTAssertTrue(
            VehicleInlineCameraAvailability.isAvailable(hasBackCamera: true, hasAnyVideoCamera: false)
        )
    }

    func testAnyVideoCameraAloneIsAvailable() {
        XCTAssertTrue(
            VehicleInlineCameraAvailability.isAvailable(hasBackCamera: false, hasAnyVideoCamera: true)
        )
    }

    func testNoCamerasIsUnavailable() {
        XCTAssertFalse(
            VehicleInlineCameraAvailability.isAvailable(hasBackCamera: false, hasAnyVideoCamera: false)
        )
    }
}
