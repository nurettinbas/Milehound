import Foundation
import SwiftData

@MainActor
enum TripCleanupService {
    static func cleanupOldTrips(in context: ModelContext, olderThanDays days: Int) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let trips = TripStore.completedBefore(cutoff, from: context)
        for trip in trips {
            TravelJournalTotals.handleTripDeletion(trip, in: context)
            let successor = TripFuelDependencyService.successor(of: trip, in: context)
            TripRollupService.remove(trip, in: context)
            VehicleOdometerService.tripRemoved(trip, in: context)
            context.delete(trip)
            if let successor {
                TripFuelDependencyService.recompute(successor, in: context)
            }
        }
        try context.save()
        if !trips.isEmpty {
            VehicleCareNotificationScheduler.evaluateKmReminders(in: context)
        }
        return trips.count
    }
}
