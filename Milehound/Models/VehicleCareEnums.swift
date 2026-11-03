import Foundation

enum VehicleScheduleKind: String, Codable, CaseIterable, Sendable {
    case service
    case inspection
    case trafficInsurance
    case casco
    case custom

    var defaultTitleKey: StaticString {
        switch self {
        case .service: "vehicles.care.kind.service"
        case .inspection: "vehicles.care.kind.inspection"
        case .trafficInsurance: "vehicles.care.kind.traffic_insurance"
        case .casco: "vehicles.care.kind.casco"
        case .custom: "vehicles.care.kind.custom"
        }
    }

    var defaultTitle: String { L10n.string(defaultTitleKey) }

    /// Positive day-before offsets stored on `VehicleSchedule` (legacy / editor sync).
    /// Actual push stages come from `reminderStages`.
    var defaultReminderOffsets: [Int] {
        switch self {
        case .service, .inspection, .custom:
            return [30, 7]
        case .trafficInsurance, .casco:
            return [7]
        }
    }

    /// Premium push ladder: early / week / due day / single overdue.
    var reminderStages: [CareReminderStage] {
        switch self {
        case .service, .inspection, .custom:
            return [.early, .week, .dueDay, .overdue]
        case .trafficInsurance, .casco:
            return [.week, .dueDay, .overdue]
        }
    }

    var systemImage: String {
        switch self {
        case .service: "wrench.and.screwdriver.fill"
        case .inspection: "seal.fill"
        case .trafficInsurance: "doc.text.fill"
        case .casco: "shield.fill"
        case .custom: "calendar"
        }
    }
}

enum VehicleScheduleIntervalKind: String, Codable, CaseIterable, Sendable {
    case none
    case everyMonths
    case everyYears
    case everyKm
    case whicheverFirst

    var displayName: String {
        switch self {
        case .none: L10n.string("vehicles.care.interval.none")
        case .everyMonths: L10n.string("vehicles.care.interval.months")
        case .everyYears: L10n.string("vehicles.care.interval.years")
        case .everyKm: L10n.string("vehicles.care.interval.km")
        case .whicheverFirst: L10n.string("vehicles.care.interval.whichever_first")
        }
    }
}

/// Picker / new entries use these eleven cases. Legacy raw values still decode via `resolved`.
enum VehicleExpenseCategory: String, Codable, CaseIterable, Sendable {
    case fuel
    case trafficInsurance
    case casco
    case service
    case inspection
    case repair
    case accessory
    case hgs
    case parking
    case mtv
    case other

    /// Legacy stored strings (not in CaseIterable picker).
    private static let legacyInsurance = "insurance"
    private static let legacyTax = "tax"
    private static let legacyParts = "parts"

    var displayName: String {
        switch self {
        case .fuel: L10n.string("vehicles.care.expense.fuel")
        case .trafficInsurance: L10n.string("vehicles.care.expense.traffic_insurance")
        case .casco: L10n.string("vehicles.care.expense.casco")
        case .service: L10n.string("vehicles.care.expense.service")
        case .inspection: L10n.string("vehicles.care.expense.inspection")
        case .repair: L10n.string("vehicles.care.expense.repair")
        case .accessory: L10n.string("vehicles.care.expense.accessory")
        case .hgs: L10n.string("vehicles.care.expense.hgs")
        case .parking: L10n.string("vehicles.care.expense.parking")
        case .mtv: L10n.string("vehicles.care.expense.mtv")
        case .other: L10n.string("vehicles.care.expense.other")
        }
    }

    var systemImage: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .trafficInsurance: "doc.text.fill"
        case .casco: "shield.fill"
        case .service: "wrench.and.screwdriver.fill"
        case .inspection: "seal.fill"
        case .repair: "hammer.fill"
        case .accessory: "bag.fill"
        case .hgs: "road.lanes"
        case .parking: "parkingsign"
        case .mtv: "building.columns.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Buckets used by Stats stacked charts.
    var costBucket: VehicleCostBucket {
        switch self {
        case .fuel: .fuel
        case .service, .repair: .service
        case .trafficInsurance: .insurance
        case .casco: .casco
        case .inspection, .accessory, .hgs, .parking, .mtv, .other: .other
        }
    }

    static func resolved(fromRaw raw: String) -> VehicleExpenseCategory {
        if let direct = VehicleExpenseCategory(rawValue: raw) { return direct }
        switch raw {
        case legacyParts: return .accessory
        case legacyInsurance: return .trafficInsurance
        case legacyTax: return .mtv
        default: return .other
        }
    }

    static func suggested(for kind: VehicleScheduleKind) -> VehicleExpenseCategory {
        switch kind {
        case .service: .service
        case .inspection: .inspection
        case .trafficInsurance: .trafficInsurance
        case .casco: .casco
        case .custom: .other
        }
    }
}

enum VehicleExpenseSource: String, Codable, Sendable {
    case manual
    case tripEstimate
}

enum VehicleCostBucket: String, CaseIterable, Sendable {
    case fuel
    case service
    case insurance
    case casco
    case other

    var displayName: String {
        switch self {
        case .fuel: L10n.string("stats.cost.bucket.fuel")
        case .service: L10n.string("stats.cost.bucket.service")
        case .insurance: L10n.string("stats.cost.bucket.insurance")
        case .casco: L10n.string("stats.cost.bucket.casco")
        case .other: L10n.string("stats.cost.bucket.other")
        }
    }
}

/// Runtime-only due state — never persisted.
enum VehicleCareDueState: Equatable, Sendable {
    case upcoming(daysLeft: Int)
    case dueToday
    case overdue(days: Int)
    /// `approaching` is true inside the interval-scaled window (chip and push).
    case upcomingKm(kmLeft: Int, approaching: Bool)
    case overdueKm(kmOver: Int)
    case noDate

    var sortPriority: Int {
        switch self {
        case .overdue, .overdueKm: 0
        case .dueToday: 1
        case .upcoming(let days): days <= 30 ? 2 : 3
        case .upcomingKm(_, let approaching): approaching ? 2 : 3
        case .noDate: 4
        }
    }

    var isUrgent: Bool {
        switch self {
        case .overdue, .overdueKm, .dueToday: true
        case .upcoming(let days): days <= 30
        case .upcomingKm(_, let approaching): approaching
        case .noDate: false
        }
    }

    var isOverdue: Bool {
        switch self {
        case .overdue, .overdueKm: true
        case .upcoming, .dueToday, .upcomingKm, .noDate: false
        }
    }

    /// Lower comes first when two states share `sortPriority`.
    var urgencySortKey: Int {
        switch self {
        case .overdue(let days): -days
        case .overdueKm(let km): -km
        case .dueToday: 0
        case .upcoming(let days): days
        case .upcomingKm(let km, _): km
        case .noDate: Int.max
        }
    }
}

struct VehicleDueItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let scheduleID: UUID
    let vehicleID: UUID
    let vehicleName: String
    let kind: VehicleScheduleKind
    let title: String
    let dueDate: Date?
    var dueOdometerKm: Int? = nil
    var kmLeft: Int? = nil
    let state: VehicleCareDueState

    var daysSortKey: Int { state.urgencySortKey }
}
