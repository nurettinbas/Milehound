import CoreLocation
import Foundation
import SwiftData

enum TripMergeError: LocalizedError, Equatable {
    case needsTwoCompletedTrips

    var errorDescription: String? {
        switch self {
        case .needsTwoCompletedTrips:
            return L10n.tripsMergeNeedsTwo
        }
    }
}

/// Combines completed trip legs into a single trip.
///
/// Heavy work runs on `TripMergeWorker` (`@ModelActor`) so the UI stays responsive. The
/// `@MainActor` façade keeps call sites and tests on a familiar surface.
@MainActor
enum TripMergeService {
    /// Merges by ID off the main thread. Prefer this from UI code.
    static func merge(
        tripIDs: [UUID],
        container: ModelContainer,
        privacyRadius: Double = AppSettings.shared.privacyRadiusMeters
    ) async throws -> UUID {
        let mergedID = try await TripMergeWorker(modelContainer: container)
            .mergeAsync(tripIDs: tripIDs, privacyRadius: privacyRadius)
        VehicleCareNotificationScheduler.evaluateKmReminders(in: container.mainContext)
        for id in tripIDs {
            TripMapSnapshotCache.shared.remove(for: id)
            TripRoutePathCache.shared.remove(for: id)
        }
        TripRoutePathCache.shared.prewarm(tripID: mergedID, container: container)
        return mergedID
    }

    /// Merges trips already loaded in `context`. Used by unit tests and any caller that already
    /// holds the models. Throws `TripMergeError.needsTwoCompletedTrips` instead of returning nil.
    static func merge(
        trips: [Trip],
        into context: ModelContext,
        privacyRadius: Double = AppSettings.shared.privacyRadiusMeters
    ) throws -> Trip {
        let sourceJournalIDs = trips.map(\.journalID)
        let merged = try TripMergeCore.merge(
            trips: trips,
            into: context,
            privacyRadius: privacyRadius
        )
        VehicleCareNotificationScheduler.evaluateKmReminders(for: merged.vehicleID, in: context)
        let deletedIDs = trips.map(\.id)
        try context.save()
        TripMergeCore.refreshJournals(ids: sourceJournalIDs, extra: merged.journalID, in: context)
        try context.save()
        for id in deletedIDs {
            TripMapSnapshotCache.shared.remove(for: id)
            TripRoutePathCache.shared.remove(for: id)
        }
        TripRoutePathCache.shared.prewarm(tripID: merged.id, container: context.container)
        return merged
    }
}

/// Shared merge body used by both the `@ModelActor` worker and the in-context façade.
enum TripMergeCore {
    static func merge(
        trips: [Trip],
        into context: ModelContext,
        privacyRadius: Double
    ) throws -> Trip {
        let completed = trips.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        let odometerVehicleIDs = Set(completed.compactMap(\.vehicleID))
        let sourceJournalIDs = completed.map(\.journalID)
        let merged = try beginMergedTrip(from: completed, into: context)
        let fuelInputs = mergedFuelInputs(from: completed)

        var sequence = 0
        var totalDistance = 0.0
        var maxSpeed: Double = 0

        for (index, trip) in completed.enumerated() {
            let next = index + 1 < completed.count ? completed[index + 1] : nil
            copyLeg(
                trip,
                next: next,
                into: merged,
                sequence: &sequence,
                totalDistance: &totalDistance,
                maxSpeed: &maxSpeed,
                context: context
            )
        }

        finalizeMergedTrip(
            merged,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            privacyRadius: privacyRadius,
            fuelConsumptionPer100: fuelInputs.consumption,
            fuelUnitPrice: fuelInputs.unitPrice,
            context: context
        )
        var affected = odometerVehicleIDs
        if let mergedVehicleID = merged.vehicleID {
            affected.insert(mergedVehicleID)
        }
        for id in affected {
            if let vehicle = VehicleResolver.vehicle(withID: id, in: context) {
                VehicleOdometerService.recompute(vehicle, in: context)
            }
        }
        applyCapturedMergeMembership(
            surviving: merged,
            journalIDs: sourceJournalIDs,
            in: context
        )
        return merged
    }

    static func applyCapturedMergeMembership(
        surviving: Trip,
        journalIDs: [UUID?],
        in context: ModelContext
    ) {
        let unique = Set(journalIDs.compactMap { $0 })
        if unique.count == 1, let only = unique.first {
            surviving.journalID = only
            let descriptor = FetchDescriptor<TravelJournal>(
                predicate: #Predicate { $0.id == only }
            )
            surviving.journal = try? context.fetch(descriptor).first
        } else {
            surviving.journal = nil
            surviving.journalID = nil
        }
    }

