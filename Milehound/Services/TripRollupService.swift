import Foundation
import SwiftData

/// Nonisolated rollup deltas so `@ModelActor` workers can maintain daily totals off the main thread.
enum TripRollupDelta {
    static func snapshot(of trip: Trip) -> TripRollupEntry? {
        guard trip.endedAt != nil else { return nil }
        let places = (try? trip.modelContext?.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let defaults = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName) ?? .standard
        let storedRadius = defaults.double(forKey: "privacyRadiusMeters")
        return TripRollupEntry(
            key: TripRollupKey(trip: trip),
            contribution: Contribution(trip: trip),
            premium: PremiumDerivedDelta.snapshot(
                of: trip,
                places: places,
                privacyRadius: storedRadius > 0 ? storedRadius : 500
            )
        )
    }

    static func add(_ trip: Trip, in context: ModelContext) {
        applyDelta(for: trip, sign: 1, in: context)
        PremiumDerivedDelta.add(trip, in: context)
    }

    static func remove(_ trip: Trip, in context: ModelContext) {
        PremiumDerivedDelta.remove(trip, in: context)
        applyDelta(for: trip, sign: -1, in: context)
    }

    static func update(_ trip: Trip, from previous: TripRollupEntry?, in context: ModelContext) {
        if let previous {
            applyDelta(key: previous.key, contribution: previous.contribution, sign: -1, in: context)
            if let premium = previous.premium {
                PremiumDerivedDelta.apply(trip: trip, snapshot: premium, sign: -1, in: context)
            }
        }
        applyDelta(for: trip, sign: 1, in: context)
        PremiumDerivedDelta.add(trip, in: context)
    }

    private static func applyDelta(for trip: Trip, sign: Double, in context: ModelContext) {
        guard trip.endedAt != nil else { return }
        applyDelta(
            key: TripRollupKey(trip: trip),
            contribution: Contribution(trip: trip),
            sign: sign,
            in: context
        )
    }

    private static func applyDelta(
        key: TripRollupKey,
        contribution: Contribution,
        sign: Double,
        in context: ModelContext
    ) {
        guard let rollup = existingRollup(for: key, in: context) ?? makeRollup(for: key, sign: sign, in: context)
        else { return }

        rollup.distanceMeters = max(0, rollup.distanceMeters + sign * contribution.distanceMeters)
        rollup.duration = max(0, rollup.duration + sign * contribution.duration)
        rollup.nightDistanceMeters = max(0, rollup.nightDistanceMeters + sign * contribution.nightMeters)
        rollup.trackedDistanceMeters = max(0, rollup.trackedDistanceMeters + sign * contribution.trackedMeters)
        rollup.estimatedFuelCost = max(0, rollup.estimatedFuelCost + sign * contribution.fuelCost)
        rollup.dynamicFuelCost = max(0, rollup.dynamicFuelCost + sign * contribution.dynamicFuelCost)
        rollup.dynamicFuelVolume = max(0, rollup.dynamicFuelVolume + sign * contribution.dynamicFuelVolume)
        rollup.dynamicFuelVolumeDistanceMeters = max(
            0,
            rollup.dynamicFuelVolumeDistanceMeters + sign * contribution.dynamicFuelVolumeDistanceMeters
        )
        rollup.fuelEfficiencyProduct = max(
            0,
            rollup.fuelEfficiencyProduct + sign * contribution.fuelEfficiencyProduct
        )
        rollup.fuelEfficiencyWeight = max(
            0,
            rollup.fuelEfficiencyWeight + sign * contribution.fuelEfficiencyWeight
        )
        rollup.fuelSpeedDeltaVolume += sign * contribution.fuelSpeedDeltaVolume
        rollup.fuelIdleVolume = max(0, rollup.fuelIdleVolume + sign * contribution.fuelIdleVolume)
        rollup.fuelTransientVolume = max(0, rollup.fuelTransientVolume + sign * contribution.fuelTransientVolume)
        rollup.fuelColdStartVolume = max(0, rollup.fuelColdStartVolume + sign * contribution.fuelColdStartVolume)
        rollup.tripCount = max(0, rollup.tripCount + Int(sign))
        rollup.stopDurationSeconds = max(0, rollup.stopDurationSeconds + sign * contribution.stopDurationSeconds)
        rollup.cruiseWeightSeconds = max(0, rollup.cruiseWeightSeconds + sign * contribution.cruiseWeightSeconds)
        rollup.cruiseSpeedProduct = max(0, rollup.cruiseSpeedProduct + sign * contribution.cruiseSpeedProduct)
        rollup.mostCommonWeightSeconds = max(0, rollup.mostCommonWeightSeconds + sign * contribution.mostCommonWeightSeconds)
        rollup.mostCommonSpeedProduct = max(0, rollup.mostCommonSpeedProduct + sign * contribution.mostCommonSpeedProduct)

        if sign > 0 {
            rollup.maxSpeedMps = max(rollup.maxSpeedMps, contribution.maxSpeedMps)
        }

        // A day with nothing left in it would otherwise keep a zeroed row forever, and a stale
        // `maxSpeedMps` that removals cannot lower.
        if rollup.tripCount == 0 {
            context.delete(rollup)
        }
    }

