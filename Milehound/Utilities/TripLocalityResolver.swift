import CoreLocation
import Foundation

enum TripLocalityResolver {
    static func privacyPlace(
        for coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> SavedPlace? {
        guard let coordinate else { return nil }
        for place in places where place.isPrivacyZone || place.kind == .home {
            let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let radius = max(place.radiusMeters, privacyRadius)
            if center.distance(from: target) <= radius {
                return place
            }
        }
        return nil
    }

    static func isPrivacyCoordinate(
        _ coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> Bool {
        privacyPlace(for: coordinate, places: places, privacyRadius: privacyRadius) != nil
    }

    /// Map pin / aggregate coordinate: saved-place center inside a privacy zone, else the raw point.
    static func mapCoordinate(
        _ coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> CLLocationCoordinate2D? {
        if let place = privacyPlace(for: coordinate, places: places, privacyRadius: privacyRadius) {
            return place.coordinate
        }
        return coordinate
    }

    static func sanitizedLocality(
        _ locality: String?,
        coordinate: CLLocationCoordinate2D?,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String? {
        if isPrivacyCoordinate(coordinate, places: places, privacyRadius: privacyRadius) {
            return nil
        }
        let trimmed = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func apply(
        to trip: Trip,
        startLocality: String?,
        startCountryCode: String?,
        endLocality: String?,
        endCountryCode: String?,
        places: [SavedPlace],
        privacyRadius: Double
    ) {
        trip.startLocality = sanitizedLocality(
            startLocality,
            coordinate: trip.startCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        trip.endLocality = sanitizedLocality(
            endLocality,
            coordinate: trip.endCoordinate,
            places: places,
            privacyRadius: privacyRadius
        )
        if trip.startLocality == nil {
            trip.startCountryCode = nil
        } else {
            trip.startCountryCode = normalizedCountryCode(startCountryCode)
        }
        if trip.endLocality == nil {
            trip.endCountryCode = nil
        } else {
            trip.endCountryCode = normalizedCountryCode(endCountryCode)
        }
    }

    static func localities(on trip: Trip) -> [String] {
        [trip.startLocality, trip.endLocality]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedCountryCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }
}
