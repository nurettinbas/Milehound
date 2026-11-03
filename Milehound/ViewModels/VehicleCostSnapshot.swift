import Foundation

enum VehicleExpenseLegendCap {
    static let maxVisible = 8

    /// Keep `allCases` order at the limit or below; above that, the largest amounts first.
    static func categories(
        _ present: [VehicleExpenseCategory],
        amount: (VehicleExpenseCategory) -> Double
    ) -> [VehicleExpenseCategory] {
        guard present.count > maxVisible else { return present }
        return Array(
            present.sorted { lhs, rhs in
                let left = amount(lhs)
                let right = amount(rhs)
                if left != right { return left > right }
                return lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
            }
            .prefix(maxVisible)
        )
    }
}

/// Per–expense-category totals for a day or month (keeps Accessory distinct from Other).
struct VehicleExpenseCategoryAmounts: Sendable, Equatable {
    private(set) var amounts: [VehicleExpenseCategory: Double] = [:]

    var total: Double { amounts.values.reduce(0, +) }

    func amount(for category: VehicleExpenseCategory) -> Double {
        amounts[category, default: 0]
    }

    mutating func add(_ amount: Double, category: VehicleExpenseCategory) {
        amounts[category, default: 0] += amount
    }

    var presentCategories: [VehicleExpenseCategory] {
        VehicleExpenseCategory.allCases.filter { amount(for: $0) > 0 }
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        VehicleExpenseCategory.allCases
            .filter { $0.costBucket == bucket }
            .reduce(0) { $0 + amount(for: $1) }
    }
}

struct VehicleMonthlyCost: Identifiable, Sendable, Equatable {
    var id: Date { monthStart }
    let monthStart: Date
    let amounts: VehicleExpenseCategoryAmounts

    var total: Double { amounts.total }

    func amount(for category: VehicleExpenseCategory) -> Double {
        amounts.amount(for: category)
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        amounts.amount(for: bucket)
    }

    init(monthStart: Date, amounts: VehicleExpenseCategoryAmounts) {
        self.monthStart = monthStart
        self.amounts = amounts
    }
}

struct VehicleDailyCost: Identifiable, Sendable, Equatable {
    var id: Date { dayStart }
    let dayStart: Date
    let amounts: VehicleExpenseCategoryAmounts

    var total: Double { amounts.total }

    func amount(for category: VehicleExpenseCategory) -> Double {
        amounts.amount(for: category)
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        amounts.amount(for: bucket)
    }

    init(dayStart: Date, amounts: VehicleExpenseCategoryAmounts) {
        self.dayStart = dayStart
        self.amounts = amounts
    }
}

struct VehicleCategoryCost: Identifiable, Sendable, Equatable {
    let id: String
    let category: VehicleExpenseCategory?
    let amount: Double
    let isTripEstimate: Bool

    /// Localized in the view layer — never resolve strings inside `@ModelActor` loaders.
    @MainActor
    var displayName: String {
        if isTripEstimate {
            return L10n.string("stats.cost.chart.trip_estimate")
        }
        if let category {
            return category.displayName
        }
        return L10n.string("stats.cost.bucket.other")
    }
}

struct VehicleExpenseShare: Identifiable, Sendable, Equatable {
    let id: String
    /// Empty when unassigned — resolve with L10n in the view.
    let storedName: String
    let amount: Double

    static let unassignedID = VehicleDistance.unassignedID

    @MainActor
    var displayName: String {
        if id == Self.unassignedID || storedName.isEmpty {
            return L10n.string("stats.vehicle.unassigned")
        }
        return storedName
    }
}

/// Per-vehicle expense seed for the compare list. Distance is joined later from trip stats.
struct VehicleCompareSeed: Identifiable, Sendable, Equatable {
    let id: String
    let storedName: String
    let iconName: String
    let photoFileName: String?
    let isElectric: Bool
    let amount: Double
    let fuel: Double
    let service: Double
    let insurance: Double
    let casco: Double
    let other: Double

    func amount(for bucket: VehicleCostBucket) -> Double {
        switch bucket {
        case .fuel: fuel
        case .service: service
        case .insurance: insurance
        case .casco: casco
        case .other: other
        }
    }
}

