import Foundation
import SwiftData

struct VehicleScheduleEditorDraft: Equatable {
    var kind: VehicleScheduleKind
    var title: String
    var nextDueDate: Date
    var intervalKind: VehicleScheduleIntervalKind
    var intervalMonths: Int
    var intervalKm: Int
    var nextDueOdometerKm: Int
    var notes: String
    var isEnabled: Bool

    init(kind: VehicleScheduleKind = .service) {
        self.kind = kind
        self.title = kind.defaultTitle
        self.nextDueDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        self.intervalKind = kind == .service ? .everyMonths : .everyYears
        self.intervalMonths = kind == .service ? 12 : (kind == .inspection ? 24 : 12)
        self.intervalKm = 15_000
        self.nextDueOdometerKm = 15_000
        self.notes = ""
        self.isEnabled = true
    }

    init(from schedule: VehicleSchedule) {
        kind = schedule.kind
        title = schedule.title
        nextDueDate = schedule.nextDueDate ?? Date()
        intervalKind = schedule.intervalKind
        intervalMonths = schedule.intervalMonths ?? 12
        intervalKm = schedule.intervalKm ?? 15_000
        nextDueOdometerKm = schedule.nextDueOdometerKm ?? 15_000
        notes = schedule.notes ?? ""
        isEnabled = schedule.isEnabled
    }

    @MainActor
    func apply(to schedule: VehicleSchedule, in context: ModelContext) throws {
        schedule.kind = kind
        schedule.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.defaultTitle
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.intervalKind = intervalKind
        schedule.intervalMonths = intervalMonths
        let usesKm = intervalKind == .everyKm || intervalKind == .whicheverFirst
        schedule.nextDueDate = intervalKind == .everyKm ? nil : nextDueDate
        schedule.intervalKm = min(50_000, max(500, intervalKm))
        schedule.nextDueOdometerKm = usesKm ? min(VehicleOdometerService.readingRange.upperBound, max(0, nextDueOdometerKm)) : nil
        schedule.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        schedule.isEnabled = isEnabled
        schedule.reminderOffsetsDays = kind.defaultReminderOffsets
        try context.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: context)
        VehicleCareNotificationScheduler.evaluateKmReminders(for: schedule.vehicle?.id, in: context)
    }

    @MainActor
    func insert(for vehicle: VehicleProfile, in context: ModelContext) throws -> VehicleSchedule {
        let schedule = VehicleSchedule(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isEnabled: isEnabled,
            nextDueDate: intervalKind == .everyKm ? nil : nextDueDate,
            nextDueOdometerKm: intervalKind == .everyKm || intervalKind == .whicheverFirst
                ? min(VehicleOdometerService.readingRange.upperBound, max(0, nextDueOdometerKm))
                : nil,
            intervalKind: intervalKind,
            intervalMonths: intervalMonths,
            intervalKm: min(50_000, max(500, intervalKm)),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            vehicle: vehicle
        )
        context.insert(schedule)
        try context.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: context)
        VehicleCareNotificationScheduler.evaluateKmReminders(for: vehicle.id, in: context)
        return schedule
    }
}

struct VehicleExpenseEditorDraft: Equatable {
    var category: VehicleExpenseCategory
    var amountText: String
    var occurredAt: Date
    var note: String
    var installmentCount: Int
    /// Receipt shown in the form. May be a fresh file that is not saved to any expense yet.
    private(set) var receiptFileName: String?
    /// Receipt the expense had when the form opened.
    private(set) var originalReceiptFileName: String?

    init(category: VehicleExpenseCategory = .fuel) {
        self.category = category
        self.amountText = ""
        self.occurredAt = Date()
        self.note = ""
        self.installmentCount = 1
        self.receiptFileName = nil
        self.originalReceiptFileName = nil
    }

    init(from expense: VehicleExpense, siblings: [VehicleExpense] = []) {
        category = expense.category
        note = expense.note ?? ""
        receiptFileName = expense.receiptFileName
        originalReceiptFileName = expense.receiptFileName
        if expense.isInstallment {
            let plan = siblings.isEmpty ? [expense] : siblings
            let total = expense.installmentTotalAmount ?? plan.reduce(0) { $0 + $1.amount }
            installmentCount = VehicleExpenseInstallmentPlan.clampedCount(
                expense.installmentCount ?? plan.count
            )
            amountText = total > 0 ? String(Int(total.rounded())) : ""
            occurredAt = plan.map(\.occurredAt).min() ?? expense.occurredAt
        } else {
            installmentCount = 1
            amountText = expense.amount > 0 ? String(Int(expense.amount.rounded())) : ""
            occurredAt = expense.occurredAt
        }
    }

    /// Whole currency units only (no kuruş / cents). Digits-only text → Int → Double.
    var amount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber), let value = Int(trimmed), value >= 0 else {
            return nil
        }
        return Double(value)
    }

    var isInstallmentPlan: Bool { installmentCount > 1 }

    // MARK: - Receipt

    /// Shows `fileName` in the form. Returns an unsaved file that is now orphaned and can be deleted.
    mutating func attachReceipt(_ fileName: String) -> String? {
        let previous = receiptFileName
        receiptFileName = fileName
        return previous != originalReceiptFileName ? previous : nil
    }

    /// Clears the receipt from the form. Returns an unsaved file that can be deleted right away.
    /// The saved original is kept on disk until Save (`receiptToDeleteAfterSave`).
    mutating func removeReceipt() -> String? {
        let previous = receiptFileName
        receiptFileName = nil
        return previous != originalReceiptFileName ? previous : nil
    }

    /// After a successful Save: the old receipt that the expense no longer uses.
    var receiptToDeleteAfterSave: String? {
        originalReceiptFileName != receiptFileName ? originalReceiptFileName : nil
    }

    /// When the form closes without saving: the new file nobody points at.
    var receiptToDeleteOnCancel: String? {
        receiptFileName != originalReceiptFileName ? receiptFileName : nil
    }

    /// Typed digits from a confirmed receipt reading (whole currency units).
    mutating func applyScannedAmount(_ wholeUnits: Int) {
        amountText = String(max(0, wholeUnits))
    }

    @MainActor
    func apply(to expense: VehicleExpense, in context: ModelContext) throws {
        guard let amount else { throw VehicleCareError.invalidAmount }
        _ = try VehicleExpenseInstallmentService.replace(
            existing: expense,
            category: category,
            totalAmount: amount.rounded(),
            startDate: occurredAt,
            installmentCount: installmentCount,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            receiptFileName: receiptFileName,
            in: context
        )
    }

    @MainActor
    func insert(for vehicle: VehicleProfile, in context: ModelContext) throws -> VehicleExpense {
        guard let amount else { throw VehicleCareError.invalidAmount }
        return try VehicleExpenseInstallmentService.insert(
            category: category,
            totalAmount: amount.rounded(),
            startDate: occurredAt,
            installmentCount: installmentCount,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            receiptFileName: receiptFileName,
            source: .manual,
            vehicle: vehicle,
            in: context
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
