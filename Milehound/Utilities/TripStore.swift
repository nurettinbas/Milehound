import Foundation
import SwiftData

@MainActor
enum TripStore {
    static func all(from context: ModelContext) -> [Trip] {
        (try? context.fetch(FetchDescriptor<Trip>())) ?? []
    }

    static func completed(from context: ModelContext) -> [Trip] {
        all(from: context).filter(isCompleted)
    }

    static func completedSince(_ date: Date, from context: ModelContext) -> [Trip] {
        let minimum = date.timeIntervalSinceReferenceDate
        return completed(from: context).filter { trip in
            trip.startedAt.timeIntervalSinceReferenceDate >= minimum
        }
    }

    static func completedBefore(_ date: Date, from context: ModelContext) -> [Trip] {
        let maximum = date.timeIntervalSinceReferenceDate
        return completed(from: context).filter { trip in
            trip.startedAt.timeIntervalSinceReferenceDate < maximum
        }
    }

    /// Unfinished trips are rare. Cap the read so a tab refresh never materializes the library.
    static let orphanFetchLimit = 8

    static func orphans(from context: ModelContext) -> [Trip] {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = orphanFetchLimit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func orphansNewestFirst(from context: ModelContext) -> [Trip] {
        orphans(from: context)
    }

    static func trip(id: UUID, from context: ModelContext) -> Trip? {
        all(from: context).first { $0.id == id }
    }

    /// Prefer persisted App Group trip ID; fall back to startedAt match, then newest orphan.
    static func orphanMatchingRecordingSession(
        tripID: UUID?,
        startedAt: Date?,
        from context: ModelContext
    ) -> Trip? {
        if let tripID, let trip = trip(id: tripID, from: context), trip.duration == nil {
            return trip
        }
        let orphans = orphansNewestFirst(from: context)
        guard !orphans.isEmpty else { return nil }
        if let startedAt {
            let tolerance: TimeInterval = 2
            if let match = orphans.first(where: {
                abs($0.startedAt.timeIntervalSince(startedAt)) <= tolerance
            }) {
                return match
            }
            return orphans.first
        }
        return nil
    }

    static func syncWidgetWeekDistance(in context: ModelContext) {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekTrips = StatsViewModel.trips(
            in: DateInterval(start: weekAgo, end: Date()),
            from: completedSince(weekAgo, from: context)
        )
        let stats = StatsViewModel.stats(for: weekTrips, includeNightRatio: false)
        let defaults = UserDefaults(suiteName: "group.com.milehound.app")
        defaults?.set(stats.totalDistanceMeters, forKey: "stats.weekDistance")

        let monthInterval = StatsViewModel.calendarMonthInterval(containing: Date())
        let monthTrips = StatsViewModel.trips(
            in: monthInterval,
            from: completedSince(monthInterval.start, from: context)
        )
        defaults?.set(
            StatsViewModel.stats(for: monthTrips, includeNightRatio: false).totalDistanceMeters,
            forKey: "stats.monthDistance"
        )

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayTrips = completedSince(startOfDay, from: context)
        let todayDistance = todayTrips.reduce(0) { $0 + $1.distanceMeters }
        TodayKmProvider.syncTodayDistance(todayDistance)
        PremiumWidgetBridge.sync(in: context)
    }

    private static func isCompleted(_ trip: Trip) -> Bool {
        trip.duration != nil
    }
}
