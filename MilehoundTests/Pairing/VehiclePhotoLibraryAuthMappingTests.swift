import Photos
import XCTest
@testable import Milehound

final class VehiclePhotoLibraryAuthMappingTests: XCTestCase {
    func testAuthorizedAndLimitedMapToAuthorized() {
        XCTAssertEqual(
            VehiclePhotoLibraryAuthMapping.state(from: .authorized),
            .authorized
        )
        XCTAssertEqual(
            VehiclePhotoLibraryAuthMapping.state(from: .limited),
            .authorized
        )
    }

    func testDeniedAndRestrictedMapToDenied() {
        XCTAssertEqual(
            VehiclePhotoLibraryAuthMapping.state(from: .denied),
            .denied
        )
        XCTAssertEqual(
            VehiclePhotoLibraryAuthMapping.state(from: .restricted),
            .denied
        )
    }

    func testNotDeterminedMapsToUndetermined() {
        XCTAssertEqual(
            VehiclePhotoLibraryAuthMapping.state(from: .notDetermined),
            .undetermined
        )
    }

    /// Loader `applyAuthorization` routes through this mapping — denied must stay denied.
    func testDeniedStatesNeverMapToAuthorized() {
        let deniedStates: [PHAuthorizationStatus] = [.denied, .restricted]
        for status in deniedStates {
            XCTAssertEqual(
                VehiclePhotoLibraryAuthMapping.state(from: status),
                .denied,
                "Expected \(status.rawValue) to map to .denied"
            )
            XCTAssertNotEqual(
                VehiclePhotoLibraryAuthMapping.state(from: status),
                .authorized
            )
        }
    }
}
