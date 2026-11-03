import Foundation
import SwiftData

struct DailyDistance: Identifiable, Sendable {
    let id: Date
    let day: Date
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct DailyDuration: Identifiable, Sendable {
    let id: Date
    let day: Date
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct DailyAverageSpeed: Identifiable, Sendable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyMaxSpeed: Identifiable, Sendable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyCruiseSpeed: Identifiable, Sendable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyMostCommonSpeed: Identifiable, Sendable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyStopDuration: Identifiable, Sendable {
    let id: Date
    let day: Date
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct DailyFuelCost: Identifiable, Sendable {
    let id: Date
    let day: Date
    /// Catalog avg cost for the day.
    let cost: Double
    /// GPS-adjusted estimated cost for the day.
    let dynamicCost: Double

    init(id: Date, day: Date, cost: Double, dynamicCost: Double = 0) {
        self.id = id
        self.day = day
        self.cost = cost
        self.dynamicCost = dynamicCost
    }
}

struct DailyTripCount: Identifiable, Sendable {
    let id: Date
    let day: Date
    let count: Int
}

struct DailyNightDistance: Identifiable, Sendable {
    let id: Date
    let day: Date
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct WeekdayDistance: Identifiable, Sendable {
    let id: Int
    let weekday: Int
    let label: String
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct WeekdayDuration: Identifiable, Sendable {
    let id: Int
    let weekday: Int
    let label: String
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct FuelFactorShare: Identifiable, Sendable, Equatable {
    let kind: FuelFactorKind
    let volume: Double

    var id: String { kind.rawValue }
}

struct CategoryDistance: Identifiable, Sendable {
    let id: String
    let name: String
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct CategoryDuration: Identifiable, Sendable {
    let id: String
    let name: String
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct CategoryFuelCost: Identifiable, Sendable {
    let id: String
    let name: String
    let cost: Double
}

struct VehicleDistance: Identifiable, Sendable {
    let id: String
    let name: String
    let distanceMeters: Double

    static let unassignedID = "unassigned"

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct VehicleDuration: Identifiable, Sendable {
    let id: String
    let name: String
    let duration: TimeInterval

    static let unassignedID = VehicleDistance.unassignedID

    var durationHours: Double { duration / 3600 }
}

struct VehicleFuelCost: Identifiable, Sendable {
    let id: String
    let name: String
    let cost: Double

    static let unassignedID = VehicleDistance.unassignedID
}

enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: L10n.string("stats.period.week")
        case .month: L10n.string("stats.period.month")
        case .custom: L10n.string("stats.period.custom")
        }
    }
}

struct StatsViewModel {
    /// - Parameter includeNightRatio: Walking every GPS point is orders of magnitude more expensive
    ///   than the other aggregations. Callers that only read distance/duration must pass `false`.
    /// Narrows completed trips by optional category, vehicle, and favorite-place name filters.
    static func filtered<T: TripStatsAggregable>(
        _ trips: [T],
        categoryID: String? = nil,
        vehicleID: UUID? = nil,
        placeName: String? = nil,
        journalID: UUID? = nil
    ) -> [T] {
        trips.filter { trip in
            guard trip.endedAt != nil else { return false }
            if let categoryID, trip.categoryID != categoryID { return false }
            if let vehicleID, trip.vehicleID != vehicleID { return false }
            if !TripPlaceFilter.matches(trip, placeName: placeName) { return false }
            if let journalID, trip.journalID != journalID { return false }
            return true
        }
    }

    static func stats<T: TripStatsAggregable>(
        for trips: [T],
        categoryID: String? = nil,
        vehicleID: UUID? = nil,
        placeName: String? = nil,
        journalID: UUID? = nil,
        includeNightRatio: Bool = true
    ) -> TripStats {
        let completed = filtered(
            trips,
            categoryID: categoryID,
            vehicleID: vehicleID,
            placeName: placeName,
            journalID: journalID
        )

        let totalDistance = completed.reduce(0) { $0 + $1.distanceMeters }
        let totalDuration = completed.compactMap(\.duration).reduce(0, +)
        let totalFuel = completed.reduce(0) { partial, trip in
            partial + trip.resolvedFuelCost
        }
        let totalDynamicFuel = completed.reduce(0) { partial, trip in
            partial + trip.resolvedDynamicFuelCost
        }
        let count = completed.reduce(0) { $0 + $1.tripCount }
        let averageDuration = count > 0 ? totalDuration / Double(count) : 0
        let averageSpeedKmh = averageSpeedKmh(distanceMeters: totalDistance, duration: totalDuration)
        // Vetted rather than derived from points: statistics span thousands of trips, and a
        // single phantom reading would otherwise become the headline figure for the period.
        let maxSpeedKmh = completed
            .compactMap { TripSpeedSummary.believableStoredMaxSpeedMps($0.maxSpeedMps) }
            .map { $0 * 3.6 }
            .max() ?? 0
        let nightTotals = includeNightRatio
            ? nightDrivingTotals(for: completed)
            : (nightMeters: 0.0, trackedMeters: 0.0)
        let nightRatio = nightTotals.trackedMeters > 0
            ? nightTotals.nightMeters / nightTotals.trackedMeters
            : 0
        var cruiseWeight = 0.0
        var cruiseProduct = 0.0
        var mostCommonWeight = 0.0
        var mostCommonProduct = 0.0
        var stopDuration = 0.0
        for trip in completed {
            let weight = trip.resolvedCruiseDurationSeconds
            let speed = trip.resolvedCruiseSpeedKmh
            if weight > 0, speed > 0 {
                cruiseWeight += weight
                cruiseProduct += speed * weight
            }
            let mostCommon = trip.resolvedMostCommonSpeedKmh
            if weight > 0, mostCommon > 0 {
                mostCommonWeight += weight
                mostCommonProduct += mostCommon * weight
            }
            stopDuration += trip.resolvedStopDurationSeconds
        }

        var totalVolume = 0.0
        var volumeDistance = 0.0
        var efficiencyProduct = 0.0
        var idleVolume = 0.0
        var transientVolume = 0.0
        var coldVolume = 0.0
        var speedAbsVolume = 0.0
        var unitKeys = Set<String>()
        for trip in completed {
            let volume = trip.resolvedDynamicFuelVolume
            totalVolume += volume
            if volume > 0 { volumeDistance += trip.distanceMeters }
            if trip.resolvedFuelEfficiencyScore > 0, trip.distanceMeters > 0 {
                efficiencyProduct += trip.resolvedFuelEfficiencyScore * trip.distanceMeters
            }
            idleVolume += trip.resolvedFuelIdleVolume
            transientVolume += trip.resolvedFuelTransientVolume
            coldVolume += trip.resolvedFuelColdStartVolume
            speedAbsVolume += abs(trip.resolvedFuelSpeedDeltaVolume)
            unitKeys.insert(trip.resolvedFuelUnitKey)
        }
        let mixedUnits = unitKeys.count > 1
        let factorShares = fuelFactorShares(
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
            averageDuration: averageDuration,
            averageSpeedKmh: averageSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            cruiseSpeedKmh: cruiseWeight > 0 ? cruiseProduct / cruiseWeight : 0,
            mostCommonSpeedKmh: mostCommonWeight > 0 ? mostCommonProduct / mostCommonWeight : 0,
            stopDuration: stopDuration,
            estimatedFuelCost: totalFuel,
            dynamicFuelCost: totalDynamicFuel,
            nightDrivingRatio: nightRatio,
            nightDistanceMeters: nightTotals.nightMeters,
            trackedDistanceMeters: nightTotals.trackedMeters,
            dynamicFuelVolume: mixedUnits ? 0 : totalVolume,
            dynamicFuelVolumeDistanceMeters: mixedUnits ? 0 : volumeDistance,
            fuelEfficiencyScore: mixedUnits || volumeDistance <= 0
                ? 0
                : efficiencyProduct / max(volumeDistance, 1),
            hasMixedFuelUnits: mixedUnits,
            fuelUnitIsElectric: !mixedUnits && unitKeys.contains("electric"),
            fuelFactorShares: factorShares,
            topFuelFactors: topFuelFactors(from: factorShares)
        )
    }

    static func averageSpeedKmh(distanceMeters: Double, duration: TimeInterval) -> Double {
        guard duration > 0, distanceMeters > 0 else { return 0 }
        let kmh = distanceMeters * 3.6 / duration
        return kmh > 0 ? kmh : 0
    }

    static func fuelCost(for trip: Trip) -> Double {
        if let cost = trip.estimatedFuelCost, cost > 0 {
            return cost
        }
        guard trip.distanceMeters > 0 else { return 0 }
        return FuelCostCalculator.estimateCost(for: trip)
    }

    static func dynamicFuelCost(for trip: Trip) -> Double {
        trip.dynamicFuelCost ?? 0
    }

    static func trips<T: TripStatsAggregable>(in interval: DateInterval, from trips: [T]) -> [T] {
        trips.filter { trip in
            guard let endedAt = trip.endedAt else { return false }
            return interval.contains(trip.startedAt) || interval.contains(endedAt)
        }
    }

    static func interval(
        for period: StatsPeriod,
        customStart: Date,
        customEnd: Date,
        selectedMonth: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        switch period {
        case .week:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return DateInterval(start: start, end: now)
        case .month:
            return calendarMonthInterval(containing: selectedMonth, calendar: calendar)
        case .custom:
            let start = min(customStart, customEnd)
            let finish = max(customStart, customEnd)
            return DateInterval(start: start, end: finish)
        }
    }

    /// Half-open calendar month `[startOfMonth, startOfNextMonth)`.
    static func calendarMonthInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }

    /// Inclusive calendar days that overlap `interval` (DST-safe).
    /// A half-open midnight end (`[1 Sep, 1 Oct)`) does not include the end day.
    static func calendarDays(
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Date] {
        let start = calendar.startOfDay(for: interval.start)
        var last = calendar.startOfDay(for: interval.end)
        if interval.end <= last {
            last = calendar.date(byAdding: .day, value: -1, to: last) ?? start
        }
        guard last >= start else { return [start] }
        var days: [Date] = []
        var day = start
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Calendar days overlapping `interval`, not `duration / 86400` (DST-safe).
    static func calendarDayCount(
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> Int {
        max(calendarDays(in: interval, calendar: calendar).count, 1)
    }

    private static func emptyCalendarDayBuckets<Value>(
        in interval: DateInterval,
        calendar: Calendar = .current,
        value: Value
    ) -> [Date: Value] {
        Dictionary(uniqueKeysWithValues: calendarDays(in: interval, calendar: calendar).map { ($0, value) })
    }

    static func calendarDaysInMonth(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Int {
        calendarDayCount(in: calendarMonthInterval(containing: date, calendar: calendar), calendar: calendar)
    }

    static func shiftMonth(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: calendarMonthInterval(containing: date, calendar: calendar).start)
            ?? date
    }

    /// Calendar month the goal ring tracks for the active filter.
    /// Week → current month; month → selected month; custom → month of the range end.
    static func goalMonth(
        for period: StatsPeriod,
        selectedMonth: Date,
        customStart: Date,
        customEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        switch period {
        case .week:
            return calendarMonthInterval(containing: now, calendar: calendar).start
        case .month:
            return calendarMonthInterval(containing: selectedMonth, calendar: calendar).start
        case .custom:
            let end = max(customStart, customEnd)
            return calendarMonthInterval(containing: end, calendar: calendar).start
        }
    }

    /// Months from the first trip's month through the current month, newest first.
    /// With no trips, only the current month is offered.
    static func selectableMonths(
        earliestTripStart: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let currentStart = calendarMonthInterval(containing: now, calendar: calendar).start
        let earliestStart: Date = {
            guard let earliestTripStart else { return currentStart }
            return calendarMonthInterval(containing: earliestTripStart, calendar: calendar).start
        }()

        guard earliestStart <= currentStart else { return [currentStart] }

        var months: [Date] = []
        var cursor = currentStart
        while cursor >= earliestStart {
            months.append(cursor)
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return months
    }

    /// Ensures `month` is one of the selectable month starts (no duplicate picker rows).
    static func clampedMonth(
        _ month: Date,
        earliestTripStart: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let months = selectableMonths(
            earliestTripStart: earliestTripStart,
            now: now,
            calendar: calendar
        )
        let normalized = calendarMonthInterval(containing: month, calendar: calendar).start
        if let exact = months.first(where: { calendar.isDate($0, equalTo: normalized, toGranularity: .month) }) {
            return exact
        }
        return months.first ?? normalized
    }

    static func previousInterval(for interval: DateInterval) -> DateInterval {
        let duration = interval.duration
        let start = interval.start.addingTimeInterval(-duration)
        return DateInterval(start: start, end: interval.start)
    }

    static func previousMonthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let previous = shiftMonth(date, by: -1, calendar: calendar)
        return calendarMonthInterval(containing: previous, calendar: calendar)
    }

    /// True when the selected month is the in-progress calendar month — comparison uses MTD, not the full prior month.
    static func usesMonthToDatePrevious(
        for period: StatsPeriod,
        selectedMonth: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard period == .month else { return false }
        let selectedFull = calendarMonthInterval(containing: selectedMonth, calendar: calendar)
        return calendar.isDate(selectedFull.start, equalTo: now, toGranularity: .month)
            && now < selectedFull.end
    }

    /// Previous period used for *comparison* (MTD-aligned for the in-progress month).
    /// Does not change the Stats fetch window — that still loads the full previous calendar month.
    static func alignedPreviousInterval(
        for period: StatsPeriod,
        selectedInterval: DateInterval,
        selectedMonth: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        switch period {
        case .week:
            let end = calendar.startOfDay(for: selectedInterval.start)
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .custom:
            return previousInterval(for: selectedInterval)
        case .month:
            let previousFull = previousMonthInterval(containing: selectedMonth, calendar: calendar)
            guard usesMonthToDatePrevious(
                for: .month,
                selectedMonth: selectedMonth,
                now: now,
                calendar: calendar
            ) else { return previousFull }

            let selectedFull = calendarMonthInterval(containing: selectedMonth, calendar: calendar)
            let nowDay = calendar.startOfDay(for: now)
            let dayAfterNow = calendar.date(byAdding: .day, value: 1, to: nowDay) ?? now
            let elapsed = dayAfterNow.timeIntervalSince(selectedFull.start)
            let alignedEnd = min(previousFull.start.addingTimeInterval(elapsed), previousFull.end)
            return DateInterval(start: previousFull.start, end: alignedEnd)
        }
    }

    /// Place, journal, and category have no expense dimension — hide cost MoM and $/km so they cannot mix with scoped trip stats.
    static func hidesUnscopedCostComparison(
        categoryID: String?,
        placeName: String?,
        journalID: UUID?
    ) -> Bool {
        let hasCategory = !(categoryID ?? "").isEmpty
        let hasPlace = !(placeName ?? "").isEmpty
        return hasCategory || hasPlace || journalID != nil
    }

    static func showsVehicleCompareList(
        hidesUnscopedCosts: Bool,
        selectedVehicleID: UUID?,
        rowCount: Int
    ) -> Bool {
        !hidesUnscopedCosts && selectedVehicleID == nil && rowCount > 1
    }

    static func periodCompareMetricIDs(includeExpenses: Bool) -> [String] {
        includeExpenses
            ? ["trips", "distance", "duration", "expenses", "fuel"]
            : ["trips", "distance", "duration", "fuel"]
    }

    /// Half-open calendar year `[1 Jan, 1 Jan next)`.
    static func calendarYearInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let year = calendar.component(.year, from: date)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            ?? start.addingTimeInterval(365 * 86_400)
        return DateInterval(start: start, end: end)
    }

    static func calendarYearInterval(
        year: Int,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            ?? Date()
        return calendarYearInterval(containing: start, calendar: calendar)
    }

    /// Newest year first. With no trips, only the current year.
    static func selectableYears(
        earliestTripStart: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Int] {
        let currentYear = calendar.component(.year, from: now)
        let earliestYear: Int = {
            guard let earliestTripStart else { return currentYear }
            return calendar.component(.year, from: earliestTripStart)
        }()
        guard earliestYear <= currentYear else { return [currentYear] }
        return Array((earliestYear...currentYear).reversed())
    }

    static func trendPercent(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    static func trendText(current: Double, previous: Double) -> String? {
        StatsTrend.make(current: current, previous: previous, polarity: .neutral)?.displayText
    }

    static func dailyDistances<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyDistance] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard buckets[tripDay] != nil else { continue }
            buckets[tripDay, default: 0] += trip.distanceMeters
        }

        return buckets.keys.sorted().map { day in
            DailyDistance(id: day, day: day, distanceMeters: buckets[day] ?? 0)
        }
    }

    static func dailyDurations<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyDuration] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard buckets[tripDay] != nil else { continue }
            buckets[tripDay, default: 0] += duration
        }

        return buckets.keys.sorted().map { day in
            DailyDuration(id: day, day: day, duration: buckets[day] ?? 0)
        }
    }

    static func dailyAverageSpeeds<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyAverageSpeed] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var distanceBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)
        var durationBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard distanceBuckets[tripDay] != nil else { continue }
            distanceBuckets[tripDay, default: 0] += trip.distanceMeters
            if let duration = trip.duration, duration > 0 {
                durationBuckets[tripDay, default: 0] += duration
            }
        }

        return distanceBuckets.keys.sorted().map { day in
            let speed = averageSpeedKmh(
                distanceMeters: distanceBuckets[day] ?? 0,
                duration: durationBuckets[day] ?? 0
            )
            return DailyAverageSpeed(id: day, day: day, speedKmh: speed)
        }
    }

    static func dailyMaxSpeeds<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyMaxSpeed] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            guard let maxSpeedMps = TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps) else {
                continue
            }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard buckets[tripDay] != nil else { continue }
            buckets[tripDay, default: 0] = max(buckets[tripDay, default: 0], maxSpeedMps * 3.6)
        }

        return buckets.keys.sorted().map { day in
            DailyMaxSpeed(id: day, day: day, speedKmh: buckets[day] ?? 0)
        }
    }

    static func dailyCruiseSpeeds<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyCruiseSpeed] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var weightBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)
        var productBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            let weight = trip.resolvedCruiseDurationSeconds
            let speed = trip.resolvedCruiseSpeedKmh
            guard weight > 0, speed > 0 else { continue }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard weightBuckets[tripDay] != nil else { continue }
            weightBuckets[tripDay, default: 0] += weight
            productBuckets[tripDay, default: 0] += speed * weight
        }

        return weightBuckets.keys.sorted().map { day in
            let weight = weightBuckets[day] ?? 0
            let speed = weight > 0 ? (productBuckets[day] ?? 0) / weight : 0
            return DailyCruiseSpeed(id: day, day: day, speedKmh: speed)
        }
    }

    static func dailyMostCommonSpeeds<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyMostCommonSpeed] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var weightBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)
        var productBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            let weight = trip.resolvedCruiseDurationSeconds
            let speed = trip.resolvedMostCommonSpeedKmh
            guard weight > 0, speed > 0 else { continue }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard weightBuckets[tripDay] != nil else { continue }
            weightBuckets[tripDay, default: 0] += weight
            productBuckets[tripDay, default: 0] += speed * weight
        }

        return weightBuckets.keys.sorted().map { day in
            let weight = weightBuckets[day] ?? 0
            let speed = weight > 0 ? (productBuckets[day] ?? 0) / weight : 0
            return DailyMostCommonSpeed(id: day, day: day, speedKmh: speed)
        }
    }

    static func dailyStopDurations<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyStopDuration] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard buckets[tripDay] != nil else { continue }
            buckets[tripDay, default: 0] += trip.resolvedStopDurationSeconds
        }

        return buckets.keys.sorted().map { day in
            DailyStopDuration(id: day, day: day, duration: buckets[day] ?? 0)
        }
    }

    static func dailyFuelCosts<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyFuelCost] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var avgBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)
        var dynamicBuckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard avgBuckets[tripDay] != nil else { continue }
            avgBuckets[tripDay, default: 0] += trip.resolvedFuelCost
            dynamicBuckets[tripDay, default: 0] += trip.resolvedDynamicFuelCost
        }

        return avgBuckets.keys.sorted().map { day in
            DailyFuelCost(
                id: day,
                day: day,
                cost: avgBuckets[day] ?? 0,
                dynamicCost: dynamicBuckets[day] ?? 0
            )
        }
    }

    static func dailyTripCounts<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyTripCount] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0)

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard buckets[tripDay] != nil else { continue }
            buckets[tripDay, default: 0] += trip.tripCount
        }

        return buckets.keys.sorted().map { day in
            DailyTripCount(id: day, day: day, count: buckets[day] ?? 0)
        }
    }

    static func dailyNightDistances<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyNightDistance] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets = emptyCalendarDayBuckets(in: interval, calendar: calendar, value: 0.0)

        for trip in filtered {
            guard let share = trip.nightDistanceShare else { continue }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            guard buckets[tripDay] != nil else { continue }
            buckets[tripDay, default: 0] += share.nightMeters
        }

        return buckets.keys.sorted().map { day in
            DailyNightDistance(id: day, day: day, distanceMeters: buckets[day] ?? 0)
        }
    }

    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    static func weekdayLabel(_ weekday: Int, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    static func weekdayDistances<T: TripStatsAggregable>(
        from trips: [T],
        calendar: Calendar = .current
    ) -> [WeekdayDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var buckets: [Int: Double] = [:]
        let order = orderedWeekdays(calendar: calendar)
        for weekday in order {
            buckets[weekday] = 0
        }
        for trip in filtered {
            let weekday = calendar.component(.weekday, from: trip.startedAt)
            buckets[weekday, default: 0] += trip.distanceMeters
        }
        return order.map { weekday in
            WeekdayDistance(
                id: weekday,
                weekday: weekday,
                label: weekdayLabel(weekday, calendar: calendar),
                distanceMeters: buckets[weekday] ?? 0
            )
        }
    }

    static func weekdayDurations<T: TripStatsAggregable>(
        from trips: [T],
        calendar: Calendar = .current
    ) -> [WeekdayDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var buckets: [Int: TimeInterval] = [:]
        let order = orderedWeekdays(calendar: calendar)
        for weekday in order {
            buckets[weekday] = 0
        }
        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            let weekday = calendar.component(.weekday, from: trip.startedAt)
            buckets[weekday, default: 0] += duration
        }
        return order.map { weekday in
            WeekdayDuration(
                id: weekday,
                weekday: weekday,
                label: weekdayLabel(weekday, calendar: calendar),
                duration: buckets[weekday] ?? 0
            )
        }
    }

    static func drivingDayCount<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T],
        calendar: Calendar = .current
    ) -> Int {
        let filtered = Self.trips(in: interval, from: trips)
        let periodDays = Set(calendarDays(in: interval, calendar: calendar))
        var days = Set<Date>()
        for trip in filtered {
            let day = calendar.startOfDay(for: trip.startedAt)
            if periodDays.contains(day) {
                days.insert(day)
            }
        }
        return days.count
    }

    static func busiestDay(from daily: [DailyDistance]) -> (day: Date, meters: Double)? {
        guard let best = daily.max(by: { $0.distanceMeters < $1.distanceMeters }),
              best.distanceMeters > 0 else {
            return nil
        }
        return (best.day, best.distanceMeters)
    }

    static func fuelFactorShares(
        idle: Double,
        transient: Double,
        cold: Double,
        speed: Double,
        mixedUnits: Bool
    ) -> [FuelFactorShare] {
        guard !mixedUnits else { return [] }
        return [
            FuelFactorShare(kind: .idleTraffic, volume: idle),
            FuelFactorShare(kind: .transientAcceleration, volume: transient),
            FuelFactorShare(kind: .coldStart, volume: cold),
            FuelFactorShare(kind: .highSpeed, volume: speed)
        ]
        .filter { $0.volume > 0.01 }
        .sorted { $0.volume > $1.volume }
    }

    static func topFuelFactors(from shares: [FuelFactorShare]) -> [FuelFactorKind] {
        Array(shares.prefix(3).map(\.kind))
    }

    /// Display names for every category key, resolved up front so the breakdowns can run away
    /// from the main actor without touching `UserCategory` models.
    static func categoryNameMap(for categories: [UserCategory]) -> StatsNameMap {
        var names: [String: String] = [:]
        for category in categories {
            names[category.storageKey] = category.name
        }
        for legacy in TripCategory.allCases {
            names[legacy.rawValue] = names[legacy.rawValue] ?? legacy.displayName
        }
        return StatsNameMap(names: names, fallback: L10n.string("label.other"))
    }

    static func vehicleNameMap(for vehicles: [VehicleProfile]) -> StatsNameMap {
        var names: [String: String] = [:]
        for vehicle in vehicles {
            names[vehicle.id.uuidString] = vehicle.name
        }
        names[VehicleDistance.unassignedID] = L10n.string("stats.vehicle.unassigned")
        return StatsNameMap(names: names, fallback: L10n.string("stats.vehicle.unknown"))
    }

    static func categoryBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categoryNames: StatsNameMap
    ) -> [CategoryDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            totals[trip.categoryID, default: 0] += trip.distanceMeters
        }

        return totals.map { key, distance in
            CategoryDistance(id: key, name: categoryNames.name(for: key), distanceMeters: distance)
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    static func categoryDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categoryNames: StatsNameMap
    ) -> [CategoryDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: TimeInterval] = [:]

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            totals[trip.categoryID, default: 0] += duration
        }

        return totals.map { key, duration in
            CategoryDuration(id: key, name: categoryNames.name(for: key), duration: duration)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func vehicleBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicleNames: StatsNameMap
    ) -> [VehicleDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            let key = trip.vehicleID?.uuidString ?? VehicleDistance.unassignedID
            totals[key, default: 0] += trip.distanceMeters
        }

        return totals.map { key, distance in
            VehicleDistance(id: key, name: vehicleNames.name(for: key), distanceMeters: distance)
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    static func vehicleDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicleNames: StatsNameMap
    ) -> [VehicleDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: TimeInterval] = [:]

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            let key = trip.vehicleID?.uuidString ?? VehicleDuration.unassignedID
            totals[key, default: 0] += duration
        }

        return totals.map { key, duration in
            VehicleDuration(id: key, name: vehicleNames.name(for: key), duration: duration)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func categoryFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categoryNames: StatsNameMap
    ) -> [CategoryFuelCost] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            totals[trip.categoryID, default: 0] += trip.resolvedFuelCost
        }

        return totals.map { key, cost in
            CategoryFuelCost(id: key, name: categoryNames.name(for: key), cost: cost)
        }
        .sorted { $0.cost > $1.cost }
    }

    static func vehicleFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicleNames: StatsNameMap
    ) -> [VehicleFuelCost] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            let key = trip.vehicleID?.uuidString ?? VehicleFuelCost.unassignedID
            totals[key, default: 0] += trip.resolvedFuelCost
        }

        return totals.map { key, cost in
            VehicleFuelCost(id: key, name: vehicleNames.name(for: key), cost: cost)
        }
        .sorted { $0.cost > $1.cost }
    }

    static func categoryBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categories: [UserCategory]
    ) -> [CategoryDistance] {
        categoryBreakdown(for: trips, categoryNames: categoryNameMap(for: categories))
    }

    static func categoryDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categories: [UserCategory]
    ) -> [CategoryDuration] {
        categoryDurationBreakdown(for: trips, categoryNames: categoryNameMap(for: categories))
    }

    static func categoryFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categories: [UserCategory]
    ) -> [CategoryFuelCost] {
        categoryFuelBreakdown(for: trips, categoryNames: categoryNameMap(for: categories))
    }

    static func vehicleBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicles: [VehicleProfile]
    ) -> [VehicleDistance] {
        vehicleBreakdown(for: trips, vehicleNames: vehicleNameMap(for: vehicles))
    }

    static func vehicleDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicles: [VehicleProfile]
    ) -> [VehicleDuration] {
        vehicleDurationBreakdown(for: trips, vehicleNames: vehicleNameMap(for: vehicles))
    }

    static func vehicleFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicles: [VehicleProfile]
    ) -> [VehicleFuelCost] {
        vehicleFuelBreakdown(for: trips, vehicleNames: vehicleNameMap(for: vehicles))
    }

    static func nightDrivingTotals<T: TripStatsAggregable>(
        for trips: [T]
    ) -> (nightMeters: Double, trackedMeters: Double) {
        var nightMeters = 0.0
        var trackedMeters = 0.0

        for trip in trips {
            guard let share = trip.nightDistanceShare else { continue }
            nightMeters += share.nightMeters
            trackedMeters += share.trackedMeters
        }

        return (nightMeters, trackedMeters)
    }

    static func nightDrivingRatio<T: TripStatsAggregable>(for trips: [T]) -> Double {
        let totals = nightDrivingTotals(for: trips)
        guard totals.trackedMeters > 0 else { return 0 }
        return totals.nightMeters / totals.trackedMeters
    }

    /// Fallback for trips whose derived split has not been backfilled yet. Walks every GPS
    /// segment, so it is the one path that still scales with recorded point count.
    static func walkNightDistanceShare(for trip: Trip) -> NightDistanceShare? {
        PerformanceSignposts.measure("NightDistanceWalk") {
            let points = trip.sortedPoints
            guard points.count >= 2 else { return nil }

            // Resolving the UTC offset once per trip keeps DST correctness without paying
            // `Calendar.component(.hour:)` on every GPS segment.
            let utcOffset = Double(TimeZone.current.secondsFromGMT(for: trip.startedAt))
            var nightMeters = 0.0
            var totalMeters = 0.0

            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let segment = approximateDistanceMeters(
                    fromLatitude: previous.latitude,
                    fromLongitude: previous.longitude,
                    toLatitude: current.latitude,
                    toLongitude: current.longitude
                )
                guard segment > 0 else { continue }

                let previousTime = previous.timestamp.timeIntervalSince1970
                let midpoint = previousTime
                    + (current.timestamp.timeIntervalSince1970 - previousTime) / 2
                totalMeters += segment
                if isNightTimestamp(midpoint, utcOffset: utcOffset) {
                    nightMeters += segment
                }
            }

            return NightDistanceShare(nightMeters: nightMeters, trackedMeters: totalMeters)
        }
    }

    /// Equirectangular approximation. Consecutive GPS samples are metres apart, so the error
    /// against the geodesic stays far below the noise floor of the samples themselves — and it
    /// avoids allocating two `CLLocation` objects per segment.
    static func approximateDistanceMeters(
        fromLatitude latitude1: Double,
        fromLongitude longitude1: Double,
        toLatitude latitude2: Double,
        toLongitude longitude2: Double
    ) -> Double {
        let metersPerDegree = 111_320.0
        let meanLatitudeRadians = ((latitude1 + latitude2) / 2) * .pi / 180
        let deltaLatitude = (latitude2 - latitude1) * metersPerDegree
        let deltaLongitude = (longitude2 - longitude1) * metersPerDegree * cos(meanLatitudeRadians)
        return (deltaLatitude * deltaLatitude + deltaLongitude * deltaLongitude).squareRoot()
    }

    static func nightDrivingPercentText(for ratio: Double) -> String {
        let percent = Int((ratio * 100).rounded())
        let format = L10n.string("stats.night_driving.format")
        return String(format: format, percent)
    }

    /// Night is 22:00–06:00 local time. `utcOffset` is resolved once per trip rather than per
    /// segment, which keeps DST correctness without paying `Calendar.component(.hour:)` per point.
    static func isNightTimestamp(_ timeIntervalSince1970: Double, utcOffset: Double) -> Bool {
        let secondsInDay = (timeIntervalSince1970 + utcOffset).truncatingRemainder(dividingBy: 86_400)
        let normalized = secondsInDay < 0 ? secondsInDay + 86_400 : secondsInDay
        let hour = Int(normalized / 3_600)
        return hour >= 22 || hour < 6
    }
}

