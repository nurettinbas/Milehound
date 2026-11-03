import XCTest
@testable import Milehound

@MainActor
final class ScreenIdleLockTests: XCTestCase {
    private final class FakeIdleTimer: IdleTimerControlling {
        var isIdleTimerDisabled = false
    }

    func testRetainDisablesIdleTimer() {
        let fake = FakeIdleTimer()
        let lock = ScreenIdleLock(controller: fake)
        XCTAssertFalse(fake.isIdleTimerDisabled)
        lock.retain()
        XCTAssertEqual(lock.retainCount, 1)
        XCTAssertTrue(fake.isIdleTimerDisabled)
    }

    func testNestedRetainRelease() {
        let fake = FakeIdleTimer()
        let lock = ScreenIdleLock(controller: fake)
        lock.retain()
        lock.retain()
        XCTAssertEqual(lock.retainCount, 2)
        XCTAssertTrue(fake.isIdleTimerDisabled)
        lock.release()
        XCTAssertEqual(lock.retainCount, 1)
        XCTAssertTrue(fake.isIdleTimerDisabled)
        lock.release()
        XCTAssertEqual(lock.retainCount, 0)
        XCTAssertFalse(fake.isIdleTimerDisabled)
    }

    func testReleaseBelowZeroIsSafe() {
        let fake = FakeIdleTimer()
        let lock = ScreenIdleLock(controller: fake)
        lock.release()
        XCTAssertEqual(lock.retainCount, 0)
        XCTAssertFalse(fake.isIdleTimerDisabled)
    }

    func testResetForTestingClears() {
        let fake = FakeIdleTimer()
        let lock = ScreenIdleLock(controller: fake)
        lock.retain()
        lock.resetForTesting()
        XCTAssertEqual(lock.retainCount, 0)
        XCTAssertFalse(fake.isIdleTimerDisabled)
    }
}
