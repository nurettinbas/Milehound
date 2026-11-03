import XCTest
@testable import Milehound

final class RecordingDisplaySamplerTests: XCTestCase {
    func testPublishRateLimitedToMinimumInterval() {
        var sampler = RecordingDisplaySampler(minimumInterval: 0.25)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(sampler.shouldPublish(now: start))

        var publishCount = 1
        for offset in stride(from: 0.1, through: 0.95, by: 0.1) {
            if sampler.shouldPublish(now: start.addingTimeInterval(offset)) {
                publishCount += 1
            }
        }

        XCTAssertLessThanOrEqual(publishCount, 4)
    }

    func testMarkPublishedAllowsImmediateRepublishAfterInterval() {
        var sampler = RecordingDisplaySampler(minimumInterval: 0.25)
        let start = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(sampler.shouldPublish(now: start))
        XCTAssertFalse(sampler.shouldPublish(now: start.addingTimeInterval(0.1)))
        XCTAssertTrue(sampler.shouldPublish(now: start.addingTimeInterval(0.26)))
    }

    func testResetAllowsImmediatePublish() {
        var sampler = RecordingDisplaySampler(minimumInterval: 0.25)
        let start = Date(timeIntervalSince1970: 3_000)

        XCTAssertTrue(sampler.shouldPublish(now: start))
        sampler.reset()
        XCTAssertTrue(sampler.shouldPublish(now: start.addingTimeInterval(0.05)))
    }
}