    private static func existingRollup(for key: TripRollupKey, in context: ModelContext) -> TripDailyRollup? {
        let dayStart = key.dayStart
        let categoryID = key.categoryID
        let vehicleKey = key.vehicleKey
        let fuelUnitKey = key.fuelUnitKey
        var descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart == dayStart
                    && rollup.categoryID == categoryID
                    && rollup.vehicleKey == vehicleKey
                    && rollup.fuelUnitKey == fuelUnitKey
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func makeRollup(
        for key: TripRollupKey,
        sign: Double,
        in context: ModelContext
    ) -> TripDailyRollup? {
        // Nothing to subtract from: the delta was already accounted for, or never applied.
        guard sign > 0 else { return nil }
        let rollup = TripDailyRollup(
            dayStart: key.dayStart,
            categoryID: key.categoryID,
            vehicleKey: key.vehicleKey,
            fuelUnitKey: key.fuelUnitKey
        )
        context.insert(rollup)
        return rollup
    }
}

/// Keeps `TripDailyRollup` in step with the trips it summarises.
///
/// Rollups are maintained as deltas at the same write sites that compute derived metrics, so a
/// finished, edited, merged or deleted trip adjusts its day's totals rather than triggering a
/// rescan. Because deltas can drift if a write is ever missed, `rebuildAll` can regenerate the
/// whole table from `Trip`, which remains the only source of truth.
@MainActor
enum TripRollupService {
    // MARK: - Delta maintenance

    static func add(_ trip: Trip, in context: ModelContext) {
        TripRollupDelta.add(trip, in: context)
    }

    static func remove(_ trip: Trip, in context: ModelContext) {
        TripRollupDelta.remove(trip, in: context)
    }

    /// Everything a trip contributed before an edit, so the edit can be applied as a delta.
    static func snapshot(of trip: Trip) -> TripRollupEntry? {
        TripRollupDelta.snapshot(of: trip)
    }

    /// Re-points a trip's contribution after an edit that may have moved it to another day,
    /// category or vehicle, or changed its distance.
    static func update(_ trip: Trip, from previous: TripRollupEntry?, in context: ModelContext) {
        TripRollupDelta.update(trip, from: previous, in: context)
    }

    // MARK: - Rebuild

    private static let rebuildVersionKey = "milehound.rollup.rebuiltVersion"
    /// Bump to force every install to regenerate the table after a change to how it is derived.
    /// Version 2 drops the phantom maxima that existing rows recorded before speeds were vetted.
    /// Version 3 fills cruise / stop totals added in schema V15.
    /// Version 4 refreshes cruise / stop after the dwell-aware profile fix.
    /// Version 5 refreshes after cruise became moving-average (not modal bucket).
    /// Version 6 refreshes after multi-minute standstills count toward stop time.
    /// Version 7 refreshes after stop time uses implied speed (GPS wander is still a stop).
    /// Version 8 fills most-common speed totals added in schema V17.
    /// Version 9 fills dynamic (VSP/Willans) fuel totals added in schema V18.
    /// Version 10 refreshes estimated fuel after the C₀-relative GPS model.
    /// Version 11 refreshes short-city idle after evidence-weighted stop handling.
    /// Version 12 rebuilds after fuel formula v4 (v11 may already have been written).
    /// Version 13 rebuilds after Stop-pin idle exclusion was removed (formula v5).
    /// Version 14 rebuilds after additive litres + per-unit volume totals (formula v6).
    private static let rebuildVersion = 14

