import Foundation
import SwiftData

/// Builds the paged fetches behind the trip list.
///
/// The list used to hold every `Trip` in memory via an unfiltered `@Query`, which made both the
/// fetch and every body pass scale with total library size. These descriptors push what the store
/// can answer down into SQLite and cap each read to one page.
enum TripListPage {
    static let pageSize = 50

    /// Trip-list vehicle chip selection. `nil` on `Filters` means All; `.unassigned` matches
    /// trips with no `vehicleID` (same bucket as Stats "No vehicle").
    enum VehicleFilter: Equatable, Hashable {
        case unassigned
        case vehicle(UUID)
    }

    struct Filters: Equatable {
        var searchText: String = ""
        var categoryID: String?
        
        var dateSection: TripDateSection?
        var vehicleFilter: VehicleFilter?
        /// Exact `SavedPlace.name` matched against start or end place name. `nil` means All.
        var placeName: String?

        var isActive: Bool {
            categoryID != nil
                || dateSection != nil
                || vehicleFilter != nil
                || placeName != nil
                || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// A completed trip's `categoryID` is derived: legacy rows still store `"personal"` /
    /// `"business"` while newer ones store a UUID string. Both spellings must match the filter.
    static func acceptableCategoryRawValues(for categoryID: String) -> [String] {
        if categoryID == BuiltInCategory.personalID.uuidString {
            return [categoryID, TripCategory.personal.rawValue]
        }
        if categoryID == BuiltInCategory.businessID.uuidString {
            return [categoryID, TripCategory.business.rawValue]
        }
        return [categoryID]
    }

    /// Earliest `startedAt` a trip can have and still belong to `section`. Only a lower bound:
    /// the exact section is confirmed in memory, since the boundaries move with the wall clock.
    static func lowerBound(for section: TripDateSection?, calendar: Calendar = .current) -> Date {
        guard let section else { return .distantPast }
        let now = Date()
        switch section {
        case .today:
            return calendar.startOfDay(for: now)
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
                ?? .distantPast
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? .distantPast
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start ?? .distantPast
        case .older:
            return .distantPast
        }
    }

    /// Fetches one page plus a probe row, so the caller can tell whether more pages exist without
    /// a second count query. Text search cannot live in `#Predicate`: optional `searchIndex!`
    /// unwraps are rejected at fetch time (same constraint as `TravelJournalPage`), so the list
    /// loads the full candidate set and `TripListView` filters in memory.
    static func descriptor(filters: Filters, limit: Int) -> FetchDescriptor<Trip> {
        let lowerBound = lowerBound(for: filters.dateSection)
        let categoryRawValues = filters.categoryID.map(acceptableCategoryRawValues(for:))
        // Empty string means All — keeps `#Predicate` free of optional place comparisons.
        let placeName = filters.placeName ?? ""
        let searching = !SearchFolding.fold(filters.searchText).isEmpty

        var descriptor = FetchDescriptor<Trip>(
            predicate: listPredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues,
                vehicleFilter: filters.vehicleFilter,
                placeName: placeName
            ),
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if !searching {
            descriptor.fetchLimit = limit + 1
        }
        return descriptor
    }

    private static func listPredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        vehicleFilter: VehicleFilter?,
        placeName: String
    ) -> Predicate<Trip> {
        if placeName.isEmpty {
            return vehiclePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues,
                vehicleFilter: vehicleFilter
            )
        }
        return vehiclePlacePredicate(
            lowerBound: lowerBound,
            categoryRawValues: categoryRawValues,
            vehicleFilter: vehicleFilter,
            placeName: placeName
        )
    }

    private static func vehiclePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        vehicleFilter: VehicleFilter?
    ) -> Predicate<Trip> {
        switch vehicleFilter {
        case .unassigned:
            return unassignedVehiclePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues
            )
        case .vehicle(let vehicleID):
            return specificVehiclePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues,
                vehicleID: vehicleID
            )
        case nil:
            return anyVehiclePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues
            )
        }
    }

    private static func vehiclePlacePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        vehicleFilter: VehicleFilter?,
        placeName: String
    ) -> Predicate<Trip> {
        switch vehicleFilter {
        case .unassigned:
            return unassignedVehiclePlacePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues,
                placeName: placeName
            )
        case .vehicle(let vehicleID):
            return specificVehiclePlacePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues,
                vehicleID: vehicleID,
                placeName: placeName
            )
        case nil:
            return anyVehiclePlacePredicate(
                lowerBound: lowerBound,
                categoryRawValues: categoryRawValues,
                placeName: placeName
            )
        }
    }

    private static func anyVehiclePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?
    ) -> Predicate<Trip> {
        #Predicate<Trip> { trip in
            trip.endedAt != nil
                && trip.startedAt >= lowerBound
                && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
        }
    }

    private static func specificVehiclePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        vehicleID: UUID
    ) -> Predicate<Trip> {
        #Predicate<Trip> { trip in
            trip.endedAt != nil
                && trip.startedAt >= lowerBound
                && trip.vehicleID == vehicleID
                && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
        }
    }

    private static func unassignedVehiclePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?
    ) -> Predicate<Trip> {
        // Capture an explicit nil so the type-checker can resolve optional UUID equality.
        let unsetVehicleID: UUID? = nil
        return #Predicate<Trip> { trip in
            trip.endedAt != nil
                && trip.startedAt >= lowerBound
                && trip.vehicleID == unsetVehicleID
                && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
        }
    }

    private static func anyVehiclePlacePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        placeName: String
    ) -> Predicate<Trip> {
        #Predicate<Trip> { trip in
            trip.endedAt != nil
                && trip.startedAt >= lowerBound
                && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
                && (trip.startPlaceName == placeName || trip.endPlaceName == placeName)
        }
    }

    private static func specificVehiclePlacePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        vehicleID: UUID,
        placeName: String
    ) -> Predicate<Trip> {
        #Predicate<Trip> { trip in
            trip.endedAt != nil
                && trip.startedAt >= lowerBound
                && trip.vehicleID == vehicleID
                && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
                && (trip.startPlaceName == placeName || trip.endPlaceName == placeName)
        }
    }

    private static func unassignedVehiclePlacePredicate(
        lowerBound: Date,
        categoryRawValues: [String]?,
        placeName: String
    ) -> Predicate<Trip> {
        let unsetVehicleID: UUID? = nil
        return #Predicate<Trip> { trip in
            trip.endedAt != nil
                && trip.startedAt >= lowerBound
                && trip.vehicleID == unsetVehicleID
                && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
                && (trip.startPlaceName == placeName || trip.endPlaceName == placeName)
        }
    }

    static func newestCompletedDescriptor() -> FetchDescriptor<Trip> {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func completedInDescriptor(from lowerBound: Date) -> FetchDescriptor<Trip> {
        FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt >= lowerBound },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    static func completedCountDescriptor() -> FetchDescriptor<Trip> {
        FetchDescriptor<Trip>(predicate: #Predicate { $0.endedAt != nil })
    }

    static func descriptor(forIDs ids: Set<UUID>) -> FetchDescriptor<Trip> {
        let idList = Array(ids)
        return FetchDescriptor<Trip>(
            predicate: #Predicate { idList.contains($0.id) },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
    }
}
