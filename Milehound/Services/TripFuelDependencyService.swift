import Foundation
import SwiftData

/// When a trip’s time, distance, duration, or vehicle changes, the next trip’s cold-start soak
/// is stale. Only the immediate successor needs a recompute.
enum TripFuelDependencyService {
    static func invalidateSuccessor(of trip: Trip, in context: ModelContext) {
        guard let successor = successor(of: trip, in: context) else { return }
        recompute(successor, in: context)
    }

    /// Call after the predecessor has already been deleted or unlinked.
    static func recompute(_ trip: Trip, in context: ModelContext) {
        let previous = TripRollupDelta.snapshot(of: trip)
        let vehicle = trip.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: context) }
        TripDerivedMetrics.recomputeFuel(
            for: trip,
            fuelType: vehicle?.fuelType ?? trip.fuelTypeSnapshot ?? .petrol,
            vehicle: vehicle
        )
        TripRollupDelta.update(trip, from: previous, in: context)
    }

    static func successor(of trip: Trip, in context: ModelContext) -> Trip? {
        guard let vehicleID = trip.vehicleID else { return nil }
        let start = trip.endedAt ?? trip.startedAt
        let tripID = trip.id
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate {
                $0.vehicleID == vehicleID
                    && $0.endedAt != nil
                    && $0.startedAt >= start
                    && $0.id != tripID
            },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