    /// Builds the table on the first launch that has it, and after any change to how rollups are
    /// derived. Cheap no-op afterwards.
    static func rebuildIfNeeded(container: ModelContainer) async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: rebuildVersionKey) < rebuildVersion else { return }
        // Fuel refresh writes `dynamicFuelCost` first. Persisting a new rollup version while
        // that walk is incomplete would freeze a half-updated Stats table.
        guard TripDerivedBackfillService.hasFinishedDynamicFuelRefresh() else { return }
        await rebuildAll(container: container)
        defaults.set(rebuildVersion, forKey: rebuildVersionKey)
    }

    /// Regenerates the whole table from `Trip`. Used on first run after the rollup shipped, and
    /// available from Settings when the numbers look wrong.
    static func rebuildAll(container: ModelContainer) async {
        await TripRollupRebuilder(modelContainer: container).run()
    }

    // MARK: - Reads

    /// Aggregates a period in time proportional to the number of days it covers.
    static func stats(
        in interval: DateInterval,
        categoryID: String?,
        vehicleID: UUID?,
        in context: ModelContext
    ) -> TripStats {
        let lowerBound = interval.start
        let upperBound = interval.end
        let descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart >= lowerBound && rollup.dayStart <= upperBound
            }
        )
        let rollups = ((try? context.fetch(descriptor)) ?? []).filter { rollup in
            if let categoryID, rollup.categoryID != categoryID { return false }
            if let vehicleID, rollup.vehicleKey != vehicleID.uuidString { return false }
            return true
        }

        var totalDistance = 0.0
        var totalDuration = 0.0
        var totalFuel = 0.0
        var totalDynamicFuel = 0.0
        var totalDynamicVolume = 0.0
        var volumeDistance = 0.0
        var efficiencyProduct = 0.0
        var efficiencyWeight = 0.0
        var idleVolume = 0.0
        var transientVolume = 0.0
        var coldVolume = 0.0
        var speedAbsVolume = 0.0
        var nightMeters = 0.0
        var trackedMeters = 0.0
        var maxSpeedMps = 0.0
        var stopDuration = 0.0
        var cruiseWeight = 0.0
        var cruiseProduct = 0.0
        var mostCommonWeight = 0.0
        var mostCommonProduct = 0.0
        var count = 0

        for rollup in rollups {
            totalDistance += rollup.distanceMeters
            totalDuration += rollup.duration
            totalFuel += rollup.estimatedFuelCost
            totalDynamicFuel += rollup.dynamicFuelCost
            totalDynamicVolume += rollup.dynamicFuelVolume
            volumeDistance += rollup.dynamicFuelVolumeDistanceMeters
            efficiencyProduct += rollup.fuelEfficiencyProduct
            efficiencyWeight += rollup.fuelEfficiencyWeight
            idleVolume += rollup.fuelIdleVolume
            transientVolume += rollup.fuelTransientVolume
            coldVolume += rollup.fuelColdStartVolume
            speedAbsVolume += abs(rollup.fuelSpeedDeltaVolume)
            nightMeters += rollup.nightDistanceMeters
            trackedMeters += rollup.trackedDistanceMeters
            maxSpeedMps = max(maxSpeedMps, rollup.maxSpeedMps)
            stopDuration += rollup.stopDurationSeconds
            cruiseWeight += rollup.cruiseWeightSeconds
            cruiseProduct += rollup.cruiseSpeedProduct
            mostCommonWeight += rollup.mostCommonWeightSeconds
            mostCommonProduct += rollup.mostCommonSpeedProduct
            count += rollup.tripCount
        }

        let unitKeys = Set(rollups.map { rollup in
            rollup.fuelUnitKey.isEmpty ? "liquid" : rollup.fuelUnitKey
        })
        let mixedUnits = unitKeys.count > 1

        let factorShares = StatsViewModel.fuelFactorShares(
            idle: idleVolume,
            transient: transientVolume,
            cold: coldVolume,
            speed: speedAbsVolume,
            mixedUnits: mixedUnits
        )

        return TripStats(
            tripCount: count,
            totalDistanceMeters: totalDistance,
            totalDuration: totalDuration,
            averageDuration: count > 0 ? totalDuration / Double(count) : 0,
            averageSpeedKmh: StatsViewModel.averageSpeedKmh(
                distanceMeters: totalDistance,
                duration: totalDuration
            ),
            maxSpeedKmh: maxSpeedMps * 3.6,
            cruiseSpeedKmh: cruiseWeight > 0 ? cruiseProduct / cruiseWeight : 0,
            mostCommonSpeedKmh: mostCommonWeight > 0 ? mostCommonProduct / mostCommonWeight : 0,
            stopDuration: stopDuration,
            estimatedFuelCost: totalFuel,
            dynamicFuelCost: totalDynamicFuel,
            nightDrivingRatio: trackedMeters > 0 ? nightMeters / trackedMeters : 0,
            nightDistanceMeters: nightMeters,
            trackedDistanceMeters: trackedMeters,
            dynamicFuelVolume: mixedUnits ? 0 : totalDynamicVolume,
            dynamicFuelVolumeDistanceMeters: mixedUnits ? 0 : volumeDistance,
            fuelEfficiencyScore: mixedUnits || efficiencyWeight <= 0
                ? 0
                : efficiencyProduct / efficiencyWeight,
            hasMixedFuelUnits: mixedUnits,
            fuelUnitIsElectric: !mixedUnits && unitKeys.contains("electric"),
            fuelFactorShares: factorShares,
            topFuelFactors: StatsViewModel.topFuelFactors(from: factorShares)
        )
    }
}

