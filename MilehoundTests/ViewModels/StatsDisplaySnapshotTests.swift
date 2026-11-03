import XCTest
@testable import Milehound

@MainActor
final class StatsDisplaySnapshotTests: XCTestCase {
    func testBuilderMatchesDirectDailyDistances() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: today.addingTimeInterval(86_399))
        let goalMonth = StatsViewModel.goalMonth(
            for: .custom,
            selectedMonth: today,
            customStart: interval.start,
            customEnd: interval.end
        )

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 4000,
            estimatedFuelCost: 80
        )
        let yesterdayTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(7200),
            distanceMeters: 2500,
            estimatedFuelCost: 50
        )
        let trips = [todayTrip, yesterdayTrip]

        let snapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: trips,
            categories: [],
            vehicles: [],
            selectedPeriod: .custom,
            customStart: interval.start,
            customEnd: interval.end,
            selectedMonth: today,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            goalMonth: goalMonth
        )

        let direct = StatsViewModel.dailyDistances(in: interval, from: trips)
        let directFuel = StatsViewModel.dailyFuelCosts(in: interval, from: trips)
        let goalMonthInterval = StatsViewModel.calendarMonthInterval(containing: goalMonth)
        let expectedGoal = StatsViewModel.stats(
            for: StatsViewModel.trips(in: goalMonthInterval, from: trips),
            includeNightRatio: false
        ).totalDistanceMeters

        XCTAssertEqual(snapshot.dailyDistance.count, direct.count)
        XCTAssertEqual(snapshot.dailyDistance.first?.distanceMeters ?? 0, direct.first?.distanceMeters ?? -1, accuracy: 0.1)
        XCTAssertEqual(snapshot.dailyFuelCost.count, directFuel.count)
        XCTAssertEqual(snapshot.dailyFuelCost.last?.cost ?? 0, 80, accuracy: 0.1)
        XCTAssertEqual(snapshot.stats.tripCount, 2)
        XCTAssertEqual(snapshot.stats.estimatedFuelCost, 130, accuracy: 0.1)
        XCTAssertEqual(snapshot.goalDistanceMeters, expectedGoal, accuracy: 0.1)
        XCTAssertTrue(snapshot.hasAnyDailyChart)
        XCTAssertNotNil(snapshot.fuelCostTrendText())
    }

    func testGoalDistanceUsesSelectedMonthNotCurrentMonth() {
        let currentMonthStart = StatsViewModel.calendarMonthInterval(containing: Date()).start
        let previousMonth = StatsViewModel.shiftMonth(currentMonthStart, by: -1)
        let previousInterval = StatsViewModel.calendarMonthInterval(containing: previousMonth)

        let previousTrip = Trip(
            startedAt: previousInterval.start.addingTimeInterval(10 * 3_600),
            endedAt: previousInterval.start.addingTimeInterval(12 * 3_600),
            distanceMeters: 12_000,
            estimatedFuelCost: 100
        )
        let currentTrip = Trip(
            startedAt: currentMonthStart.addingTimeInterval(10 * 3_600),
            endedAt: currentMonthStart.addingTimeInterval(12 * 3_600),
            distanceMeters: 99_000,
            estimatedFuelCost: 200
        )

        let snapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: [previousTrip, currentTrip],
            categories: [],
            vehicles: [],
            selectedPeriod: .month,
            customStart: Date(),
            customEnd: Date(),
            selectedMonth: previousMonth,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            goalMonth: previousMonth
        )

        XCTAssertEqual(snapshot.goalDistanceMeters, 12_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.stats.totalDistanceMeters, 12_000, accuracy: 0.1)
    }

    func testInProgressMonthPreviousStatsUsesMTDSliceNotFullPreviousMonth() {
        let now = Date()
        let currentStart = StatsViewModel.calendarMonthInterval(containing: now).start
        let selectedInterval = StatsViewModel.calendarMonthInterval(containing: currentStart)
        let previousFull = StatsViewModel.previousMonthInterval(containing: currentStart)
        let aligned = StatsViewModel.alignedPreviousInterval(
            for: .month,
            selectedInterval: selectedInterval,
            selectedMonth: currentStart,
            now: now
        )
        let latePrevious = aligned.end.addingTimeInterval(2 * 86_400)
        guard latePrevious < previousFull.end else { return }

        let earlyPreviousTrip = Trip(
            startedAt: previousFull.start.addingTimeInterval(3_600),
            endedAt: previousFull.start.addingTimeInterval(7_200),
            distanceMeters: 1_000
        )
        let latePreviousTrip = Trip(
            startedAt: latePrevious,
            endedAt: latePrevious.addingTimeInterval(3_600),
            distanceMeters: 9_000
        )
        let currentTrip = Trip(
            startedAt: currentStart.addingTimeInterval(3_600),
            endedAt: currentStart.addingTimeInterval(7_200),
            distanceMeters: 2_000
        )

        let snapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: [earlyPreviousTrip, latePreviousTrip, currentTrip],
            categories: [],
            vehicles: [],
            selectedPeriod: .month,
            customStart: now,
            customEnd: now,
            selectedMonth: currentStart,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            goalMonth: currentStart
        )

        XCTAssertEqual(snapshot.previousStats.totalDistanceMeters, 1_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.stats.totalDistanceMeters, 2_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.distanceTrend?.isFavorable, true)
    }

    func testWeekGoalDistanceUsesCurrentMonthNotWeekWindow() {
        let calendar = Calendar.current
        let currentMonthStart = StatsViewModel.calendarMonthInterval(containing: Date()).start
        let today = calendar.startOfDay(for: Date())

        // Early in the month, outside last-7-calendar-days when today is late enough;
        // when today is near month start this still lands in the goal month.
        let earlyMonthTrip = Trip(
            startedAt: currentMonthStart.addingTimeInterval(10 * 3_600),
            endedAt: currentMonthStart.addingTimeInterval(12 * 3_600),
            distanceMeters: 20_000
        )
        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3_600),
            endedAt: today.addingTimeInterval(7_200),
            distanceMeters: 5_000
        )

        let goalMonth = StatsViewModel.goalMonth(
            for: .week,
            selectedMonth: today,
            customStart: Date(),
            customEnd: Date()
        )
        let weekSnapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: [earlyMonthTrip, todayTrip],
            categories: [],
            vehicles: [],
            selectedPeriod: .week,
            customStart: Date(),
            customEnd: Date(),
            selectedMonth: today,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            goalMonth: goalMonth
        )

        XCTAssertEqual(weekSnapshot.goalDistanceMeters, 25_000, accuracy: 0.1)
        // Summary still follows the week filter; goal ring does not.
        XCTAssertLessThanOrEqual(weekSnapshot.stats.totalDistanceMeters, 25_000)
        XCTAssertEqual(weekSnapshot.periodDayCount, 7)
        XCTAssertEqual(weekSnapshot.previousPeriodDayCount, 7)
        XCTAssertEqual(weekSnapshot.dailyTripCount.count, 7)
    }

    func testPlaceFilterNarrowsSummaryAndDailyChartsButNotGoal() {
        let calendar = Calendar.current
        // Mid-month so "yesterday" stays in the same calendar month as customEnd
        // (goal ring). Using Date() fails on the 1st when yesterday is last month.
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let intervalEnd = today.addingTimeInterval(12 * 3_600)
        let interval = DateInterval(start: yesterday, end: intervalEnd)
        let goalMonth = StatsViewModel.goalMonth(
            for: .custom,
            selectedMonth: today,
            customStart: interval.start,
            customEnd: interval.end
        )

        let homeTrip = Trip(
            startedAt: today.addingTimeInterval(3_600),
            endedAt: today.addingTimeInterval(7_200),
            distanceMeters: 4_000,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let otherTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3_600),
            endedAt: yesterday.addingTimeInterval(7_200),
            distanceMeters: 2_500,
            startPlaceName: "Market",
            endPlaceName: "Ofis"
        )

        let snapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: [homeTrip, otherTrip],
            categories: [],
            vehicles: [],
            selectedPeriod: .custom,
            customStart: interval.start,
            customEnd: interval.end,
            selectedMonth: today,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            selectedPlaceName: "Ev",
            goalMonth: goalMonth
        )

        XCTAssertEqual(snapshot.stats.tripCount, 1)
        XCTAssertEqual(snapshot.stats.totalDistanceMeters, 4_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.dailyDistance.reduce(0) { $0 + $1.distanceMeters }, 4_000, accuracy: 0.1)
        // Goal ring ignores place filter.
        XCTAssertEqual(snapshot.goalDistanceMeters, 6_500, accuracy: 0.1)
    }

    func testGoalMonthResolver() {
        let now = Date()
        let currentStart = StatsViewModel.calendarMonthInterval(containing: now).start
        let previous = StatsViewModel.shiftMonth(currentStart, by: -1)
        let customEnd = previous.addingTimeInterval(10 * 86_400)

        XCTAssertEqual(
            StatsViewModel.goalMonth(
                for: .week,
                selectedMonth: previous,
                customStart: previous,
                customEnd: customEnd,
                now: now
            ),
            currentStart
        )
        XCTAssertEqual(
            StatsViewModel.goalMonth(
                for: .month,
                selectedMonth: previous,
                customStart: previous,
                customEnd: customEnd,
                now: now
            ),
            previous
        )
        XCTAssertEqual(
            StatsViewModel.goalMonth(
                for: .custom,
                selectedMonth: currentStart,
                customStart: previous,
                customEnd: customEnd,
                now: now
            ),
            StatsViewModel.calendarMonthInterval(containing: customEnd).start
        )
    }

    func testSnapshotAddsTripCountNightWeekdayAndMixFlags() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: now)
        let goalMonth = StatsViewModel.goalMonth(
            for: .custom,
            selectedMonth: today,
            customStart: interval.start,
            customEnd: interval.end
        )

        let peak = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 8_000
        )
        peak.stopDurationSeconds = 300
        peak.nightDistanceMeters = 2_000
        peak.trackedDistanceMeters = 8_000
        peak.fuelIdleVolume = 0.25
        peak.dynamicFuelVolume = 1.0

        let quiet = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(5400),
            distanceMeters: 1_000
        )
        quiet.stopDurationSeconds = 60
        quiet.nightDistanceMeters = 0
        quiet.trackedDistanceMeters = 1_000

        let snapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: [peak, quiet],
            categories: [],
            vehicles: [],
            selectedPeriod: .custom,
            customStart: interval.start,
            customEnd: interval.end,
            selectedMonth: today,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            goalMonth: goalMonth
        )

        XCTAssertEqual(snapshot.dailyTripCount.last?.count, 1)
        XCTAssertEqual(snapshot.dailyNightDistance.last?.distanceMeters ?? 0, 2_000, accuracy: 0.1)
        XCTAssertTrue(snapshot.hasNightDailyChart)
        XCTAssertTrue(snapshot.hasWeekdayCharts)
        XCTAssertTrue(snapshot.hasMixCharts)
        XCTAssertEqual(snapshot.drivingDayCount, 2)
        XCTAssertEqual(snapshot.periodDayCount, 2)
        XCTAssertEqual(snapshot.busiestDay, today)
        XCTAssertEqual(snapshot.busiestDayMeters, 8_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.stats.averageDistanceMeters, 4_500, accuracy: 0.1)
        XCTAssertFalse(snapshot.stats.fuelFactorShares.isEmpty)
        XCTAssertEqual(snapshot.weekdayDistance.count, 7)
    }

    func testEmptyPeriodHidesWeekdayAndMixCards() {
        XCTAssertFalse(StatsDisplaySnapshot.empty.hasWeekdayCharts)
        XCTAssertFalse(StatsDisplaySnapshot.empty.hasMixCharts)
        XCTAssertFalse(StatsDisplaySnapshot.empty.hasNightDailyChart)
        XCTAssertEqual(StatsDisplaySnapshot.empty.drivingDayCount, 0)
        XCTAssertNil(StatsDisplaySnapshot.empty.busiestDay)
    }
}
