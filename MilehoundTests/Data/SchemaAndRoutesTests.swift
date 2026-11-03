import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class TripRoutePathDataSafetyTests: XCTestCase {
    func testDisplayPathBuildDoesNotMutateStoredPoints() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_200),
            distanceMeters: 8_000
        )
        context.insert(trip)
        for index in 0..<80 {
            context.insert(
                TripPoint(
                    timestamp: startedAt.addingTimeInterval(Double(index) * 10),
                    latitude: 41.0 + Double(index) * 0.0002,
                    longitude: 29.0 + Double(index) * 0.0002,
                    sequence: index,
                    speedMps: 14,
                    trip: trip
                )
            )
        }
        try context.save()

        let pointCountBefore = trip.points.count
        let pieces = await TripRoutePathCache.shared.path(for: trip, container: container)
        XCTAssertFalse(pieces.isEmpty)
        trip.invalidatePointCaches()

        XCTAssertEqual(trip.points.count, pointCountBefore)

        TripRoutePathCache.shared.remove(for: trip.id)
        TripRoutePathCache.shared.clearMemory()
        try await Task.sleep(for: .milliseconds(50))

        let rebuilt = await TripRoutePathCache.shared.path(for: trip, container: container)
        XCTAssertEqual(rebuilt.count, pieces.count)
        XCTAssertEqual(rebuilt.first?.count, pieces.first?.count)

        TripRoutePathCache.shared.remove(for: trip.id)
    }
}

@MainActor
final class FrequentRoutesServiceTests: XCTestCase {
    func testDetectsRepeatedRoute() {
        let tripA = Trip(
            startedAt: Date(),
            endedAt: Date(),
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let tripB = Trip(
            startedAt: Date(),
            endedAt: Date(),
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let routes = FrequentRoutesService.frequentRoutes(from: [tripA, tripB], places: [], privacyRadius: 500)
        XCTAssertEqual(routes.first?.count, 2)
        XCTAssertEqual(routes.first?.startDisplay, "Ev")
        XCTAssertEqual(routes.first?.endDisplay, "Ofis")
    }

    func testCategoryHistogramCountsUserSetTripsOnly() {
        let learned = Trip(
            startedAt: Date(),
            endedAt: Date(),
            category: .business,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let ignoredDefault = Trip(
            startedAt: Date(),
            endedAt: Date(),
            category: .personal,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let histogram = FrequentRoutesService.categoryHistogram(from: [learned, ignoredDefault])
        let pairKey = FrequentRoutesService.pairKey(for: learned)
        XCTAssertEqual(histogram[pairKey ?? ""]?[BuiltInCategory.businessID.uuidString], 1)
        XCTAssertNil(histogram[pairKey ?? ""]?[BuiltInCategory.personalID.uuidString])
    }
}

@MainActor
final class SchemaMigrationTests: XCTestCase {
    func testV6TripSupportsNullableVehicleID() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV6.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let trip = Trip(startedAt: Date(), endedAt: Date(), distanceMeters: 1200)
        container.mainContext.insert(trip)
        try container.mainContext.save()

        let trips = try container.mainContext.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertNil(trips.first?.vehicleID)
        XCTAssertNil(trips.first?.vehicle)
    }

    func testV6SupportsVehicleProfile() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV6.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let vehicle = VehicleProfile(name: "Test", fuelType: .petrol, consumption: 7.5)
        container.mainContext.insert(vehicle)
        try container.mainContext.save()

        let vehicles = try container.mainContext.fetch(FetchDescriptor<VehicleProfile>())
        XCTAssertEqual(vehicles.count, 1)
    }

    func testVehicleProfilePersistsPairedRoute() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let vehicle = VehicleProfile(
            name: "Ford Puma",
            consumption: 6.5,
            autoStartEnabled: true,
            pairedRouteUID: "puma-bt-uid",
            pairedRouteName: "Ford Puma"
        )
        container.mainContext.insert(vehicle)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<VehicleProfile>()).first
        XCTAssertTrue(fetched?.autoStartEnabled == true)
        XCTAssertEqual(fetched?.pairedRouteUID, "puma-bt-uid")
        XCTAssertEqual(fetched?.pairedRouteName, "Ford Puma")
    }

    func testV12PersistsVehiclePhotoFileName() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV12.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let vehicle = VehicleProfile(
            name: "Photo Car",
            photoFileName: "abc-123.jpg"
        )
        container.mainContext.insert(vehicle)
        try container.mainContext.save()

        let fetched = try container.mainContext.fetch(FetchDescriptor<VehicleProfile>()).first
        XCTAssertEqual(fetched?.photoFileName, "abc-123.jpg")
        XCTAssertNil(VehicleProfile(name: "No Photo").photoFileName)
    }
}
