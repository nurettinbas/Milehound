import CoreLocation
import Foundation
import SwiftData

/// Loads a trip's GPS points and builds the decimated display path off the main actor.
/// Original points are never modified — this is a pure read-path transform.
@ModelActor
actor TripRoutePathWorker {
    func build(tripID: UUID) async -> TripRoutePathPayload? {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.id == tripID }
        )
        descriptor.fetchLimit = 1
        guard let trip = (try? modelContext.fetch(descriptor))?.first else { return nil }

        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        let samples = RouteDisplayPath.samples(from: trip.sortedPoints)
        let pieces = RouteDisplayPath.displaySegments(samples: samples)

        // Drop the faulted relationship so this actor does not retain every GPS point.
        trip.invalidatePointCaches()

        return TripRoutePathPayload.from(samples: pieces, fingerprint: fingerprint)
    }
}
