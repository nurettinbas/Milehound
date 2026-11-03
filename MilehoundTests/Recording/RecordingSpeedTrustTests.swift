import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

/// Reproduces the field report end to end: a trip that claimed 203 km/h at its start, on a drive
/// where the car never went near that.
@MainActor
final class RecordingSpeedTrustTests: XCTestCase {
    func testFirstFixWithLargePositionErrorDoesNotSetTheMaximum() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let locationService = LocationService()
        let service = TripRecordingService(
            locationService: locationService,
            settings: AppSettings(
                userDefaults: UserDefaults(suiteName: "test.milehound.speed.\(UUID().uuidString)")!
            )
        )
        service.configure(modelContext: context)

        XCTAssertTrue(service.startManualRecording())
        let tripID = try XCTUnwrap(service.activeTripID)

        // The cold-start fix: Core Location is still converging, is 170 m out, and reports a speed
        // left over from before. Accurate enough to keep as a position, not to believe as a speed.
        let start = CLLocationCoordinate2D(latitude: 38.4237, longitude: 27.1428)
        await emit(
            fix(at: start, horizontalAccuracy: 170, speed: 56.4, speedAccuracy: 5),
            through: locationService
        )

        // Three seconds later, a clean fix from a car doing 43 km/h.
        await emit(
            fix(
                at: CLLocationCoordinate2D(latitude: 38.4240, longitude: 27.1428),
                horizontalAccuracy: 6,
                speed: 12,
                speedAccuracy: 0.5
            ),
            through: locationService
        )

        service.stopManualRecording()

        let trip = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Trip>()).first { $0.id == tripID }
        )
        let recorded = trip.maxSpeedMps ?? 0
        XCTAssertLessThan(recorded * 3.6, 100, "a converging first fix must not set a 203 km/h record")
        XCTAssertTrue(
            trip.sortedPoints.allSatisfy { ($0.speedMps ?? 0) <= RecordingMovementPolicy.maximumRecordedSpeedMps },
            "no point may carry a speed no car reaches"
        )
    }

    private func emit(_ location: CLLocation, through locationService: LocationService) async {
        locationService.onLocationUpdate?(location)
        // The service hops to the main actor to handle the fix; let that hop land.
        for _ in 0..<5 { await Task.yield() }
    }

    private func fix(
        at coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: CLLocationAccuracy,
        speed: CLLocationSpeed,
        speedAccuracy: CLLocationSpeedAccuracy
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 10,
            course: 0,
            courseAccuracy: 5,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: Date()
        )
    }
}