struct VehicleCompareRow: Identifiable, Sendable, Equatable {
    let id: String
    let storedName: String
    let iconName: String
    let photoFileName: String?
    let isElectric: Bool
    let amount: Double
    let distanceMeters: Double
    let fuel: Double
    let service: Double
    let insurance: Double
    let casco: Double
    let other: Double
    let isMostExpensive: Bool

    var costPerKm: Double? {
        let kilometers = distanceMeters / 1000
        guard kilometers > 0, amount > 0 else { return nil }
        return amount / kilometers
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        switch bucket {
        case .fuel: fuel
        case .service: service
        case .insurance: insurance
        case .casco: casco
        case .other: other
        }
    }

    @MainActor
    var displayName: String {
        if id == VehicleExpenseShare.unassignedID || storedName.isEmpty {
            return L10n.string("stats.vehicle.unassigned")
        }
        return storedName
    }
}

enum StatsVehicleCompareBuilder {
    static func rows(
        seeds: [VehicleCompareSeed],
        distances: [VehicleDistance]
    ) -> [VehicleCompareRow] {
        let distanceByID = Dictionary(
            distances.map { ($0.id, $0.distanceMeters) },
            uniquingKeysWith: { first, _ in first }
        )
        let sorted = seeds.sorted { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        let topAmount = sorted.first?.amount ?? 0
        return sorted.map { seed in
            VehicleCompareRow(
                id: seed.id,
                storedName: seed.storedName,
                iconName: seed.iconName,
                photoFileName: seed.photoFileName,
                isElectric: seed.isElectric,
                amount: seed.amount,
                distanceMeters: distanceByID[seed.id] ?? 0,
                fuel: seed.fuel,
                service: seed.service,
                insurance: seed.insurance,
                casco: seed.casco,
                other: seed.other,
                isMostExpensive: seed.amount > 0 && seed.amount == topAmount
            )
        }
    }

    static func barShare(amount: Double, maxAmount: Double) -> Double {
        guard maxAmount > 0, amount > 0 else { return 0 }
        return min(1, amount / maxAmount)
    }
}

struct VehicleCostSnapshot: Sendable, Equatable {
    let months: [VehicleMonthlyCost]
    let days: [VehicleDailyCost]
    let categoryBreakdown: [VehicleCategoryCost]
    let vehicleBreakdown: [VehicleExpenseShare]
    let compareSeeds: [VehicleCompareSeed]
    let total: Double
    let previousTotal: Double
    let fuelTotal: Double
    let serviceTotal: Double
    let insuranceTotal: Double
    let cascoTotal: Double
    let otherTotal: Double

    static let empty = VehicleCostSnapshot(
        months: [],
        days: [],
        categoryBreakdown: [],
        vehicleBreakdown: [],
        compareSeeds: [],
        total: 0,
        previousTotal: 0,
        fuelTotal: 0,
        serviceTotal: 0,
        insuranceTotal: 0,
        cascoTotal: 0,
        otherTotal: 0
    )

    var hasData: Bool { total > 0 || !months.isEmpty || !days.isEmpty }
    var hasCategoryBreakdown: Bool { categoryBreakdown.contains { $0.amount > 0 } }
    var hasVehicleBreakdown: Bool { vehicleBreakdown.contains { $0.amount > 0 } }
    var hasTimelineChart: Bool { !days.isEmpty || !months.isEmpty }

    var expenseTrend: StatsTrend? {
        StatsTrend.make(current: total, previous: previousTotal, polarity: .lowerIsBetter)
    }
}

struct VehicleCostSnapshotRequest: Sendable, Hashable {
    let storeVersion: Int
    let periodStart: Date
    let periodEnd: Date
    /// Previous-period slice for MoM totals. Defaults to an empty window at `periodStart`.
    let compareStart: Date
    let compareEnd: Date
    let selectedVehicleID: UUID?

    init(
        storeVersion: Int,
        periodStart: Date,
        periodEnd: Date,
        selectedVehicleID: UUID?,
        compareStart: Date? = nil,
        compareEnd: Date? = nil
    ) {
        self.storeVersion = storeVersion
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.compareStart = compareStart ?? periodStart
        self.compareEnd = compareEnd ?? periodStart
        self.selectedVehicleID = selectedVehicleID
    }
}
