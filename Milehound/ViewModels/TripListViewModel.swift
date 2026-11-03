import CoreLocation
import Foundation

struct TripListViewModel {
    static func routeSummary(for trip: Trip, places: [SavedPlace] = [], privacyRadius: Double = 500) -> String {
        let start = displayName(
            placeName: trip.startPlaceName,
            address: trip.startAddress,
            coordinate: trip.startCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        let end = displayName(
            placeName: trip.endPlaceName,
            address: trip.endAddress,
            coordinate: trip.endCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        return "\(start) → \(end)"
    }

    /// Start-point label for trip-started notifications (favorite / Near Home / address / coords).
    static func startSummary(
        coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String {
        var placeName: String?
        if let coordinate, let matched = places.first(where: { $0.contains(coordinate) }) {
            placeName = matched.name
        }
        return displayName(
            placeName: placeName,
            address: nil,
            coordinate: coordinate,
            places: places,
            privacyRadius: privacyRadius
        )
    }

    static func displayName(
        placeName: String?,
        address: String?,
        coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String {
        if let coordinate,
           let privacy = PlaceMatchingService.privacyDisplayName(for: coordinate, places: places, privacyRadius: privacyRadius) {
            return privacy
        }
        if let placeName, !placeName.isEmpty { return placeName }
        // Prefer a matching saved place over the raw geocoded address.
        if let coordinate,
           let matched = places.first(where: { $0.contains(coordinate) }) {
            return matched.name
        }
        if let address, !address.isEmpty { return address }
        if let coordinate { return DateFormatters.formatCoordinate(coordinate) }
        return "—"
    }

    static func durationText(for trip: Trip) -> String {
        guard let duration = trip.duration else { return "—" }
        return DateFormatters.formatDuration(duration)
    }

    static func distanceText(for trip: Trip) -> String {
        DateFormatters.formatDistance(trip.distanceMeters)
    }

    static func dateText(for trip: Trip) -> String {
        DateFormatters.formatTripDateRange(startedAt: trip.startedAt, endedAt: trip.endedAt)
    }

    static func fuelText(for trip: Trip) -> String? {
        let cost = StatsViewModel.fuelCost(for: trip)
        guard cost > 0 else { return nil }
        return FuelCostCalculator.formatCost(cost)
    }

    /// Reads the stored maximum rather than deriving one from the points: a row must never touch
    /// `trip.sortedPoints`, which would load every point of every visible trip while scrolling.
    /// The stored value is only vetted for plausibility, so a trip recorded before speeds were
    /// checked shows no chip instead of a number the car never reached.
    static func maxSpeedText(for trip: Trip) -> String? {
        guard let maxSpeed = TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps) else {
            return nil
        }
        return L10n.formatSpeedKmh(maxSpeed * 3.6)
    }

    static func averageSpeedText(for trip: Trip) -> String? {
        guard let duration = trip.duration, duration > 0, trip.distanceMeters > 0 else { return nil }
        let averageKmh = trip.distanceMeters * 3.6 / duration
        guard averageKmh > 0 else { return nil }
        return L10n.formatSpeedKmh(averageKmh)
    }

    static func maxSpeedLabel(for trip: Trip) -> String? {
        guard let speed = maxSpeedText(for: trip) else { return nil }
        return "\(L10n.maxAbbr) \(speed)"
    }

    static func averageSpeedLabel(for trip: Trip) -> String? {
        guard let speed = averageSpeedText(for: trip) else { return nil }
        return "\(L10n.avgAbbr) \(speed)"
    }

    /// Note, addresses, stored place names, the live route summary (including "Ev yakını"),
    /// and the canonical saved-place name even when the row privacy-masks it.
    static func searchCorpus(
        for trip: Trip,
        places: [SavedPlace] = [],
        privacyRadius: Double = 500
    ) -> String {
        var parts: [String] = [
            routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
        ]
        if let note = trip.note, !note.isEmpty { parts.append(note) }
        if let startAddress = trip.startAddress, !startAddress.isEmpty { parts.append(startAddress) }
        if let endAddress = trip.endAddress, !endAddress.isEmpty { parts.append(endAddress) }
        if let startPlaceName = trip.startPlaceName, !startPlaceName.isEmpty { parts.append(startPlaceName) }
        if let endPlaceName = trip.endPlaceName, !endPlaceName.isEmpty { parts.append(endPlaceName) }

        if let start = trip.startCoordinate,
           let name = PlaceMatchingService.matchingPlace(
               at: start, places: places, privacyRadius: privacyRadius
           )?.name {
            parts.append(name)
        }
        if let end = trip.endCoordinate,
           let name = PlaceMatchingService.matchingPlace(
               at: end, places: places, privacyRadius: privacyRadius
           )?.name {
            parts.append(name)
        }

        return parts.joined(separator: "\n")
    }

    static func matchesSearch(
        _ trip: Trip,
        searchText: String,
        places: [SavedPlace] = [],
        privacyRadius: Double = 500
    ) -> Bool {
        let needle = SearchFolding.fold(searchText)
        guard !needle.isEmpty else { return true }

        if let searchIndex = trip.searchIndex, SearchFolding.fold(searchIndex).contains(needle) {
            return true
        }

        return SearchFolding.fold(
            searchCorpus(for: trip, places: places, privacyRadius: privacyRadius)
        ).contains(needle)
    }

    /// Visible while the user is typing (debounce pending) or results are applying.
    static func isSearchActivityVisible(
        searchText: String,
        debouncedSearchText: String,
        isApplying: Bool
    ) -> Bool {
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return false }
        return isApplying || searchText != debouncedSearchText
    }
}
