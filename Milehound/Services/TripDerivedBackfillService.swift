import Foundation
import SwiftData

/// Fills in `TripDerivedMetrics` values for trips recorded before those fields existed.
///
/// Runs on its own `@ModelActor`, off the main thread, so walking the GPS points of a large
/// library cannot stall the UI. Work is committed in small batches, which makes it safe to
/// interrupt: the next launch resumes where this one stopped. Existing trip data is only
/// augmented — nothing is deleted or rewritten.
@ModelActor
actor TripDerivedBackfiller {
    func run(privacyRadius: Double) async {
        // Fetched on this actor's own context: `SavedPlace` cannot cross actor boundaries.
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let vehicles = vehiclesByID()

        while !Task.isCancelled {
            let pending = fetchPendingBatch()
            guard !pending.isEmpty else { break }

            for trip in pending {
                let vehicle = trip.vehicleID.flatMap { vehicles[$0] }
                TripDerivedMetrics.recompute(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius,
                    fuelType: vehicle?.fuelType ?? .petrol,
                    vehicle: vehicle
                )
                // The derived values are what read paths need from here on; holding every
                // TripPoint alive would defeat the point of backfilling in batches.
                trip.invalidatePointCaches()
            }

            do {
                try modelContext.save()
            } catch {
                return
            }

            await Task.yield()
        }
    }

    /// Re-runs cruise / stop and GPS fuel after a formula change. One GPS walk when both
    /// versions are stale. Interruptible: version keys are written only after every completed
    /// trip has been visited.
    /// - Returns: `false` when cancelled or a save failed, so rollups must not freeze a partial table.
    func refreshDerivedKinematicsIfNeeded(
        speedProfileVersionKey: String,
        speedProfileVersion: Int,
        dynamicFuelVersionKey: String,
        dynamicFuelVersion: Int
    ) async -> Bool {
        let defaults = UserDefaults.standard
        let needSpeed = defaults.integer(forKey: speedProfileVersionKey) < speedProfileVersion
        let needFuel = defaults.integer(forKey: dynamicFuelVersionKey) < dynamicFuelVersion
        guard needSpeed || needFuel else { return true }

        let vehicles = vehiclesByID()
        let ids = completedTripIDs()
        var index = 0
        while index < ids.count {
            if Task.isCancelled { return false }
            let end = min(index + 25, ids.count)
            for id in ids[index..<end] {
                guard let trip = trip(withID: id) else { continue }
                // Fault GPS + stops before the walk; a relationship that stays unfaulted
                // would recompute against an empty trace and keep the stale stored cost.
                _ = trip.points.count
                _ = trip.stops.count
                let vehicle = trip.vehicleID.flatMap { vehicles[$0] }
                if needSpeed {
                    TripDerivedMetrics.recomputeSpeedProfile(for: trip)
                }
                if needFuel {
                    TripDerivedMetrics.recomputeFuel(
                        for: trip,
                        fuelType: vehicle?.fuelType ?? .petrol,
                        vehicle: vehicle
                    )
                }
                trip.invalidatePointCaches()
            }

            do {
                try modelContext.save()
            } catch {
                return false
            }

            index = end
            await Task.yield()
        }

        guard !Task.isCancelled else { return false }
        if needSpeed {
            defaults.set(speedProfileVersion, forKey: speedProfileVersionKey)
        }
        if needFuel {
            defaults.set(dynamicFuelVersion, forKey: dynamicFuelVersionKey)
        }
        return true
    }

    /// Re-runs place matching + search index after the corpus gained canonical saved-place names
    /// and SearchFolding. Does not rewrite GPS, notes, or other user fields.
    ///
    /// Must persist on this actor's context (not a second main-thread context): another
    /// `ModelContext` can still hold pre-backfill snapshots and a later save would clobber
    /// derived fields. SwiftUI is kept off this thread by `onStoreSave`'s main-thread receive.
    func refreshSearchIndexesIfNeeded(privacyRadius: Double) async {
        let defaults = UserDefaults.standard
        let searchIndexVersionKey = "milehound.derived.searchIndexVersion"
        let searchIndexVersion = 1
        guard defaults.integer(forKey: searchIndexVersionKey) < searchIndexVersion else {
            return
        }

        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        var offset = 0
        while !Task.isCancelled {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = 25

            let batch = (try? modelContext.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }

            for trip in batch {
                PlaceMatchingService.matchPlaces(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius
                )
                TripDerivedMetrics.refreshSearchIndex(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius
                )
            }

            do {
                try modelContext.save()
            } catch {
                return
            }

            offset += batch.count
            await Task.yield()
        }

        guard !Task.isCancelled else { return }
        defaults.set(searchIndexVersion, forKey: searchIndexVersionKey)
    }

    /// Completed trips are the only ones read paths aggregate, and an unfinished trip would be
    /// recomputed again the moment it is finalized.
    private func fetchPendingBatch() -> [Trip] {
        // Separate predicates: a single OR over optionals can overwhelm the type checker.
        var pendingByID: [UUID: Trip] = [:]
        for trip in fetchBatch(
            predicate: #Predicate { $0.endedAt != nil && $0.stopDurationSeconds == nil }
        ) {
            pendingByID[trip.id] = trip
        }
        for trip in fetchBatch(
            predicate: #Predicate { $0.endedAt != nil && $0.nightDistanceMeters == nil }
        ) {
            pendingByID[trip.id] = trip
        }
        for trip in fetchBatch(
            predicate: #Predicate { $0.endedAt != nil && $0.dynamicFuelCost == nil }
        ) {
            pendingByID[trip.id] = trip
        }
        return Array(pendingByID.values)
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(25)
            .map { $0 }
    }

    private func fetchBatch(predicate: Predicate<Trip>) -> [Trip] {
        var descriptor = FetchDescriptor<Trip>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func completedTripIDs() -> [UUID] {
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil }
        )
        let trips = (try? modelContext.fetch(descriptor)) ?? []
        return trips.sorted { lhs, rhs in
            let left = lhs.vehicleID?.uuidString ?? ""
            let right = rhs.vehicleID?.uuidString ?? ""
            if left != right { return left < right }
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }.map(\.id)
    }

    private func trip(withID id: UUID) -> Trip? {
        let tripID = id
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.id == tripID }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func vehiclesByID() -> [UUID: VehicleProfile] {
        let vehicles = (try? modelContext.fetch(FetchDescriptor<VehicleProfile>())) ?? []
        var map: [UUID: VehicleProfile] = [:]
        for vehicle in vehicles {
            map[vehicle.id] = vehicle
        }
        return map
    }
}