struct TripStats: Sendable {
    let tripCount: Int
    let totalDistanceMeters: Double
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double
    let cruiseSpeedKmh: Double
    let mostCommonSpeedKmh: Double
    let stopDuration: TimeInterval
    let estimatedFuelCost: Double
    let dynamicFuelCost: Double
    let nightDrivingRatio: Double
    let nightDistanceMeters: Double
    let trackedDistanceMeters: Double
    let dynamicFuelVolume: Double
    let dynamicFuelVolumeDistanceMeters: Double
    let fuelEfficiencyScore: Double
    let hasMixedFuelUnits: Bool
    let fuelUnitIsElectric: Bool
    let fuelFactorShares: [FuelFactorShare]
    let topFuelFactors: [FuelFactorKind]

    init(
        tripCount: Int,
        totalDistanceMeters: Double,
        totalDuration: TimeInterval,
        averageDuration: TimeInterval,
        averageSpeedKmh: Double = 0,
        maxSpeedKmh: Double = 0,
        cruiseSpeedKmh: Double = 0,
        mostCommonSpeedKmh: Double = 0,
        stopDuration: TimeInterval = 0,
        estimatedFuelCost: Double,
        dynamicFuelCost: Double = 0,
        nightDrivingRatio: Double = 0,
        nightDistanceMeters: Double = 0,
        trackedDistanceMeters: Double = 0,
        dynamicFuelVolume: Double = 0,
        dynamicFuelVolumeDistanceMeters: Double = 0,
        fuelEfficiencyScore: Double = 0,
        hasMixedFuelUnits: Bool = false,
        fuelUnitIsElectric: Bool = false,
        fuelFactorShares: [FuelFactorShare] = [],
        topFuelFactors: [FuelFactorKind] = []
    ) {
        self.tripCount = tripCount
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDuration = totalDuration
        self.averageDuration = averageDuration
        self.averageSpeedKmh = averageSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.cruiseSpeedKmh = cruiseSpeedKmh
        self.mostCommonSpeedKmh = mostCommonSpeedKmh
        self.stopDuration = stopDuration
        self.estimatedFuelCost = estimatedFuelCost
        self.dynamicFuelCost = dynamicFuelCost
        self.nightDrivingRatio = nightDrivingRatio
        self.nightDistanceMeters = nightDistanceMeters
        self.trackedDistanceMeters = trackedDistanceMeters
        self.dynamicFuelVolume = dynamicFuelVolume
        self.dynamicFuelVolumeDistanceMeters = dynamicFuelVolumeDistanceMeters
        self.fuelEfficiencyScore = fuelEfficiencyScore
        self.hasMixedFuelUnits = hasMixedFuelUnits
        self.fuelUnitIsElectric = fuelUnitIsElectric
        self.fuelFactorShares = fuelFactorShares
        self.topFuelFactors = topFuelFactors.isEmpty
            ? StatsViewModel.topFuelFactors(from: fuelFactorShares)
            : topFuelFactors
    }

