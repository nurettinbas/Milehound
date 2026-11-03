import Foundation

struct StatsYearAwardsRequest: Sendable, Hashable {
    let storeVersion: Int
    let year: Int
}

struct StatsYearMonthlyDistance: Sendable, Equatable {
    let monthStart: Date
    let distanceMeters: Double
}

struct StatsYearAwardsSnapshot: Sendable, Equatable {
    let year: Int
    let totalDistanceMeters: Double
    let nightRatio: Double
    let busiestDay: Date?
    let busiestDayMeters: Double
    let monthlyDistances: [StatsYearMonthlyDistance]
    let mostExpensiveVehicleName: String
    let mostExpensiveVehicleAmount: Double
    let mostExpensiveMonthStart: Date?
    let mostExpensiveMonthAmount: Double

    var hasTripData: Bool { totalDistanceMeters > 0 || !monthlyDistances.isEmpty }
    var hasExpenseData: Bool { mostExpensiveVehicleAmount > 0 || mostExpensiveMonthAmount > 0 }
    var hasData: Bool { hasTripData || hasExpenseData }

    static func empty(year: Int) -> StatsYearAwardsSnapshot {
        StatsYearAwardsSnapshot(
            year: year,
            totalDistanceMeters: 0,
            nightRatio: 0,
            busiestDay: nil,
            busiestDayMeters: 0,
            monthlyDistances: [],
            mostExpensiveVehicleName: "",
            mostExpensiveVehicleAmount: 0,
            mostExpensiveMonthStart: nil,
            mostExpensiveMonthAmount: 0
        )
    }
}

enum StatsYearAwardKind: String, CaseIterable, Sendable {
    case distance
    case nightOwl
    case goal
    case busiestDay
    case expensiveVehicle
    case expensiveMonth
}

struct StatsYearAward: Identifiable, Equatable {
    let kind: StatsYearAwardKind
    let isUnlocked: Bool
    let title: String
    let detail: String
    let systemImage: String

    var id: String { kind.rawValue }
}

enum StatsYearAwardsPresenter {
    static let distanceThresholdsKm = [1_000.0, 5_000.0, 10_000.0]
    static let nightOwlRatio = 0.20

    static func medals(
        from snapshot: StatsYearAwardsSnapshot,
        goalMetersForMonth: (Date) -> Double,
        currencyCode: String
    ) -> [StatsYearAward] {
        StatsYearAwardKind.allCases.map { kind in
            medal(
                kind: kind,
                snapshot: snapshot,
                goalMetersForMonth: goalMetersForMonth,
                currencyCode: currencyCode
            )
        }
    }

    private static func medal(
        kind: StatsYearAwardKind,
        snapshot: StatsYearAwardsSnapshot,
        goalMetersForMonth: (Date) -> Double,
        currencyCode: String
    ) -> StatsYearAward {
        switch kind {
        case .distance:
            let km = snapshot.totalDistanceMeters / 1000
            let unlocked = distanceThresholdsKm.last(where: { km >= $0 })
            let detail: String
            if let unlocked {
                detail = String(format: L10n.string("stats.awards.distance_unlocked"), Int(unlocked))
            } else {
                detail = DateFormatters.formatDistance(snapshot.totalDistanceMeters)
            }
            return StatsYearAward(
                kind: kind,
                isUnlocked: unlocked != nil,
                title: L10n.string("stats.awards.distance"),
                detail: detail,
                systemImage: "road.lanes"
            )
        case .nightOwl:
            let unlocked = snapshot.nightRatio >= nightOwlRatio
            let percent = Int((snapshot.nightRatio * 100).rounded())
            return StatsYearAward(
                kind: kind,
                isUnlocked: unlocked,
                title: L10n.string("stats.awards.night_owl"),
                detail: String(format: L10n.string("stats.awards.night_detail"), percent),
                systemImage: "moon.stars.fill"
            )
        case .goal:
            let hitCount = snapshot.monthlyDistances.filter { month in
                let target = goalMetersForMonth(month.monthStart)
                return target > 0 && month.distanceMeters >= target
            }.count
            return StatsYearAward(
                kind: kind,
                isUnlocked: hitCount > 0,
                title: L10n.string("stats.awards.goal"),
                detail: String(format: L10n.string("stats.awards.goal_months"), hitCount),
                systemImage: "target"
            )
        case .busiestDay:
            let unlocked = snapshot.busiestDay != nil && snapshot.busiestDayMeters > 0
            let detail: String
            if unlocked, let day = snapshot.busiestDay {
                detail = "\(DateFormatters.chartDay.string(from: day)) · \(DateFormatters.formatDistance(snapshot.busiestDayMeters))"
            } else {
                detail = L10n.string("stats.awards.locked")
            }
            return StatsYearAward(
                kind: kind,
                isUnlocked: unlocked,
                title: L10n.string("stats.awards.busiest_day"),
                detail: detail,
                systemImage: "calendar"
            )
        case .expensiveVehicle:
            let unlocked = snapshot.mostExpensiveVehicleAmount > 0
            let name = snapshot.mostExpensiveVehicleName.isEmpty
                ? L10n.string("stats.vehicle.unassigned")
                : snapshot.mostExpensiveVehicleName
            let detail = unlocked
                ? "\(name) · \(FuelCostCalculator.formatCost(snapshot.mostExpensiveVehicleAmount, currencyCode: currencyCode))"
                : L10n.string("stats.awards.locked")
            return StatsYearAward(
                kind: kind,
                isUnlocked: unlocked,
                title: L10n.string("stats.awards.expensive_vehicle"),
                detail: detail,
                systemImage: "car.fill"
            )
        case .expensiveMonth:
            let unlocked = snapshot.mostExpensiveMonthStart != nil && snapshot.mostExpensiveMonthAmount > 0
            let detail: String
            if unlocked, let month = snapshot.mostExpensiveMonthStart {
                detail = "\(DateFormatters.monthYear.string(from: month)) · \(FuelCostCalculator.formatCost(snapshot.mostExpensiveMonthAmount, currencyCode: currencyCode))"
            } else {
                detail = L10n.string("stats.awards.locked")
            }
            return StatsYearAward(
                kind: kind,
                isUnlocked: unlocked,
                title: L10n.string("stats.awards.expensive_month"),
                detail: detail,
                systemImage: "creditcard.fill"
            )
        }
    }
}
