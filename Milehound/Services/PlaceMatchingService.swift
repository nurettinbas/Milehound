import CoreLocation
import Foundation
import SwiftData

enum PlaceMatchingService {
    /// Same radius the trip row uses: the place's own radius, or the privacy radius for
    /// home / privacy-zone places so "Ev yakını" rows also get `startPlaceName == "Ev"`.
    static func matchingPlace(
        at coordinate: CLLocationCoordinate2D,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> SavedPlace? {
        if let exact = places.first(where: { $0.contains(coordinate) }) {
            return exact
        }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for place in places where place.isPrivacyZone || place.kind == .home {
            let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let radius = max(place.radiusMeters, privacyRadius)
            if center.distance(from: target) <= radius {
                return place
            }
        }
        return nil
    }

    static func matchPlaces(
        for trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double = 500
    ) {
        if let start = trip.startCoordinate,
           let startPlace = matchingPlace(at: start, places: places, privacyRadius: privacyRadius) {
            trip.startPlaceName = startPlace.name
        }
        if let end = trip.endCoordinate,
           let endPlace = matchingPlace(at: end, places: places, privacyRadius: privacyRadius) {
            trip.endPlaceName = endPlace.name
        }
    }

    /// Re-applies saved-place names to trip endpoints and refreshes search indexes.
    /// Call after a `SavedPlace` is created or updated so existing trips pick up the label.
    static func rematchTrips(
        _ trips: [Trip],
        places: [SavedPlace],
        privacyRadius: Double,
        suggestionsEnabled: Bool = true,
        workHours: TripCategoryWorkHours = .default
    ) {
        guard !places.isEmpty else { return }

        for trip in trips {
            matchPlaces(for: trip, places: places, privacyRadius: privacyRadius)
            TripDerivedMetrics.refreshSearchIndex(
                for: trip,
                places: places,
                privacyRadius: privacyRadius
            )
            TripCategorySuggestionService.refreshPending(
                on: trip,
                among: trips,
                places: places,
                enabled: suggestionsEnabled,
                workHours: workHours
            )
        }
    }

    static func privacyDisplayName(
        for coordinate: CLLocationCoordinate2D,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String? {
        for place in places where place.isPrivacyZone || place.kind == .home {
            let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let radius = max(place.radiusMeters, privacyRadius)
            if center.distance(from: target) <= radius {
                return L10n.placeNearName(place.name)
            }
        }
        return nil
    }

    static func blurredCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (coordinate.latitude * 100).rounded() / 100,
            longitude: (coordinate.longitude * 100).rounded() / 100
        )
    }
}