    var averageDistanceMeters: Double {
        tripCount > 0 ? totalDistanceMeters / Double(tripCount) : 0
    }

    var movingDuration: TimeInterval {
        max(0, totalDuration - stopDuration)
    }

    var daytimeDistanceMeters: Double {
        max(0, trackedDistanceMeters - nightDistanceMeters)
    }

    var totalDistanceText: String { DateFormatters.formatDistance(totalDistanceMeters) }
    var averageDistanceText: String {
        averageDistanceMeters > 0 ? DateFormatters.formatDistance(averageDistanceMeters) : "—"
    }
    var totalDurationText: String { DateFormatters.formatDuration(totalDuration) }
    var averageDurationText: String { DateFormatters.formatDuration(averageDuration) }
    var movingDurationText: String {
        movingDuration > 0 ? DateFormatters.formatDuration(movingDuration) : "—"
    }
    var nightDistanceText: String {
        nightDistanceMeters > 0 ? DateFormatters.formatDistance(nightDistanceMeters) : "—"
    }
    var averageSpeedText: String {
        averageSpeedKmh > 0 ? L10n.formatSpeedKmh(averageSpeedKmh) : "—"
    }
    var maxSpeedText: String {
        maxSpeedKmh > 0 ? L10n.formatSpeedKmh(maxSpeedKmh) : "—"
    }
    var cruiseSpeedText: String {
        cruiseSpeedKmh > 0 ? L10n.formatSpeedKmh(cruiseSpeedKmh) : "—"
    }
    var mostCommonSpeedText: String {
        mostCommonSpeedKmh > 0 ? L10n.formatSpeedKmh(mostCommonSpeedKmh) : "—"
    }
    var stopDurationText: String {
        stopDuration > 0 ? DateFormatters.formatDuration(stopDuration) : "—"
    }
    var fuelCostText: String { FuelCostCalculator.formatCost(estimatedFuelCost) }
    var dynamicFuelCostText: String { FuelCostCalculator.formatCost(dynamicFuelCost) }
    var nightDrivingText: String { StatsViewModel.nightDrivingPercentText(for: nightDrivingRatio) }

