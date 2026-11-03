import Foundation
import SwiftData

/// Pre-aggregated totals for one (day, category, vehicle) combination.
///
/// Statistics over a period otherwise scale with the number of trips in it. Rolling trips up by
/// day makes them scale with the number of *days* instead: a typical driver produces a handful of
/// rows per day, so a decade of history is a few thousand rows rather than a hundred thousand.
///
/// This is a derived cache. It is rebuilt from `Trip` whenever it might have drifted, and nothing
/// here is a source of truth for user data.
@Model
final class TripDailyRollup {
    /// Midnight, local time, of the day the trips started.
    var dayStart: Date = Date()
    var categoryID: String = ""
    /// Empty string rather than `nil` so the key stays comparable inside `#Predicate`.
    var vehicleKey: String = ""
    var distanceMeters: Double = 0
    var duration: TimeInterval = 0
    var nightDistanceMeters: Double = 0
    var trackedDistanceMeters: Double = 0
    var estimatedFuelCost: Double = 0
    /// Sum of each trip's GPS-adjusted estimated fuel cost for the day.
    var dynamicFuelCost: Double = 0
    /// `liquid` or `electric` so Stats never sums litres with kWh.
    var fuelUnitKey: String = "liquid"
    var dynamicFuelVolume: Double = 0
    var dynamicFuelVolumeDistanceMeters: Double = 0
    var fuelEfficiencyProduct: Double = 0
    var fuelEfficiencyWeight: Double = 0
    var fuelSpeedDeltaVolume: Double = 0
    var fuelIdleVolume: Double = 0
    var fuelTransientVolume: Double = 0
    var fuelColdStartVolume: Double = 0
    var tripCount: Int = 0
    var maxSpeedMps: Double = 0
    var stopDurationSeconds: Double = 0
    /// Sum of each trip's cruise-bucket duration (weight for the day's cruise speed).
    var cruiseWeightSeconds: Double = 0
    /// Sum of (cruiseSpeedKmh × cruiseDurationSeconds) across trips.
    var cruiseSpeedProduct: Double = 0
    /// Sum of each trip's moving duration that had a most-common speed (weight).
    var mostCommonWeightSeconds: Double = 0
    /// Sum of (mostCommonSpeedKmh × cruiseDurationSeconds) across trips.
    var mostCommonSpeedProduct: Double = 0

    init(
        dayStart: Date,
        categoryID: String,
        vehicleKey: String,
        fuelUnitKey: String = "liquid"
    ) {
        self.dayStart = dayStart
        self.categoryID = categoryID
        self.vehicleKey = vehicleKey
        self.fuelUnitKey = fuelUnitKey
    }

    static func vehicleKey(for vehicleID: UUID?) -> String {
        vehicleID?.uuidString ?? ""
    }
}
