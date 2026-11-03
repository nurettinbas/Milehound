import Foundation
import SwiftData

/// The only writer of denormalized journal totals, mosaic IDs, and `searchIndex`.
enum TravelJournalTotals {
    static let avgFuelTotalsVersionKey = "milehound.journal.avgFuelTotalsVersion"
    static let avgFuelTotalsVersion = 1

    /// Avg fuel (catalog: distance × consumption × unit price). Not VSP estimated fuel.
    static func fuelCost(for trip: Trip) -> Double {
        FuelCostCalculator.estimateCost(for: trip)
    }

    static func refresh(_ journal: TravelJournal) {
        let members = journal.trips
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }

        journal.tripCount = members.count
        journal.distanceMeters = members.reduce(0) { $0 + $1.distanceMeters }
        journal.fuelCost = members.reduce(0) { $0 + fuelCost(for: $1) }

        if let first = members.first {
            journal.startedOn = Calendar.current.startOfDay(for: first.startedAt)
        }
        if let last = members.last {
            let endDate = last.endedAt ?? last.startedAt
            journal.endedOn = Calendar.current.startOfDay(for: endDate)
        }

        let byDistance = members.sorted { $0.distanceMeters > $1.distanceMeters }
        journal.coverTripID = byDistance.first?.id
        journal.mosaicTripIDsRaw = byDistance.prefix(TravelJournal.mosaicSlotCount).map(\.id.uuidString).joined(separator: ",")
        journal.searchIndex = searchIndex(for: journal)
    }

    static func refresh(journalID: UUID?, in context: ModelContext) {
        guard let journalID else { return }
        let descriptor = FetchDescriptor<TravelJournal>(
            predicate: #Predicate { $0.id == journalID }
        )
        guard let journal = try? context.fetch(descriptor).first else { return }
        refresh(journal)
    }

    /// One-shot rewrite of denormalized `fuelCost` after list totals switched from estimated to avg fuel.
    /// Existing trip rows are left untouched.
    static func refreshAvgFuelTotalsIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: avgFuelTotalsVersionKey) < avgFuelTotalsVersion else { return }

        let journals = (try? context.fetch(FetchDescriptor<TravelJournal>())) ?? []
        for journal in journals {
            refresh(journal)
        }
        do {
            try context.save()
            defaults.set(avgFuelTotalsVersion, forKey: avgFuelTotalsVersionKey)
        } catch {
            return
        }
    }

    /// Assigns `trip` to `journal` (or unassigns when `journal` is nil). A trip has at most one parent.
    static func assign(trip: Trip, to journal: TravelJournal?, in context: ModelContext) {
        let previousID = trip.journalID
        if let current = trip.journal, current.id != journal?.id {
            trip.journal = nil
            trip.journalID = nil
            refresh(current)
        }

        trip.journal = journal
        trip.journalID = journal?.id

        if let journal {
            refresh(journal)
        }
        if previousID != journal?.id {
            refresh(journalID: previousID, in: context)
        }
    }

    static func applyMergeMembership(surviving: Trip, sources: [Trip], in context: ModelContext) {
        let journalIDs = Set(sources.compactMap(\.journalID))
        let affected = journalIDs
        if journalIDs.count == 1, let only = journalIDs.first {
            surviving.journalID = only
            let descriptor = FetchDescriptor<TravelJournal>(
                predicate: #Predicate { $0.id == only }
            )
            surviving.journal = try? context.fetch(descriptor).first
        } else {
            surviving.journal = nil
            surviving.journalID = nil
        }
        for journalID in affected {
            refresh(journalID: journalID, in: context)
        }
        if let current = surviving.journalID {
            refresh(journalID: current, in: context)
        }
    }

    static func handleTripDeletion(_ trip: Trip, in context: ModelContext) {
        let journalID = trip.journalID
        trip.journal = nil
        trip.journalID = nil
        refresh(journalID: journalID, in: context)
    }

    static func prepareForDelete(_ journal: TravelJournal) {
        for trip in journal.trips {
            trip.journalID = nil
            trip.journal = nil
        }
    }

    static func searchIndex(for journal: TravelJournal) -> String {
        let parts = [
            journal.title,
            journal.note ?? "",
            DateFormatters.tripDateOnly.string(from: journal.startedOn),
            DateFormatters.tripDateOnly.string(from: journal.endedOn)
        ]
        return SearchFolding.fold(parts.joined(separator: " "))
    }
}
