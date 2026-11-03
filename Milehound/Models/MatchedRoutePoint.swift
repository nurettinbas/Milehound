import CoreLocation
import Foundation
import SwiftData

@Model
final class MatchedRoutePoint {
    var latitude: Double
    var longitude: Double
    var sequence: Int
    var trip: Trip?

    init(
        latitude: Double,
        longitude: Double,
        sequence: Int,
        trip: Trip? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.sequence = sequence
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