/// Rebuilds the whole rollup table off the main thread, since it has to visit every trip.
@ModelActor
actor TripRollupRebuilder {
    private static let batchSize = 200

    func run() async {
        for existing in (try? modelContext.fetch(FetchDescriptor<TripDailyRollup>())) ?? [] {
            modelContext.delete(existing)
        }

        var offset = 0
        var accumulator: [TripRollupKey: Contribution] = [:]

        while !Task.isCancelled {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize

            let batch = (try? modelContext.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }

            for trip in batch {
                    accumulator[TripRollupKey(trip: trip), default: .zero].merge(Contribution(trip: trip))
                trip.invalidatePointCaches()
            }

            offset += batch.count
            await Task.yield()
            
            
        }

        for (key, contribution) in accumulator {
            let rollup = TripDailyRollup(
                dayStart: key.dayStart,
                categoryID: key.categoryID,
                vehicleKey: key.vehicleKey,
                fuelUnitKey: key.fuelUnitKey
            )
            rollup.distanceMeters = contribution.distanceMeters
            rollup.duration = contribution.duration
            rollup.nightDistanceMeters = contribution.nightMeters
            rollup.trackedDistanceMeters = contribution.trackedMeters
            rollup.estimatedFuelCost = contribution.fuelCost
            rollup.dynamicFuelCost = contribution.dynamicFuelCost
            rollup.dynamicFuelVolume = contribution.dynamicFuelVolume
            rollup.dynamicFuelVolumeDistanceMeters = contribution.dynamicFuelVolumeDistanceMeters
            rollup.fuelEfficiencyProduct = contribution.fuelEfficiencyProduct
            rollup.fuelEfficiencyWeight = contribution.fuelEfficiencyWeight
            rollup.fuelSpeedDeltaVolume = contribution.fuelSpeedDeltaVolume
            rollup.fuelIdleVolume = contribution.fuelIdleVolume
            rollup.fuelTransientVolume = contribution.fuelTransientVolume
            rollup.fuelColdStartVolume = contribution.fuelColdStartVolume
            rollup.tripCount = contribution.tripCount
            rollup.maxSpeedMps = contribution.maxSpeedMps
            rollup.stopDurationSeconds = contribution.stopDurationSeconds
            rollup.cruiseWeightSeconds = contribution.cruiseWeightSeconds
            rollup.cruiseSpeedProduct = contribution.cruiseSpeedProduct
            rollup.mostCommonWeightSeconds = contribution.mostCommonWeightSeconds
            rollup.mostCommonSpeedProduct = contribution.mostCommonSpeedProduct
            modelContext.insert(rollup)
        }

        try? modelContext.save()
    }
}

/// Identifies the rollup bucket a trip belongs to.
struct TripRollupKey: Hashable {
    let dayStart: Date
    let categoryID: String
    let vehicleKey: String
    let fuelUnitKey: String

    init(trip: Trip) {
        self.dayStart = Calendar.current.startOfDay(for: trip.startedAt)
        self.categoryID = trip.categoryID
        self.vehicleKey = TripDailyRollup.vehicleKey(for: trip.vehicleID)
        self.fuelUnitKey = trip.fuelUnitKey
    }
}

/// A trip's rollup bucket together with the amounts it put in it.
struct TripRollupEntry {
    fileprivate let key: TripRollupKey
    fileprivate let contribution: Contribution
    fileprivate let premium: PremiumTripSnapshot?
}

