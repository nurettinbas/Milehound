import Foundation

/// Shared start-or-end place-name match for the Trips list and Stats filters.
///
/// Trips store denormalized `startPlaceName` / `endPlaceName` (no place ID). Matching is
/// case-sensitive exact equality against the name `PlaceMatchingService` writes.
enum TripPlaceFilter {
    /// `nil` / empty `placeName` means no place filter (all trips match).
    static func matches(startPlaceName: String?, endPlaceName: String?, placeName: String?) -> Bool {
        guard let placeName, !placeName.isEmpty else { return true }
        return startPlaceName == placeName || endPlaceName == placeName
    }

    static func matches<T: TripStatsAggregable>(_ trip: T, placeName: String?) -> Bool {
        matches(
            startPlaceName: trip.startPlaceName,
            endPlaceName: trip.endPlaceName,
            placeName: placeName
        )
    }
}
