import XCTest
@testable import Milehound

final class KmReminderPlannerTests: XCTestCase {
    private let scheduleID = UUID(uuidString: "00000000-0000-4000-8000-000000000024")!

    func testStagesAndDedupeKeyChangeWithTheTarget() {
        let early = KmReminderPlanner.decision(
            scheduleID: scheduleID,
            dueKm: 4_000,
            odometerKm: 3_500,
            intervalKm: 4_000
        )
        XCTAssertEqual(early?.stage, .kmEarly)
        XCTAssertEqual(early?.kmLeft, 500)

        let due = KmReminderPlanner.decision(
            scheduleID: scheduleID,
            dueKm: 4_000,
            odometerKm: 4_000,
            intervalKm: 4_000
        )
        XCTAssertEqual(due?.stage, .kmDue)

        let overdue = KmReminderPlanner.decision(
            scheduleID: scheduleID,
            dueKm: 4_000,
            odometerKm: 5_000,
            intervalKm: 4_000
        )
        XCTAssertEqual(overdue?.stage, .kmOverdue)

        let quiet = KmReminderPlanner.decision(
            scheduleID: scheduleID,
            dueKm: 10_000,
            odometerKm: 4_000,
            intervalKm: 4_000
        )
        XCTAssertNil(quiet)

        XCTAssertNotEqual(early?.dedupeKey, due?.dedupeKey)
        let nextService = KmReminderPlanner.decision(
            scheduleID: scheduleID,
            dueKm: 8_000,
            odometerKm: 7_500,
            intervalKm: 4_000
        )
        XCTAssertNotEqual(early?.dedupeKey, nextService?.dedupeKey)
    }

    func testRecordingAndRepeatSuppressTheSend() {
        let decision = KmReminderPlanner.decision(
            scheduleID: scheduleID,
            dueKm: 1_000,
            odometerKm: 800,
            intervalKm: 1_000
        )
        XCTAssertFalse(KmReminderPlanner.shouldSend(recordingActive: true, alreadySent: false, decision: decision))
        XCTAssertFalse(KmReminderPlanner.shouldSend(recordingActive: false, alreadySent: true, decision: decision))
        XCTAssertFalse(KmReminderPlanner.shouldSend(recordingActive: false, alreadySent: false, decision: nil))
        XCTAssertTrue(KmReminderPlanner.shouldSend(recordingActive: false, alreadySent: false, decision: decision))
    }
}
