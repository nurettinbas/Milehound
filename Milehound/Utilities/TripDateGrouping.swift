import Foundation

enum TripDateSection: Int, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: L10n.sectionToday
        case .yesterday: L10n.sectionYesterday
        case .thisWeek: L10n.sectionThisWeek
        case .thisMonth: L10n.sectionThisMonth
        case .older: L10n.sectionOlder
        }
    }
}

enum TripDateGrouping {
    /// Mutually exclusive bucket used for list section headers (a trip appears once).
    static func section(
        for date: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> TripDateSection {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        return .older
    }

    /// Inclusive match for the trip-list date filter chips. Broader chips must include the
    /// narrower buckets: "This Week" covers today/yesterday when they fall in the same week,
    /// and "This Month" covers everything still in the current month.
    static func matches(
        _ section: TripDateSection,
        date: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        switch section {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            guard let yesterday = calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.startOfDay(for: now)
            ) else { return false }
            return calendar.isDate(date, inSameDayAs: yesterday)
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .older:
            return self.section(for: date, calendar: calendar, now: now) == .older
        }
    }

    static func groupedSections(
        from trips: [Trip],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [(section: TripDateSection, trips: [Trip])] {
        let grouped = Dictionary(grouping: trips) { trip in
            section(for: trip.startedAt, calendar: calendar, now: now)
        }

        return TripDateSection.allCases.compactMap { section in
            guard let sectionTrips = grouped[section], !sectionTrips.isEmpty else { return nil }
            let sorted = sectionTrips.sorted {
                $0.startedAt.timeIntervalSinceReferenceDate > $1.startedAt.timeIntervalSinceReferenceDate
            }
            return (section, sorted)
        }
    }
}