    /// Call after `save()` so deleted legs have left the journal relationship.
    static func refreshJournals(ids: [UUID?], extra: UUID? = nil, in context: ModelContext) {
        var unique = Set(ids.compactMap { $0 })
        if let extra { unique.insert(extra) }
        for journalID in unique {
            TravelJournalTotals.refresh(journalID: journalID, in: context)
        }
    }

    /// Yields on the merge worker every this many copied GPS points so a dense first
    /// leg cannot stall the progress overlay until the whole history is inserted.
    static let pointCopyYieldInterval = 500

    /// Copies one chronological leg onto `merged`.
    static func copyLeg(
        _ trip: Trip,
        next: Trip?,
        into merged: Trip,
        sequence: inout Int,
        totalDistance: inout Double,
        maxSpeed: inout Double,
        context: ModelContext
    ) {
        for point in trip.sortedPoints {
            insertCopiedPoint(
                point,
                into: merged,
                sequence: &sequence,
                maxSpeed: &maxSpeed,
                context: context
            )
        }
        finishCopiedLeg(
            trip,
            next: next,
            into: merged,
            totalDistance: &totalDistance,
            context: context
        )
    }

    static func insertCopiedPoint(
        _ point: TripPoint,
        into merged: Trip,
        sequence: inout Int,
        maxSpeed: inout Double,
        context: ModelContext
    ) {
        let newPoint = TripPoint(
            timestamp: point.timestamp,
            latitude: point.latitude,
            longitude: point.longitude,
            sequence: sequence,
            speedMps: point.speedMps,
            trip: merged
        )
        sequence += 1
        // `trip:` already wires the inverse relationship — no `merged.points.append`.
        context.insert(newPoint)
        if let speed = point.speedMps { maxSpeed = max(maxSpeed, speed) }
    }

    static func finishCopiedLeg(
        _ trip: Trip,
        next: Trip?,
        into merged: Trip,
        totalDistance: inout Double,
        context: ModelContext
    ) {
        totalDistance += trip.distanceMeters

        var copiedStops: [TripStop] = []
        for stop in trip.stops {
            let newStop = TripStop(
                latitude: stop.latitude,
                longitude: stop.longitude,
                startedAt: stop.startedAt,
                durationSeconds: stop.durationSeconds,
                trip: merged
            )
            copiedStops.append(newStop)
            context.insert(newStop)
        }

        junction(from: trip, to: next)?
            .apply(to: merged, candidates: copiedStops, context: context)

        trip.invalidatePointCaches()
        let successor = TripFuelDependencyService.successor(of: trip, in: context)
        TripRollupDelta.remove(trip, in: context)
        context.delete(trip)
        if let successor {
            TripFuelDependencyService.recompute(successor, in: context)
        }
    }

    static func beginMergedTrip(from completed: [Trip], into context: ModelContext) throws -> Trip {
        guard completed.count >= 2 else { throw TripMergeError.needsTwoCompletedTrips }
        let first = completed[0]
        let last = completed[completed.count - 1]

        let merged = Trip(
            startedAt: first.startedAt,
            endedAt: last.endedAt
        )
        merged.categoryID = first.categoryID
        // Hand-picked by the driver, so unlike the route match the merged trip regenerates,
        // nothing can bring it back once the legs are deleted.
        merged.vehicleID = completed.compactMap(\.vehicleID).first
        merged.startAddress = first.startAddress
        merged.startPlaceName = first.startPlaceName
        merged.endAddress = last.endAddress
        merged.endPlaceName = last.endPlaceName
        merged.startLocality = first.startLocality
        merged.endLocality = last.endLocality
        merged.startCountryCode = first.startCountryCode
        merged.endCountryCode = last.endCountryCode
        merged.startLatitude = first.startLatitude
        merged.startLongitude = first.startLongitude
        merged.endLatitude = last.endLatitude
        merged.endLongitude = last.endLongitude
        merged.note = mergedNotes(from: completed)
        // Insert before copying points so inverse relationships resolve against a registered trip.
        context.insert(merged)
        return merged
    }

