import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class StatsYearAwardsLoaderTests: XCTestCase {
    func testBuildsFromRollupsAndExpensesWithoutTrips() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 12))!
        let otherDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!
        let vehicle = VehicleProfile(name: "Year Car")
        context.insert(vehicle)

        let busy = TripDailyRollup(
            dayStart: calendar.startOfDay(for: day),
            categoryID: BuiltInCategory.personalID.uuidString,
            vehicleKey: vehicle.id.uuidString
        )
        busy.distanceMeters = 80_000
        busy.nightDistanceMeters = 20_000
        busy.trackedDistanceMeters = 80_000
        busy.tripCount = 2
        context.insert(busy)

        let quiet = TripDailyRollup(
            dayStart: calendar.startOfDay(for: otherDay),
            categoryID: BuiltInCategory.personalID.uuidString,
            vehicleKey: vehicle.id.uuidString
        )
        quiet.distanceMeters = 10_000
        quiet.nightDistanceMeters = 0
        quiet.trackedDistanceMeters = 10_000
        quiet.tripCount = 1
        context.insert(quiet)

        context.insert(VehicleExpense(
            category: .fuel,
            amount: 400,
            occurredAt: day,
            vehicle: vehicle
        ))
        let marchStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        context.insert(VehicleExpense(
            category: .service,
            amount: 900,
            occurredAt: marchStart.addingTimeInterval(5 * 86_400),
            vehicle: vehicle
        ))
        try context.save()

        let trips = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertTrue(trips.isEmpty, "year awards must not require Trip rows")

        let loader = StatsYearAwardsLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: StatsYearAwardsRequest(storeVersion: 1, year: 2026)
        )

        XCTAssertEqual(snap.totalDistanceMeters, 90_000, accuracy: 0.1)
        XCTAssertEqual(snap.nightRatio, 20_000 / 90_000, accuracy: 0.001)
        XCTAssertEqual(snap.busiestDayMeters, 80_000, accuracy: 0.1)
        XCTAssertEqual(calendar.component(.day, from: snap.busiestDay ?? .distantPast), 12)
        XCTAssertEqual(snap.mostExpensiveVehicleAmount, 1_300, accuracy: 0.01)
        XCTAssertEqual(snap.mostExpensiveVehicleName, "Year Car")
        XCTAssertEqual(snap.mostExpensiveMonthAmount, 1_300, accuracy: 0.01)
        XCTAssertEqual(snap.monthlyDistances.count, 1)
    }

    func testIgnoresOtherYears() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 12))!
        let rollup = TripDailyRollup(
            dayStart: lastYear,
            categoryID: BuiltInCategory.personalID.uuidString,
            vehicleKey: ""
        )
        rollup.distanceMeters = 50_000
        rollup.trackedDistanceMeters = 50_000
        context.insert(rollup)
        try context.save()

        let loader = StatsYearAwardsLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: StatsYearAwardsRequest(storeVersion: 1, year: 2026)
        )
        XCTAssertEqual(snap.totalDistanceMeters, 0, accuracy: 0.1)
        XCTAssertFalse(snap.hasData)
    }

    func testPresenterUnlocksDistanceNightGoalAndBusiestDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let snapshot = StatsYearAwardsSnapshot(
            year: 2026,
            totalDistanceMeters: 5_500_000,
            nightRatio: 0.25,
            busiestDay: march,
            busiestDayMeters: 200_000,
            monthlyDistances: [
                StatsYearMonthlyDistance(monthStart: march, distanceMeters: 600_000)
            ],
            mostExpensiveVehicleName: "Alpha",
            mostExpensiveVehicleAmount: 80,
            mostExpensiveMonthStart: march,
            mostExpensiveMonthAmount: 80
        )
        let medals = StatsYearAwardsPresenter.medals(
            from: snapshot,
            goalMetersForMonth: { _ in 500_000 },
            currencyCode: "TRY"
        )
        XCTAssertEqual(medals.count, 6)
        XCTAssertTrue(medals.first { $0.kind == .distance }?.isUnlocked ?? false)
        XCTAssertTrue(medals.first { $0.kind == .nightOwl }?.isUnlocked ?? false)
        XCTAssertTrue(medals.first { $0.kind == .goal }?.isUnlocked ?? false)
        XCTAssertTrue(medals.first { $0.kind == .busiestDay }?.isUnlocked ?? false)
        XCTAssertTrue(medals.first { $0.kind == .expensiveVehicle }?.isUnlocked ?? false)
        XCTAssertTrue(medals.first { $0.kind == .expensiveMonth }?.isUnlocked ?? false)
    }

    func testAwardsTotalsStayTheSameWhenCategoryIsHgsParkingOrMtv() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 12))!
        let vehicle = VehicleProfile(name: "Toll Awards")
        context.insert(vehicle)
        context.insert(VehicleExpense(category: .fuel, amount: 100, occurredAt: day, vehicle: vehicle))
        context.insert(VehicleExpense(category: .hgs, amount: 20, occurredAt: day.addingTimeInterval(60), vehicle: vehicle))
        context.insert(VehicleExpense(category: .parking, amount: 30, occurredAt: day.addingTimeInterval(120), vehicle: vehicle))
        context.insert(VehicleExpense(category: .mtv, amount: 50, occurredAt: day.addingTimeInterval(180), vehicle: vehicle))
        try context.save()

        let loader = StatsYearAwardsLoader(modelContainer: container)
        let snap = await loader.snapshot(for: StatsYearAwardsRequest(storeVersion: 1, year: 2026))
        XCTAssertEqual(snap.mostExpensiveVehicleAmount, 200, accuracy: 0.01)
        XCTAssertEqual(snap.mostExpensiveMonthAmount, 200, accuracy: 0.01)
        XCTAssertEqual(snap.mostExpensiveVehicleName, "Toll Awards")
    }
}

