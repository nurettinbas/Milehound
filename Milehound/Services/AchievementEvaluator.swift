import Foundation
import SwiftData

enum AchievementEvaluator {
    static let catalogSeedKey = "milehound.achievements.catalogSeed"
    /// Bump when new trip-derived families need a one-shot backfill from existing trips.
    static let catalogSeedVersion = 3

    static func markCatalogSeeded() {
        UserDefaults.standard.set(catalogSeedVersion, forKey: catalogSeedKey)
    }

    static let celebrationReplayKey = "milehound.achievements.celebrationReplay"
    static let celebrationReplayVersion = 1

    /// One-shot: already-earned medals play the Stats unlock overlay as if they were new.
    /// Does not write inbox rows. Later visits stay quiet.
    @discardableResult
    static func replayUnlockCelebrationsIfNeeded(in context: ModelContext) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: celebrationReplayKey) < celebrationReplayVersion else {
            return false
        }
        let rows = (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
        var didChange = false
        for row in rows where row.unlockedAt != nil && row.seenAt != nil {
            row.seenAt = nil
            didChange = true
        }
        defaults.set(celebrationReplayVersion, forKey: celebrationReplayKey)
        if didChange {
            try? context.save()
        }
        return didChange
    }

    @discardableResult
    static func apply(
        trip: Trip,
        sign: Double,
        localities: [String],
        in context: ModelContext,
        notify: Bool = true
    ) -> [AchievementID] {
        guard trip.endedAt != nil else { return [] }
        let eventDate = trip.endedAt ?? trip.startedAt
        let silent = !notify
        var newly: [AchievementID] = []
        func collect(_ id: AchievementID, unlocked: Bool) {
            if unlocked { newly.append(id) }
        }
        collect(.firstTrip, unlocked: bump(.firstTrip, by: sign, at: eventDate, silent: silent, in: context))
        collect(.distance100, unlocked: bump(.distance100, by: sign * trip.distanceMeters, at: eventDate, silent: silent, in: context))
        collect(.distance1000, unlocked: bump(.distance1000, by: sign * trip.distanceMeters, at: eventDate, silent: silent, in: context))
        collect(.distance10000, unlocked: bump(.distance10000, by: sign * trip.distanceMeters, at: eventDate, silent: silent, in: context))
        collect(.distance100000, unlocked: bump(.distance100000, by: sign * trip.distanceMeters, at: eventDate, silent: silent, in: context))
        seedDistance100000(in: context)
        if trip.categoryID == BuiltInCategory.businessID.uuidString {
            collect(.business10, unlocked: bump(.business10, by: sign, at: eventDate, silent: silent, in: context))
            collect(.business50, unlocked: bump(.business50, by: sign, at: eventDate, silent: silent, in: context))
            collect(.business100, unlocked: bump(.business100, by: sign, at: eventDate, silent: silent, in: context))
        }
        collect(.nightOwl, unlocked: bump(.nightOwl, by: sign * (trip.nightDistanceMeters ?? 0), at: eventDate, silent: silent, in: context))
        collect(.night1000, unlocked: bump(.night1000, by: sign * (trip.nightDistanceMeters ?? 0), at: eventDate, silent: silent, in: context))
        collect(.trips50, unlocked: bump(.trips50, by: sign, at: eventDate, silent: silent, in: context))
        collect(.trips250, unlocked: bump(.trips250, by: sign, at: eventDate, silent: silent, in: context))
        let hours = sign * (trip.duration ?? 0) / 3600
        collect(.hours24, unlocked: bump(.hours24, by: hours, at: eventDate, silent: silent, in: context))
        collect(.hours100, unlocked: bump(.hours100, by: hours, at: eventDate, silent: silent, in: context))
        if trip.distanceMeters + 0.000_1 >= 100_000 {
            collect(.longhaul1, unlocked: bump(.longhaul1, by: sign, at: eventDate, silent: silent, in: context))
            collect(.longhaul10, unlocked: bump(.longhaul10, by: sign, at: eventDate, silent: silent, in: context))
        }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: trip.startedAt)
        if (5...8).contains(hour) {
            collect(.dawn10, unlocked: bump(.dawn10, by: sign, at: eventDate, silent: silent, in: context))
            collect(.dawn50, unlocked: bump(.dawn50, by: sign, at: eventDate, silent: silent, in: context))
        }
        if calendar.isDateInWeekend(trip.startedAt) {
            collect(.weekend10, unlocked: bump(.weekend10, by: sign, at: eventDate, silent: silent, in: context))
            collect(.weekend50, unlocked: bump(.weekend50, by: sign, at: eventDate, silent: silent, in: context))
        }
        newly.append(contentsOf: refreshFleetAndCountries(at: eventDate, silent: silent, in: context))
        newly.append(contentsOf: applyLocalities(localities, sign: sign, at: eventDate, silent: silent, in: context))
        newly.append(contentsOf: refreshStreak(at: eventDate, silent: silent, in: context))
        newly.append(contentsOf: refreshRouteRegular(at: eventDate, silent: silent, in: context))
        seedFillLadders(in: context)
        if notify, sign > 0, !newly.isEmpty, !UITestSupport.isUnitTesting {
            let ids = newly
            Task { @MainActor in
                TripNotificationService.notifyAchievementsUnlocked(ids)
            }
        }
        return newly
    }

    static func displays(in context: ModelContext) -> [AchievementDisplay] {
        seedNewFamiliesIfNeeded(in: context)
        seedDistance100000(in: context)
        seedFillLadders(in: context)
        try? context.save()
        let rows = (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.achievementID, $0) })
        let unlocked = Set(rows.compactMap { row -> AchievementID? in
            guard row.unlockedAt != nil else { return nil }
            return AchievementID(rawValue: row.achievementID)
        })
        return AchievementID.allCases.compactMap { id in
            if let predecessor = id.predecessor,
               !id.listsWhilePredecessorLocked,
               !unlocked.contains(predecessor),
               byID[id.rawValue]?.unlockedAt == nil {
                return nil
            }
            let row = byID[id.rawValue]
            return AchievementDisplay(
                id: id,
                currentValue: row?.currentValue ?? 0,
                unlockedAt: row?.unlockedAt,
                needsCelebration: row?.needsCelebration ?? false
            )
        }
        .sorted(by: AchievementDisplay.listOrder)
    }

    static func markSeen(_ ids: [AchievementID], in context: ModelContext) {
        let names = Set(ids.map(\.rawValue))
        let rows = (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
        let now = Date()
        for row in rows where names.contains(row.achievementID) && row.needsCelebration {
            row.seenAt = now
        }
    }

    static func rebuild(in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? [] {
            context.delete(row)
        }
        for row in (try? context.fetch(FetchDescriptor<VisitedLocality>())) ?? [] {
            context.delete(row)
        }

        markCatalogSeeded()
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let trips = (try? context.fetch(descriptor)) ?? []
        for trip in trips {
            apply(
                trip: trip,
                sign: 1,
                localities: TripLocalityResolver.localities(on: trip),
                in: context,
                notify: false
            )
        }
    }

    @discardableResult
    private static func seedNewFamiliesIfNeeded(in context: ModelContext) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: catalogSeedKey) < catalogSeedVersion else { return false }
        let trips = endedTrips(in: context)
        let knownTrips = storedValue(for: .firstTrip, in: context)
        // An empty (or short) fetch while first-trip already counted history means the
        // store did not load yet — do not stamp the seed key or those trips are lost forever.
        if trips.isEmpty || knownTrips > Double(trips.count) + 0.000_1 {
            return false
        }
        applyTotals(totals(from: trips), in: context, silent: true)
        markCatalogSeeded()
        try? context.save()
        return true
    }

    private static func endedTrips(in context: ModelContext) -> [Trip] {
        ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter { $0.endedAt != nil }
    }

    private struct TripCatalogTotals {
        var trips = 0.0
        var hours = 0.0
        var longhaul = 0.0
        var dawn = 0.0
        var weekend = 0.0
        var vehicleIDs = Set<UUID>()
        var countries = Set<String>()
        var distanceMeters = 0.0
        var nightMeters = 0.0
        var business = 0.0
    }

    private static func totals(from trips: [Trip], calendar: Calendar = .current) -> TripCatalogTotals {
        var t = TripCatalogTotals()
        for trip in trips {
            t.trips += 1
            t.hours += (trip.duration ?? 0) / 3600
            t.distanceMeters += trip.distanceMeters
            t.nightMeters += trip.nightDistanceMeters ?? 0
            if trip.categoryID == BuiltInCategory.businessID.uuidString {
                t.business += 1
            }
            if trip.distanceMeters + 0.000_1 >= 100_000 {
                t.longhaul += 1
            }
            let hour = calendar.component(.hour, from: trip.startedAt)
            if (5...8).contains(hour) {
                t.dawn += 1
            }
            if calendar.isDateInWeekend(trip.startedAt) {
                t.weekend += 1
            }
            if let vehicleID = trip.vehicleID {
                t.vehicleIDs.insert(vehicleID)
            }
            if let code = trip.startCountryCode, !code.isEmpty {
                t.countries.insert(code)
            }
            if let code = trip.endCountryCode, !code.isEmpty {
                t.countries.insert(code)
            }
        }
        return t
    }

    private static func applyTotals(_ t: TripCatalogTotals, in context: ModelContext, silent: Bool) {
        let eventDate = Date()
        setValue(.firstTrip, t.trips, at: eventDate, silent: silent, in: context)
        setValue(.distance100, t.distanceMeters, at: eventDate, silent: silent, in: context)
        setValue(.distance1000, t.distanceMeters, at: eventDate, silent: silent, in: context)
        setValue(.distance10000, t.distanceMeters, at: eventDate, silent: silent, in: context)
        setValue(.distance100000, t.distanceMeters, at: eventDate, silent: silent, in: context)
        setValue(.business10, t.business, at: eventDate, silent: silent, in: context)
        setValue(.business50, t.business, at: eventDate, silent: silent, in: context)
        setValue(.business100, t.business, at: eventDate, silent: silent, in: context)
        setValue(.nightOwl, t.nightMeters, at: eventDate, silent: silent, in: context)
        setValue(.night1000, t.nightMeters, at: eventDate, silent: silent, in: context)
        setValue(.trips50, t.trips, at: eventDate, silent: silent, in: context)
        setValue(.trips250, t.trips, at: eventDate, silent: silent, in: context)
        setValue(.hours24, t.hours, at: eventDate, silent: silent, in: context)
        setValue(.hours100, t.hours, at: eventDate, silent: silent, in: context)
        setValue(.longhaul1, t.longhaul, at: eventDate, silent: silent, in: context)
        setValue(.longhaul10, t.longhaul, at: eventDate, silent: silent, in: context)
        setValue(.dawn10, t.dawn, at: eventDate, silent: silent, in: context)
        setValue(.dawn50, t.dawn, at: eventDate, silent: silent, in: context)
        setValue(.weekend10, t.weekend, at: eventDate, silent: silent, in: context)
        setValue(.weekend50, t.weekend, at: eventDate, silent: silent, in: context)
        setValue(.fleet2, Double(t.vehicleIDs.count), at: eventDate, silent: silent, in: context)
        setValue(.countries2, Double(t.countries.count), at: eventDate, silent: silent, in: context)
    }

    private static func seedFillLadders(in context: ModelContext) {
        copyUp(.trips50, from: [.firstTrip], in: context)
        copyUp(.trips250, from: [.firstTrip, .trips50], in: context)
        copyUp(.business100, from: [.business10, .business50], in: context)
        copyUp(.night1000, from: [.nightOwl], in: context)
        copyUp(.cities50, from: [.cities10, .cities25], in: context)
        copyUp(.routes25, from: [.routesRegular], in: context)
        copyUp(.streak100, from: [.streak7, .streak30], in: context)
    }

    private static func copyUp(_ id: AchievementID, from sources: [AchievementID], in context: ModelContext) {
        let value = sources.map { storedValue(for: $0, in: context) }.max() ?? 0
        guard value > 0 else { return }
        let row = progress(for: id, in: context)
        if row.currentValue + 0.000_1 < value {
            row.currentValue = value
        }
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= id.threshold {
            let now = Date()
            row.unlockedAt = now
            row.seenAt = now
            YearRecapCache.invalidate(yearContaining: now)
        }
    }

    /// Copy cumulative metres onto the 100,000 km row without a full rebuild.
    /// Already-earned unlocks skip the celebration overlay (`seenAt = now`).
    private static func seedDistance100000(in context: ModelContext) {
        let meters = [
            storedValue(for: .distance100, in: context),
            storedValue(for: .distance1000, in: context),
            storedValue(for: .distance10000, in: context)
        ].max() ?? 0
        guard meters > 0 else { return }
        let row = progress(for: .distance100000, in: context)
        if row.currentValue + 0.000_1 < meters {
            row.currentValue = meters
        }
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= AchievementID.distance100000.threshold {
            let now = Date()
            row.unlockedAt = now
            row.seenAt = now
            YearRecapCache.invalidate(yearContaining: now)
        }
    }

    private static func storedValue(for id: AchievementID, in context: ModelContext) -> Double {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<AchievementProgress>(
            predicate: #Predicate { row in
                row.achievementID == raw
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.currentValue ?? 0
    }

    @discardableResult
    private static func bump(
        _ id: AchievementID,
        by delta: Double,
        at eventDate: Date,
        silent: Bool,
        in context: ModelContext
    ) -> Bool {
        guard delta != 0 else { return false }
        let row = progress(for: id, in: context)
        row.currentValue = max(0, row.currentValue + delta)
        return unlockIfNeeded(row, id: id, at: eventDate, silent: silent)
    }

    @discardableResult
    private static func applyLocalities(
        _ localities: [String],
        sign: Double,
        at eventDate: Date,
        silent: Bool,
        in context: ModelContext
    ) -> [AchievementID] {
        guard sign != 0 else { return [] }
        for name in Set(localities) {
            let existing = locality(named: name, in: context)
            if sign > 0 {
                if let existing {
                    existing.visitCount += 1
                } else {
                    context.insert(VisitedLocality(name: name, visitCount: 1))
                }
            } else if let existing {
                existing.visitCount = max(0, existing.visitCount - 1)
                if existing.visitCount == 0 {
                    context.delete(existing)
                }
            }
        }
        let count = Double(((try? context.fetch(FetchDescriptor<VisitedLocality>())) ?? []).count)
        var newly: [AchievementID] = []
        if setValue(.cities10, count, at: eventDate, silent: silent, in: context) { newly.append(.cities10) }
        if setValue(.cities25, count, at: eventDate, silent: silent, in: context) { newly.append(.cities25) }
        if setValue(.cities50, count, at: eventDate, silent: silent, in: context) { newly.append(.cities50) }
        return newly
    }

    @discardableResult
    private static func refreshStreak(at eventDate: Date, silent: Bool, in context: ModelContext) -> [AchievementID] {
        let streak = currentStreakDays(in: context)
        var newly: [AchievementID] = []
        if setValue(.streak7, Double(streak), at: eventDate, silent: silent, in: context) { newly.append(.streak7) }
        if setValue(.streak30, Double(streak), at: eventDate, silent: silent, in: context) { newly.append(.streak30) }
        if setValue(.streak100, Double(streak), at: eventDate, silent: silent, in: context) { newly.append(.streak100) }
        return newly
    }

    @discardableResult
    private static func refreshRouteRegular(at eventDate: Date, silent: Bool, in context: ModelContext) -> [AchievementID] {
        var descriptor = FetchDescriptor<FrequentRouteAggregate>(
            sortBy: [SortDescriptor(\.count, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let best = Double((try? context.fetch(descriptor))?.first?.count ?? 0)
        var newly: [AchievementID] = []
        if setValue(.routesRegular, best, at: eventDate, silent: silent, in: context) { newly.append(.routesRegular) }
        if setValue(.routes25, best, at: eventDate, silent: silent, in: context) { newly.append(.routes25) }
        return newly
    }

    @discardableResult
    private static func refreshFleetAndCountries(
        at eventDate: Date,
        silent: Bool,
        in context: ModelContext
    ) -> [AchievementID] {
        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter { $0.endedAt != nil }
        let t = totals(from: trips)
        var newly: [AchievementID] = []
        if setValue(.fleet2, Double(t.vehicleIDs.count), at: eventDate, silent: silent, in: context) { newly.append(.fleet2) }
        if setValue(.countries2, Double(t.countries.count), at: eventDate, silent: silent, in: context) { newly.append(.countries2) }
        return newly
    }

    static func currentStreakDays(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let rollups = (try? context.fetch(FetchDescriptor<TripDailyRollup>())) ?? []
        var days = Set<Date>()
        for rollup in rollups where rollup.tripCount > 0 {
            days.insert(calendar.startOfDay(for: rollup.dayStart))
        }
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
            guard days.contains(cursor) else { return 0 }
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    @discardableResult
    private static func setValue(
        _ id: AchievementID,
        _ value: Double,
        at eventDate: Date,
        silent: Bool,
        in context: ModelContext
    ) -> Bool {
        let row = progress(for: id, in: context)
        row.currentValue = max(0, value)
        return unlockIfNeeded(row, id: id, at: eventDate, silent: silent)
    }

    @discardableResult
    private static func unlockIfNeeded(
        _ row: AchievementProgress,
        id: AchievementID,
        at eventDate: Date,
        silent: Bool
    ) -> Bool {
        guard row.unlockedAt == nil, row.currentValue + 0.000_1 >= id.threshold else { return false }
        row.unlockedAt = eventDate
        if silent {
            row.seenAt = eventDate
        }
        YearRecapCache.invalidate(yearContaining: eventDate)
        return true
    }

    private static func progress(for id: AchievementID, in context: ModelContext) -> AchievementProgress {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<AchievementProgress>(
            predicate: #Predicate { row in
                row.achievementID == raw
            }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = AchievementProgress(achievementID: raw)
        context.insert(created)
        return created
    }

    private static func locality(named name: String, in context: ModelContext) -> VisitedLocality? {
        var descriptor = FetchDescriptor<VisitedLocality>(
            predicate: #Predicate { row in
                row.name == name
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

/// Stats unlock overlay queue. Append newly unlocked badges; never reset the card on screen.
enum AchievementUnlockQueue {
    static func merging(queued: [AchievementDisplay], pending: [AchievementDisplay]) -> [AchievementDisplay] {
        if queued.isEmpty { return pending }
        let ids = Set(queued.map(\.id))
        return queued + pending.filter { !ids.contains($0.id) }
    }
}

/// Compact Recap card: every unlocked medal, wrapping into centered rows.
enum AchievementStripPreview {
    static func medals(from achievements: [AchievementDisplay]) -> [AchievementDisplay] {
        achievements.filter(\.isUnlocked)
    }
}