    static func finalizeMergedTrip(
        _ merged: Trip,
        totalDistance: Double,
        maxSpeed: Double,
        privacyRadius: Double,
        fuelConsumptionPer100: Double? = nil,
        fuelUnitPrice: Double? = nil,
        context: ModelContext
    ) {
        merged.distanceMeters = totalDistance
        merged.maxSpeedMps = maxSpeed > 0 ? maxSpeed : nil
        let vehicle = merged.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: context) }
        FuelCostCalculator.applyEstimate(
            to: merged,
            distanceMeters: totalDistance,
            vehicle: vehicle,
            consumptionPer100: fuelConsumptionPer100,
            unitPrice: fuelUnitPrice
        )
        merged.geocodeStatus = .pending

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        TripDerivedMetrics.recompute(
            for: merged,
            places: places,
            privacyRadius: privacyRadius,
            fuelType: vehicle?.fuelType ?? .petrol,
            vehicle: vehicle
        )
        TripRollupDelta.add(merged, in: context)
    }

    /// Distance-weighted average of leg snapshots when present; otherwise `nil` so defaults apply.
    private static func mergedFuelInputs(from trips: [Trip]) -> (consumption: Double?, unitPrice: Double?) {
        var consumptionWeight = 0.0
        var consumptionSum = 0.0
        var priceWeight = 0.0
        var priceSum = 0.0

        for trip in trips {
            let distance = max(trip.distanceMeters, 0)
            guard distance > 0 else { continue }
            if let consumption = trip.fuelConsumptionPer100, consumption > 0 {
                consumptionSum += consumption * distance
                consumptionWeight += distance
            }
            if let price = trip.fuelUnitPrice, price > 0 {
                priceSum += price * distance
                priceWeight += distance
            }
        }

        let consumption = consumptionWeight > 0 ? consumptionSum / consumptionWeight : nil
        let unitPrice = priceWeight > 0 ? priceSum / priceWeight : nil
        return (consumption, unitPrice)
    }

    /// The standstill between two merged legs. Merging used to join them with nothing but a
    /// break in the polyline, which hid the fact that the car had been parked there.
    private static func junction(from leg: Trip, to next: Trip?) -> TripStandstill? {
        guard let next, let legEnd = leg.endedAt else { return nil }

        let waited = next.startedAt.timeIntervalSince(legEnd)
        guard waited >= RecordingConfiguration.minimumMergeJunctionStopSeconds else { return nil }

        // Where the driver actually stood: the last fix of the leg that ended, falling back to
        // the first fix of the leg that resumes.
        guard let coordinate = leg.sortedPoints.last?.coordinate
            ?? next.sortedPoints.first?.coordinate else { return nil }

        return TripStandstill(coordinate: coordinate, startedAt: legEnd, endedAt: next.startedAt)
    }

    private static func mergedNotes(from trips: [Trip]) -> String? {
        let notes = trips.compactMap(\.note).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: "\n\n")
    }
}

/// Off-main-thread merge so long GPS histories cannot stall the trip list.
@ModelActor
actor TripMergeWorker {
    func mergeAsync(tripIDs: [UUID], privacyRadius: Double) async throws -> UUID {
        let idList = tripIDs
        let fetched = (try? modelContext.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { idList.contains($0.id) })
        )) ?? []

        let completed = fetched.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        let odometerVehicleIDs = Set(completed.compactMap(\.vehicleID))
        let sourceJournalIDs = completed.map(\.journalID)
        let merged = try TripMergeCore.beginMergedTrip(from: completed, into: modelContext)

        var sequence = 0
        var totalDistance = 0.0
        var maxSpeed: Double = 0

        for (index, trip) in completed.enumerated() {
            let next = index + 1 < completed.count ? completed[index + 1] : nil
            let points = trip.sortedPoints
            for (offset, point) in points.enumerated() {
                TripMergeCore.insertCopiedPoint(
                    point,
                    into: merged,
                    sequence: &sequence,
                    maxSpeed: &maxSpeed,
                    context: modelContext
                )
                if (offset + 1).isMultiple(of: TripMergeCore.pointCopyYieldInterval) {
                    await Task.yield()
                }
            }
            TripMergeCore.finishCopiedLeg(
                trip,
                next: next,
                into: merged,
                totalDistance: &totalDistance,
                context: modelContext
            )
            // Let the awaiting MainActor keep the progress overlay alive between legs.
            await Task.yield()
        }

        TripMergeCore.finalizeMergedTrip(
            merged,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            privacyRadius: privacyRadius,
            context: modelContext
        )
        var affected = odometerVehicleIDs
        if let mergedVehicleID = merged.vehicleID {
            affected.insert(mergedVehicleID)
        }
        for id in affected {
            if let vehicle = VehicleResolver.vehicle(withID: id, in: modelContext) {
                VehicleOdometerService.recompute(vehicle, in: modelContext)
            }
        }
        TripMergeCore.applyCapturedMergeMembership(
            surviving: merged,
            journalIDs: sourceJournalIDs,
            in: modelContext
        )
        try modelContext.save()
        TripMergeCore.refreshJournals(ids: sourceJournalIDs, extra: merged.journalID, in: modelContext)
        try modelContext.save()
        return merged.id
    }
}
