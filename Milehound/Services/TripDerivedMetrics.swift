import Foundation
import SwiftData

/// Computes the values that read paths would otherwise derive by walking every GPS point.
///
/// Stats, the trip list and search all used to fault a trip's whole `points` relationship just to
/// read its first coordinate or its night-driving share. Writing those values once, at the few
/// places where a trip's points actually change, keeps those reads O(1).
enum TripDerivedMetrics {
    /// Recomputes every field derived from `points`. Safe to call repeatedly.
    /// - Parameter fuelType: Used for idle + regen factors when `vehicle` is nil.
    /// - Parameter vehicle: Preferred source of consumption, unit price, and fuel type.
    static func recompute(
        for trip: Trip,
        fuelType: VehicleFuelType = .petrol,
        vehicle: VehicleProfile? = nil
    ) {
        recomputeEndpoints(for: trip)
        recomputeNightDistance(for: trip)
        recomputeSpeedProfile(for: trip)
        recomputeFuel(for: trip, fuelType: fuelType, vehicle: vehicle)
    }

    /// Full refresh including the search index, which additionally depends on saved places.
    static func recompute(
        for trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        fuelType: VehicleFuelType = .petrol,
        vehicle: VehicleProfile? = nil
    ) {
        recompute(for: trip, fuelType: fuelType, vehicle: vehicle)
        PlaceMatchingService.matchPlaces(for: trip, places: places, privacyRadius: privacyRadius)
        refreshSearchIndex(for: trip, places: places, privacyRadius: privacyRadius)
    }

    static func recomputeEndpoints(for trip: Trip) {
        let points = trip.sortedPoints
        if let first = points.first {
            trip.startLatitude = first.latitude
            trip.startLongitude = first.longitude
        } else {
            trip.startLatitude = nil
            trip.startLongitude = nil
        }
        if let last = points.last {
            trip.endLatitude = last.latitude
            trip.endLongitude = last.longitude
        } else {
            trip.endLatitude = nil
            trip.endLongitude = nil
        }
    }

    static func recomputeNightDistance(for trip: Trip) {
        let share = StatsViewModel.walkNightDistanceShare(for: trip)
        trip.nightDistanceMeters = share?.nightMeters ?? 0
        trip.trackedDistanceMeters = share?.trackedMeters ?? 0
    }

    /// Writes cruise / stop / most-common totals so stats never have to walk points. Always
    /// sets every field (0 when there is nothing to report) so backfill can treat `nil` as pending.
    static func recomputeSpeedProfile(for trip: Trip) {
        let profile = TripSpeedProfile.compute(points: trip.sortedPoints)
        trip.cruiseSpeedKmh = profile.cruiseSpeedKmh ?? 0
        trip.cruiseDurationSeconds = profile.cruiseDurationSeconds
        trip.stopDurationSeconds = profile.stopDurationSeconds
        trip.mostCommonSpeedKmh = profile.mostCommonSpeedKmh ?? 0
    }

