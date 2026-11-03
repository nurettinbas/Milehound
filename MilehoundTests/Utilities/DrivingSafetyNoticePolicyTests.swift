import XCTest
@testable import Milehound

final class DrivingSafetyNoticePolicyTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DrivingSafetyNoticePolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstManualStartShowsTheNotice() {
        XCTAssertTrue(DrivingSafetyNoticePolicy(defaults: defaults).shouldShow)
    }

    func testNoticeStaysHiddenAfterConfirm() {
        DrivingSafetyNoticePolicy(defaults: defaults).markShown()
        XCTAssertFalse(DrivingSafetyNoticePolicy(defaults: defaults).shouldShow)
    }

    func testResetShowsTheNoticeAgain() {
        let policy = DrivingSafetyNoticePolicy(defaults: defaults)
        policy.markShown()
        policy.reset()
        XCTAssertTrue(policy.shouldShow)
    }
}
