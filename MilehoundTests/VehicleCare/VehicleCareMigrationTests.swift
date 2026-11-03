import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class VehicleCareMigrationTests: XCTestCase {
    func testV13SupportsSchedulesAndExpenses() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV13.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Test Car", consumption: 7.0)
        context.insert(vehicle)

        let schedule = VehicleSchedule(
            kind: .service,
            nextDueDate: Date().addingTimeInterval(86400 * 14),
            intervalKind: .everyMonths,
            intervalMonths: 12,
            vehicle: vehicle
        )
        context.insert(schedule)

        let expense = VehicleExpense(
            category: .fuel,
            amount: 500,
            vehicle: vehicle
        )
        context.insert(expense)
        try context.save()

        let trips = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 0)

        let schedules = try context.fetch(FetchDescriptor<VehicleSchedule>())
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.kind, .service)

        let expenses = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.amount, 500)
    }

    func testInMemoryFactoryIncludesCareModels() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Factory Car")
        context.insert(vehicle)
        let schedule = VehicleSchedule(kind: .casco, nextDueDate: Date(), vehicle: vehicle)
        context.insert(schedule)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleSchedule>()).count, 1)
        XCTAssertEqual(ModelContainerFactory.currentSchemaVersion, 24)
    }

    func testTripDataSurvivesAlongsideCareModels() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Keeper")
        context.insert(vehicle)
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 12_500,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(trip)
        try context.save()

        context.insert(VehicleExpense(category: .service, amount: 2500, vehicle: vehicle))
        try context.save()

        let trips = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.distanceMeters, 12_500)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleExpense>()).count, 1)
    }

    func testInMemoryFactoryIncludesFuelCalibration() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicleID = UUID()
        context.insert(VehicleFuelCalibration(vehicleID: vehicleID))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleFuelCalibration>()).count, 1)
        XCTAssertEqual(ModelContainerFactory.currentSchemaVersion, 24)
    }

    func testSuccessorRecomputeUsesPreviousTripSoak() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Soak Car", consumption: 7.5)
        context.insert(vehicle)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            distanceMeters: 12_000,
            fuelConsumptionPer100: 7.5,
            fuelUnitPrice: 65,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(first)
        appendCruisePoints(to: first, start: start, seconds: 1_800, kmh: 40, in: context)
        let secondStart = start.addingTimeInterval(1_800 + 8 * 3_600)
        let second = Trip(
            startedAt: secondStart,
            endedAt: secondStart.addingTimeInterval(180),
            distanceMeters: 2_000,
            fuelConsumptionPer100: 7.5,
            fuelUnitPrice: 65,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(second)
        appendCruisePoints(to: second, start: secondStart, seconds: 180, kmh: 40, in: context)
        try context.save()

        TripDerivedMetrics.recomputeFuel(for: first, vehicle: vehicle)
        TripDerivedMetrics.recomputeFuel(for: second, vehicle: vehicle)
        let coldAfterLongSoak = second.fuelColdStartVolume ?? 0

        first.endedAt = secondStart.addingTimeInterval(-5 * 60)
        try context.save()
        TripFuelDependencyService.invalidateSuccessor(of: first, in: context)
        let coldAfterShortSoak = second.fuelColdStartVolume ?? 0
        XCTAssertGreaterThan(coldAfterLongSoak, 0)
        XCTAssertGreaterThan(coldAfterLongSoak, coldAfterShortSoak)
    }

    private func appendCruisePoints(to trip: Trip, start: Date, seconds: Int, kmh: Double, in context: ModelContext) {
        let speed = kmh / 3.6
        var travelled = 0.0
        for index in 0...seconds {
            if index > 0 { travelled += speed }
            let point = TripPoint(
                timestamp: start.addingTimeInterval(Double(index)),
                latitude: 38.42,
                longitude: 27.14 + travelled / 90_000,
                sequence: index,
                speedMps: speed,
                trip: trip
            )
            trip.points.append(point)
            context.insert(point)
        }
    }

    func testDiskStoreKeepsReceiptFileNameAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptDisk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Milehound.store")
        let schema = Schema(versionedSchema: MilehoundSchemaV23.self)

        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL))
            let context = container.mainContext
            let vehicle = VehicleProfile(name: "Disk Car")
            context.insert(vehicle)
            context.insert(VehicleExpense(category: .fuel, amount: 1_492, vehicle: vehicle, receiptFileName: "r.jpg"))
            context.insert(VehicleExpense(category: .service, amount: 300, vehicle: vehicle))
            try context.save()
        }

        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL))
        let rows = try reopened.mainContext.fetch(FetchDescriptor<VehicleExpense>(sortBy: [SortDescriptor(\.amount)]))
        XCTAssertEqual(rows.map(\.amount), [300, 1_492])
        XCTAssertEqual(rows.map(\.receiptFileName), [nil, "r.jpg"])
    }

    /// Opens a copy of a real pre-receipt (V22) on-disk store with the live V23 schema.
    /// Run with `TEST_RUNNER_MILEHOUND_MIGRATION_STORE=/path/Milehound.store` and
    /// `TEST_RUNNER_MILEHOUND_MIGRATION_EXPECT="<expenses>|<amount sum>|<trips>"`.
    /// The source store is copied first and never opened in place.
    func testRealV22StoreOpensUnderV23WithoutDataLoss() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sourcePath = env["MILEHOUND_MIGRATION_STORE"], !sourcePath.isEmpty else {
            throw XCTSkip("Set MILEHOUND_MIGRATION_STORE to a V22 Milehound.store to run")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V22Migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Milehound.store")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: sourcePath + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: storeURL.path + suffix))
        }

        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV23.self),
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = container.mainContext
        let expenses = try context.fetch(FetchDescriptor<VehicleExpense>())
        let trips = try context.fetchCount(FetchDescriptor<Trip>())
        XCTAssertTrue(expenses.allSatisfy { $0.receiptFileName == nil })

        if let expect = env["MILEHOUND_MIGRATION_EXPECT"]?.split(separator: "|"), expect.count == 3 {
            XCTAssertEqual(expenses.count, Int(expect[0]))
            XCTAssertEqual(expenses.reduce(0) { $0 + $1.amount }, Double(expect[1]) ?? -1, accuracy: 0.01)
            XCTAssertEqual(trips, Int(expect[2]))
        }

        expenses.first?.receiptFileName = "after-migration.jpg"
        try context.save()
        XCTAssertEqual(ExpenseReceiptStore.referenceCount(of: "after-migration.jpg", in: context), expenses.isEmpty ? 0 : 1)
    }

    func testV14KeepsExistingExpensesAsOneShot() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV14.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Legacy Expense")
        context.insert(vehicle)
        context.insert(VehicleExpense(category: .fuel, amount: 90, vehicle: vehicle))
        try context.save()

        let expense = try XCTUnwrap(context.fetch(FetchDescriptor<VehicleExpense>()).first)
        XCTAssertNil(expense.installmentGroupID)
        XCTAssertNil(expense.installmentIndex)
        XCTAssertNil(expense.installmentCount)
        XCTAssertNil(expense.installmentTotalAmount)
        XCTAssertFalse(expense.isInstallment)
        XCTAssertEqual(expense.amount, 90)
    }

    func testDiskStoreKeepsLegacyTaxParkingAndNewHgsRawAcrossV23Reopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExpenseCategoryDisk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Milehound.store")
        let schema = Schema(versionedSchema: MilehoundSchemaV23.self)

        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL))
            let context = container.mainContext
            let vehicle = VehicleProfile(name: "Category Disk")
            context.insert(vehicle)
            let tax = VehicleExpense(category: .other, amount: 70, vehicle: vehicle)
            tax.categoryRaw = "tax"
            context.insert(tax)
            let parking = VehicleExpense(category: .other, amount: 30, vehicle: vehicle)
            parking.categoryRaw = "parking"
            context.insert(parking)
            context.insert(VehicleExpense(category: .hgs, amount: 15, vehicle: vehicle))
            context.insert(VehicleExpense(category: .other, amount: 5, vehicle: vehicle))
            context.insert(VehicleExpense(category: .fuel, amount: 90, vehicle: vehicle))
            try context.save()
        }

        XCTAssertEqual(ModelContainerFactory.currentSchemaVersion, 24)
        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(url: storeURL))
        let rows = try reopened.mainContext.fetch(
            FetchDescriptor<VehicleExpense>(sortBy: [SortDescriptor(\.amount)])
        )
        XCTAssertEqual(rows.map(\.amount), [5, 15, 30, 70, 90])
        XCTAssertEqual(rows.map(\.categoryRaw), ["other", "hgs", "parking", "tax", "fuel"])
        XCTAssertEqual(rows.map(\.category), [.other, .hgs, .parking, .mtv, .fuel])
    }

    func testV23DiskStoreOpensUnderV24AndBackfillsOdometerAnchor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OdometerV24-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Milehound.store")
        let anchorMoment = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: MilehoundSchemaV23.self),
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = container.mainContext
            let vehicle = VehicleProfile(name: "Kept Car", currentOdometerKm: 42_000)
            context.insert(vehicle)
            context.insert(VehicleSchedule(
                kind: .service,
                nextDueDate: anchorMoment,
                intervalKind: .everyMonths,
                intervalMonths: 12,
                vehicle: vehicle
            ))
            context.insert(VehicleExpense(category: .service, amount: 1_800, vehicle: vehicle))
            context.insert(Trip(
                startedAt: anchorMoment,
                endedAt: anchorMoment.addingTimeInterval(600),
                distanceMeters: 12_500,
                vehicleID: vehicle.id,
                vehicle: vehicle
            ))
            try context.save()
        }

        let reopened = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV24.self),
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = reopened.mainContext
        let vehicle = try XCTUnwrap(context.fetch(FetchDescriptor<VehicleProfile>()).first)
        XCTAssertEqual(vehicle.name, "Kept Car")
        XCTAssertEqual(vehicle.currentOdometerKm, 42_000)
        XCTAssertNil(vehicle.odometerAnchorKm)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleSchedule>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleExpense>()).first?.amount, 1_800)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Trip>()).first?.distanceMeters, 12_500)

        VehicleOdometerService.backfillAnchorsIfNeeded(in: context, now: anchorMoment.addingTimeInterval(86_400))
        XCTAssertEqual(vehicle.odometerAnchorKm, 42_000)
        XCTAssertEqual(vehicle.odometerTripMetersSinceAnchor, 0)
        XCTAssertEqual(vehicle.currentOdometerKm, 42_000)
        VehicleOdometerService.backfillAnchorsIfNeeded(in: context, now: Date())
        XCTAssertEqual(vehicle.odometerAnchorAt, anchorMoment.addingTimeInterval(86_400))
    }
}