    /// Writes trip-specific GPS-adjusted fuel cost. Always sets a non-nil value (0 when empty) so
    /// backfill can treat `nil` as pending. Does not rewrite `estimatedFuelCost` (avg).
    static func recomputeFuel(
        for trip: Trip,
        fuelType: VehicleFuelType = .petrol,
        vehicle: VehicleProfile? = nil
    ) {
        let resolvedType = trip.fuelTypeSnapshot
            ?? vehicle?.fuelType
            ?? fuelType
        if let vehicle {
            trip.fuelTypeSnapshot = vehicle.fuelType
        } else if trip.fuelTypeSnapshot == nil {
            trip.fuelTypeSnapshot = fuelType
        }
        let c0 = FuelCostCalculator.resolvedConsumption(
            tripConsumption: trip.fuelConsumptionPer100,
            vehicle: vehicle
        )
        let unitPrice = FuelCostCalculator.resolvedUnitPrice(
            tripUnitPrice: trip.fuelUnitPrice,
            vehicle: vehicle,
            fuelType: trip.fuelTypeSnapshot ?? resolvedType
        )
        // Do not feed `TripStop` pins into idle exclusion. Auto-detected parking is written
        // after two minutes below 2 km/h — the same signature as a long light or queue — and
        // the recorder drops stationary fixes, so the pin sits on a GPS hole. Treating that as
        // engine-off made short city trips report *below* catalog average.
        let estimate = TripFuelEstimate.compute(
            points: trip.sortedPoints,
            distanceMeters: trip.distanceMeters,
            consumptionPer100: c0,
            unitPrice: unitPrice,
            fuelType: trip.fuelTypeSnapshot ?? resolvedType,
            durationSeconds: trip.duration,
            thermal: thermalInput(for: trip),
            calibration: TripFuelCalibrationService.snapshot(
                for: trip.vehicleID,
                in: trip.modelContext
            )
        )
        trip.dynamicFuelCost = estimate.dynamicCost
        trip.dynamicFuelVolume = estimate.dynamicVolume
        trip.dynamicFuelRatePer100 = estimate.ratePer100
        trip.fuelEfficiencyScore = estimate.efficiencyScore
        trip.fuelEstimateConfidence = estimate.confidence
        trip.fuelSpeedDeltaVolume = estimate.breakdown.speedDelta
        trip.fuelIdleVolume = estimate.breakdown.idleLitres
        trip.fuelTransientVolume = estimate.breakdown.transientDelta
        trip.fuelColdStartVolume = estimate.breakdown.coldStartLitres
        trip.fuelTrafficScore = estimate.trafficScore
        trip.dynamicFuelModelVersion = TripFuelEstimate.currentModelVersion
    }

    static func thermalInput(for trip: Trip) -> FuelThermalInput {
        guard let previous = previousCompletedTrip(for: trip) else {
            return .unknown(startedAt: trip.startedAt)
        }
        let movingSeconds = previous.cruiseDurationSeconds ?? previous.duration ?? 0
        return FuelThermalInput(
            previousEndedAt: previous.endedAt,
            previousMovingMinutes: movingSeconds / 60,
            previousDistanceKm: previous.distanceMeters / 1_000,
            tripStartedAt: trip.startedAt,
            hasVehicleContinuity: true
        )
    }

    private static func previousCompletedTrip(for trip: Trip) -> Trip? {
        guard let context = trip.modelContext, let vehicleID = trip.vehicleID else { return nil }
        let start = trip.startedAt
        let tripID = trip.id
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate {
                $0.vehicleID == vehicleID
                    && $0.endedAt != nil
                    && $0.id != tripID
            },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        return (try? context.fetch(descriptor))?.first { candidate in
            guard let ended = candidate.endedAt else { return false }
            return ended <= start
        }
    }

    /// Rewrites stored GPS fuel for a completed trip the user is looking at, so a stale
    /// `dynamicFuelCost` does not sit on screen until launch backfill finishes (or if that
    /// walk already marked itself done on an older formula). Avg fuel is untouched.
    @MainActor
    @discardableResult
    static func refreshPersistedFuel(for trip: Trip, in context: ModelContext) -> Bool {
        guard trip.endedAt != nil else { return false }
        let previous = TripRollupService.snapshot(of: trip)
        let before = trip.dynamicFuelCost
        let beforeVolume = trip.dynamicFuelVolume
        let vehicle = trip.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: context) }
        recomputeFuel(
            for: trip,
            fuelType: vehicle?.fuelType ?? trip.fuelTypeSnapshot ?? .petrol,
            vehicle: vehicle
        )
        guard trip.dynamicFuelCost != before || trip.dynamicFuelVolume != beforeVolume else { return false }
        TripRollupService.update(trip, from: previous, in: context)
        return true
    }

    /// Mirrors the fields `TripListViewModel.matchesSearch` scans, folded once up front so
    /// filtering never has to resolve place names or coordinates per keystroke.
    static func refreshSearchIndex(for trip: Trip, places: [SavedPlace], privacyRadius: Double) {
        trip.searchIndex = SearchFolding.fold(
            TripListViewModel.searchCorpus(for: trip, places: places, privacyRadius: privacyRadius)
        )
    }
}
