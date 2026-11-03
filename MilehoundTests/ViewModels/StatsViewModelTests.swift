import XCTest
@testable import Milehound

final class StatsViewModelTests: XCTestCase {
    func testStatsAggregatesCompletedTripsOnly() {
        let completed = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5000,
            estimatedFuelCost: 40
        )
        let active = Trip(startedAt: Date(), endedAt: nil, distanceMeters: 1000)

        let stats = StatsViewModel.stats(for: [completed, active])

        XCTAssertEqual(stats.tripCount, 1)
        XCTAssertEqual(stats.totalDistanceMeters, 5000, accuracy: 0.1)
        XCTAssertEqual(stats.estimatedFuelCost, 40, accuracy: 0.1)
        XCTAssertEqual(stats.averageSpeedKmh, 5, accuracy: 0.1)
        XCTAssertEqual(stats.maxSpeedKmh, 0, accuracy: 0.1)
    }

    func testStatsComputesAverageAndMaxSpeed() {
        let fast = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 36_000,
            maxSpeedMps: 33.33
        )
        let slow = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 9_000,
            maxSpeedMps: 22.22
        )

        let stats = StatsViewModel.stats(for: [fast, slow])

        // (36000 + 9000) m over 5400 s = 8.333 m/s = 30 km/h
        XCTAssertEqual(stats.averageSpeedKmh, 30, accuracy: 0.1)
        XCTAssertEqual(stats.maxSpeedKmh, 33.33 * 3.6, accuracy: 0.1)
    }

    func testStatsWeightsCruiseSpeedByCruiseDuration() {
        let city = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 5_000
        )
        city.cruiseSpeedKmh = 30
        city.cruiseDurationSeconds = 300 // 5 minutes
        city.stopDurationSeconds = 120
        city.mostCommonSpeedKmh = 25

        let highway = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 40_000
        )
        highway.cruiseSpeedKmh = 110
        highway.cruiseDurationSeconds = 7_200 // 2 hours
        highway.stopDurationSeconds = 60
        highway.mostCommonSpeedKmh = 100

        let stats = StatsViewModel.stats(for: [city, highway])

        // (30*300 + 110*7200) / (300+7200) ≈ 106.8
        XCTAssertEqual(stats.cruiseSpeedKmh, 106.8, accuracy: 0.2)
        XCTAssertEqual(stats.mostCommonSpeedKmh, 97.0, accuracy: 0.2)
        XCTAssertEqual(stats.stopDuration, 180, accuracy: 0.1)
    }

    /// A trip recorded before speeds were vetted can carry a maximum no car reached. Statistics
    /// cannot afford to load its points to check, so the value is hidden rather than headlined.
    func testStatsHidesAnImplausibleStoredMaximum() {
        let phantom = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 36_000,
            maxSpeedMps: 56.4 // 203 km/h
        )
        let real = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 9_000,
            maxSpeedMps: 22.22
        )

        let stats = StatsViewModel.stats(for: [phantom, real])

        XCTAssertEqual(stats.maxSpeedKmh, 22.22 * 3.6, accuracy: 0.1)
    }

    func testDailyMaxSpeedsHideAnImplausibleStoredMaximum() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let interval = DateInterval(start: today, end: today.addingTimeInterval(86_399))
        let phantom = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 36_000,
            maxSpeedMps: 56.4
        )

        let daily = StatsViewModel.dailyMaxSpeeds(in: interval, from: [phantom])

        XCTAssertEqual(daily.first?.speedKmh ?? -1, 0, accuracy: 0.001)
    }

    func testDailyAverageAndMaxSpeedsBucketByDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: today.addingTimeInterval(86_399))

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 36_000,
            maxSpeedMps: 30
        )
        let yesterdayTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(5400),
            distanceMeters: 9_000,
            maxSpeedMps: 20
        )

        let averages = StatsViewModel.dailyAverageSpeeds(
            in: interval,
            from: [todayTrip, yesterdayTrip]
        )
        let maxSpeeds = StatsViewModel.dailyMaxSpeeds(
            in: interval,
            from: [todayTrip, yesterdayTrip]
        )

        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages.first?.speedKmh ?? 0, 18, accuracy: 0.1)
        XCTAssertEqual(averages.last?.speedKmh ?? 0, 36, accuracy: 0.1)
        XCTAssertEqual(maxSpeeds.first?.speedKmh ?? 0, 72, accuracy: 0.1)
        XCTAssertEqual(maxSpeeds.last?.speedKmh ?? 0, 108, accuracy: 0.1)
    }

    func testStatsFiltersByCategory() {
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 3000,
            category: .business
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal
        )

        let stats = StatsViewModel.stats(for: [business, personal], categoryID: BuiltInCategory.businessID.uuidString)

        XCTAssertEqual(stats.tripCount, 1)
        XCTAssertEqual(stats.totalDistanceMeters, 3000, accuracy: 0.1)
    }

    func testStatsFiltersByPlaceNameMatchingStartOrEnd() {
        let startHome = Trip(
            startedAt: Date().addingTimeInterval(-7_200),
            endedAt: Date().addingTimeInterval(-3_600),
            distanceMeters: 3_000,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let endHome = Trip(
            startedAt: Date().addingTimeInterval(-1_800),
            endedAt: Date(),
            distanceMeters: 2_000,
            startPlaceName: "Market",
            endPlaceName: "Ev"
        )
        let other = Trip(
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date().addingTimeInterval(-300),
            distanceMeters: 1_000,
            startPlaceName: "Market",
            endPlaceName: "Ofis"
        )

        let stats = StatsViewModel.stats(for: [startHome, endHome, other], placeName: "Ev")

        XCTAssertEqual(stats.tripCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 5_000, accuracy: 0.1)
    }

    func testDailyDistancesBucketsByDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: today.addingTimeInterval(86_399))

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 4000
        )
        let yesterdayTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(7200),
            distanceMeters: 2500
        )

        let buckets = StatsViewModel.dailyDistances(in: interval, from: [todayTrip, yesterdayTrip])

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets.first?.distanceMeters ?? 0, 2500, accuracy: 0.1)
        XCTAssertEqual(buckets.last?.distanceMeters ?? 0, 4000, accuracy: 0.1)
    }

    func testDailyFuelCostsBucketByDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: today.addingTimeInterval(86_399))

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
        let secondToday = Trip(
            startedAt: today.addingTimeInterval(8000),
            endedAt: today.addingTimeInterval(9000),
            distanceMeters: 1000,
            estimatedFuelCost: 20
        )

        let daily = StatsViewModel.dailyFuelCosts(
            in: interval,
            from: [todayTrip, yesterdayTrip, secondToday]
        )

        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily.first?.cost ?? 0, 50, accuracy: 0.1)
        XCTAssertEqual(daily.last?.cost ?? 0, 100, accuracy: 0.1)
        XCTAssertEqual(daily.first?.dynamicCost ?? 0, 0, accuracy: 0.1)
        XCTAssertEqual(daily.last?.dynamicCost ?? 0, 0, accuracy: 0.1)
    }

    func testDailyFuelCostsIncludeDynamicSeries() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let interval = DateInterval(start: today, end: today.addingTimeInterval(86_399))

        let trip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 4000,
            estimatedFuelCost: 80,
            dynamicFuelCost: 95
        )

        let daily = StatsViewModel.dailyFuelCosts(in: interval, from: [trip])
        let todayBucket = daily.first { calendar.isDate($0.day, inSameDayAs: today) }
        XCTAssertEqual(todayBucket?.cost ?? 0, 80, accuracy: 0.1)
        XCTAssertEqual(todayBucket?.dynamicCost ?? 0, 95, accuracy: 0.1)
    }

    func testCategoryAndVehicleFuelBreakdown() {
        let vehicleA = UUID()
        let vehicleB = UUID()
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 3000,
            category: .business,
            estimatedFuelCost: 60,
            vehicleID: vehicleA
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal,
            estimatedFuelCost: 40,
            vehicleID: vehicleB
        )
        let categories = [
            UserCategory(id: BuiltInCategory.businessID, name: "Business", sortOrder: 0),
            UserCategory(id: BuiltInCategory.personalID, name: "Personal", sortOrder: 1)
        ]
        let vehicles = [
            VehicleProfile(id: vehicleA, name: "Car A"),
            VehicleProfile(id: vehicleB, name: "Car B")
        ]

        let categoryFuel = StatsViewModel.categoryFuelBreakdown(for: [business, personal], categories: categories)
        let vehicleFuel = StatsViewModel.vehicleFuelBreakdown(for: [business, personal], vehicles: vehicles)

        XCTAssertEqual(categoryFuel.count, 2)
        XCTAssertEqual(categoryFuel[0].cost, 60, accuracy: 0.1)
        XCTAssertEqual(categoryFuel[1].cost, 40, accuracy: 0.1)
        XCTAssertEqual(vehicleFuel.count, 2)
        XCTAssertEqual(vehicleFuel[0].cost, 60, accuracy: 0.1)
        XCTAssertEqual(vehicleFuel[1].cost, 40, accuracy: 0.1)
    }

    func testCostPerKmAndAverageCostPerTrip() {
        let stats = TripStats(
            tripCount: 2,
            totalDistanceMeters: 10_000,
            totalDuration: 3600,
            averageDuration: 1800,
            estimatedFuelCost: 100
        )

        XCTAssertEqual(stats.costPerKm, 10, accuracy: 0.01)
        XCTAssertEqual(stats.averageCostPerTrip, 50, accuracy: 0.01)

        let empty = TripStats(
            tripCount: 0,
            totalDistanceMeters: 0,
            totalDuration: 0,
            averageDuration: 0,
            estimatedFuelCost: 0
        )
        XCTAssertEqual(empty.costPerKm, 0, accuracy: 0.001)
        XCTAssertEqual(empty.averageCostPerTrip, 0, accuracy: 0.001)
        XCTAssertEqual(empty.costPerKmText, "—")
        XCTAssertEqual(empty.averageCostPerTripText, "—")
    }

    func testStatsAggregatesDynamicFuelCost() {
        let first = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 5_000,
            estimatedFuelCost: 50,
            dynamicFuelCost: 60
        )
        let second = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 4_000,
            estimatedFuelCost: 40,
            dynamicFuelCost: 40
        )

        let stats = StatsViewModel.stats(for: [first, second])

        XCTAssertEqual(stats.estimatedFuelCost, 90, accuracy: 0.1)
        XCTAssertEqual(stats.dynamicFuelCost, 100, accuracy: 0.1)
    }

    func testDynamicCostPerKmAndPerTrip() {
        let stats = TripStats(
            tripCount: 2,
            totalDistanceMeters: 10_000,
            totalDuration: 3600,
            averageDuration: 1800,
            estimatedFuelCost: 80,
            dynamicFuelCost: 100
        )

        XCTAssertEqual(stats.dynamicCostPerKm, 10, accuracy: 0.01)
        XCTAssertEqual(stats.dynamicCostPerTrip, 50, accuracy: 0.01)

        let empty = TripStats(
            tripCount: 0,
            totalDistanceMeters: 0,
            totalDuration: 0,
            averageDuration: 0,
            estimatedFuelCost: 0,
            dynamicFuelCost: 0
        )
        XCTAssertEqual(empty.dynamicCostPerKm, 0, accuracy: 0.001)
        XCTAssertEqual(empty.dynamicCostPerTrip, 0, accuracy: 0.001)
        XCTAssertEqual(empty.dynamicCostPerKmText, "—")
        XCTAssertEqual(empty.dynamicCostPerTripText, "—")
    }

    func testCategoryBreakdownSortsByDistance() {
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 8000,
            category: .business
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal
        )
        let categories = [
            UserCategory(id: BuiltInCategory.businessID, name: "Business", sortOrder: 0),
            UserCategory(id: BuiltInCategory.personalID, name: "Personal", sortOrder: 1)
        ]

        let breakdown = StatsViewModel.categoryBreakdown(for: [business, personal], categories: categories)

        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown[0].id, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(breakdown[0].distanceMeters, 8000, accuracy: 0.1)
    }

    func testCategoryDurationBreakdownSortsByDuration() {
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 8000,
            category: .business
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal
        )
        let categories = [
            UserCategory(id: BuiltInCategory.businessID, name: "Business", sortOrder: 0),
            UserCategory(id: BuiltInCategory.personalID, name: "Personal", sortOrder: 1)
        ]

        let breakdown = StatsViewModel.categoryDurationBreakdown(for: [business, personal], categories: categories)

        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown[0].id, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(breakdown[0].duration, 3600, accuracy: 0.1)
        XCTAssertEqual(breakdown[1].duration, 1800, accuracy: 0.1)
    }

    func testTrendTextWhenPreviousIsZero() {
        XCTAssertEqual(StatsViewModel.trendText(current: 10, previous: 0), L10n.string("stats.trend.new"))
        XCTAssertNil(StatsViewModel.trendText(current: 0, previous: 0))
    }

    func testTrendPercentCalculation() {
        XCTAssertEqual(StatsViewModel.trendPercent(current: 150, previous: 100)!, 50, accuracy: 0.1)
        XCTAssertEqual(StatsViewModel.trendPercent(current: 0, previous: 100)!, -100, accuracy: 0.1)
        XCTAssertNil(StatsViewModel.trendPercent(current: 10, previous: 0))
    }

    func testAlignedPreviousIntervalSlicesInProgressMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 15))!
        let selected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let selectedInterval = StatsViewModel.calendarMonthInterval(containing: selected, calendar: calendar)
        let previous = StatsViewModel.alignedPreviousInterval(
            for: .month,
            selectedInterval: selectedInterval,
            selectedMonth: selected,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.month, from: previous.start), 8)
        XCTAssertEqual(calendar.component(.day, from: previous.start), 1)
        XCTAssertEqual(calendar.component(.month, from: previous.end), 8)
        XCTAssertEqual(calendar.component(.day, from: previous.end), 5)
        let fullPrevious = StatsViewModel.previousMonthInterval(containing: selected, calendar: calendar)
        XCTAssertEqual(fullPrevious.start, previous.start)
        XCTAssertLessThan(previous.end, fullPrevious.end)
        XCTAssertTrue(
            StatsViewModel.usesMonthToDatePrevious(
                for: .month,
                selectedMonth: selected,
                now: now,
                calendar: calendar
            )
        )
    }

    func testAlignedPreviousIntervalKeepsFullPastMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let selectedInterval = StatsViewModel.calendarMonthInterval(containing: june, calendar: calendar)
        let previous = StatsViewModel.alignedPreviousInterval(
            for: .month,
            selectedInterval: selectedInterval,
            selectedMonth: june,
            now: now,
            calendar: calendar
        )
        let expected = StatsViewModel.previousMonthInterval(containing: june, calendar: calendar)
        XCTAssertEqual(previous.start, expected.start)
        XCTAssertEqual(previous.end, expected.end)
        XCTAssertFalse(
            StatsViewModel.usesMonthToDatePrevious(
                for: .month,
                selectedMonth: june,
                now: now,
                calendar: calendar
            )
        )
    }

    func testHidesUnscopedCostComparisonForTripOnlyFilters() {
        XCTAssertFalse(
            StatsViewModel.hidesUnscopedCostComparison(
                categoryID: nil,
                placeName: nil,
                journalID: nil
            )
        )
        XCTAssertTrue(
            StatsViewModel.hidesUnscopedCostComparison(
                categoryID: BuiltInCategory.personalID.uuidString,
                placeName: nil,
                journalID: nil
            )
        )
        XCTAssertTrue(
            StatsViewModel.hidesUnscopedCostComparison(
                categoryID: nil,
                placeName: "Home",
                journalID: nil
            )
        )
        XCTAssertTrue(
            StatsViewModel.hidesUnscopedCostComparison(
                categoryID: nil,
                placeName: nil,
                journalID: UUID()
            )
        )
        XCTAssertEqual(
            StatsViewModel.periodCompareMetricIDs(includeExpenses: true),
            ["trips", "distance", "duration", "expenses", "fuel"]
        )
        XCTAssertEqual(
            StatsViewModel.periodCompareMetricIDs(includeExpenses: false),
            ["trips", "distance", "duration", "fuel"]
        )
        XCTAssertTrue(
            StatsViewModel.showsVehicleCompareList(
                hidesUnscopedCosts: false,
                selectedVehicleID: nil,
                rowCount: 2
            )
        )
        XCTAssertFalse(
            StatsViewModel.showsVehicleCompareList(
                hidesUnscopedCosts: true,
                selectedVehicleID: nil,
                rowCount: 3
            )
        )
        XCTAssertFalse(
            StatsViewModel.showsVehicleCompareList(
                hidesUnscopedCosts: false,
                selectedVehicleID: UUID(),
                rowCount: 3
            )
        )
    }

    func testSelectableYearsSpansFirstTripToNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!
        let earliest = calendar.date(from: DateComponents(year: 2024, month: 11, day: 2))!
        XCTAssertEqual(
            StatsViewModel.selectableYears(earliestTripStart: earliest, now: now, calendar: calendar),
            [2026, 2025, 2024]
        )
    }

    func testCustomIntervalUsesOrderedBounds() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 5_000)
        let interval = StatsViewModel.interval(for: .custom, customStart: end, customEnd: start)

        XCTAssertEqual(interval.start, start)
        XCTAssertEqual(interval.end, end)
    }

    func testMonthIntervalUsesCalendarMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
        let interval = StatsViewModel.calendarMonthInterval(containing: selected, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: interval.start), 1)
        XCTAssertEqual(calendar.component(.month, from: interval.start), 6)
        XCTAssertEqual(calendar.component(.month, from: interval.end), 7)
        XCTAssertEqual(calendar.component(.day, from: interval.end), 1)
    }

    func testWeekIntervalSpansSevenCalendarDaysIncludingToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 13, minute: 10))!
        let interval = StatsViewModel.interval(
            for: .week,
            customStart: now,
            customEnd: now,
            now: now,
            calendar: calendar
        )
        let expectedStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        XCTAssertEqual(calendar.startOfDay(for: interval.start), expectedStart)
        XCTAssertEqual(interval.end, now)
        XCTAssertEqual(StatsViewModel.calendarDays(in: interval, calendar: calendar).count, 7)

        let previous = StatsViewModel.alignedPreviousInterval(
            for: .week,
            selectedInterval: interval,
            selectedMonth: now,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(StatsViewModel.calendarDays(in: previous, calendar: calendar).count, 7)
        XCTAssertEqual(calendar.startOfDay(for: previous.start), calendar.date(from: DateComponents(year: 2026, month: 9, day: 7)))
        XCTAssertEqual(calendar.startOfDay(for: previous.end), expectedStart)
    }

    func testCalendarDaysExcludesExclusiveMidnightEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
        let interval = StatsViewModel.calendarMonthInterval(containing: june, calendar: calendar)
        XCTAssertEqual(StatsViewModel.calendarDays(in: interval, calendar: calendar).count, 30)
        XCTAssertEqual(StatsViewModel.calendarDayCount(in: interval, calendar: calendar), 30)
    }

    func testDrivingDayCountStaysInsidePeriodDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 13))!
        let interval = DateInterval(start: start, end: now)
        let outside = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 22))!
        let inside = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10))!
        let overnight = Trip(
            startedAt: outside,
            endedAt: start.addingTimeInterval(3600),
            distanceMeters: 4_000
        )
        let inRange = Trip(
            startedAt: inside,
            endedAt: inside.addingTimeInterval(1800),
            distanceMeters: 2_000
        )
        XCTAssertEqual(
            StatsViewModel.drivingDayCount(in: interval, from: [overnight, inRange], calendar: calendar),
            1
        )
    }

    func testSelectableMonthsSpansFirstTripToNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let earliest = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let months = StatsViewModel.selectableMonths(
            earliestTripStart: earliest,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(months.count, 3)
        XCTAssertEqual(calendar.component(.month, from: months[0]), 7)
        XCTAssertEqual(calendar.component(.month, from: months[1]), 6)
        XCTAssertEqual(calendar.component(.month, from: months[2]), 5)
    }

    func testSelectableMonthsWithoutTripsIsCurrentMonthOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let months = StatsViewModel.selectableMonths(
            earliestTripStart: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(months.count, 1)
        XCTAssertEqual(calendar.component(.month, from: months[0]), 7)
    }

    func testClampedMonthDeduplicatesToSelectableStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let earliest = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let midJune = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 15))!
        let clamped = StatsViewModel.clampedMonth(
            midJune,
            earliestTripStart: earliest,
            now: now,
            calendar: calendar
        )
        let juneStart = StatsViewModel.calendarMonthInterval(containing: midJune, calendar: calendar).start

        XCTAssertEqual(clamped, juneStart)
    }

    func testAverageDistanceAndMovingDuration() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 10_000
        )
        trip.stopDurationSeconds = 600

        let stats = StatsViewModel.stats(for: [trip])

        XCTAssertEqual(stats.averageDistanceMeters, 10_000, accuracy: 0.1)
        XCTAssertEqual(stats.movingDuration, 3000, accuracy: 0.1)
        XCTAssertEqual(stats.stopDuration, 600, accuracy: 0.1)
    }

    func testNightDrivingTotalsFromStoredShare() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 8_000
        )
        trip.nightDistanceMeters = 2_000
        trip.trackedDistanceMeters = 8_000

        let stats = StatsViewModel.stats(for: [trip])

        XCTAssertEqual(stats.nightDistanceMeters, 2_000, accuracy: 0.1)
        XCTAssertEqual(stats.trackedDistanceMeters, 8_000, accuracy: 0.1)
        XCTAssertEqual(stats.daytimeDistanceMeters, 6_000, accuracy: 0.1)
        XCTAssertEqual(stats.nightDrivingRatio, 0.25, accuracy: 0.001)
    }

    func testFuelFactorSharesRankByVolumeAndSkipMixedUnits() {
        let petrol = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5_000
        )
        petrol.fuelIdleVolume = 0.40
        petrol.fuelColdStartVolume = 0.10
        petrol.fuelTransientVolume = 0.20
        petrol.fuelSpeedDeltaVolume = 0.05
        petrol.dynamicFuelVolume = 1.2

        let stats = StatsViewModel.stats(for: [petrol])
        XCTAssertEqual(stats.fuelFactorShares.map(\.kind), [
            .idleTraffic, .transientAcceleration, .coldStart, .highSpeed
        ])
        XCTAssertEqual(stats.topFuelFactors, [.idleTraffic, .transientAcceleration, .coldStart])

        let electric = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 4_000
        )
        electric.fuelTypeSnapshot = .electric
        electric.fuelIdleVolume = 0.30
        electric.dynamicFuelVolume = 2.0

        let mixed = StatsViewModel.stats(for: [petrol, electric])
        XCTAssertTrue(mixed.hasMixedFuelUnits)
        XCTAssertTrue(mixed.fuelFactorShares.isEmpty)
        XCTAssertTrue(mixed.topFuelFactors.isEmpty)
    }

    func testDailyTripCountsAndNightDistanceBucketByDay() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: now)

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 4_000
        )
        todayTrip.nightDistanceMeters = 1_000
        todayTrip.trackedDistanceMeters = 4_000

        let yesterdayOne = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(5400),
            distanceMeters: 2_000
        )
        yesterdayOne.nightDistanceMeters = 0
        yesterdayOne.trackedDistanceMeters = 2_000

        let yesterdayTwo = Trip(
            startedAt: yesterday.addingTimeInterval(8000),
            endedAt: yesterday.addingTimeInterval(9000),
            distanceMeters: 1_000
        )
        yesterdayTwo.nightDistanceMeters = 500
        yesterdayTwo.trackedDistanceMeters = 1_000

        let trips = [todayTrip, yesterdayOne, yesterdayTwo]
        let counts = StatsViewModel.dailyTripCounts(in: interval, from: trips)
        let nights = StatsViewModel.dailyNightDistances(in: interval, from: trips)

        XCTAssertEqual(counts.first?.count, 2)
        XCTAssertEqual(counts.last?.count, 1)
        XCTAssertEqual(nights.first?.distanceMeters ?? 0, 500, accuracy: 0.1)
        XCTAssertEqual(nights.last?.distanceMeters ?? 0, 1_000, accuracy: 0.1)
    }

    func testWeekdayDistancesFollowFirstWeekdayOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 10))!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10))!

        let commute = Trip(
            startedAt: monday,
            endedAt: monday.addingTimeInterval(1800),
            distanceMeters: 12_000
        )
        let weekend = Trip(
            startedAt: saturday,
            endedAt: saturday.addingTimeInterval(3600),
            distanceMeters: 3_000
        )

        let distances = StatsViewModel.weekdayDistances(from: [commute, weekend], calendar: calendar)
        XCTAssertEqual(distances.count, 7)
        XCTAssertEqual(distances.map(\.weekday), [2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(distances.first?.distanceMeters ?? 0, 12_000, accuracy: 0.1)
        XCTAssertEqual(distances[5].distanceMeters, 3_000, accuracy: 0.1)
        XCTAssertEqual(StatsViewModel.drivingDayCount(
            in: DateInterval(start: monday, end: saturday.addingTimeInterval(4000)),
            from: [commute, weekend],
            calendar: calendar
        ), 2)
    }

    func testBusiestDayPicksThePeakAndIgnoresZeros() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let daily = [
            DailyDistance(id: yesterday, day: yesterday, distanceMeters: 1_000),
            DailyDistance(id: today, day: today, distanceMeters: 9_000)
        ]
        let peak = StatsViewModel.busiestDay(from: daily)
        XCTAssertEqual(peak?.day, today)
        XCTAssertEqual(peak?.meters ?? 0, 9_000, accuracy: 0.1)
        XCTAssertNil(StatsViewModel.busiestDay(from: [
            DailyDistance(id: today, day: today, distanceMeters: 0)
        ]))
    }
}