    var costPerKm: Double {
        let kilometers = totalDistanceMeters / 1000
        guard kilometers > 0, estimatedFuelCost > 0 else { return 0 }
        return estimatedFuelCost / kilometers
    }

    var averageCostPerTrip: Double {
        guard tripCount > 0, estimatedFuelCost > 0 else { return 0 }
        return estimatedFuelCost / Double(tripCount)
    }

    var dynamicCostPerKm: Double {
        let kilometers = totalDistanceMeters / 1000
        guard kilometers > 0, dynamicFuelCost > 0 else { return 0 }
        return dynamicFuelCost / kilometers
    }

    var dynamicCostPerTrip: Double {
        guard tripCount > 0, dynamicFuelCost > 0 else { return 0 }
        return dynamicFuelCost / Double(tripCount)
    }

    var costPerKmText: String {
        costPerKm > 0 ? FuelCostCalculator.formatCost(costPerKm) : "—"
    }

    var averageCostPerTripText: String {
        averageCostPerTrip > 0 ? FuelCostCalculator.formatCost(averageCostPerTrip) : "—"
    }

    var dynamicCostPerKmText: String {
        dynamicCostPerKm > 0 ? FuelCostCalculator.formatCost(dynamicCostPerKm) : "—"
    }

    var dynamicCostPerTripText: String {
        dynamicCostPerTrip > 0 ? FuelCostCalculator.formatCost(dynamicCostPerTrip) : "—"
    }
}
