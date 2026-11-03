import Foundation
import SwiftData

struct PremiumTripSnapshot: Equatable, Sendable {
    let route: FrequentRouteSnapshot?
    let localities: [String]
    let isCompleted: Bool
}

enum PremiumDerivedDelta {
    static func snapshot(
        of trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> PremiumTripSnapshot {
        PremiumTripSnapshot(
            route: FrequentRouteAggregateService.snapshot(
                of: trip,
                places: places,
                privacyRadius: privacyRadius
            ),
            localities: TripLocalityResolver.localities(on: trip),
            isCompleted: trip.endedAt != nil
        )
    }

    static func add(_ trip: Trip, in context: ModelContext) {
        guard canPersist(in: context) else { return }
        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = privacyRadiusMeters()
        apply(
            trip: trip,
            snapshot: snapshot(of: trip, places: places, privacyRadius: privacyRadius),
            sign: 1,
            in: context
        )
    }

    static func remove(_ trip: Trip, in context: ModelContext) {
        guard canPersist(in: context) else { return }
        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = privacyRadiusMeters()
        apply(
            trip: trip,
            snapshot: snapshot(of: trip, places: places, privacyRadius: privacyRadius),
            sign: -1,
            in: context
        )
    }

    static func update(
        _ trip: Trip,
        from previous: PremiumTripSnapshot?,
        in context: ModelContext
    ) {
        if let previous {
            apply(trip: trip, snapshot: previous, sign: -1, in: context)
        }
        add(trip, in: context)
    }

    static func apply(
        trip: Trip,
        snapshot: PremiumTripSnapshot,
        sign: Double,
        in context: ModelContext,
        notify: Bool = true
    ) {
        guard canPersist(in: context) else { return }
        guard snapshot.isCompleted || trip.endedAt != nil else { return }
        if let route = snapshot.route {
            if sign > 0 {
                FrequentRouteAggregateService.add(route, in: context)
            } else {
                FrequentRouteAggregateService.remove(route, in: context)
            }
        }
        AchievementEvaluator.apply(
            trip: trip,
            sign: sign,
            localities: snapshot.localities,
            in: context,
            notify: notify
        )
        YearRecapCache.invalidate(yearContaining: trip.startedAt)
    }

    private static func canPersist(in context: ModelContext) -> Bool {
        do {
            var descriptor = FetchDescriptor<FrequentRouteAggregate>()
            descriptor.fetchLimit = 0
            _ = try context.fetch(descriptor)
            return true
        } catch {
            return false
        }
    }

    private static func privacyRadiusMeters() -> Double {
        let defaults = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName) ?? .standard
        let value = defaults.double(forKey: "privacyRadiusMeters")
        return value > 0 ? value : 500
    }
}

@MainActor
enum PremiumDerivedMaintenance {
    private static let rebuildVersionKey = "milehound.premium.rebuiltVersion"
    private static let rebuildVersion = 1
    /// Existing installs already stamped `rebuiltVersion` 1 while achievements only
    /// counted trips finished after the feature shipped. Replay history once, silently.
    /// Version 2 replays again so trip/hours/dawn/weekend/fleet families added later
    /// pick up the same historical trips (the v1 stamp skipped them).
    private static let achievementRebuildVersionKey = "milehound.premium.achievementRebuiltVersion"
    private static let achievementRebuildVersion = 2
    /// Version 2 rebuilds corridors with geo-cell + undirected pairing so old reverse-geocode
    /// name drift no longer fragments the same commute (v1 name keys skipped that merge).
    private static let routeRebuildVersionKey = "milehound.premium.routeRebuiltVersion"
    private static let routeRebuildVersion = 2

    static func rebuildIfNeeded(container: ModelContainer) async {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: rebuildVersionKey) < rebuildVersion {
            await rebuildAll(container: container)
            defaults.set(rebuildVersion, forKey: rebuildVersionKey)
            defaults.set(achievementRebuildVersion, forKey: achievementRebuildVersionKey)
            defaults.set(routeRebuildVersion, forKey: routeRebuildVersionKey)
            return
        }
        if defaults.integer(forKey: routeRebuildVersionKey) < routeRebuildVersion {
            await rebuildRoutes(container: container)
            defaults.set(routeRebuildVersion, forKey: routeRebuildVersionKey)
        }
        guard defaults.integer(forKey: achievementRebuildVersionKey) < achievementRebuildVersion else { return }
        await rebuildAchievements(container: container)
        defaults.set(achievementRebuildVersion, forKey: achievementRebuildVersionKey)
    }

    static func rebuildAll(container: ModelContainer) async {
        await PremiumDerivedRebuilder(modelContainer: container).run()
    }

    static func rebuildRoutes(container: ModelContainer) async {
        await PremiumDerivedRebuilder(modelContainer: container).runRoutes()
    }

    static func rebuildAchievements(container: ModelContainer) async {
        await PremiumDerivedRebuilder(modelContainer: container).runAchievements()
    }
}

@ModelActor
actor PremiumDerivedRebuilder {
    private static let batchSize = 200

    func run() async {
        clearRoutes()
        clearAchievements()
        try? modelContext.save()
        await replayTrips(includeRoutes: true)
    }

    func runRoutes() async {
        clearRoutes()
        try? modelContext.save()
        await replayRouteAggregates()
    }

    func runAchievements() async {
        clearAchievements()
        try? modelContext.save()
        await replayTrips(includeRoutes: false)
    }

    private func clearRoutes() {
        for row in (try? modelContext.fetch(FetchDescriptor<FrequentRouteAggregate>())) ?? [] {
            modelContext.delete(row)
        }
    }

    private func clearAchievements() {
        for row in (try? modelContext.fetch(FetchDescriptor<AchievementProgress>())) ?? [] {
            modelContext.delete(row)
        }
        for row in (try? modelContext.fetch(FetchDescriptor<VisitedLocality>())) ?? [] {
            modelContext.delete(row)
        }
    }

    private func replayTrips(includeRoutes: Bool) async {
        AchievementEvaluator.markCatalogSeeded()
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName)?
            .double(forKey: "privacyRadiusMeters") ?? 150
        let radius = privacyRadius > 0 ? privacyRadius : 500

        var offset = 0
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
                if includeRoutes {
                    let snapshot = PremiumDerivedDelta.snapshot(
                        of: trip,
                        places: places,
                        privacyRadius: radius
                    )
                    PremiumDerivedDelta.apply(
                        trip: trip,
                        snapshot: snapshot,
                        sign: 1,
                        in: modelContext,
                        notify: false
                    )
                    trip.invalidatePointCaches()
                } else {
                    AchievementEvaluator.apply(
                        trip: trip,
                        sign: 1,
                        localities: TripLocalityResolver.localities(on: trip),
                        in: modelContext,
                        notify: false
                    )
                }
            }
            try? modelContext.save()
            offset += batch.count
            await Task.yield()
        }

        YearRecapCache.invalidateAll()
    }

    /// Routes only — must not re-apply achievements (those stay on their own replay).
    private func replayRouteAggregates() async {
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName)?
            .double(forKey: "privacyRadiusMeters") ?? 150
        let radius = privacyRadius > 0 ? privacyRadius : 500

        var offset = 0
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
                if let snapshot = FrequentRouteAggregateService.snapshot(
                    of: trip,
                    places: places,
                    privacyRadius: radius
                ) {
                    FrequentRouteAggregateService.add(snapshot, in: modelContext)
                }
            }
            try? modelContext.save()
            offset += batch.count
            await Task.yield()
        }

        YearRecapCache.invalidateAll()
    }
}
