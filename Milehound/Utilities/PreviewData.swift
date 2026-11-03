import CoreLocation
import SwiftData
import SwiftUI

@MainActor
final class PreviewData {
    static let shared = PreviewData()

    let locationService = LocationService()
    let recordingService: TripRecordingService
    let container: ModelContainer

    private init() {
        recordingService = TripRecordingService(
            locationService: locationService
        )

        let container = try! ModelContainerFactory.makeInMemory()
        let trip = PreviewData.sampleTrip
        container.mainContext.insert(trip)
        for point in trip.points { container.mainContext.insert(point) }
        self.container = container
    }

    static var sampleTrip: Trip {
        let startedAt = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        let endedAt = Calendar.current.date(byAdding: .minute, value: -70, to: Date()) ?? Date()

        let start = CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)
        let end = CLLocationCoordinate2D(latitude: 41.0621, longitude: 29.0115)
        let mid = CLLocationCoordinate2D(latitude: 41.0350, longitude: 28.9950)

        let trip = Trip(
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: 14200,
            startAddress: "Kadikoy, Istanbul",
            endAddress: "Levent, Istanbul",
            category: .business,
            geocodeStatus: .complete,
            maxSpeedMps: 22,
            estimatedFuelCost: 85,
            startPlaceName: "Home",
            endPlaceName: "Office"
        )

        let points = [
            TripPoint(timestamp: startedAt, latitude: start.latitude, longitude: start.longitude, sequence: 0, speedMps: 10, trip: trip),
            TripPoint(timestamp: startedAt.addingTimeInterval(600), latitude: mid.latitude, longitude: mid.longitude, sequence: 1, speedMps: 15, trip: trip),
            TripPoint(timestamp: endedAt, latitude: end.latitude, longitude: end.longitude, sequence: 2, speedMps: 8, trip: trip)
        ]
        trip.points = points
        return trip
    }
}
