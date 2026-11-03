import Foundation
import SwiftData

@MainActor
enum VehicleExpenseInstallmentService {
    static func siblings(of expense: VehicleExpense, in context: ModelContext) -> [VehicleExpense] {
        guard let groupID = expense.installmentGroupID else { return [expense] }
        let all = (try? context.fetch(FetchDescriptor<VehicleExpense>())) ?? []
        let matches = all.filter { $0.installmentGroupID == groupID }
        if matches.isEmpty { return [expense] }
        return matches.sorted { lhs, rhs in
            let li = lhs.installmentIndex ?? 0
            let ri = rhs.installmentIndex ?? 0
            if li != ri { return li < ri }
            return lhs.occurredAt < rhs.occurredAt
        }
    }

    @discardableResult
    static func insert(
        category: VehicleExpenseCategory,
        totalAmount: Double,
        startDate: Date,
        installmentCount: Int,
        note: String?,
        receiptFileName: String? = nil,
        linkedScheduleID: UUID? = nil,
        odometerKm: Int? = nil,
        source: VehicleExpenseSource = .manual,
        vehicle: VehicleProfile,
        in context: ModelContext
    ) throws -> VehicleExpense {
        guard totalAmount >= 0 else { throw VehicleCareError.invalidAmount }
        let slices = VehicleExpenseInstallmentPlan.slices(
            total: totalAmount,
            count: installmentCount,
            start: startDate
        )
        let groupID = slices.count > 1 ? UUID() : nil
        var first: VehicleExpense?
        for slice in slices {
            let expense = makeExpense(
                category: category,
                slice: slice,
                totalAmount: totalAmount,
                count: slices.count,
                groupID: groupID,
                note: note,
                receiptFileName: receiptFileName,
                linkedScheduleID: linkedScheduleID,
                odometerKm: slice.index == 1 ? odometerKm : nil,
                source: source,
                vehicle: vehicle
            )
            context.insert(expense)
            if first == nil { first = expense }
            YearRecapCache.invalidate(yearContaining: slice.dueDate)
        }
        try context.save()
        return first!
    }

    @discardableResult
    static func replace(
        existing: VehicleExpense,
        category: VehicleExpenseCategory,
        totalAmount: Double,
        startDate: Date,
        installmentCount: Int,
        note: String?,
        receiptFileName: String?,
        in context: ModelContext
    ) throws -> VehicleExpense {
        guard totalAmount >= 0 else { throw VehicleCareError.invalidAmount }
        let current = siblings(of: existing, in: context)
        let slices = VehicleExpenseInstallmentPlan.slices(
            total: totalAmount,
            count: installmentCount,
            start: startDate
        )
        let groupID = slices.count > 1 ? (existing.installmentGroupID ?? UUID()) : nil
        var byIndex: [Int: VehicleExpense] = [:]
        for row in current {
            byIndex[row.installmentIndex ?? 1] = row
        }
        if byIndex[1] == nil {
            byIndex[1] = existing
        }

        var first: VehicleExpense?
        for slice in slices {
            if let row = byIndex.removeValue(forKey: slice.index) {
                apply(
                    slice,
                    to: row,
                    category: category,
                    totalAmount: totalAmount,
                    count: slices.count,
                    groupID: groupID,
                    note: note,
                    receiptFileName: receiptFileName
                )
                if first == nil { first = row }
            } else {
                let created = makeExpense(
                    category: category,
                    slice: slice,
                    totalAmount: totalAmount,
                    count: slices.count,
                    groupID: groupID,
                    note: note,
                    receiptFileName: receiptFileName,
                    linkedScheduleID: existing.linkedScheduleID,
                    odometerKm: slice.index == 1 ? existing.odometerKm : nil,
                    source: existing.source,
                    vehicle: existing.vehicle
                )
                context.insert(created)
                if first == nil { first = created }
            }
        }

        for leftover in byIndex.values {
            YearRecapCache.invalidate(yearContaining: leftover.occurredAt)
            context.delete(leftover)
        }
        for slice in slices {
            YearRecapCache.invalidate(yearContaining: slice.dueDate)
        }
        try context.save()
        return first ?? existing
    }

    static func deleteOne(_ expense: VehicleExpense, in context: ModelContext) {
        let receipt = expense.receiptFileName
        YearRecapCache.invalidate(yearContaining: expense.occurredAt)
        context.delete(expense)
        try? context.save()
        ExpenseReceiptStore.shared.removeIfUnreferenced(fileName: receipt, in: context)
    }

    static func deleteGroup(of expense: VehicleExpense, in context: ModelContext) {
        let receipts = Set(siblings(of: expense, in: context).compactMap(\.receiptFileName))
        for sibling in siblings(of: expense, in: context) {
            YearRecapCache.invalidate(yearContaining: sibling.occurredAt)
            context.delete(sibling)
        }
        try? context.save()
        for receipt in receipts {
            ExpenseReceiptStore.shared.removeIfUnreferenced(fileName: receipt, in: context)
        }
    }

    private static func makeExpense(
        category: VehicleExpenseCategory,
        slice: VehicleExpenseInstallmentSlice,
        totalAmount: Double,
        count: Int,
        groupID: UUID?,
        note: String?,
        receiptFileName: String?,
        linkedScheduleID: UUID?,
        odometerKm: Int? = nil,
        source: VehicleExpenseSource,
        vehicle: VehicleProfile?
    ) -> VehicleExpense {
        VehicleExpense(
            category: category,
            amount: slice.amount,
            occurredAt: slice.dueDate,
            odometerKm: odometerKm,
            note: note,
            linkedScheduleID: linkedScheduleID,
            source: source,
            vehicle: vehicle,
            installmentGroupID: groupID,
            installmentIndex: groupID == nil ? nil : slice.index,
            installmentCount: groupID == nil ? nil : count,
            installmentTotalAmount: groupID == nil ? nil : totalAmount,
            receiptFileName: receiptFileName
        )
    }

    private static func apply(
        _ slice: VehicleExpenseInstallmentSlice,
        to expense: VehicleExpense,
        category: VehicleExpenseCategory,
        totalAmount: Double,
        count: Int,
        groupID: UUID?,
        note: String?,
        receiptFileName: String?
    ) {
        expense.category = category
        expense.amount = slice.amount
        expense.occurredAt = slice.dueDate
        expense.note = note
        expense.receiptFileName = receiptFileName
        expense.installmentGroupID = groupID
        expense.installmentIndex = groupID == nil ? nil : slice.index
        expense.installmentCount = groupID == nil ? nil : count
        expense.installmentTotalAmount = groupID == nil ? nil : totalAmount
    }
}
