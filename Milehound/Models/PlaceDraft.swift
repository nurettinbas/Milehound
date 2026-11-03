import CoreLocation
import Foundation

/// Prefill payload for creating a `SavedPlace` (e.g. from a trip endpoint).
struct PlaceDraft: Equatable, Identifiable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var kind: SavedPlaceKind

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: CLLocationCoordinate2D,
        address: String? = nil,
        kind: SavedPlaceKind = .other
    ) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.address = address
        self.kind = kind
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