@MainActor
enum TripDerivedBackfillService {
    static let speedProfileVersionKey = "milehound.derived.speedProfileVersion"
    /// Bump when `TripSpeedProfile` changes so already-filled trips are recomputed.
    static let speedProfileVersion = 6
    static let dynamicFuelVersionKey = "milehound.derived.dynamicFuelVersion"
    /// Bump when `TripFuelEstimate` changes so already-filled trips are recomputed.
    /// 4: short-city idle evidence (devices that already wrote 3 must walk again).
    /// 5: auto-detected Stop pins no longer zero traffic-queue idle.
    /// 6: additive C₀-scaled litres (speed + idle + transient + cold).
    static let dynamicFuelVersion = 6

    /// Coalesce overlapping calls on the same store. A process-wide flag would skip a second
    /// container (tests) or return before the first walk had written the fuel version (Stats).
    private static var inFlight: [ObjectIdentifier: Task<Bool, Never>] = [:]

    static func hasFinishedDynamicFuelRefresh() -> Bool {
        UserDefaults.standard.integer(forKey: dynamicFuelVersionKey) >= dynamicFuelVersion
    }

    /// - Returns: `false` when kinematic refresh did not finish; callers must not persist a
    ///   rollup rebuild version on top of a partial fuel table.
    @discardableResult
    static func backfillIfNeeded(container: ModelContainer) async -> Bool {
        let key = ObjectIdentifier(container)
        if let existing = inFlight[key] {
            return await existing.value
        }
        let task = Task { @MainActor in
            await performBackfill(container: container)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return await task.value
    }

    private static func performBackfill(container: ModelContainer) async -> Bool {
        let privacyRadius = AppSettings.shared.privacyRadiusMeters
        let backfiller = TripDerivedBackfiller(modelContainer: container)
        await backfiller.run(privacyRadius: privacyRadius)
        let kinematicsComplete = await backfiller.refreshDerivedKinematicsIfNeeded(
            speedProfileVersionKey: speedProfileVersionKey,
            speedProfileVersion: speedProfileVersion,
            dynamicFuelVersionKey: dynamicFuelVersionKey,
            dynamicFuelVersion: dynamicFuelVersion
        )
        await backfiller.refreshSearchIndexesIfNeeded(privacyRadius: privacyRadius)
        return kinematicsComplete
    }
}
