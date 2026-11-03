import XCTest
@testable import Milehound

final class VehicleExpenseCategoryTests: XCTestCase {
    func testPickerHasElevenCases() {
        XCTAssertEqual(VehicleExpenseCategory.allCases.count, 11)
        XCTAssertEqual(
            VehicleExpenseCategory.allCases.map(\.rawValue),
            [
                "fuel",
                "trafficInsurance",
                "casco",
                "service",
                "inspection",
                "repair",
                "accessory",
                "hgs",
                "parking",
                "mtv",
                "other"
            ]
        )
    }

    func testLegacyRawValuesResolve() {
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "parts"), .accessory)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "insurance"), .trafficInsurance)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "tax"), .mtv)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "parking"), .parking)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "hgs"), .hgs)
        XCTAssertEqual(VehicleExpenseCategory.hgs.displayName, L10n.string("vehicles.care.expense.hgs"))
        XCTAssertNotEqual(VehicleExpenseCategory.hgs.displayName, "HGS")
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "mtv"), .mtv)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "fuel"), .fuel)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "repair"), .repair)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "trafficInsurance"), .trafficInsurance)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "unknown"), .other)
    }

    func testReadingLegacyRawDoesNotRewriteStoredString() {
        let expense = VehicleExpense(category: .fuel, amount: 1)
        expense.categoryRaw = "tax"
        XCTAssertEqual(expense.category, .mtv)
        XCTAssertEqual(expense.categoryRaw, "tax")

        expense.categoryRaw = "parking"
        XCTAssertEqual(expense.category, .parking)
        XCTAssertEqual(expense.categoryRaw, "parking")
    }

    func testCostBuckets() {
        XCTAssertEqual(VehicleExpenseCategory.fuel.costBucket, .fuel)
        XCTAssertEqual(VehicleExpenseCategory.service.costBucket, .service)
        XCTAssertEqual(VehicleExpenseCategory.repair.costBucket, .service)
        XCTAssertEqual(VehicleExpenseCategory.trafficInsurance.costBucket, .insurance)
        XCTAssertEqual(VehicleExpenseCategory.casco.costBucket, .casco)
        XCTAssertEqual(VehicleExpenseCategory.accessory.costBucket, .other)
        XCTAssertEqual(VehicleExpenseCategory.inspection.costBucket, .other)
        XCTAssertEqual(VehicleExpenseCategory.hgs.costBucket, .other)
        XCTAssertEqual(VehicleExpenseCategory.parking.costBucket, .other)
        XCTAssertEqual(VehicleExpenseCategory.mtv.costBucket, .other)
    }

    func testSuggestedForScheduleKind() {
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .service), .service)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .inspection), .inspection)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .casco), .casco)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .trafficInsurance), .trafficInsurance)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .custom), .other)
    }

    func testLegendCapKeepsAllCasesOrderAtEightOrFewer() {
        let present: [VehicleExpenseCategory] = [.fuel, .service, .hgs, .other]
        let capped = VehicleExpenseLegendCap.categories(present) { category in
            switch category {
            case .other: 500
            case .hgs: 400
            default: 10
            }
        }
        XCTAssertEqual(capped, present)
    }

    func testLegendCapTakesEightLargestWhenOverLimit() {
        let present = VehicleExpenseCategory.allCases
        XCTAssertEqual(present.count, 11)
        let amounts: [VehicleExpenseCategory: Double] = [
            .fuel: 11,
            .trafficInsurance: 10,
            .casco: 9,
            .service: 8,
            .inspection: 7,
            .repair: 6,
            .accessory: 5,
            .hgs: 4,
            .parking: 3,
            .mtv: 2,
            .other: 1
        ]
        let capped = VehicleExpenseLegendCap.categories(present) { amounts[$0, default: 0] }
        XCTAssertEqual(capped.count, 8)
        XCTAssertEqual(
            capped,
            [.fuel, .trafficInsurance, .casco, .service, .inspection, .repair, .accessory, .hgs]
        )
        XCTAssertFalse(capped.contains(.parking))
        XCTAssertFalse(capped.contains(.mtv))
        XCTAssertFalse(capped.contains(.other))
    }
}