@MainActor
final class VehicleCostCompareSnapshotTests: XCTestCase {
    func testPreviousTotalUsesCompareWindowNotCurrentMonth() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "MoM Car")
        context.insert(vehicle)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let previousStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let compareEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        context.insert(VehicleExpense(
            category: .fuel,
            amount: 100,
            occurredAt: currentStart.addingTimeInterval(86_400),
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .fuel,
            amount: 40,
            occurredAt: previousStart.addingTimeInterval(86_400),
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .fuel,
            amount: 999,
            occurredAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!,
            vehicle: vehicle
        ))
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: currentStart,
                periodEnd: periodEnd,
                selectedVehicleID: nil,
                compareStart: previousStart,
                compareEnd: compareEnd
            )
        )

        XCTAssertEqual(snap.total, 100, accuracy: 0.01)
        XCTAssertEqual(snap.previousTotal, 40, accuracy: 0.01)
        XCTAssertEqual(snap.compareSeeds.count, 1)
        XCTAssertEqual(snap.compareSeeds.first?.amount ?? 0, 100, accuracy: 0.01)
    }

    func testCompareSeedsSplitFuelAndServiceBuckets() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Bucket Car")
        context.insert(vehicle)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        context.insert(VehicleExpense(
            category: .fuel,
            amount: 80,
            occurredAt: periodStart.addingTimeInterval(86_400),
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .service,
            amount: 120,
            occurredAt: periodStart.addingTimeInterval(2 * 86_400),
            vehicle: vehicle
        ))
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: periodStart,
                periodEnd: periodEnd,
                selectedVehicleID: nil
            )
        )

        let seed = try XCTUnwrap(snap.compareSeeds.first)
        XCTAssertEqual(seed.fuel, 80, accuracy: 0.01)
        XCTAssertEqual(seed.service, 120, accuracy: 0.01)
        XCTAssertEqual(seed.amount, 200, accuracy: 0.01)
        XCTAssertEqual(snap.fuelTotal, 80, accuracy: 0.01)
        XCTAssertEqual(snap.serviceTotal, 120, accuracy: 0.01)
    }

    func testCurrentWindowIsHalfOpenAtPeriodEnd() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Boundary Car")
        context.insert(vehicle)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        context.insert(VehicleExpense(
            category: .fuel,
            amount: 50,
            occurredAt: periodStart,
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .fuel,
            amount: 999,
            occurredAt: periodEnd,
            vehicle: vehicle
        ))
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: periodStart,
                periodEnd: periodEnd,
                selectedVehicleID: nil
            )
        )

        XCTAssertEqual(snap.total, 50, accuracy: 0.01)
        XCTAssertEqual(snap.fuelTotal, 50, accuracy: 0.01)
    }
}
