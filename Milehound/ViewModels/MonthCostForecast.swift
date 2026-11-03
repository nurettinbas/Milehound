import Foundation
import SwiftData

enum MonthCostForecastConfidence: String, Sendable, Equatable {
    case low
    case medium
    case high
}

struct MonthCostForecast: Equatable, Sendable {
    var mtdFuel: Double
    var projectedFuel: Double
    var installmentsDue: Double
    var loggedFuel: Double
    var otherExpenses: Double
    var projectedTotal: Double
    var previousMonthTotal: Double
    var dailyRunRate: Double
    var confidence: MonthCostForecastConfidence
    var monthStart: Date
    var asOf: Date
    var monthlyTotals: [VehicleMonthlyCost]

    static let empty = MonthCostForecast(
        mtdFuel: 0,
        projectedFuel: 0,
        installmentsDue: 0,
        loggedFuel: 0,
        otherExpenses: 0,
        projectedTotal: 0,
        previousMonthTotal: 0,
        dailyRunRate: 0,
        confidence: .low,
        monthStart: Date(),
        asOf: Date(),
        monthlyTotals: []
    )

    var hasData: Bool {
        projectedTotal > 0 || mtdFuel > 0 || installmentsDue > 0 || loggedFuel > 0 || otherExpenses > 0
    }

    var trendRatio: Double? {
        guard previousMonthTotal > 0 else { return nil }
        return (projectedTotal - previousMonthTotal) / previousMonthTotal
    }

    /// Drive / installments / other as fractions of the hero total. Logged pump fuel is excluded.
    var compositionShares: MonthCostForecastShares {
        MonthCostForecastShares.shares(
            drive: projectedFuel,
            installments: installmentsDue,
            other: otherExpenses
        )
    }

    var hasComposition: Bool {
        projectedFuel > 0 || installmentsDue > 0 || otherExpenses > 0
    }
}

struct MonthCostForecastShares: Equatable, Sendable {
    var drive: Double
    var installments: Double
    var other: Double

    static let zero = MonthCostForecastShares(drive: 0, installments: 0, other: 0)

    static func shares(drive: Double, installments: Double, other: Double) -> MonthCostForecastShares {
        let total = drive + installments + other
        guard total > 0 else { return .zero }
        return MonthCostForecastShares(
            drive: drive / total,
            installments: installments / total,
            other: other / total
        )
    }
}

struct MonthCostForecastRequest: Sendable, Hashable {
    let storeVersion: Int
    let selectedVehicleID: UUID?
    let now: Date
}

enum MonthCostForecastMath {
    static func forecast(
        now: Date,
        calendar: Calendar = .current,
        mtdTripFuelByDay: [Date: Double],
        previousMonthTripFuelByDay: [Date: Double],
        thisMonthExpenses: [ForecastExpense],
        previousMonthExpenses: [ForecastExpense],
        sparklineMonths: [VehicleMonthlyCost] = []
    ) -> MonthCostForecast {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dayOfMonth = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let remainingDays = max(0, daysInMonth - dayOfMonth)

        let mtdFuel = mtdTripFuelByDay.values.reduce(0, +)
        let tripDays = mtdTripFuelByDay.filter { $0.value > 0 }.count

        let dailyRunRate: Double
        if dayOfMonth <= 3 {
            let fallbackDays = previousMonthTripFuelByDay.filter { day, _ in
                calendar.component(.day, from: day) <= dayOfMonth
            }
            let fallbackTotal = fallbackDays.values.reduce(0, +)
            let fallbackCount = max(1, fallbackDays.filter { $0.value > 0 }.count)
            dailyRunRate = fallbackTotal / Double(fallbackCount)
        } else {
            let completedDays = max(1, dayOfMonth - 1)
            let elapsedFuel = mtdTripFuelByDay.filter { day, _ in
                calendar.component(.day, from: day) < dayOfMonth
            }.values.reduce(0, +)
            dailyRunRate = elapsedFuel / Double(completedDays)
        }

        let projectedFuel = mtdFuel + Double(remainingDays) * dailyRunRate
        let installmentsDue = thisMonthExpenses.filter(\.isInstallment).reduce(0) { $0 + $1.amount }
        let loggedFuel = thisMonthExpenses.filter { $0.category == .fuel && !$0.isInstallment }
            .reduce(0) { $0 + $1.amount }
        let otherExpenses = thisMonthExpenses.filter { $0.category != .fuel && !$0.isInstallment }
            .reduce(0) { $0 + $1.amount }
        let projectedTotal = projectedFuel + installmentsDue + otherExpenses

        let previousFuel = previousMonthTripFuelByDay.values.reduce(0, +)
        let previousInstallments = previousMonthExpenses.filter(\.isInstallment).reduce(0) { $0 + $1.amount }
        let previousOther = previousMonthExpenses.filter { $0.category != .fuel && !$0.isInstallment }
            .reduce(0) { $0 + $1.amount }
        let previousMonthTotal = previousFuel + previousInstallments + previousOther

        let confidence: MonthCostForecastConfidence
        if tripDays <= 2 {
            confidence = .low
        } else if tripDays <= 10 {
            confidence = .medium
        } else {
            confidence = .high
        }

        return MonthCostForecast(
            mtdFuel: mtdFuel,
            projectedFuel: projectedFuel,
            installmentsDue: installmentsDue,
            loggedFuel: loggedFuel,
            otherExpenses: otherExpenses,
            projectedTotal: projectedTotal,
            previousMonthTotal: previousMonthTotal,
            dailyRunRate: dailyRunRate,
            confidence: confidence,
            monthStart: monthStart,
            asOf: now,
            monthlyTotals: sparklineMonths
        )
    }
}

