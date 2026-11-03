import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class VehicleCostSnapshotLoaderTests: XCTestCase {
    func testAggregatesOnlyManualExpensesIgnoreTripFuel() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Cost Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!

        context.insert(VehicleExpense(
            category: .fuel,
            amount: 100,
            occurredAt: monthStart.addingTimeInterval(86400),
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .service,
            amount: 200,
            occurredAt: monthStart.addingTimeInterval(86400 * 2),
            vehicle: vehicle
        ))

        let trip = Trip(
            startedAt: monthStart.addingTimeInterval(86400 * 3),
            endedAt: monthStart.addingTimeInterval(86400 * 3 + 3600),
            distanceMeters: 50_000,
            estimatedFuelCost: 999,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(trip)
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: monthStart,
                periodEnd: end,
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertEqual(snap.fuelTotal, 100, accuracy: 0.01)
        XCTAssertEqual(snap.serviceTotal, 200, accuracy: 0.01)
        XCTAssertEqual(snap.total, 300, accuracy: 0.01)
        XCTAssertEqual(snap.days.count, 2)
        XCTAssertEqual(snap.days.first?.amount(for: VehicleExpenseCategory.fuel) ?? 0, 100, accuracy: 0.01)
        XCTAssertFalse(snap.categoryBreakdown.contains(where: \.isTripEstimate))
    }

    func testKeepsAccessoryDistinctFromOtherOnDailyBars() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Accessory Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        context.insert(VehicleExpense(
            category: .fuel,
            amount: 100,
            occurredAt: day,
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .accessory,
            amount: 250,
            occurredAt: day.addingTimeInterval(3600),
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .other,
            amount: 50,
            occurredAt: day.addingTimeInterval(7200),
            vehicle: vehicle
        ))
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: day,
                periodEnd: day.addingTimeInterval(86_400),
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertEqual(snap.days.count, 1)
        let dayCost = try XCTUnwrap(snap.days.first)
        XCTAssertEqual(dayCost.amount(for: VehicleExpenseCategory.fuel), 100, accuracy: 0.01)
        XCTAssertEqual(dayCost.amount(for: VehicleExpenseCategory.accessory), 250, accuracy: 0.01)
        XCTAssertEqual(dayCost.amount(for: VehicleExpenseCategory.other), 50, accuracy: 0.01)
        XCTAssertEqual(
            snap.categoryBreakdown.map(\.id).sorted(),
            ["accessory", "fuel", "other"]
        )
    }

    func testTripFuelAloneDoesNotCreateVehicleCostBars() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Trip Fuel Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let trip = Trip(
            startedAt: monthStart.addingTimeInterval(86400),
            endedAt: monthStart.addingTimeInterval(86400 + 1800),
            distanceMeters: 20_000,
            estimatedFuelCost: 75,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(trip)
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: monthStart,
                periodEnd: end,
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertEqual(snap.fuelTotal, 0, accuracy: 0.01)
        XCTAssertEqual(snap.total, 0, accuracy: 0.01)
        XCTAssertFalse(snap.hasData)
    }

    func testCategoryBreakdownGroupsManualExpensesOnly() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Breakdown Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let monthStart = calendar.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!

        context.insert(VehicleExpense(
            category: .service,
            amount: 150,
            occurredAt: monthStart.addingTimeInterval(86400),
            vehicle: vehicle
        ))
        context.insert(VehicleExpense(
            category: .casco,
            amount: 250,
            occurredAt: monthStart.addingTimeInterval(86400 * 2),
            vehicle: vehicle
        ))

        let trip = Trip(
            startedAt: monthStart.addingTimeInterval(86400 * 3),
            endedAt: monthStart.addingTimeInterval(86400 * 3 + 1800),
            distanceMeters: 20_000,
            estimatedFuelCost: 80,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(trip)
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: monthStart,
                periodEnd: end,
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertTrue(snap.hasCategoryBreakdown)
        XCTAssertEqual(snap.categoryBreakdown.count, 2)
        let serviceAmount = snap.categoryBreakdown.first(where: { $0.category == .service })?.amount
        let cascoAmount = snap.categoryBreakdown.first(where: { $0.category == .casco })?.amount
        XCTAssertEqual(serviceAmount ?? 0, 150, accuracy: 0.01)
        XCTAssertEqual(cascoAmount ?? 0, 250, accuracy: 0.01)
        XCTAssertNil(snap.categoryBreakdown.first(where: \.isTripEstimate))
    }

    func testAllVehiclesSumWhenNoVehicleFilter() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = VehicleProfile(name: "One")
        let second = VehicleProfile(name: "Two")
        context.insert(first)
        context.insert(second)

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        context.insert(VehicleExpense(
            category: .fuel,
            amount: 100,
            occurredAt: monthStart.addingTimeInterval(86400),
            vehicle: first
        ))
        context.insert(VehicleExpense(
            category: .fuel,
            amount: 50,
            occurredAt: monthStart.addingTimeInterval(86400 * 2),
            vehicle: second
        ))
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: monthStart,
                periodEnd: end,
                selectedVehicleID: nil
            )
        )

        XCTAssertEqual(snap.total, 150, accuracy: 0.01)
        XCTAssertEqual(snap.days.count, 2)
        XCTAssertEqual(snap.vehicleBreakdown.count, 2)
        XCTAssertEqual(
            snap.vehicleBreakdown.first(where: { $0.id == first.id.uuidString })?.amount ?? 0,
            100,
            accuracy: 0.01
        )
        XCTAssertEqual(
            snap.vehicleBreakdown.first(where: { $0.id == second.id.uuidString })?.amount ?? 0,
            50,
            accuracy: 0.01
        )
    }

    func testHgsParkingMtvStayDistinctFromOtherAndStayInOtherBucket() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Toll Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        context.insert(VehicleExpense(category: .fuel, amount: 100, occurredAt: day, vehicle: vehicle))
        context.insert(VehicleExpense(category: .hgs, amount: 40, occurredAt: day.addingTimeInterval(3600), vehicle: vehicle))
        context.insert(VehicleExpense(category: .parking, amount: 25, occurredAt: day.addingTimeInterval(7200), vehicle: vehicle))
        context.insert(VehicleExpense(category: .mtv, amount: 80, occurredAt: day.addingTimeInterval(10_800), vehicle: vehicle))
        context.insert(VehicleExpense(category: .other, amount: 15, occurredAt: day.addingTimeInterval(14_400), vehicle: vehicle))
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: day,
                periodEnd: day.addingTimeInterval(86_400),
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertEqual(snap.total, 260, accuracy: 0.01)
        XCTAssertEqual(snap.fuelTotal, 100, accuracy: 0.01)
        XCTAssertEqual(snap.otherTotal, 160, accuracy: 0.01)
        XCTAssertEqual(
            snap.categoryBreakdown.map(\.id).sorted(),
            ["fuel", "hgs", "mtv", "other", "parking"]
        )
        XCTAssertEqual(snap.categoryBreakdown.first(where: { $0.id == "hgs" })?.amount ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(snap.categoryBreakdown.first(where: { $0.id == "parking" })?.amount ?? 0, 25, accuracy: 0.01)
        XCTAssertEqual(snap.categoryBreakdown.first(where: { $0.id == "mtv" })?.amount ?? 0, 80, accuracy: 0.01)
        XCTAssertEqual(snap.categoryBreakdown.first(where: { $0.id == "other" })?.amount ?? 0, 15, accuracy: 0.01)
    }

    func testLegacyTaxAndParkingRawStayInOtherBucketWithoutChangingFuelTotal() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Legacy Tax Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        context.insert(VehicleExpense(category: .fuel, amount: 90, occurredAt: day, vehicle: vehicle))
        let tax = VehicleExpense(category: .other, amount: 70, occurredAt: day.addingTimeInterval(3600), vehicle: vehicle)
        tax.categoryRaw = "tax"
        context.insert(tax)
        let parking = VehicleExpense(category: .other, amount: 30, occurredAt: day.addingTimeInterval(7200), vehicle: vehicle)
        parking.categoryRaw = "parking"
        context.insert(parking)
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: day,
                periodEnd: day.addingTimeInterval(86_400),
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertEqual(tax.categoryRaw, "tax")
        XCTAssertEqual(parking.categoryRaw, "parking")
        XCTAssertEqual(snap.total, 190, accuracy: 0.01)
        XCTAssertEqual(snap.fuelTotal, 90, accuracy: 0.01)
        XCTAssertEqual(snap.otherTotal, 100, accuracy: 0.01)
        XCTAssertEqual(
            snap.categoryBreakdown.map(\.id).sorted(),
            ["fuel", "mtv", "parking"]
        )
        XCTAssertFalse(snap.categoryBreakdown.contains { $0.id == "other" })
    }

    func testEightCurrentRawValuesKeepExistingSliceIdsAndBucketTotals() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Eight Car")
        context.insert(vehicle)

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let rows: [(VehicleExpenseCategory, Double)] = [
            (.fuel, 10),
            (.trafficInsurance, 20),
            (.casco, 30),
            (.service, 40),
            (.inspection, 50),
            (.repair, 60),
            (.accessory, 70),
            (.other, 80)
        ]
        for (index, row) in rows.enumerated() {
            context.insert(VehicleExpense(
                category: row.0,
                amount: row.1,
                occurredAt: day.addingTimeInterval(Double(index) * 60),
                vehicle: vehicle
            ))
        }
        try context.save()

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let snap = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: day,
                periodEnd: day.addingTimeInterval(86_400),
                selectedVehicleID: vehicle.id
            )
        )

        XCTAssertEqual(
            snap.categoryBreakdown.map(\.id).sorted(),
            ["accessory", "casco", "fuel", "inspection", "other", "repair", "service", "trafficInsurance"]
        )
        XCTAssertEqual(snap.fuelTotal, 10, accuracy: 0.01)
        XCTAssertEqual(snap.serviceTotal, 100, accuracy: 0.01)
        XCTAssertEqual(snap.insuranceTotal, 20, accuracy: 0.01)
        XCTAssertEqual(snap.cascoTotal, 30, accuracy: 0.01)
        XCTAssertEqual(snap.otherTotal, 200, accuracy: 0.01)
        XCTAssertEqual(snap.total, 360, accuracy: 0.01)
        XCTAssertFalse(snap.categoryBreakdown.contains { $0.id == "hgs" })
        XCTAssertFalse(snap.categoryBreakdown.contains { $0.id == "parking" })
        XCTAssertFalse(snap.categoryBreakdown.contains { $0.id == "mtv" })
    }
}
