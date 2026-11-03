import Foundation
import SwiftData

/// Year-in-review aggregation. Rollups + expenses only — never fetches `Trip`.
@ModelActor
actor StatsYearAwardsLoader {
    private static let maxCacheEntries = 4

    private var cache: [StatsYearAwardsRequest: StatsYearAwardsSnapshot] = [:]
    private var cacheOrder: [StatsYearAwardsRequest] = []
    private var cachedStoreVersion: Int?

    func snapshot(for request: StatsYearAwardsRequest) -> StatsYearAwardsSnapshot {
        if cachedStoreVersion != request.storeVersion {
            cache.removeAll(keepingCapacity: true)
            cacheOrder.removeAll(keepingCapacity: true)
            cachedStoreVersion = request.storeVersion
        }
        if let cached = cache[request] { return cached }
        let built = PerformanceSignposts.measure("StatsYearAwardsBuild") {
            build(request)
        }
        insertCache(request, snapshot: built)
        return built
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        cachedStoreVersion = nil
    }

    private func insertCache(_ request: StatsYearAwardsRequest, snapshot: StatsYearAwardsSnapshot) {
        if cache[request] == nil {
            cacheOrder.append(request)
        }
        cache[request] = snapshot
        while cacheOrder.count > Self.maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func build(_ request: StatsYearAwardsRequest) -> StatsYearAwardsSnapshot {
        let calendar = Calendar.current
        let interval = StatsViewModel.calendarYearInterval(year: request.year, calendar: calendar)
        let lowerBound = calendar.startOfDay(for: interval.start)
        let upperBound = interval.end

        let rollups = fetchRollups(from: lowerBound, to: upperBound)
        var totalDistance = 0.0
        var nightMeters = 0.0
        var trackedMeters = 0.0
        var dayDistance: [Date: Double] = [:]
        var monthDistance: [Date: Double] = [:]

        for rollup in rollups {
            totalDistance += rollup.distanceMeters
            nightMeters += rollup.nightDistanceMeters
            trackedMeters += rollup.trackedDistanceMeters
            let day = calendar.startOfDay(for: rollup.dayStart)
            dayDistance[day, default: 0] += rollup.distanceMeters
            let month = calendar.date(
                from: calendar.dateComponents([.year, .month], from: rollup.dayStart)
            ) ?? rollup.dayStart
            monthDistance[month, default: 0] += rollup.distanceMeters
        }

        let busiest = dayDistance.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }

        let monthlyDistances = monthDistance.keys.sorted().map { month in
            StatsYearMonthlyDistance(monthStart: month, distanceMeters: monthDistance[month] ?? 0)
        }

        let nightRatio = trackedMeters > 0 ? nightMeters / trackedMeters : 0

        var vehicleTotals: [String: (name: String, amount: Double)] = [:]
        var monthExpense: [Date: Double] = [:]
        let expenses = fetchExpenses(from: lowerBound, to: upperBound)
        for expense in expenses {
            let vehicleKey = expense.vehicle?.id.uuidString ?? VehicleExpenseShare.unassignedID
            let vehicleName = expense.vehicle?.name ?? ""
            let existing = vehicleTotals[vehicleKey]
            vehicleTotals[vehicleKey] = (
                name: existing?.name.isEmpty == false ? existing!.name : vehicleName,
                amount: (existing?.amount ?? 0) + expense.amount
            )
            let month = calendar.date(
                from: calendar.dateComponents([.year, .month], from: expense.occurredAt)
            ) ?? expense.occurredAt
            monthExpense[month, default: 0] += expense.amount
        }

        let topVehicle = vehicleTotals.max { lhs, rhs in
            if lhs.value.amount != rhs.value.amount { return lhs.value.amount < rhs.value.amount }
            return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
        let topMonth = monthExpense.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        }

        return StatsYearAwardsSnapshot(
            year: request.year,
            totalDistanceMeters: totalDistance,
            nightRatio: nightRatio,
            busiestDay: busiest?.key,
            busiestDayMeters: busiest?.value ?? 0,
            monthlyDistances: monthlyDistances,
            mostExpensiveVehicleName: topVehicle?.value.name ?? "",
            mostExpensiveVehicleAmount: topVehicle?.value.amount ?? 0,
            mostExpensiveMonthStart: topMonth?.key,
            mostExpensiveMonthAmount: topMonth?.value ?? 0
        )
    }

    private func fetchRollups(from lowerBound: Date, to upperBound: Date) -> [TripDailyRollup] {
        let descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { $0.dayStart >= lowerBound && $0.dayStart <= upperBound },
            sortBy: [SortDescriptor(\.dayStart, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchExpenses(from lowerBound: Date, to upperBound: Date) -> [VehicleExpense] {
        let descriptor = FetchDescriptor<VehicleExpense>(
            predicate: #Predicate { expense in
                expense.occurredAt >= lowerBound && expense.occurredAt < upperBound
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
