import CoreLocation
import Foundation
import SwiftData

@Model
final class TripStop {
    var latitude: Double
    var longitude: Double
    var startedAt: Date
    var durationSeconds: TimeInterval
    var trip: Trip?

    init(
        latitude: Double,
        longitude: Double,
        startedAt: Date,
        durationSeconds: TimeInterval,
        trip: Trip? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
