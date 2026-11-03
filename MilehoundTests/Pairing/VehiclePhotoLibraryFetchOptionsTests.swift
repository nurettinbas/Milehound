import Photos
import XCTest
@testable import Milehound

final class VehiclePhotoLibraryFetchOptionsTests: XCTestCase {
    func testRecentImagesFetchOptionsMatchCaptureContract() throws {
        let options = VehiclePhotoLibraryLoader.makeRecentImagesFetchOptions()

        XCTAssertEqual(options.fetchLimit, VehiclePhotoLibraryLoader.fetchLimit)
        XCTAssertEqual(options.fetchLimit, 120)

        let sort = try XCTUnwrap(options.sortDescriptors?.first)
        XCTAssertEqual(sort.key, "creationDate")
        XCTAssertFalse(sort.ascending)

        let predicate = try XCTUnwrap(options.predicate)
        XCTAssertEqual(
            predicate.predicateFormat,
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue).predicateFormat
        )
    }

    func testCustomLimitIsHonored() {
        let options = VehiclePhotoLibraryLoader.makeRecentImagesFetchOptions(limit: 40)
        XCTAssertEqual(options.fetchLimit, 40)
    }
}
