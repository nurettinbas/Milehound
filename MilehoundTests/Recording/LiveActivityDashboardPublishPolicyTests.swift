import XCTest
@testable import Milehound

final class LiveActivityDashboardPublishPolicyTests: XCTestCase {
    func testCarPlayCallOcclusionRequiresBothCallAndCarAudio() {
        XCTAssertFalse(
            LiveActivityDashboardPublishPolicy.isCarPlayCallOcclusion(
                hasActiveCall: false,
                isCarAudioRoute: false
            )
        )
        XCTAssertFalse(
            LiveActivityDashboardPublishPolicy.isCarPlayCallOcclusion(
                hasActiveCall: true,
                isCarAudioRoute: false
            )
        )
        XCTAssertFalse(
            LiveActivityDashboardPublishPolicy.isCarPlayCallOcclusion(
                hasActiveCall: false,
                isCarAudioRoute: true
            )
        )
        XCTAssertTrue(
            LiveActivityDashboardPublishPolicy.isCarPlayCallOcclusion(
                hasActiveCall: true,
                isCarAudioRoute: true
            )
        )
    }

    func testSkipsRegularTicksWhileDashboardIsOccluded() {
        XCTAssertFalse(
            LiveActivityDashboardPublishPolicy.shouldPublish(
                dashboardOccluded: true,
                force: false,
                pauseStateChanged: false,
                secondsSinceLastUpdate: 10
            )
        )
    }

    func testForceAndPauseStillPublishWhileOccluded() {
        XCTAssertTrue(
            LiveActivityDashboardPublishPolicy.shouldPublish(
                dashboardOccluded: true,
                force: true,
                pauseStateChanged: false,
                secondsSinceLastUpdate: 0
            )
        )
        XCTAssertTrue(
            LiveActivityDashboardPublishPolicy.shouldPublish(
                dashboardOccluded: true,
                force: false,
                pauseStateChanged: true,
                secondsSinceLastUpdate: 0
            )
        )
    }

    func testThrottleMatchesPreviousThreeSecondFloor() {
        XCTAssertTrue(
            LiveActivityDashboardPublishPolicy.shouldPublish(
                dashboardOccluded: false,
                force: false,
                pauseStateChanged: false,
                secondsSinceLastUpdate: nil
            )
        )
        XCTAssertFalse(
            LiveActivityDashboardPublishPolicy.shouldPublish(
                dashboardOccluded: false,
                force: false,
                pauseStateChanged: false,
                secondsSinceLastUpdate: 2.9
            )
        )
        XCTAssertTrue(
            LiveActivityDashboardPublishPolicy.shouldPublish(
                dashboardOccluded: false,
                force: false,
                pauseStateChanged: false,
                secondsSinceLastUpdate: 3
            )
        )
    }
}
