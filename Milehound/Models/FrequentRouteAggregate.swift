import Foundation
import SwiftData
import CoreLocation

/// Derived start→end pair totals. Not a source of truth — rebuilt from `Trip`.
@Model
final class FrequentRouteAggregate {
    var pairKey: String = ""
    var startKey: String = ""
    var endKey: String = ""
    var startDisplay: String = ""
    var endDisplay: String = ""
    var startLatitude: Double = 0
    var startLongitude: Double = 0
    var endLatitude: Double = 0
    var endLongitude: Double = 0
    var count: Int = 0
    var totalDistanceMeters: Double = 0
    var totalFuelCost: Double = 0
    var lastStartedAt: Date = Date()
    var businessCount: Int = 0
    var personalCount: Int = 0

    init(pairKey: String, startKey: String, endKey: String) {
        self.pairKey = pairKey
        self.startKey = startKey
        self.endKey = endKey
    }

    var startCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var endCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }

    var isBusinessHeavy: Bool {
        businessCount > personalCount
    }

    var hasValidCoordinates: Bool {
        abs(startLatitude) > 0.0001 || abs(startLongitude) > 0.0001
            || abs(endLatitude) > 0.0001 || abs(endLongitude) > 0.0001
    }
}