struct ForecastExpense: Equatable, Sendable {
    let amount: Double
    let category: VehicleExpenseCategory
    let isInstallment: Bool
    let occurredAt: Date
}

enum MonthCostForecastStore {
    static func forecast(
        in context: ModelContext,
        vehicleID: UUID?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthCostForecast {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        guard
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart),
            let previousStart = calendar.date(byAdding: .month, value: -1, to: monthStart)
        else {
            return .empty
        }
        let sparklineStart = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? previousStart
        return MonthCostForecastMath.forecast(
            now: now,
            calendar: calendar,
            mtdTripFuelByDay: tripFuelByDay(from: monthStart, to: monthEnd, vehicleID: vehicleID, in: context),
            previousMonthTripFuelByDay: tripFuelByDay(from: previousStart, to: monthStart, vehicleID: vehicleID, in: context),
            thisMonthExpenses: expenses(from: monthStart, to: monthEnd, vehicleID: vehicleID, in: context),
            previousMonthExpenses: expenses(from: previousStart, to: monthStart, vehicleID: vehicleID, in: context),
            sparklineMonths: monthlySparkline(from: sparklineStart, to: monthEnd, vehicleID: vehicleID, in: context)
        )
    }

    static func tripFuelByDay(
        from: Date,
        to: Date,
        vehicleID: UUID?,
        in context: ModelContext
    ) -> [Date: Double] {
        let descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart >= from && rollup.dayStart < to
            }
        )
        let rollups = (try? context.fetch(descriptor)) ?? []
        var days: [Date: Double] = [:]
        for rollup in rollups {
            if let vehicleID, rollup.vehicleKey != vehicleID.uuidString { continue }
            days[rollup.dayStart, default: 0] += rollup.estimatedFuelCost
        }
        return days
    }

    static func expenses(
        from: Date,
        to: Date,
        vehicleID: UUID?,
        in context: ModelContext
    ) -> [ForecastExpense] {
        let descriptor = FetchDescriptor<VehicleExpense>(
            predicate: #Predicate { expense in
                expense.occurredAt >= from && expense.occurredAt < to
            }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.compactMap { expense in
            if let vehicleID, expense.vehicle?.id != vehicleID { return nil }
            return ForecastExpense(
                amount: expense.amount,
                category: expense.category,
                isInstallment: expense.isInstallment,
                occurredAt: expense.occurredAt
            )
        }
    }

    static func monthlySparkline(
        from: Date,
        to: Date,
        vehicleID: UUID?,
        in context: ModelContext
    ) -> [VehicleMonthlyCost] {
        let rows = expenses(from: from, to: to, vehicleID: vehicleID, in: context)
        let calendar = Calendar.current
        var months: [Date: VehicleExpenseCategoryAmounts] = [:]
        for expense in rows {
            let month = calendar.date(
                from: calendar.dateComponents([.year, .month], from: expense.occurredAt)
            ) ?? expense.occurredAt
            var bucket = months[month] ?? VehicleExpenseCategoryAmounts()
            bucket.add(expense.amount, category: expense.category)
            months[month] = bucket
        }
        return months.keys.sorted().map { VehicleMonthlyCost(monthStart: $0, amounts: months[$0]!) }
    }
}

