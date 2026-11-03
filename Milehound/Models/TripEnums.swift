import Foundation

enum TripCategory: String, Codable, CaseIterable {
    case personal
    case business

    var displayName: String {
        switch self {
        case .personal: L10n.categoryPersonal
        case .business: L10n.categoryBusiness
        }
    }
}

/// How the trip's current category was chosen. `nil` storage means legacy / default.
enum TripCategoryOrigin: String, Codable {
    case `default`
    case user
    case accepted
    case dismissed

    var blocksSuggestion: Bool {
        switch self {
        case .user, .accepted, .dismissed: true
        case .default: false
        }
    }

    var countsTowardLearning: Bool {
        switch self {
        case .user, .accepted: true
        case .default, .dismissed: false
        }
    }
}

enum TripCategorySuggestionReason: String, Codable {
    case route
    case place
    case hours
}

struct TripCategoryWorkHours: Equatable, Sendable {
    var startHour: Int
    var endHour: Int

    static let `default` = TripCategoryWorkHours(startHour: 9, endHour: 18)

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        return hour >= startHour || hour < endHour
    }
}

struct TripCategorySuggestion: Equatable, Sendable {
    let categoryID: String
    let reason: TripCategorySuggestionReason
    let confidence: Double
}

enum GeocodeStatus: String, Codable {
    case pending
    case complete
    case failed
}

enum SavedPlaceKind: String, Codable, CaseIterable {
    case home
    case work
    case other

    var displayName: String {
        switch self {
        case .home: L10n.placeHome
        case .work: L10n.placeWork
        case .other: L10n.placeOther
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .work: "building.2.fill"
        case .other: "mappin.circle.fill"
        }
    }
}

enum FuelMeasurementSource: String, Codable, Sendable {
    case catalogSnapshot
    case userMeasured
}

enum VehicleFuelType: String, Codable, CaseIterable {
    case petrol
    case diesel
    case lpg
    case hybrid
    case electric

    var displayName: String {
        switch self {
        case .petrol: L10n.fuelPetrol
        case .diesel: L10n.fuelDiesel
        case .lpg: L10n.fuelLpg
        case .hybrid: L10n.fuelHybrid
        case .electric: L10n.fuelElectric
        }
    }
}

enum VehicleIconOption: String, CaseIterable, Identifiable {
    case car = "car.fill"
    case carSide = "car.side.fill"
    case carRear = "car.rear.fill"
    case carFrontWaves = "car.front.waves.up.fill"
    case carCircle = "car.circle.fill"
    case cars = "car.2.fill"
    case electric = "bolt.car.fill"
    case suv = "suv.side.fill"
    case convertible = "convertible.side.fill"
    case pickup = "truck.pickup.side.fill"
    case truck = "truck.box.fill"
    case bus = "bus.fill"
    case doubleDecker = "bus.doubledecker.fill"
    case tram = "tram.fill"
    case cableCar = "cablecar.fill"
    case scooter = "scooter"
    case bicycle = "bicycle"
    case bicycleCircle = "bicycle.circle.fill"
    case mopedOutline = "moped"
    case moped = "moped.fill"
    case motorcycleOutline = "motorcycle"
    case motorcycle = "motorcycle.fill"

    var id: String { rawValue }

    /// Fixed side-profile mark when no vehicle photo is set (faces left in SF Symbols → flip `-1`).
    static let `default`: VehicleIconOption = .carSide

    static var available: [VehicleIconOption] {
        allCases.filter(\.isAvailable)
    }

    var isAvailable: Bool {
        switch self {
        case .convertible, .moped, .mopedOutline, .motorcycle, .motorcycleOutline:
            if #available(iOS 18.0, *) { return true }
            return false
        default:
            return true
        }
    }

    /// Maps stored / legacy icon names to a known option; unknown values → `.default`.
    static func resolved(_ iconName: String?) -> VehicleIconOption {
        guard let iconName else { return .default }
        if let option = VehicleIconOption(rawValue: iconName), option.isAvailable {
            return option
        }
        return .default
    }

}
