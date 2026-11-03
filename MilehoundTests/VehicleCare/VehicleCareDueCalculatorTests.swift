import XCTest
@testable import Milehound

final class VehicleCareDueCalculatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testUpcomingTodayOverdueAndNoDate() {
        var components = DateComponents(year: 2026, month: 8, day: 8)
        let today = calendar.date(from: components)!

        components.day = 15
        let upcoming = calendar.date(from: components)!
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: upcoming, today: today, calendar: calendar),
            .upcoming(daysLeft: 7)
        )

        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: today, today: today, calendar: calendar),
            .dueToday
        )

        components.day = 5
        let overdue = calendar.date(from: components)!
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: overdue, today: today, calendar: calendar),
            .overdue(days: 3)
        )

        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: nil, today: today, calendar: calendar),
            .noDate
        )
    }

    func testRollForwardMonthsAndYears() {
        let completed = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let nextMonth = VehicleCareDueCalculator.nextDueDateAfterCompletion(
            completedOn: completed,
            intervalKind: .everyMonths,
            intervalMonths: 12,
            calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: nextMonth!),
            DateComponents(year: 2027, month: 1, day: 10)
        )

        let nextYear = VehicleCareDueCalculator.nextDueDateAfterCompletion(
            completedOn: completed,
            intervalKind: .everyYears,
            intervalMonths: 24,
            calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: nextYear!),
            DateComponents(year: 2028, month: 1, day: 10)
        )

        XCTAssertNil(
            VehicleCareDueCalculator.nextDueDateAfterCompletion(
                completedOn: completed,
                intervalKind: .none,
                intervalMonths: nil,
                calendar: calendar
            )
        )
    }

    func testDefaultReminderOffsets() {
        XCTAssertEqual(VehicleScheduleKind.service.defaultReminderOffsets, [30, 7])
        XCTAssertEqual(VehicleScheduleKind.inspection.defaultReminderOffsets, [30, 7])
        XCTAssertEqual(VehicleScheduleKind.trafficInsurance.defaultReminderOffsets, [7])
        XCTAssertEqual(VehicleScheduleKind.casco.defaultReminderOffsets, [7])
    }

    func testUrgencyBandMapping() {
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .overdue(days: 2)), .alert)
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .dueToday), .warning)
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .upcoming(daysLeft: 30)), .warning)
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .upcoming(daysLeft: 7)), .warning)
        XCTAssertNil(VehicleCareUrgencyStyle.band(for: .upcoming(daysLeft: 31)))
        XCTAssertNil(VehicleCareUrgencyStyle.band(for: .noDate))
        XCTAssertNil(VehicleCareUrgencyStyle.chipText(for: .upcoming(daysLeft: 45)))
        XCTAssertNotNil(VehicleCareUrgencyStyle.chipText(for: .upcoming(daysLeft: 5)))
    }

    func testKmThresholdScalesWithInterval() {
        XCTAssertEqual(VehicleCareDueCalculator.kmSoonThreshold(intervalKm: 1_000), 300)
        XCTAssertEqual(VehicleCareDueCalculator.kmSoonThreshold(intervalKm: 4_000), 600)
        XCTAssertEqual(VehicleCareDueCalculator.kmSoonThreshold(intervalKm: 10_000), 1_500)
        XCTAssertEqual(VehicleCareDueCalculator.kmSoonThreshold(intervalKm: 15_000), 1_500)
    }

    func testEveryKmAndWhicheverFirstPickTheSoonerSide() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let farDate = calendar.date(from: DateComponents(year: 2027, month: 6, day: 1))!
        let soonDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 3))!

        let vespa = VehicleSchedule(
            kind: .service,
            nextDueDate: nil,
            nextDueOdometerKm: 1_000,
            intervalKind: .everyKm,
            intervalKm: 1_000
        )
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(schedule: vespa, odometerKm: 800, today: today, calendar: calendar),
            .upcomingKm(kmLeft: 200, approaching: true)
        )
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(schedule: vespa, odometerKm: nil, today: today, calendar: calendar),
            .noDate
        )
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(schedule: vespa, odometerKm: 1_000, today: today, calendar: calendar),
            .dueToday
        )
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(schedule: vespa, odometerKm: 1_250, today: today, calendar: calendar),
            .overdueKm(kmOver: 250)
        )

        let car = VehicleSchedule(
            kind: .service,
            nextDueDate: farDate,
            nextDueOdometerKm: 15_000,
            intervalKind: .whicheverFirst,
            intervalMonths: 12,
            intervalKm: 15_000
        )
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(schedule: car, odometerKm: 14_000, today: today, calendar: calendar),
            .upcomingKm(kmLeft: 1_000, approaching: true)
        )

        let dateFirst = VehicleSchedule(
            kind: .inspection,
            nextDueDate: soonDate,
            nextDueOdometerKm: 20_000,
            intervalKind: .whicheverFirst,
            intervalMonths: 24,
            intervalKm: 15_000
        )
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(schedule: dateFirst, odometerKm: 4_000, today: today, calendar: calendar),
            .upcoming(daysLeft: 2)
        )

        let monthsOnly = VehicleSchedule(
            kind: .service,
            nextDueDate: farDate,
            nextDueOdometerKm: 1_000,
            intervalKind: .everyMonths,
            intervalMonths: 12,
            intervalKm: 10_000
        )
        let monthsState = VehicleCareDueCalculator.dueState(
            schedule: monthsOnly,
            odometerKm: 9_900,
            today: today,
            calendar: calendar
        )
        if case .upcoming = monthsState {
        } else {
            XCTFail("A months-only reminder must ignore kilometres")
        }
    }

    func testKmUrgencyBands() {
        XCTAssertEqual(
            VehicleCareUrgencyStyle.band(for: .upcomingKm(kmLeft: 200, approaching: true)),
            .warning
        )
        XCTAssertNil(VehicleCareUrgencyStyle.band(for: .upcomingKm(kmLeft: 8_000, approaching: false)))
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .overdueKm(kmOver: 40)), .alert)
        XCTAssertNotNil(VehicleCareUrgencyStyle.chipText(for: .upcomingKm(kmLeft: 200, approaching: true)))
    }

    func testEncodeDecodeOffsets() {
        let raw = VehicleSchedule.encodeOffsets([30, 7])
        XCTAssertEqual(raw, "30,7")
        XCTAssertEqual(VehicleSchedule.decodeOffsets(raw), [30, 7])
    }
}
