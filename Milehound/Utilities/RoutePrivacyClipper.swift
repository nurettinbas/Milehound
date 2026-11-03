import CoreLocation
import Foundation

/// Value snapshot of a saved place for privacy clipping — Sendable and free of SwiftData.
struct RoutePrivacyPlace: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let expandsClipRadius: Bool

    init(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        expandsClipRadius: Bool
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.expandsClipRadius = expandsClipRadius
    }

    init(_ place: SavedPlace) {
        latitude = place.latitude
        longitude = place.longitude
        radiusMeters = place.radiusMeters
        expandsClipRadius = place.isPrivacyZone || place.kind == .home
    }
}

enum RoutePrivacyClipper {
    static func clip(
        _ coordinates: [CLLocationCoordinate2D],
        privacyRadiusMeters: Double,
        places: [SavedPlace] = []
    ) -> [CLLocationCoordinate2D] {
        let range = clippedRange(
            coordinates,
            privacyRadiusMeters: privacyRadiusMeters,
            places: places.map(RoutePrivacyPlace.init)
        )
        return Array(coordinates[range])
    }

    static func clip(
        _ coordinates: [CLLocationCoordinate2D],
        privacyRadiusMeters: Double,
        places: [RoutePrivacyPlace]
    ) -> [CLLocationCoordinate2D] {
        let range = clippedRange(
            coordinates,
            privacyRadiusMeters: privacyRadiusMeters,
            places: places
        )
        return Array(coordinates[range])
    }

    /// The surviving index range, so callers holding per-point metadata (timestamps, speed)
    /// can trim the same way without dropping that metadata.
    static func clippedRange(
        _ coordinates: [CLLocationCoordinate2D],
        privacyRadiusMeters: Double,
        places: [SavedPlace] = []
    ) -> Range<Int> {
        clippedRange(
            coordinates,
            privacyRadiusMeters: privacyRadiusMeters,
            places: places.map(RoutePrivacyPlace.init)
        )
    }

    static func clippedRange(
        _ coordinates: [CLLocationCoordinate2D],
        privacyRadiusMeters: Double,
        places: [RoutePrivacyPlace]
    ) -> Range<Int> {
        let full = coordinates.startIndex..<coordinates.endIndex
        guard coordinates.count >= 2 else { return full }
        guard let routeStart = coordinates.first, let routeEnd = coordinates.last else { return full }

        let startRadius = effectiveRadius(for: routeStart, places: places, defaultRadius: privacyRadiusMeters)
        let endRadius = effectiveRadius(for: routeEnd, places: places, defaultRadius: privacyRadiusMeters)
        // Radius 0 (and no expanded home/privacy zone) means "do not clip".
        // Using `distance <= 0` would otherwise drop the exact start/end vertices.
        if startRadius <= 0 && endRadius <= 0 { return full }

        let startLocation = CLLocation(latitude: routeStart.latitude, longitude: routeStart.longitude)
        let endLocation = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)

        var lower = 0
        var upper = coordinates.count

        while upper - lower > 2 {
            let first = coordinates[lower]
            let distance = CLLocation(latitude: first.latitude, longitude: first.longitude)
                .distance(from: startLocation)
            if distance <= startRadius { lower += 1 } else { break }
        }

        while upper - lower > 2 {
            let last = coordinates[upper - 1]
            let distance = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: endLocation)
            if distance <= endRadius { upper -= 1 } else { break }
        }

        return upper - lower >= 2 ? lower..<upper : full
    }

    private static func effectiveRadius(
        for coordinate: CLLocationCoordinate2D,
        places: [RoutePrivacyPlace],
        defaultRadius: Double
    ) -> Double {
        var radius = defaultRadius
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for place in places where place.expandsClipRadius {
            let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
            if center.distance(from: target) <= max(place.radiusMeters, defaultRadius) {
                radius = max(radius, place.radiusMeters, defaultRadius)
            }
        }
        return radius
    }
}