fileprivate struct Contribution {
    var distanceMeters = 0.0
    var duration = 0.0
    var nightMeters = 0.0
    var trackedMeters = 0.0
    var fuelCost = 0.0
    var dynamicFuelCost = 0.0
    var dynamicFuelVolume = 0.0
    var dynamicFuelVolumeDistanceMeters = 0.0
    var fuelEfficiencyProduct = 0.0
    var fuelEfficiencyWeight = 0.0
    var fuelSpeedDeltaVolume = 0.0
    var fuelIdleVolume = 0.0
    var fuelTransientVolume = 0.0
    var fuelColdStartVolume = 0.0
    var maxSpeedMps = 0.0
    var stopDurationSeconds = 0.0
    var cruiseWeightSeconds = 0.0
    var cruiseSpeedProduct = 0.0
    var mostCommonWeightSeconds = 0.0
    var mostCommonSpeedProduct = 0.0
    var tripCount = 0

    static let zero = Contribution()

    init(trip: Trip) {
        distanceMeters = trip.distanceMeters
        duration = trip.duration ?? 0
        nightMeters = trip.nightDistanceMeters ?? 0
        trackedMeters = trip.trackedDistanceMeters ?? 0
        fuelCost = StatsViewModel.fuelCost(for: trip)
        dynamicFuelCost = trip.dynamicFuelCost ?? 0
        dynamicFuelVolume = trip.dynamicFuelVolume ?? 0
        if let volume = trip.dynamicFuelVolume, volume > 0 {
            dynamicFuelVolumeDistanceMeters = trip.distanceMeters
        }
        if let score = trip.fuelEfficiencyScore, trip.distanceMeters > 0 {
            fuelEfficiencyProduct = score * trip.distanceMeters
            fuelEfficiencyWeight = trip.distanceMeters
        }
        fuelSpeedDeltaVolume = trip.fuelSpeedDeltaVolume ?? 0
        fuelIdleVolume = trip.fuelIdleVolume ?? 0
        fuelTransientVolume = trip.fuelTransientVolume ?? 0
        fuelColdStartVolume = trip.fuelColdStartVolume ?? 0
        // A rollup keeps the highest value it ever saw and never lowers it, so one phantom
        // maximum would poison a whole day's statistics permanently.
        maxSpeedMps = TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps) ?? 0
        stopDurationSeconds = trip.stopDurationSeconds ?? 0
        let cruiseSpeed = trip.cruiseSpeedKmh ?? 0
        let cruiseWeight = trip.cruiseDurationSeconds ?? 0
        if cruiseSpeed > 0, cruiseWeight > 0 {
            cruiseWeightSeconds = cruiseWeight
            cruiseSpeedProduct = cruiseSpeed * cruiseWeight
        }
        let mostCommonSpeed = trip.mostCommonSpeedKmh ?? 0
        if mostCommonSpeed > 0, cruiseWeight > 0 {
            mostCommonWeightSeconds = cruiseWeight
            mostCommonSpeedProduct = mostCommonSpeed * cruiseWeight
        }
        tripCount = 1
    }

    init() {}

    mutating func merge(_ other: Contribution) {
        distanceMeters += other.distanceMeters
        duration += other.duration
        nightMeters += other.nightMeters
        trackedMeters += other.trackedMeters
        fuelCost += other.fuelCost
        dynamicFuelCost += other.dynamicFuelCost
        dynamicFuelVolume += other.dynamicFuelVolume
        dynamicFuelVolumeDistanceMeters += other.dynamicFuelVolumeDistanceMeters
        fuelEfficiencyProduct += other.fuelEfficiencyProduct
        fuelEfficiencyWeight += other.fuelEfficiencyWeight
        fuelSpeedDeltaVolume += other.fuelSpeedDeltaVolume
        fuelIdleVolume += other.fuelIdleVolume
        fuelTransientVolume += other.fuelTransientVolume
        fuelColdStartVolume += other.fuelColdStartVolume
        maxSpeedMps = max(maxSpeedMps, other.maxSpeedMps)
        stopDurationSeconds += other.stopDurationSeconds
        cruiseWeightSeconds += other.cruiseWeightSeconds
        cruiseSpeedProduct += other.cruiseSpeedProduct
        mostCommonWeightSeconds += other.mostCommonWeightSeconds
        mostCommonSpeedProduct += other.mostCommonSpeedProduct
        tripCount += other.tripCount
    }
}
