import Foundation
import SwiftData

enum TripRecoveryService {
    static let staleThreshold: TimeInterval = 24 * 60 * 60

    struct OrphanTrip: Identifiable {
        let id: UUID
        let trip: Trip
        let lastActivity: Date
        let isStale: Bool
    }

    @MainActor
    static func findOrphanTrips(in context: ModelContext) -> [OrphanTrip] {
        var results: [OrphanTrip] = []
        results.reserveCapacity(4)

        for trip in TripStore.orphansNewestFirst(from: context) {
            let lastPoint = trip.sortedPoints.last?.timestamp ?? trip.startedAt
            let lastActivity = max(lastPoint, trip.startedAt)
            let isStale = Date().timeIntervalSince(lastActivity) >= staleThreshold
            results.append(
                OrphanTrip(id: trip.id, trip: trip, lastActivity: lastActivity, isStale: isStale)
            )
        }

        return results
    }

    @MainActor
    static func scheduleOrphanStaleNotifications(
        for orphans: [OrphanTrip],
        excludingTripID: UUID? = nil
    ) {
        for orphan in orphans where !orphan.isStale && orphan.id != excludingTripID {
            TripNotificationService.scheduleOrphanStaleNotification(
                tripID: orphan.id,
                lastActivity: orphan.lastActivity
            )
        }
    }

    @MainActor
    static func scheduleOrphanStaleNotifications(
        in context: ModelContext,
        excludingTripID: UUID? = nil
    ) {
        scheduleOrphanStaleNotifications(
            for: findOrphanTrips(in: context),
            excludingTripID: excludingTripID
        )
    }

    @MainActor
    static func finalizeStaleOrphans(in context: ModelContext) {
        for orphan in findOrphanTrips(in: context) where orphan.isStale {
            TripNotificationService.cancelOrphanStaleNotification(tripID: orphan.id)
            finalizeOrphan(orphan.trip, in: context, saveTrip: true)
        }
    }

    @MainActor
    @discardableResult
    static func finalizeOrphan(_ trip: Trip, in context: ModelContext, saveTrip: Bool) -> Bool {
        TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)
        if trip.endedAt != nil {
            return true
        }
        trip.endedAt = trip.sortedPoints.last?.timestamp ?? Date()
        if saveTrip {
            trip.geocodeStatus = .pending
            let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
            let vehicle = trip.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: context) }
            TripDerivedMetrics.recompute(
                for: trip,
                places: places,
                privacyRadius: AppSettings.shared.privacyRadiusMeters,
                fuelType: vehicle?.fuelType ?? .petrol,
                vehicle: vehicle
            )
            TripRollupService.add(trip, in: context)
            VehicleOdometerService.tripAdded(trip, in: context)
        } else {
            context.delete(trip)
        }
        do {
            try context.save()
            if saveTrip {
                VehicleCareNotificationScheduler.evaluateKmReminders(for: trip.vehicleID, in: context)
                PersonalRecordToast.presentIfNeeded(
                    for: trip,
                    in: context,
                    timing: .followingCurrent
                )
                let tripUUID = trip.id
                let container = context.container
                Task { @MainActor in
                    await TripPostProcessor.process(tripUUID: tripUUID, container: container)
                }
                TripStore.syncWidgetWeekDistance(in: context)
            }
            return true
        } catch {
            AppErrorPresenter.shared.present(L10n.orphanSaveFailed(error.localizedDescription))
            return false
        }
    }

    @MainActor
    @discardableResult
    static func deleteOrphan(_ trip: Trip, in context: ModelContext) -> Bool {
        if trip.endedAt != nil {
            TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)
            return true
        }
        TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)
        context.delete(trip)
        do {
            try context.save()
            return true
        } catch {
            AppErrorPresenter.shared.present(L10n.orphanDeleteFailed(error.localizedDescription))
            return false
        }
    }

    @MainActor
    @discardableResult
    static func resumeOrphan(_ trip: Trip, recordingService: TripRecordingService) -> Bool {
        if trip.endedAt != nil {
            return false
        }
        guard recordingService.state == .idle else {
            AppErrorPresenter.shared.present(L10n.orphanResumeBusy)
            return false
        }
        TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)
        recordingService.resumeRecording(trip: trip)
        guard recordingService.state == .recording else {
            AppErrorPresenter.shared.present(L10n.orphanResumeFailed)
            return false
        }
        return true
    }
}
