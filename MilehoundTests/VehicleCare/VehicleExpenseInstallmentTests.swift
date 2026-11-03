import SwiftData
import XCTest
@testable import Milehound

final class VehicleExpenseInstallmentPlanTests: XCTestCase {
    func testSplitPutsRemainderOnLastInstallment() {
        let amounts = VehicleExpenseInstallmentPlan.splitAmounts(total: 10_000, count: 6)
        XCTAssertEqual(amounts.count, 6)
        XCTAssertEqual(amounts.dropLast(), Array(repeating: 1_666.66, count: 5))
        XCTAssertEqual(amounts.last ?? 0, 1_666.70, accuracy: 0.001)
        XCTAssertEqual(amounts.reduce(0, +), 10_000, accuracy: 0.001)
    }

    func testSplitEvenAmountStaysEven() {
        let amounts = VehicleExpenseInstallmentPlan.splitAmounts(total: 1_200, count: 6)
        XCTAssertEqual(amounts, Array(repeating: 200, count: 6))
    }

    func testSplitTinyRemainderLandsOnLast() {
        let amounts = VehicleExpenseInstallmentPlan.splitAmounts(total: 0.01, count: 3)
        XCTAssertEqual(amounts, [0, 0, 0.01])
    }

    func testDueDatesAdvanceByCalendarMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let slices = VehicleExpenseInstallmentPlan.slices(
            total: 300,
            count: 3,
            start: start,
            calendar: calendar
        )
        XCTAssertEqual(slices.map(\.index), [1, 2, 3])
        XCTAssertEqual(calendar.component(.month, from: slices[0].dueDate), 1)
        XCTAssertEqual(calendar.component(.day, from: slices[0].dueDate), 31)
        XCTAssertEqual(calendar.component(.month, from: slices[1].dueDate), 2)
        XCTAssertEqual(calendar.component(.day, from: slices[1].dueDate), 28)
        XCTAssertEqual(calendar.component(.month, from: slices[2].dueDate), 3)
        XCTAssertEqual(calendar.component(.day, from: slices[2].dueDate), 31)
    }

    func testClampsCount() {
        XCTAssertEqual(VehicleExpenseInstallmentPlan.clampedCount(0), 1)
        XCTAssertEqual(VehicleExpenseInstallmentPlan.clampedCount(36), 24)
    }
}

@MainActor
final class VehicleExpenseInstallmentServiceTests: XCTestCase {
    func testInsertCreatesMonthlySlices() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Installment Car")
        context.insert(vehicle)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!

        let first = try VehicleExpenseInstallmentService.insert(
            category: .accessory,
            totalAmount: 1_200,
            startDate: start,
            installmentCount: 6,
            note: "Tyres",
            vehicle: vehicle,
            in: context
        )

        let rows = try context.fetch(FetchDescriptor<VehicleExpense>())
            .sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(Set(rows.map(\.installmentGroupID)), [first.installmentGroupID])
        XCTAssertEqual(rows.map(\.amount), Array(repeating: 200.0, count: 6))
        XCTAssertEqual(rows.map(\.installmentIndex), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(rows.first?.installmentTotalAmount, 1_200)
        XCTAssertEqual(calendar.component(.month, from: rows[0].occurredAt), 8)
        XCTAssertEqual(calendar.component(.month, from: rows[5].occurredAt), 1)
        XCTAssertEqual(calendar.component(.year, from: rows[5].occurredAt), 2027)
        XCTAssertTrue(rows.allSatisfy(\.isInstallment))
    }

    func testInsertOneShotLeavesInstallmentFieldsNil() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Cash Car")
        context.insert(vehicle)

        let expense = try VehicleExpenseInstallmentService.insert(
            category: .fuel,
            totalAmount: 80,
            startDate: Date(),
            installmentCount: 1,
            note: nil,
            vehicle: vehicle,
            in: context
        )

        XCTAssertNil(expense.installmentGroupID)
        XCTAssertNil(expense.installmentIndex)
        XCTAssertFalse(expense.isInstallment)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleExpense>()).count, 1)
    }

    func testReplaceShrinksAndGrowsPlan() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Resize Car")
        context.insert(vehicle)
        let start = Date()

        let first = try VehicleExpenseInstallmentService.insert(
            category: .casco,
            totalAmount: 1_200,
            startDate: start,
            installmentCount: 6,
            note: nil,
            vehicle: vehicle,
            in: context
        )

        _ = try VehicleExpenseInstallmentService.replace(
            existing: first,
            category: .casco,
            totalAmount: 900,
            startDate: start,
            installmentCount: 3,
            note: "Adjusted",
            receiptFileName: nil,
            in: context
        )
        var rows = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.amount).reduce(0, +), 900, accuracy: 0.001)
        XCTAssertTrue(rows.allSatisfy { $0.note == "Adjusted" })

        _ = try VehicleExpenseInstallmentService.replace(
            existing: rows[0],
            category: .casco,
            totalAmount: 900,
            startDate: start,
            installmentCount: 1,
            note: nil,
            receiptFileName: nil,
            in: context
        )
        rows = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].amount, 900, accuracy: 0.001)
        XCTAssertFalse(rows[0].isInstallment)
    }

    func testDeleteOneKeepsSiblings() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Delete Car")
        context.insert(vehicle)

        let first = try VehicleExpenseInstallmentService.insert(
            category: .service,
            totalAmount: 600,
            startDate: Date(),
            installmentCount: 3,
            note: nil,
            vehicle: vehicle,
            in: context
        )
        let siblings = VehicleExpenseInstallmentService.siblings(of: first, in: context)
        VehicleExpenseInstallmentService.deleteOne(siblings[1], in: context)

        let remaining = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(Set(remaining.compactMap(\.installmentIndex)), [1, 3])
    }
}

@MainActor
final class VehicleExpenseInstallmentSnapshotTests: XCTestCase {
    func testMonthChartCountsOnlyThatMonthsInstallment() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Chart Car")
        context.insert(vehicle)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!

        _ = try VehicleExpenseInstallmentService.insert(
            category: .accessory,
            totalAmount: 1_200,
            startDate: start,
            installmentCount: 6,
            note: nil,
            vehicle: vehicle,
            in: context
        )

        let loader = VehicleCostSnapshotLoader(modelContainer: container)
        let augustStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let septemberStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let marchStart = calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))!

        let august = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 1,
                periodStart: augustStart,
                periodEnd: septemberStart.addingTimeInterval(-1),
                selectedVehicleID: vehicle.id
            )
        )
        XCTAssertEqual(august.total, 200, accuracy: 0.01)
        XCTAssertEqual(august.days.count, 1)

        let yearSpan = await loader.snapshot(
            for: VehicleCostSnapshotRequest(
                storeVersion: 2,
                periodStart: augustStart,
                periodEnd: marchStart,
                selectedVehicleID: vehicle.id
            )
        )
        XCTAssertEqual(yearSpan.total, 1_200, accuracy: 0.01)
        XCTAssertEqual(yearSpan.months.count, 6)
    }
}
