import Foundation

struct VehicleExpenseInstallmentSlice: Equatable, Sendable {
    var index: Int
    var amount: Double
    var dueDate: Date
}

/// Splits a purchase into monthly cash-basis installments.
/// Charts and the expense list use each slice’s `dueDate` as `occurredAt`.
enum VehicleExpenseInstallmentPlan {
    static let minCount = 1
    static let maxCount = 24

    static func clampedCount(_ count: Int) -> Int {
        min(max(count, minCount), maxCount)
    }

    static func slices(
        total: Double,
        count: Int,
        start: Date,
        calendar: Calendar = .current
    ) -> [VehicleExpenseInstallmentSlice] {
        let n = clampedCount(count)
        let amounts = splitAmounts(total: total, count: n)
        return (0..<n).map { offset in
            let due = calendar.date(byAdding: .month, value: offset, to: start) ?? start
            return VehicleExpenseInstallmentSlice(
                index: offset + 1,
                amount: amounts[offset],
                dueDate: due
            )
        }
    }

    /// Integer-cent split so the last installment absorbs leftover kuruş.
    static func splitAmounts(total: Double, count: Int) -> [Double] {
        let n = max(count, 1)
        let cents = Int((total * 100).rounded())
        let base = cents / n
        let remainder = cents % n
        return (0..<n).map { index in
            let sliceCents = index == n - 1 ? base + remainder : base
            return Double(sliceCents) / 100.0
        }
    }
}
