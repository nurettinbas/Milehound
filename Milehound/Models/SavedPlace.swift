import CoreLocation
import Foundation
import SwiftData

@Model
final class SavedPlace {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var kindRaw: String
    var isPrivacyZone: Bool

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 300,
        kind: SavedPlaceKind = .other,
        isPrivacyZone: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.kindRaw = kind.rawValue
        self.isPrivacyZone = isPrivacyZone
    }

    var kind: SavedPlaceKind {
        get { SavedPlaceKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let place = CLLocation(latitude: latitude, longitude: longitude)
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return place.distance(from: target) <= radiusMeters
    }
}
