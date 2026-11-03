import CoreLocation
import Foundation
import SwiftData

struct TravelJournalTripSnapshot: Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let startLatitude: Double?
    let startLongitude: Double?
    let endLatitude: Double?
    let endLongitude: Double?
    let startPlaceName: String?
    let endPlaceName: String?
    let journalID: UUID?
}

struct TravelJournalHomeSnapshot: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
}

struct TravelJournalDateRange: Equatable, Sendable {
    let start: Date
    let end: Date
}

/// Reads completed trips off the main actor. The trips tab must not scan the library
/// just to decide whether a travel suggestion banner exists.
@ModelActor
actor TravelSuggestionLoader {
    func suggestion(
        homes: [TravelJournalHomeSnapshot],
        existingJournalRanges: [TravelJournalDateRange],
        dismissedFingerprints: Set<String>,
        calendar: Calendar = .current
    ) -> TravelJournalSuggestion? {
        let completed = (try? modelContext.fetch(TripListPage.completedCountDescriptor())) ?? []
        let snapshots = completed.map(TravelJournalSuggester.snapshot(from:))
        return TravelJournalSuggester.suggest(
            trips: snapshots,
            homes: homes,
            existingJournalRanges: existingJournalRanges.map { (start: $0.start, end: $0.end) },
            dismissedFingerprints: dismissedFingerprints,
            calendar: calendar
        )
    }
}

struct TravelJournalSuggestion: Equatable, Sendable {
    let tripIDs: [UUID]
    let startedOn: Date
    let endedOn: Date
    let title: String
    let distanceMeters: Double

    var fingerprint: String {
        let ids = tripIDs.map(\.uuidString).sorted().joined(separator: ",")
        return "\(startedOn.timeIntervalSince1970)|\(endedOn.timeIntervalSince1970)|\(ids)"
    }
}

/// Pure suggestion rules. Never walks GPS points — endpoints only.
enum TravelJournalSuggester {
    static let minimumDistanceMeters: Double = 150_000
    static let minimumCalendarDays = 3

    static func suggest(
        trips: [TravelJournalTripSnapshot],
        homes: [TravelJournalHomeSnapshot],
        existingJournalRanges: [(start: Date, end: Date)] = [],
        dismissedFingerprints: Set<String> = [],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> TravelJournalSuggestion? {
        guard !homes.isEmpty else { return nil }

        let completed = trips
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        guard !completed.isEmpty else { return nil }

        let awayDays = Dictionary(grouping: completed) { calendar.startOfDay(for: $0.startedAt) }
            .compactMap { day, dayTrips -> Date? in
                let judged = dayTrips.filter { hasEndpoints($0) }
                guard !judged.isEmpty else { return nil }
                let allAway = judged.allSatisfy { trip in
                    !isAtHome(trip, homes: homes)
                }
                return allAway ? day : nil
            }
            .sorted()

        let chains = consecutiveDayChains(awayDays, calendar: calendar)
        for chain in chains {
            let chainTrips = completed.filter { trip in
                let day = calendar.startOfDay(for: trip.startedAt)
                return chain.contains(where: { calendar.isDate($0, inSameDayAs: day) })
            }
            let unassigned = chainTrips.filter { $0.journalID == nil }
            guard !unassigned.isEmpty else { continue }
            guard !rangeCovered(
                start: chain.first ?? now,
                end: chain.last ?? now,
                existing: existingJournalRanges,
                calendar: calendar
            ) else { continue }

            let nightOK = chain.count >= minimumCalendarDays
            let distance = unassigned.reduce(0) { $0 + $1.distanceMeters }
            let distanceOK = distance >= minimumDistanceMeters
            guard nightOK || distanceOK else { continue }

            let startedOn = chain.first ?? calendar.startOfDay(for: unassigned[0].startedAt)
            let endedOn = chain.last ?? startedOn
            let suggestion = TravelJournalSuggestion(
                tripIDs: unassigned.map(\.id),
                startedOn: startedOn,
                endedOn: endedOn,
                title: seededTitle(from: unassigned, startedOn: startedOn, endedOn: endedOn, calendar: calendar),
                distanceMeters: distance
            )
            if dismissedFingerprints.contains(suggestion.fingerprint) { continue }
            return suggestion
        }
        return nil
    }

    static func snapshot(from trip: Trip) -> TravelJournalTripSnapshot {
        TravelJournalTripSnapshot(
            id: trip.id,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt,
            distanceMeters: trip.distanceMeters,
            startLatitude: trip.startLatitude,
            startLongitude: trip.startLongitude,
            endLatitude: trip.endLatitude,
            endLongitude: trip.endLongitude,
            startPlaceName: trip.startPlaceName,
            endPlaceName: trip.endPlaceName,
            journalID: trip.journalID
        )
    }

    static func homeSnapshots(from places: [SavedPlace]) -> [TravelJournalHomeSnapshot] {
        places.filter { $0.kind == .home }.map {
            TravelJournalHomeSnapshot(
                latitude: $0.latitude,
                longitude: $0.longitude,
                radiusMeters: $0.radiusMeters
            )
        }
    }

    private static func hasEndpoints(_ trip: TravelJournalTripSnapshot) -> Bool {
        trip.startLatitude != nil && trip.startLongitude != nil
            && trip.endLatitude != nil && trip.endLongitude != nil
    }

    private static func isAtHome(
        _ trip: TravelJournalTripSnapshot,
        homes: [TravelJournalHomeSnapshot]
    ) -> Bool {
        if let lat = trip.startLatitude, let lon = trip.startLongitude,
           homes.contains(where: { $0.contains(latitude: lat, longitude: lon) }) {
            return true
        }
        if let lat = trip.endLatitude, let lon = trip.endLongitude,
           homes.contains(where: { $0.contains(latitude: lat, longitude: lon) }) {
            return true
        }
        return false
    }

    private static func consecutiveDayChains(
        _ days: [Date],
        calendar: Calendar
    ) -> [[Date]] {
        guard let first = days.first else { return [] }
        var chains: [[Date]] = [[first]]
        for day in days.dropFirst() {
            guard let previous = chains[chains.count - 1].last,
                  let expected = calendar.date(byAdding: .day, value: 1, to: previous),
                  calendar.isDate(day, inSameDayAs: expected) else {
                chains.append([day])
                continue
            }
            chains[chains.count - 1].append(day)
        }
        return chains
    }

    private static func rangeCovered(
        start: Date,
        end: Date,
        existing: [(start: Date, end: Date)],
        calendar: Calendar
    ) -> Bool {
        existing.contains { journal in
            calendar.startOfDay(for: journal.start) <= start
                && calendar.startOfDay(for: journal.end) >= end
        }
    }

    private static func seededTitle(
        from trips: [TravelJournalTripSnapshot],
        startedOn: Date,
        endedOn: Date,
        calendar: Calendar
    ) -> String {
        let names = trips.flatMap { trip -> [String] in
            [trip.startPlaceName, trip.endPlaceName].compactMap { name in
                guard let name, !name.isEmpty else { return nil }
                return name
            }
        }
        if let farthest = names.max(by: { $0.count < $1.count }) {
            return farthest
        }
        let start = DateFormatters.chartDay.string(from: startedOn)
        if calendar.isDate(startedOn, inSameDayAs: endedOn) {
            return start
        }
        return "\(start) – \(DateFormatters.chartDay.string(from: endedOn))"
    }
}

private extension TravelJournalHomeSnapshot {
    func contains(latitude: Double, longitude: Double) -> Bool {
        let place = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return place.distance(from: target) <= radiusMeters
    }
}
