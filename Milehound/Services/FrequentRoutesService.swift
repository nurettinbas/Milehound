import CoreLocation
import Foundation

struct FrequentRoute: Identifiable, Hashable {
    let id: String
    let startKey: String
    let endKey: String
    let startDisplay: String
    let endDisplay: String
    let count: Int
}

enum FrequentRoutesService {
    static func frequentRoutes(
        from trips: [Trip],
        places: [SavedPlace],
        privacyRadius: Double,
        minimumCount: Int = 2
    ) -> [FrequentRoute] {
        var counts: [String: (start: String, end: String, count: Int)] = [:]

        for trip in trips where trip.endedAt != nil {
            let startDisplay = displayName(
                placeName: trip.startPlaceName,
                address: trip.startAddress,
                coordinate: trip.startCoordinate,
                places: places,
                privacyRadius: privacyRadius
            )
            let endDisplay = displayName(
                placeName: trip.endPlaceName,
                address: trip.endAddress,
                coordinate: trip.endCoordinate,
                places: places,
                privacyRadius: privacyRadius
            )
            let startKey = routeKey(placeName: trip.startPlaceName, address: trip.startAddress, coordinate: trip.startCoordinate)
            let endKey = routeKey(placeName: trip.endPlaceName, address: trip.endAddress, coordinate: trip.endCoordinate)
            guard startKey != "unknown", endKey != "unknown", startKey != endKey else { continue }

            let pairKey = "\(startKey)→\(endKey)"
            if var existing = counts[pairKey] {
                existing.count += 1
                counts[pairKey] = existing
            } else {
                counts[pairKey] = (start: startDisplay, end: endDisplay, count: 1)
            }
        }

        return counts
            .filter { $0.value.count >= minimumCount }
            .map { key, value in
                let parts = key.split(separator: "→", maxSplits: 1).map(String.init)
                return FrequentRoute(
                    id: key,
                    startKey: parts.first ?? "",
                    endKey: parts.count > 1 ? parts[1] : "",
                    startDisplay: value.start,
                    endDisplay: value.end,
                    count: value.count
                )
            }
            .sorted { $0.count > $1.count }
    }

    static func routeKey(placeName: String?, address: String?, coordinate: CLLocationCoordinate2D?) -> String {
        if let placeName, !placeName.isEmpty { return "place:\(placeName.lowercased())" }
        if let address, !address.isEmpty { return "addr:\(address.lowercased())" }
        if let coordinate {
            return String(format: "coord:%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        }
        return "unknown"
    }

    static func pairKey(for trip: Trip) -> String? {
        let startKey = routeKey(
            placeName: trip.startPlaceName,
            address: trip.startAddress,
            coordinate: trip.startCoordinate
        )
        let endKey = routeKey(
            placeName: trip.endPlaceName,
            address: trip.endAddress,
            coordinate: trip.endCoordinate
        )
        guard startKey != "unknown", endKey != "unknown", startKey != endKey else { return nil }
        return "\(startKey)→\(endKey)"
    }

    /// Category counts per `startKey→endKey` from trips the user (or an accepted suggestion)
    /// actually categorized. Default Personal rows are ignored so they cannot poison learning.
    static func categoryHistogram(
        from trips: [Trip],
        excluding tripID: UUID? = nil
    ) -> [String: [String: Int]] {
        var counts: [String: [String: Int]] = [:]

        for trip in trips where trip.endedAt != nil {
            if let tripID, trip.id == tripID { continue }
            guard trip.categoryOrigin.countsTowardLearning else { continue }
            guard let pairKey = pairKey(for: trip) else { continue }
            counts[pairKey, default: [:]][trip.categoryID, default: 0] += 1
        }

        return counts
    }

    static func placeSuggestions(
        from trips: [Trip],
        places: [SavedPlace],
        privacyRadius: Double,
        minimumVisits: Int = 3
    ) -> [(name: String, coordinate: CLLocationCoordinate2D, visits: Int)] {
        var visits: [String: (name: String, coordinate: CLLocationCoordinate2D, count: Int)] = [:]

        for trip in trips where trip.endedAt != nil {
            for endpoint in [(trip.startPlaceName, trip.startAddress, trip.startCoordinate),
                             (trip.endPlaceName, trip.endAddress, trip.endCoordinate)] {
                let display = displayName(
                    placeName: endpoint.0,
                    address: endpoint.1,
                    coordinate: endpoint.2,
                    places: places,
                    privacyRadius: privacyRadius
                )
                guard let coordinate = endpoint.2 else { continue }
                let key = routeKey(placeName: endpoint.0, address: endpoint.1, coordinate: coordinate)
                guard key != "unknown" else { continue }
                if places.contains(where: { $0.contains(coordinate) }) { continue }

                if var existing = visits[key] {
                    existing.count += 1
                    visits[key] = existing
                } else {
                    visits[key] = (name: display, coordinate: coordinate, count: 1)
                }
            }
        }

        return visits.values
            .filter { $0.count >= minimumVisits }
            .map { ($0.name, $0.coordinate, $0.count) }
            .sorted { $0.visits > $1.visits }
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
        if let coordinate,
           let matched = places.first(where: { $0.contains(coordinate) }) {
            return matched.name
        }
        if let address, !address.isEmpty { return address }
        if let coordinate { return DateFormatters.formatCoordinate(coordinate) }
        return "—"
    }
}
