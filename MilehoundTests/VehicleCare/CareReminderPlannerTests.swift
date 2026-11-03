import XCTest
@testable import Milehound

final class CareReminderPlannerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testServiceStagesIncludeEarlyWeekDueAndOverdue() {
        XCTAssertEqual(
            CareReminderPlanner.stages(for: .service),
            [.early, .week, .dueDay, .overdue]
        )
        XCTAssertEqual(
            CareReminderPlanner.stages(for: .trafficInsurance),
            [.week, .dueDay, .overdue]
        )
    }

    func testFullLadderSchedulesFutureFireDays() {
        let today = date(year: 2026, month: 8, day: 1)
        let due = date(year: 2026, month: 9, day: 10)
        let entries = CareReminderPlanner.plan(
            stages: [.early, .week, .dueDay, .overdue],
            dueDate: due,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.map(\.stage), [.early, .week, .dueDay, .overdue])
        XCTAssertEqual(entries[0].action, .schedule(fireDay: date(year: 2026, month: 8, day: 11)))
        XCTAssertEqual(entries[1].action, .schedule(fireDay: date(year: 2026, month: 9, day: 3)))
        XCTAssertEqual(entries[2].action, .schedule(fireDay: date(year: 2026, month: 9, day: 10)))
        XCTAssertEqual(entries[3].action, .schedule(fireDay: date(year: 2026, month: 9, day: 11)))
    }

    func testSkipsPastPreDueStages() {
        let today = date(year: 2026, month: 9, day: 8)
        let due = date(year: 2026, month: 9, day: 10)
        let entries = CareReminderPlanner.plan(
            stages: [.early, .week, .dueDay, .overdue],
            dueDate: due,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(entries.map(\.stage), [.dueDay, .overdue])
        XCTAssertEqual(entries[0].action, .schedule(fireDay: date(year: 2026, month: 9, day: 10)))
        XCTAssertEqual(entries[1].action, .schedule(fireDay: date(year: 2026, month: 9, day: 11)))
    }

    func testOverdueCatchUpWhenFireDayAlreadyPassed() {
        let today = date(year: 2026, month: 9, day: 15)
        let due = date(year: 2026, month: 9, day: 10)
        let entries = CareReminderPlanner.plan(
            stages: [.early, .week, .dueDay, .overdue],
            dueDate: due,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].stage, .overdue)
        XCTAssertEqual(
            entries[0].action,
            .catchUpImmediate(fireDay: date(year: 2026, month: 9, day: 11))
        )
    }

    func testInsuranceOmitsEarlyStage() {
        let today = date(year: 2026, month: 8, day: 1)
        let due = date(year: 2026, month: 8, day: 20)
        let entries = CareReminderPlanner.plan(
            stages: CareReminderPlanner.stages(for: .casco),
            dueDate: due,
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(entries.map(\.stage), [.week, .dueDay, .overdue])
        XCTAssertFalse(entries.contains { $0.stage == .early })
    }

    func testDueDayKey() {
        let due = date(year: 2026, month: 8, day: 10)
        XCTAssertEqual(CareReminderPlanner.dueDayKey(dueDate: due, calendar: calendar), "20260810")
    }
}
