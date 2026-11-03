import Foundation
import SwiftData

@ModelActor
actor YearRecapSnapshotLoader {
    private var cache: [Int: YearRecapSnapshot] = [:]
    private var cachedStoreVersion: Int?

    func snapshot(year: Int, storeVersion: Int, now: Date = Date()) -> YearRecapSnapshot {
        let storeChanged = cachedStoreVersion != nil && cachedStoreVersion != storeVersion
        if cachedStoreVersion != storeVersion {
            cache.removeAll(keepingCapacity: true)
            cachedStoreVersion = storeVersion
        }
        if let cached = cache[year] { return cached }
        if !storeChanged, let disk = YearRecapCache.load(year: year) {
            cache[year] = disk
            return disk
        }
        let built = build(year: year, now: now)
        cache[year] = built
        YearRecapCache.save(built)
        return built
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cachedStoreVersion = nil
    }

    private func build(year: Int, now: Date) -> YearRecapSnapshot {
        _ = now
        let calendar = Calendar.current
        guard
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart)
        else {
            return .empty(year: year)
        }

        let rollupDescriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart >= yearStart && rollup.dayStart < yearEnd
            }
        )
        let rollups = (try? modelContext.fetch(rollupDescriptor)) ?? []

        var distance = 0.0
        var duration = 0.0
        var tripCount = 0
        var night = 0.0
        var fuel = 0.0
        var businessDistance = 0.0
        var otherDistance = 0.0
        var monthDistance: [Int: Double] = [:]
        var activeDays = Set<Date>()
        var purposeTotals: [String: RecapPurposeBucket] = [:]

        let categories = (try? modelContext.fetch(FetchDescriptor<UserCategory>())) ?? []
        var customNames: [String: String] = [:]
        for category in categories where !category.isBuiltIn {
            let trimmed = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                customNames[category.id.uuidString] = trimmed
            }
        }
        let knownCustomIDs = Set(customNames.keys)

        let businessID = BuiltInCategory.businessID.uuidString
        let legacyBusiness = TripCategory.business.rawValue
        for rollup in rollups {
            distance += rollup.distanceMeters
            duration += rollup.duration
            tripCount += rollup.tripCount
            night += rollup.nightDistanceMeters
            fuel += rollup.estimatedFuelCost
            if rollup.categoryID == businessID || rollup.categoryID == legacyBusiness {
                businessDistance += rollup.distanceMeters
            } else {
                otherDistance += rollup.distanceMeters
            }
            let key = RecapPurposePolicy.bucketKey(
                forCategoryID: rollup.categoryID,
                knownCustomIDs: knownCustomIDs
            )
            let kind = RecapPurposePolicy.kind(forCategoryID: rollup.categoryID)
            let resolvedKind: RecapPurposeKind = key == "other" ? .custom : kind
            var bucket = purposeTotals[key] ?? RecapPurposeBucket(
                kind: resolvedKind,
                customName: key == "other" ? nil : customNames[key],
                distanceMeters: 0
            )
            bucket.distanceMeters += rollup.distanceMeters
            purposeTotals[key] = bucket
            let month = calendar.component(.month, from: rollup.dayStart)
            monthDistance[month, default: 0] += rollup.distanceMeters
            if rollup.tripCount > 0 {
                activeDays.insert(calendar.startOfDay(for: rollup.dayStart))
            }
        }

        let tripDescriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in
                trip.endedAt != nil && trip.startedAt >= yearStart && trip.startedAt < yearEnd
            }
        )
        let trips = (try? modelContext.fetch(tripDescriptor)) ?? []
        var cityCounts: [String: Int] = [:]
        for trip in trips {
            for name in TripLocalityResolver.localities(on: trip) {
                cityCounts[name, default: 0] += 1
            }
        }
        let topCities = cityCounts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(3).map(\.key)

        let topRoute = yearTopRoute(from: trips)

        let expenseDescriptor = FetchDescriptor<VehicleExpense>(
            predicate: #Predicate { expense in
                expense.occurredAt >= yearStart && expense.occurredAt < yearEnd
            }
        )
        let paid = ((try? modelContext.fetch(expenseDescriptor)) ?? [])
            .filter { $0.category == .fuel }
            .reduce(0) { $0 + $1.amount }

        let progressRows = ((try? modelContext.fetch(FetchDescriptor<AchievementProgress>())) ?? [])
        let yearUnlocked = progressRows.compactMap { row -> String? in
            guard let unlockedAt = row.unlockedAt else { return nil }
            let unlockedYear = calendar.component(.year, from: unlockedAt)
            return unlockedYear == year ? row.achievementID : nil
        }
        let lifetimeUnlocked = progressRows.compactMap { row -> String? in
            row.unlockedAt == nil ? nil : row.achievementID
        }
        let unlocked = yearUnlocked.isEmpty ? lifetimeUnlocked : yearUnlocked

        let busiest = monthDistance.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }

        return YearRecapSnapshot(
            year: year,
            tripCount: tripCount,
            distanceMeters: distance,
            duration: duration,
            cityCount: cityCounts.count,
            topCities: Array(topCities),
            topRouteStart: topRoute?.start,
            topRouteEnd: topRoute?.end,
            topRouteCount: topRoute?.count ?? 0,
            topRouteStartLatitude: topRoute?.startLatitude,
            topRouteStartLongitude: topRoute?.startLongitude,
            topRouteEndLatitude: topRoute?.endLatitude,
            topRouteEndLongitude: topRoute?.endLongitude,
            nightDistanceMeters: night,
            longestStreak: longestStreak(in: activeDays, calendar: calendar),
            busiestMonth: busiest?.key,
            busiestMonthDistanceMeters: busiest?.value ?? 0,
            businessDistanceMeters: businessDistance,
            personalDistanceMeters: otherDistance,
            purposeVerdict: RecapPurposePolicy.verdict(from: Array(purposeTotals.values)),
            estimatedFuelCost: fuel,
            paidExpenses: paid,
            unlockedAchievementIDs: unlocked
        )
    }

    private struct YearTopRoute {
        var start: String
        var end: String
        var count: Int
        var startLatitude: Double?
        var startLongitude: Double?
        var endLatitude: Double?
        var endLongitude: Double?
    }

    private func yearTopRoute(from trips: [Trip]) -> YearTopRoute? {
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = privacyRadiusMeters()
        var counts: [String: (snapshot: FrequentRouteSnapshot, count: Int)] = [:]
        for trip in trips {
            guard let snapshot = FrequentRouteAggregateService.snapshot(
                of: trip,
                places: places,
                privacyRadius: privacyRadius
            ) else { continue }
            var entry = counts[snapshot.pairKey] ?? (snapshot, 0)
            entry.count += 1
            entry.snapshot = snapshot
            counts[snapshot.pairKey] = entry
        }
        guard let best = counts.values.max(by: { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs.snapshot.pairKey > rhs.snapshot.pairKey
        }) else { return nil }
        return YearTopRoute(
            start: best.snapshot.startDisplay,
            end: best.snapshot.endDisplay,
            count: best.count,
            startLatitude: best.snapshot.startLatitude,
            startLongitude: best.snapshot.startLongitude,
            endLatitude: best.snapshot.endLatitude,
            endLongitude: best.snapshot.endLongitude
        )
    }

    private func privacyRadiusMeters() -> Double {
        let defaults = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName) ?? .standard
        let value = defaults.double(forKey: "privacyRadiusMeters")
        return value > 0 ? value : 500
    }

    private func longestStreak(in days: Set<Date>, calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var best = 1
        var current = 1
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let day = sorted[index]
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: day) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
}
