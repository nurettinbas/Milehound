import Foundation

enum AchievementID: String, CaseIterable, Sendable {
    case firstTrip = "first.trip"
    case distance100 = "distance.100"
    case distance1000 = "distance.1000"
    case distance10000 = "distance.10000"
    case distance100000 = "distance.100000"
    case business10 = "business.10"
    case business50 = "business.50"
    case business100 = "business.100"
    case streak7 = "streak.7"
    case streak30 = "streak.30"
    case streak100 = "streak.100"
    case cities10 = "cities.10"
    case cities25 = "cities.25"
    case cities50 = "cities.50"
    case nightOwl = "night.owl"
    case night1000 = "night.1000"
    case routesRegular = "routes.regular"
    case routes25 = "routes.25"
    case trips50 = "trips.50"
    case trips250 = "trips.250"
    case hours24 = "hours.24"
    case hours100 = "hours.100"
    case longhaul1 = "longhaul.1"
    case longhaul10 = "longhaul.10"
    case dawn10 = "dawn.10"
    case dawn50 = "dawn.50"
    case weekend10 = "weekend.10"
    case weekend50 = "weekend.50"
    case fleet2 = "fleet.2"
    case countries2 = "countries.2"

    var threshold: Double {
        switch self {
        case .firstTrip: 1
        case .distance100: 100_000
        case .distance1000: 1_000_000
        case .distance10000: 10_000_000
        case .distance100000: 100_000_000
        case .business10: 10
        case .business50: 50
        case .business100: 100
        case .streak7: 7
        case .streak30: 30
        case .streak100: 100
        case .cities10: 10
        case .cities25: 25
        case .cities50: 50
        case .nightOwl: 100_000
        case .night1000: 1_000_000
        case .routesRegular: 10
        case .routes25: 25
        case .trips50: 50
        case .trips250: 250
        case .hours24: 24
        case .hours100: 100
        case .longhaul1: 1
        case .longhaul10: 10
        case .dawn10: 10
        case .dawn50: 50
        case .weekend10: 10
        case .weekend50: 50
        case .fleet2: 2
        case .countries2: 2
        }
    }

    var systemImage: String {
        switch self {
        case .firstTrip: "flag.checkered"
        case .distance100, .distance1000, .distance10000, .distance100000:
            "point.bottomleft.forward.to.point.topright.scurvepath"
        case .business10: "briefcase"
        case .business50: "briefcase.fill"
        case .business100: "building.columns.fill"
        case .streak7: "flame"
        case .streak30: "flame.fill"
        case .streak100: "burst.fill"
        case .cities10: "building.2"
        case .cities25: "building.2.fill"
        case .cities50: "building.columns"
        case .nightOwl: "moon.stars.fill"
        case .night1000: "moon.fill"
        case .routesRegular: "arrow.triangle.swap"
        case .routes25: "arrow.2.squarepath"
        case .trips50: "steeringwheel"
        case .trips250: "gauge.with.dots.needle.67percent"
        case .hours24: "hourglass"
        case .hours100: "hourglass.bottomhalf.filled"
        case .longhaul1: "car.side.fill"
        case .longhaul10: "mountain.2.fill"
        case .dawn10: "sunrise"
        case .dawn50: "sunrise.fill"
        case .weekend10: "calendar"
        case .weekend50: "calendar.badge.clock"
        case .fleet2: "car.2.fill"
        case .countries2: "globe.europe.africa.fill"
        }
    }

    /// Canvas km medals share a backup SF name; every other ID must be unique.
    var usesCanvasGlyph: Bool { family == .distance }

    var titleKey: String { "premium.achievement.\(rawValue).title" }
    var bodyKey: String { "premium.achievement.\(rawValue).body" }

    var predecessor: AchievementID? {
        switch self {
        case .distance1000: .distance100
        case .distance10000: .distance1000
        case .distance100000: .distance10000
        case .business50: .business10
        case .business100: .business50
        case .streak30: .streak7
        case .streak100: .streak30
        case .cities25: .cities10
        case .cities50: .cities25
        case .night1000: .nightOwl
        case .routes25: .routesRegular
        case .trips250: .trips50
        case .hours100: .hours24
        case .longhaul10: .longhaul1
        case .dawn50: .dawn10
        case .weekend50: .weekend10
        default: nil
        }
    }

