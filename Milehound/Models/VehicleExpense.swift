import Foundation
import SwiftData

@Model
final class VehicleExpense {
    var id: UUID
    var categoryRaw: String
    var amount: Double
    var occurredAt: Date
    var odometerKm: Int?
    var vendor: String?
    var note: String?
    var linkedScheduleID: UUID?
    var sourceRaw: String
    /// Shared by every monthly slice of one purchase. Nil = one-shot expense.
    var installmentGroupID: UUID?
    var installmentIndex: Int?
    var installmentCount: Int?
    var installmentTotalAmount: Double?
    /// File in `ExpenseReceiptStore`. Every slice of one installment plan shares the same name.
    var receiptFileName: String?

    var vehicle: VehicleProfile?

    init(
        id: UUID = UUID(),
        category: VehicleExpenseCategory,
        amount: Double,
        occurredAt: Date = Date(),
        odometerKm: Int? = nil,
        vendor: String? = nil,
        note: String? = nil,
        linkedScheduleID: UUID? = nil,
        source: VehicleExpenseSource = .manual,
        vehicle: VehicleProfile? = nil,
        installmentGroupID: UUID? = nil,
        installmentIndex: Int? = nil,
        installmentCount: Int? = nil,
        installmentTotalAmount: Double? = nil,
        receiptFileName: String? = nil
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.occurredAt = occurredAt
        self.odometerKm = odometerKm
        self.vendor = vendor
        self.note = note
        self.linkedScheduleID = linkedScheduleID
        self.sourceRaw = source.rawValue
        self.vehicle = vehicle
        self.installmentGroupID = installmentGroupID
        self.installmentIndex = installmentIndex
        self.installmentCount = installmentCount
        self.installmentTotalAmount = installmentTotalAmount
        self.receiptFileName = receiptFileName
    }

    var category: VehicleExpenseCategory {
        get { VehicleExpenseCategory.resolved(fromRaw: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var source: VehicleExpenseSource {
        get { VehicleExpenseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isInstallment: Bool {
        installmentGroupID != nil && (installmentCount ?? 1) > 1
    }
}
