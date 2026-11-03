import CoreLocation
import Foundation
import SwiftData

@Model
final class TripPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var sequence: Int
    var speedMps: Double?
    var trip: Trip?

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        sequence: Int,
        speedMps: Double? = nil,
        trip: Trip? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.sequence = sequence
        self.speedMps = speedMps
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