    var listsWhilePredecessorLocked: Bool {
        family == .distance
    }

    var sortOrder: Int {
        switch self {
        case .firstTrip: 0
        case .distance100: 1
        case .distance1000: 2
        case .distance10000: 3
        case .distance100000: 4
        case .business10: 5
        case .business50: 6
        case .business100: 7
        case .streak7: 8
        case .streak30: 9
        case .streak100: 10
        case .cities10: 11
        case .cities25: 12
        case .cities50: 13
        case .nightOwl: 14
        case .night1000: 15
        case .routesRegular: 16
        case .routes25: 17
        case .trips50: 18
        case .trips250: 19
        case .hours24: 20
        case .hours100: 21
        case .longhaul1: 22
        case .longhaul10: 23
        case .dawn10: 24
        case .dawn50: 25
        case .weekend10: 26
        case .weekend50: 27
        case .fleet2: 28
        case .countries2: 29
        }
    }

    var family: AchievementFamily {
        switch self {
        case .firstTrip: .firstTrip
        case .distance100, .distance1000, .distance10000, .distance100000: .distance
        case .business10, .business50, .business100: .business
        case .streak7, .streak30, .streak100: .streak
        case .cities10, .cities25, .cities50: .cities
        case .nightOwl, .night1000: .night
        case .routesRegular, .routes25: .routes
        case .trips50, .trips250: .trips
        case .hours24, .hours100: .hours
        case .longhaul1, .longhaul10: .longhaul
        case .dawn10, .dawn50: .dawn
        case .weekend10, .weekend50: .weekend
        case .fleet2: .fleet
        case .countries2: .countries
        }
    }

    var familyTier: Int {
        switch self {
        case .distance1000, .business50, .streak30, .cities25,
             .night1000, .routes25, .trips250, .hours100, .longhaul10, .dawn50, .weekend50:
            1
        case .distance10000, .business100, .streak100, .cities50:
            2
        case .distance100000:
            3
        default:
            0
        }
    }

    var progressKind: AchievementProgressKind {
        switch self {
        case .distance100, .distance1000, .distance10000, .distance100000, .nightOwl, .night1000:
            .distanceMeters
        default:
            .count
        }
    }

    var medalMaterial: AchievementMedalMaterial? {
        switch self {
        case .distance100: .silver
        case .distance1000: .gold
        case .distance10000: .platinum
        case .distance100000: .diamond
        default: nil
        }
    }
}

enum AchievementMedalMaterial: String, Equatable, Sendable {
    case silver
    case gold
    case platinum
    case diamond
}

enum AchievementFamily: String, CaseIterable, Sendable {
    case firstTrip
    case distance
    case business
    case streak
    case cities
    case night
    case routes
    case trips
    case hours
    case longhaul
    case dawn
    case weekend
    case fleet
    case countries
}

enum AchievementProgressKind: Sendable {
    case distanceMeters
    case count
}

enum AchievementProgressCaption {
    static func text(for item: AchievementDisplay) -> String {
        text(current: item.currentValue, threshold: item.threshold, kind: item.id.progressKind)
    }

    static func text(current: Double, threshold: Double, kind: AchievementProgressKind) -> String {
        switch kind {
        case .distanceMeters:
            "\(DateFormatters.formatDistance(current)) / \(DateFormatters.formatDistance(threshold))"
        case .count:
            "\(Int(current.rounded())) / \(Int(threshold.rounded()))"
        }
    }
}

struct AchievementDisplay: Identifiable, Equatable, Sendable {
    let id: AchievementID
    let currentValue: Double
    let unlockedAt: Date?
    let needsCelebration: Bool

    var isUnlocked: Bool { unlockedAt != nil }
    var threshold: Double { id.threshold }
    var progress: Double {
        guard threshold > 0 else { return isUnlocked ? 1 : 0 }
        return min(1, currentValue / threshold)
    }

    static func listOrder(_ lhs: AchievementDisplay, _ rhs: AchievementDisplay) -> Bool {
        if lhs.isUnlocked != rhs.isUnlocked { return lhs.isUnlocked && !rhs.isUnlocked }
        return lhs.id.sortOrder < rhs.id.sortOrder
    }
}
