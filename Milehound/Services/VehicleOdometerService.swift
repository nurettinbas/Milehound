import Foundation
import SwiftData

/// Reading captured before a trip's distance, start, or vehicle changes.
struct TripOdometerSnapshot: Equatable, Sendable {
    var meters: Double
    var startedAt: Date
    var vehicleID: UUID?
}

/// Keeps `VehicleProfile.currentOdometerKm` equal to the last typed reading plus later trips.
/// A trip counts only when it has a vehicle and started on or after that reading.
enum VehicleOdometerService {
    static let readingRange = 0...2_000_000

    static func parseReading(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 7,
              trimmed.allSatisfy(\.isNumber),
              let value = Int(trimmed),
              readingRange.contains(value)
        else { return nil }
        return value
    }

    /// Copies an existing reading into the anchor once. Does not add trips that already happened.
    static func backfillAnchorsIfNeeded(in context: ModelContext, now: Date = Date()) {
        let vehicles = (try? context.fetch(FetchDescriptor<VehicleProfile>())) ?? []
        var changed = false
        for vehicle in vehicles where vehicle.odometerAnchorKm == nil && vehicle.currentOdometerKm != nil {
            vehicle.odometerAnchorKm = vehicle.currentOdometerKm
            vehicle.odometerAnchorAt = now
            vehicle.odometerTripMetersSinceAnchor = 0
            changed = true
        }
        guard changed else { return }
        try? context.save()
    }

    static func tripAdded(_ trip: Trip, in context: ModelContext) {
        guard let vehicle = vehicle(for: trip.vehicleID, in: context) else { return }
        apply(meters: max(0, trip.distanceMeters), startedAt: trip.startedAt, to: vehicle)
    }

    static func tripRemoved(_ trip: Trip, in context: ModelContext) {
        guard let vehicle = vehicle(for: trip.vehicleID, in: context) else { return }
        apply(meters: -max(0, trip.distanceMeters), startedAt: trip.startedAt, to: vehicle)
    }

    static func tripUpdated(_ trip: Trip, previous: TripOdometerSnapshot, in context: ModelContext) {
        let sameVehicle = previous.vehicleID == trip.vehicleID
        let sameStart = previous.startedAt == trip.startedAt
        if sameVehicle && sameStart {
            let delta = trip.distanceMeters - previous.meters
            guard delta != 0, let vehicle = vehicle(for: trip.vehicleID, in: context) else { return }
            apply(meters: delta, startedAt: trip.startedAt, to: vehicle)
            return
        }
        if let vehicle = vehicle(for: previous.vehicleID, in: context) {
            apply(meters: -max(0, previous.meters), startedAt: previous.startedAt, to: vehicle)
        }
        tripAdded(trip, in: context)
    }

    /// Manual reading wins. Trips that started earlier are left out; later trips add on top.
    static func setReading(km: Int, at date: Date = Date(), vehicle: VehicleProfile, in context: ModelContext) {
        guard readingRange.contains(km) else { return }
        vehicle.odometerAnchorKm = km
        vehicle.odometerAnchorAt = date
        recompute(vehicle, in: context)
    }

    static func clearReading(_ vehicle: VehicleProfile) {
        vehicle.odometerAnchorKm = nil
        vehicle.odometerAnchorAt = nil
        vehicle.odometerTripMetersSinceAnchor = nil
        vehicle.currentOdometerKm = nil
    }

    /// Full sum of this vehicle's trips. Used when the anchor changes or after a merge.
    static func recompute(_ vehicle: VehicleProfile, in context: ModelContext) {
        guard let anchorAt = vehicle.odometerAnchorAt, vehicle.odometerAnchorKm != nil else {
            vehicle.odometerTripMetersSinceAnchor = nil
            return
        }
        let vehicleID = vehicle.id
        let trips = (try? context.fetch(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.vehicleID == vehicleID }
        ))) ?? []
        var meters = 0.0
        for trip in trips where trip.startedAt >= anchorAt {
            meters += max(0, trip.distanceMeters)
        }
        vehicle.odometerTripMetersSinceAnchor = meters
        publish(vehicle)
    }

    private static func apply(meters: Double, startedAt: Date, to vehicle: VehicleProfile) {
        guard let anchorAt = vehicle.odometerAnchorAt, vehicle.odometerAnchorKm != nil else { return }
        guard startedAt >= anchorAt else { return }
        let next = max(0, (vehicle.odometerTripMetersSinceAnchor ?? 0) + meters)
        vehicle.odometerTripMetersSinceAnchor = next
        publish(vehicle)
    }

    private static func publish(_ vehicle: VehicleProfile) {
        guard let anchor = vehicle.odometerAnchorKm else {
            vehicle.currentOdometerKm = nil
            return
        }
        let meters = max(0, vehicle.odometerTripMetersSinceAnchor ?? 0)
        vehicle.odometerTripMetersSinceAnchor = meters
        vehicle.currentOdometerKm = anchor + Int((meters / 1000).rounded(.down))
    }

    private static func vehicle(for id: UUID?, in context: ModelContext) -> VehicleProfile? {
        guard let id else { return nil }
        return VehicleResolver.vehicle(withID: id, in: context)
    }
}
