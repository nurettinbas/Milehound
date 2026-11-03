import XCTest
@testable import Milehound

final class SystemSettingsLinkTests: XCTestCase {
    func testPublicSettingsURLIsTheSystemAppSettingsLink() {
        XCTAssertEqual(
            SystemSettingsLink.publicAppSettingsURL?.absoluteString,
            "app-settings:"
        )
    }
}
