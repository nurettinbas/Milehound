import Foundation
import SwiftData

enum TripsTabListMode: String, CaseIterable, Identifiable {
    case trips
    case travels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: L10n.tripsSegmentTrips
        case .travels: L10n.tripsSegmentTravels
        }
    }
}

enum TravelJournalPage {
    static let pageSize = 50

    struct Filters: Equatable {
        var searchText: String = ""

        var isActive: Bool {
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func descriptor(filters: Filters, limit: Int) -> FetchDescriptor<TravelJournal> {
        var descriptor = FetchDescriptor<TravelJournal>(
            sortBy: [SortDescriptor(\.endedOn, order: .reverse)]
        )
        // SwiftData rejects optional `searchIndex!` unwraps, so search is applied in
        // memory after fetch. Load the full library when filtering; page otherwise.
        if !filters.isActive {
            descriptor.fetchLimit = limit + 1
        }
        return descriptor
    }

    static func fetch(
        filters: Filters,
        limit: Int,
        in context: ModelContext
    ) throws -> (journals: [TravelJournal], hasMore: Bool) {
        let fetched = try context.fetch(descriptor(filters: filters, limit: limit))
        let matches = filters.isActive
            ? fetched.filter { matchesSearch($0, searchText: filters.searchText) }
            : fetched
        return (Array(matches.prefix(limit)), matches.count > limit)
    }

    /// Title is the primary field. `searchIndex` also covers note and dates. Matching is
    /// case-insensitive and Turkish-aware (`ı`/`I`/`İ` → `i`, diacritics stripped).
    static func matchesSearch(_ journal: TravelJournal, searchText: String) -> Bool {
        let needle = SearchFolding.fold(searchText)
        guard !needle.isEmpty else { return true }
        if SearchFolding.fold(journal.title).contains(needle) { return true }
        if let note = journal.note, SearchFolding.fold(note).contains(needle) { return true }
        if let index = journal.searchIndex, SearchFolding.fold(index).contains(needle) { return true }
        return false
    }

    static func countDescriptor() -> FetchDescriptor<TravelJournal> {
        FetchDescriptor<TravelJournal>()
    }
}

/// Case-, diacritic-, and Turkish-i-insensitive folding for substring search.
enum SearchFolding {
    static func fold(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "i")
            .replacingOccurrences(of: "I", with: "i")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }
}
