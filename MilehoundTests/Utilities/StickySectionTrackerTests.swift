import XCTest
@testable import Milehound

final class StickySectionTrackerTests: XCTestCase {
    private enum Section: String, Hashable {
        case summary
        case daily
        case weekday
        case mix
    }

    func testTopmostVisibleFollowsOrder() {
        var tracker = StickySectionTracker<Section>(order: [.summary, .daily, .weekday, .mix], initial: .summary)
        tracker.markAppeared(.daily)
        tracker.markAppeared(.weekday)
        XCTAssertEqual(tracker.visibleSection, .daily)

        tracker.markAppeared(.summary)
        XCTAssertEqual(tracker.visibleSection, .summary)

        tracker.markDisappeared(.summary)
        XCTAssertEqual(tracker.visibleSection, .daily)
    }

    func testScrollPositionIgnoredDuringTapScroll() {
        var tracker = StickySectionTracker<Section>(order: [.summary, .daily, .weekday], initial: .summary)
        tracker.beginTapScroll(to: .weekday)
        XCTAssertEqual(tracker.visibleSection, .weekday)
        XCTAssertTrue(tracker.isTapScrolling)

        tracker.applyScrollPosition(.daily)
        tracker.markAppeared(.daily)
        tracker.markDisappeared(.summary)
        XCTAssertEqual(tracker.visibleSection, .weekday)

        tracker.endTapScroll()
        XCTAssertFalse(tracker.isTapScrolling)
        XCTAssertEqual(tracker.visibleSection, .weekday)
    }

    func testUpdateOrderDropsHiddenSelection() {
        var tracker = StickySectionTracker<Section>(order: [.summary, .daily, .mix], initial: .mix)
        tracker.updateOrder([.summary, .daily])
        XCTAssertEqual(tracker.visibleSection, .summary)
    }
}
