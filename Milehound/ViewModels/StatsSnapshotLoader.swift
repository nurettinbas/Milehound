import Foundation
import SwiftData

/// Everything needed to build a stats snapshot away from the main actor.
struct StatsSnapshotRequest: Sendable, Hashable {
    let storeVersion: Int
    let selectedPeriod: StatsPeriod
    let customStart: Date
    let customEnd: Date
    let selectedMonth: Date
    /// Normalized calendar-month start the goal ring tracks.
    let goalMonth: Date
    let selectedCategoryID: String?
    let selectedVehicleID: UUID?
    /// Exact `SavedPlace.name` for start-or-end matching. `nil` means All.
    let selectedPlaceName: String?
    let selectedJournalID: UUID?
    let categoryNames: StatsNameMap
    let vehicleNames: StatsNameMap
    let vehicleCount: Int

    init(
        storeVersion: Int,
        selectedPeriod: StatsPeriod,
        customStart: Date,
        customEnd: Date,
        selectedMonth: Date,
        goalMonth: Date,
        selectedCategoryID: String?,
        selectedVehicleID: UUID?,
        selectedPlaceName: String?,
        selectedJournalID: UUID? = nil,
        categoryNames: StatsNameMap,
        vehicleNames: StatsNameMap,
        vehicleCount: Int
    ) {
        self.storeVersion = storeVersion
        self.selectedPeriod = selectedPeriod
        self.customStart = customStart
        self.customEnd = customEnd
        self.selectedMonth = selectedMonth
        self.goalMonth = goalMonth
        self.selectedCategoryID = selectedCategoryID
        self.selectedVehicleID = selectedVehicleID
        self.selectedPlaceName = selectedPlaceName
        self.selectedJournalID = selectedJournalID
        self.categoryNames = categoryNames
        self.vehicleNames = vehicleNames
        self.vehicleCount = vehicleCount
    }
}

extension StatsNameMap: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(names)
        hasher.combine(fallback)
    }

    static func == (lhs: StatsNameMap, rhs: StatsNameMap) -> Bool {
        lhs.names == rhs.names && lhs.fallback == rhs.fallback
    }
}

/// Fetches trips (or daily rollups) and builds a `StatsDisplaySnapshot` on its own model context,
/// so the stats tab never aggregates on the main thread.
@ModelActor
actor StatsSnapshotLoader {
    private static let rollupThreshold: TimeInterval = 92 * 86_400
    private static let maximumTripDuration: TimeInterval = 48 * 3_600
    private static let maxCacheEntries = 8

    private var cache: [StatsSnapshotRequest: StatsDisplaySnapshot] = [:]
    private var cacheOrder: [StatsSnapshotRequest] = []
    private var cachedStoreVersion: Int?

    func snapshot(for request: StatsSnapshotRequest) -> StatsDisplaySnapshot {
        if cachedStoreVersion != request.storeVersion {
            cache.removeAll(keepingCapacity: true)
            cacheOrder.removeAll(keepingCapacity: true)
            cachedStoreVersion = request.storeVersion
        }

        if let cached = cache[request] {
            return cached
        }

        let built = build(request)
        insertCache(request, snapshot: built)
        return built
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        cachedStoreVersion = nil
    }

    private func insertCache(_ request: StatsSnapshotRequest, snapshot: StatsDisplaySnapshot) {
        if cache[request] == nil {
            cacheOrder.append(request)
        }
        cache[request] = snapshot
        while cacheOrder.count > Self.maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func build(_ request: StatsSnapshotRequest) -> StatsDisplaySnapshot {
        let selected = StatsViewModel.interval(
            for: request.selectedPeriod,
            customStart: request.customStart,
            customEnd: request.customEnd,
            selectedMonth: request.selectedMonth
        )
        let previous: DateInterval
        switch request.selectedPeriod {
        case .month:
            previous = StatsViewModel.previousMonthInterval(containing: request.selectedMonth)
        case .week:
            previous = StatsViewModel.alignedPreviousInterval(
                for: .week,
                selectedInterval: selected,
                selectedMonth: request.selectedMonth
            )
        case .custom:
            previous = StatsViewModel.previousInterval(for: selected)
        }
        let goalMonthInterval = StatsViewModel.calendarMonthInterval(containing: request.goalMonth)
        let interval = DateInterval(
            start: min(selected.start, previous.start, goalMonthInterval.start),
            end: max(selected.end, previous.end, goalMonthInterval.end)
        )

        let rows = fetchStatsRows(
            in: interval,
            placeName: request.selectedPlaceName,
            journalID: request.selectedJournalID
        )
        return StatsDisplaySnapshotBuilder.build(
            completedTrips: rows,
            categoryNames: request.categoryNames,
            vehicleNames: request.vehicleNames,
            vehicleCount: request.vehicleCount,
            selectedPeriod: request.selectedPeriod,
            customStart: request.customStart,
            customEnd: request.customEnd,
            selectedMonth: request.selectedMonth,
            selectedCategoryID: request.selectedCategoryID,
            selectedVehicleID: request.selectedVehicleID,
            selectedPlaceName: request.selectedPlaceName,
            selectedJournalID: request.selectedJournalID,
            goalMonth: request.goalMonth
        )
    }

    /// Place or journal filter forces the trip path: daily rollups have neither dimension.
    private func fetchStatsRows(
        in interval: DateInterval,
        placeName: String?,
        journalID: UUID?
    ) -> [TripStatsRow] {
        let placeFilterActive = !(placeName ?? "").isEmpty
        let journalFilterActive = journalID != nil
        if !placeFilterActive, !journalFilterActive, interval.duration > Self.rollupThreshold {
            let rollupRows = fetchRollupRows(in: interval)
            if !rollupRows.isEmpty { return rollupRows }
        }
        return fetchTripRows(in: interval)
    }

    private func fetchRollupRows(in interval: DateInterval) -> [TripStatsRow] {
        let calendar = Calendar.current
        let lowerBound = calendar.startOfDay(for: interval.start)
        let upperBound = interval.end
        let descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { $0.dayStart >= lowerBound && $0.dayStart <= upperBound },
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        let rollups = (try? modelContext.fetch(descriptor)) ?? []
        return rollups.map(TripStatsRow.init(rollup:))
    }

    private func fetchTripRows(in interval: DateInterval) -> [TripStatsRow] {
        let lowerBound = interval.start
        let upperBound = interval.end
        let fetchLowerBound = lowerBound.addingTimeInterval(-Self.maximumTripDuration)
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in
                trip.endedAt != nil && trip.startedAt >= fetchLowerBound && trip.startedAt <= upperBound
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let trips = (try? modelContext.fetch(descriptor)) ?? []
        return trips.map(TripStatsRow.init(trip:))
    }
}
