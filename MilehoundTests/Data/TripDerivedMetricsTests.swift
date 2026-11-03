import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

/// Exercises the V10 derived fields against a real on-disk store, because an empty in-memory
/// container cannot show whether an existing user library survives the schema bump.
@MainActor
final class TripDerivedMetricsMigrationTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MilehoundMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let storeDirectory {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        storeDirectory = nil
        try super.tearDownWithError()
    }

    private var storeURL: URL {
        storeDirectory.appendingPathComponent("Milehound.store")
    }

    private func makeDiskContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([
                Trip.self,
                TripPoint.self,
                SavedPlace.self,
                TripStop.self,
                UserCategory.self,
                MatchedRoutePoint.self,
                VehicleProfile.self,
                VehicleFuelCalibration.self,
            ]),
            configurations: ModelConfiguration(url: storeURL)
        )
    }

    /// Seeds a trip whose derived fields are `nil`, exactly how a row written before V10 looks
    /// after SwiftData's lightweight migration adds the new optional columns.
    @discardableResult
    private func seedLegacyTrip(
        in context: ModelContext,
        startedAt: Date,
        pointCount: Int = 12,
        distanceMeters: Double = 4_200
    ) -> UUID {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: distanceMeters,
            startAddress: "Kadıköy",
            endAddress: "Levent",
            label: "İş"
        )
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 60),
                latitude: 41.0 + Double(index) * 0.001,
                longitude: 29.0 + Double(index) * 0.001,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            trip.points.append(point)
            context.insert(point)
        }

        trip.nightDistanceMeters = nil
        trip.trackedDistanceMeters = nil
        trip.startLatitude = nil
        trip.startLongitude = nil
        trip.endLatitude = nil
        trip.endLongitude = nil
        trip.searchIndex = nil
        return trip.id
    }

    func testExistingOnDiskStoreSurvivesDerivedFieldSchema() throws {
        let seededIDs: [UUID]
        do {
            let container = try makeDiskContainer()
            let context = container.mainContext
            seededIDs = [
                seedLegacyTrip(in: context, startedAt: Date().addingTimeInterval(-86_400)),
                seedLegacyTrip(in: context, startedAt: Date().addingTimeInterval(-172_800)),
            ]
            try context.save()
        }

        // Fresh container over the same file: the app relaunching after the update.
        let reopened = try makeDiskContainer()
        let trips = try reopened.mainContext.fetch(FetchDescriptor<Trip>())

        XCTAssertEqual(trips.count, 2, "existing trips must survive the schema bump")
        XCTAssertEqual(Set(trips.map(\.id)), Set(seededIDs))
        for trip in trips {
            XCTAssertEqual(trip.distanceMeters, 4_200, accuracy: 0.1)
            XCTAssertEqual(trip.points.count, 12, "GPS points must not be dropped")
            XCTAssertEqual(trip.startAddress, "Kadıköy")
            XCTAssertNil(trip.nightDistanceMeters, "pre-V10 rows start out un-backfilled")
        }
    }

    func testBackfillPopulatesDerivedFieldsWithoutTouchingUserData() async throws {
        let container = try makeDiskContainer()
        seedLegacyTrip(in: container.mainContext, startedAt: Date().addingTimeInterval(-86_400))
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let trip = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<Trip>()).first)

        XCTAssertNotNil(trip.nightDistanceMeters)
        XCTAssertNotNil(trip.trackedDistanceMeters)
        XCTAssertEqual(try XCTUnwrap(trip.startLatitude), 41.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.endLatitude), 41.011, accuracy: 0.0001)
        XCTAssertTrue(
            SearchFolding.fold(try XCTUnwrap(trip.searchIndex)).contains(SearchFolding.fold("kadıköy"))
        )

        XCTAssertEqual(trip.distanceMeters, 4_200, accuracy: 0.1, "recorded distance must be untouched")
        XCTAssertEqual(trip.points.count, 12, "backfill must never reduce GPS points")
        XCTAssertEqual(trip.label, "İş")
    }

    func testBackfillIsIdempotentAndResumesAcrossBatches() async throws {
        let container = try makeDiskContainer()
        // Two full batches plus a partial one, so a single pass has to loop.
        let tripCount = 55
        for index in 0..<tripCount {
            seedLegacyTrip(
                in: container.mainContext,
                startedAt: Date().addingTimeInterval(-Double(index + 1) * 86_400),
                pointCount: 4
            )
        }
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let context = ModelContext(container)
        let firstPass = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(firstPass.count, tripCount)
        XCTAssertTrue(
            firstPass.allSatisfy { $0.nightDistanceMeters != nil },
            "every completed trip should be backfilled in one run"
        )
        let trackedBefore = firstPass.map(\.trackedDistanceMeters)

        // Running again must be a no-op rather than double-counting anything.
        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let secondContext = ModelContext(container)
        let secondPass = try secondContext.fetch(FetchDescriptor<Trip>())
            .sorted { $0.startedAt > $1.startedAt }
        XCTAssertEqual(secondPass.count, tripCount)
        XCTAssertEqual(
            secondPass.map(\.trackedDistanceMeters),
            firstPass.sorted { $0.startedAt > $1.startedAt }.map(\.trackedDistanceMeters)
        )
        XCTAssertEqual(trackedBefore.count, tripCount)
    }

    func testBackfillSkipsInProgressTrips() async throws {
        let container = try makeDiskContainer()
        let active = Trip(startedAt: Date(), endedAt: nil, distanceMeters: 500)
        container.mainContext.insert(active)
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let context = ModelContext(container)
        let trip = try XCTUnwrap(try context.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertNil(trip.nightDistanceMeters, "an unfinished trip is recomputed when it ends")
    }

    func testSearchIndexRefreshRewritesStalePlaceNamesWithoutTouchingUserData() async throws {
        let versionKey = "milehound.derived.searchIndexVersion"
        let previousVersion = UserDefaults.standard.integer(forKey: versionKey)
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.set(previousVersion, forKey: versionKey) }

        let container = try makeDiskContainer()
        let context = container.mainContext
        let startedAt = Date().addingTimeInterval(-86_400)
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: 4_200,
            startAddress: "Old Street",
            note: "Keep this note"
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.endLatitude = 41.01
        trip.endLongitude = 29.01
        trip.nightDistanceMeters = 0
        trip.trackedDistanceMeters = 4_200
        trip.stopDurationSeconds = 0
        trip.dynamicFuelCost = 0
        trip.searchIndex = "old street"
        context.insert(trip)

        let home = SavedPlace(
            name: "Ev",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300,
            kind: .home,
            isPrivacyZone: true
        )
        context.insert(home)
        try context.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let updated = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertEqual(updated.note, "Keep this note")
        XCTAssertEqual(updated.distanceMeters, 4_200, accuracy: 0.1)
        XCTAssertEqual(updated.startPlaceName, "Ev")
        XCTAssertTrue(SearchFolding.fold(try XCTUnwrap(updated.searchIndex)).contains(SearchFolding.fold("Ev")))
        XCTAssertTrue(TripListViewModel.matchesSearch(updated, searchText: "ev"))
    }

    func testRefreshDynamicFuelVersionRewritesAllCompletedTrips() async throws {
        let fuelKey = TripDerivedBackfillService.dynamicFuelVersionKey
        let previous = UserDefaults.standard.integer(forKey: fuelKey)
        UserDefaults.standard.set(1, forKey: fuelKey)
        defer { UserDefaults.standard.set(previous, forKey: fuelKey) }

        let container = try makeDiskContainer()
        let startedAt = Date().addingTimeInterval(-86_400)
        let tripID = seedLegacyTrip(in: container.mainContext, startedAt: startedAt)
        let trip = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<Trip>()).first { $0.id == tripID }
        )
        trip.estimatedFuelCost = 243.75
        trip.fuelConsumptionPer100 = 7.5
        trip.fuelUnitPrice = 65
        trip.dynamicFuelCost = 9_999
        trip.nightDistanceMeters = 0
        trip.trackedDistanceMeters = 4_200
        trip.stopDurationSeconds = 0
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: fuelKey),
            TripDerivedBackfillService.dynamicFuelVersion
        )
        let updated = try XCTUnwrap(
            try ModelContext(container).fetch(FetchDescriptor<Trip>()).first { $0.id == tripID }
        )
        XCTAssertEqual(updated.estimatedFuelCost ?? 0, 243.75, accuracy: 0.01)
        XCTAssertNotEqual(updated.dynamicFuelCost ?? 0, 9_999)
        XCTAssertGreaterThan(updated.dynamicFuelCost ?? 0, 0)
    }

    /// Version 3 was already written on devices that ran the first C₀ model. A later idle
    /// fix must still walk every completed trip, including those past the first 25-row batch.
    func testFuelVersionBumpRewritesEveryCompletedTripAcrossBatches() async throws {
        let container = try makeDiskContainer()
        let context = container.mainContext
        let start = Date().addingTimeInterval(-86_400)
        for index in 0..<30 {
            seedLegacyTrip(
                in: context,
                startedAt: start.addingTimeInterval(Double(index) * 60),
                pointCount: 4
            )
        }
        for trip in try context.fetch(FetchDescriptor<Trip>()) {
            trip.estimatedFuelCost = 100
            trip.fuelConsumptionPer100 = 7.5
            trip.fuelUnitPrice = 65
            trip.dynamicFuelCost = 9_999
            trip.nightDistanceMeters = 0
            trip.trackedDistanceMeters = trip.distanceMeters
            trip.stopDurationSeconds = 0
        }
        try context.save()

        // Isolated keys so a parallel test cannot mark the process-wide fuel version current
        // and skip this walk.
        let isolatedFuelKey = "milehound.test.dynamicFuelVersion.\(UUID().uuidString)"
        let isolatedSpeedKey = "milehound.test.speedProfileVersion.\(UUID().uuidString)"
        UserDefaults.standard.set(3, forKey: isolatedFuelKey)
        defer {
            UserDefaults.standard.removeObject(forKey: isolatedFuelKey)
            UserDefaults.standard.removeObject(forKey: isolatedSpeedKey)
        }

        let backfiller = TripDerivedBackfiller(modelContainer: container)
        let finished = await backfiller.refreshDerivedKinematicsIfNeeded(
            speedProfileVersionKey: isolatedSpeedKey,
            speedProfileVersion: 0,
            dynamicFuelVersionKey: isolatedFuelKey,
            dynamicFuelVersion: 4
        )
        XCTAssertTrue(finished)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: isolatedFuelKey), 4)

        let updated = try ModelContext(container).fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(updated.count, 30)
        for trip in updated {
            XCTAssertNotEqual(trip.dynamicFuelCost ?? 0, 9_999, "trip \(trip.id)")
            XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, 0)
        }
    }

    /// Opening trip detail must rewrite Est. fuel even when launch backfill thinks it is done.
    func testRefreshPersistedFuelRewritesStaleCostWhenLaunchVersionIsCurrent() throws {
        let container = try makeDiskContainer()
        let tripID = seedLegacyTrip(
            in: container.mainContext,
            startedAt: Date().addingTimeInterval(-3_600)
        )
        let trip = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<Trip>()).first { $0.id == tripID }
        )
        trip.fuelConsumptionPer100 = 7.5
        trip.fuelUnitPrice = 65
        trip.dynamicFuelCost = 9_999
        try container.mainContext.save()

        XCTAssertTrue(TripDerivedMetrics.refreshPersistedFuel(for: trip, in: container.mainContext))
        XCTAssertNotEqual(trip.dynamicFuelCost ?? 0, 9_999)
        XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, 0)
    }
}

@MainActor
final class TripDerivedMetricsTests: XCTestCase {
    private func makeTrip(startedAt: Date, coordinates: [(Double, Double)]) -> Trip {
        let trip = Trip(startedAt: startedAt, endedAt: startedAt.addingTimeInterval(3_600))
        for (index, coordinate) in coordinates.enumerated() {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 60),
                latitude: coordinate.0,
                longitude: coordinate.1,
                sequence: index,
                trip: trip
            )
            trip.points.append(point)
        }
        return trip
    }

    /// The pre-optimisation implementation, kept here as the reference the fast loop must match.
    private func legacyNightRatio(for trips: [Trip]) -> Double {
        var nightMeters = 0.0
        var totalMeters = 0.0
        let calendar = Calendar.current

        for trip in trips {
            let points = trip.sortedPoints
            guard points.count >= 2 else { continue }
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let segment = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
                guard segment > 0 else { continue }
                let midpoint = previous.timestamp.addingTimeInterval(
                    current.timestamp.timeIntervalSince(previous.timestamp) / 2
                )
                totalMeters += segment
                let hour = calendar.component(.hour, from: midpoint)
                if hour >= 22 || hour < 6 {
                    nightMeters += segment
                }
            }
        }

        guard totalMeters > 0 else { return 0 }
        return nightMeters / totalMeters
    }

    func testFastNightRatioMatchesLegacyImplementation() throws {
        let calendar = Calendar.current
        let nightStart = try XCTUnwrap(
            calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date().addingTimeInterval(-86_400))
        )
        let dayStart = try XCTUnwrap(
            calendar.date(bySettingHour: 13, minute: 0, second: 0, of: Date().addingTimeInterval(-86_400))
        )

        let coordinates: [(Double, Double)] = (0..<40).map { index in
            let offset = Double(index)
            return (41.0 + offset * 0.002, 29.0 + offset * 0.0015)
        }
        let nightTrip = makeTrip(startedAt: nightStart, coordinates: coordinates)
        let dayTrip = makeTrip(startedAt: dayStart, coordinates: coordinates)

        let expected = legacyNightRatio(for: [nightTrip, dayTrip])
        let actual = StatsViewModel.nightDrivingRatio(for: [nightTrip, dayTrip])

        XCTAssertEqual(actual, expected, accuracy: 0.01)
    }

    func testApproximateDistanceTracksGeodesicForShortSegments() {
        let distance = StatsViewModel.approximateDistanceMeters(
            fromLatitude: 41.0,
            fromLongitude: 29.0,
            toLatitude: 41.0005,
            toLongitude: 29.0005
        )
        let geodesic = CLLocation(latitude: 41.0, longitude: 29.0)
            .distance(from: CLLocation(latitude: 41.0005, longitude: 29.0005))

        XCTAssertEqual(distance, geodesic, accuracy: geodesic * 0.01)
    }

    func testNightRatioPrefersStoredValuesOverWalkingPoints() {
        let trip = makeTrip(startedAt: Date(), coordinates: [(41.0, 29.0), (41.01, 29.01)])
        trip.nightDistanceMeters = 300
        trip.trackedDistanceMeters = 1_000

        XCTAssertEqual(StatsViewModel.nightDrivingRatio(for: [trip]), 0.3, accuracy: 0.0001)
    }

    func testRecomputeWritesEndpointsAndNightDistance() throws {
        let calendar = Calendar.current
        let nightStart = try XCTUnwrap(
            calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Date().addingTimeInterval(-86_400))
        )
        let trip = makeTrip(
            startedAt: nightStart,
            coordinates: [(41.0, 29.0), (41.005, 29.005), (41.01, 29.01)]
        )

        TripDerivedMetrics.recompute(for: trip)

        XCTAssertEqual(try XCTUnwrap(trip.startLatitude), 41.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.startLongitude), 29.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.endLatitude), 41.01, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.endLongitude), 29.01, accuracy: 0.0001)
        let tracked: Double = try XCTUnwrap(trip.trackedDistanceMeters)
        let night: Double = try XCTUnwrap(trip.nightDistanceMeters)
        XCTAssertEqual(tracked, 1_400, accuracy: 200)
        XCTAssertEqual(night, tracked, accuracy: 0.1, "a trip driven entirely after 22:00 is fully night driving")
        XCTAssertNotNil(trip.stopDurationSeconds)
        XCTAssertNotNil(trip.cruiseSpeedKmh)
        XCTAssertNotNil(trip.cruiseDurationSeconds)
        XCTAssertNotNil(trip.mostCommonSpeedKmh)
        XCTAssertNotNil(trip.dynamicFuelCost)
    }

    func testRecomputeFuelDoesNotRewriteAvgCost() {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        trip.distanceMeters = 5_000
        trip.fuelConsumptionPer100 = 7.5
        trip.fuelUnitPrice = 65
        trip.estimatedFuelCost = 243.75

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .petrol)

        XCTAssertEqual(trip.estimatedFuelCost ?? 0, 243.75, accuracy: 0.01)
        XCTAssertNotNil(trip.dynamicFuelCost)
        XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, 0)
    }

    /// The screenshot trip had a Stop pin on a 5:50 queue. That pin must not zero idle.
    func testRecomputeFuelKeepsCityQueueIdleWhenParkingPinExists() {
        let startedAt = Date().addingTimeInterval(-3_600)
        let movingSeconds = 375.0
        let stopSeconds = 350.0
        let distance = 3_300.0
        let speedMps = distance / movingSeconds
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(movingSeconds + stopSeconds)
        )
        trip.distanceMeters = distance
        trip.fuelConsumptionPer100 = 7
        trip.fuelUnitPrice = 65
        trip.estimatedFuelCost = distance / 1_000 * 7 / 100 * 65

        func appendPoint(sequence: Int, offsetSeconds: TimeInterval, metersEast: Double) {
            let metersPerDegree = 111_320.0 * cos(41.0 * .pi / 180)
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(offsetSeconds),
                latitude: 41.0,
                longitude: 29.0 + metersEast / metersPerDegree,
                sequence: sequence,
                speedMps: speedMps,
                trip: trip
            )
            trip.points.append(point)
        }
        appendPoint(sequence: 0, offsetSeconds: 0, metersEast: 0)
        appendPoint(sequence: 1, offsetSeconds: 188, metersEast: speedMps * 188)
        appendPoint(sequence: 2, offsetSeconds: 188 + stopSeconds, metersEast: speedMps * 188)
        appendPoint(
            sequence: 3,
            offsetSeconds: movingSeconds + stopSeconds,
            metersEast: distance
        )

        let pin = TripStop(
            latitude: 41.0,
            longitude: 29.0,
            startedAt: startedAt.addingTimeInterval(188),
            durationSeconds: stopSeconds,
            trip: trip
        )
        trip.stops.append(pin)

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .petrol)

        XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, trip.estimatedFuelCost ?? 0)
    }

    /// Stored avg cost is the display source of truth — Settings / vehicle averages must not
    /// replace it when recompute runs again under a different fuel type.
    func testStoredAvgFuelSurvivesRecomputeAndStatsFuelCost() {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        trip.distanceMeters = 5_000
        trip.fuelConsumptionPer100 = 7.5
        trip.fuelUnitPrice = 65
        trip.estimatedFuelCost = 243.75

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .petrol)
        let firstDynamic = trip.dynamicFuelCost ?? 0
        XCTAssertGreaterThan(firstDynamic, 0)

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .diesel)
        XCTAssertEqual(trip.estimatedFuelCost ?? 0, 243.75, accuracy: 0.01)
        XCTAssertEqual(StatsViewModel.fuelCost(for: trip), 243.75, accuracy: 0.01)
        XCTAssertNotNil(trip.dynamicFuelCost)
        XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, 0)
    }

    func testRecomputeFuelUsesVehicleWhenTripSnapshotMissing() {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        trip.distanceMeters = 10_000
        trip.fuelConsumptionPer100 = nil
        trip.fuelUnitPrice = nil
        let vehicle = VehicleProfile(
            name: "Car",
            fuelType: .petrol,
            consumption: 6
        )

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .diesel, vehicle: vehicle)

        XCTAssertEqual(trip.fuelTypeSnapshot, .petrol)
        let petrol = TripFuelEstimate.compute(
            points: trip.sortedPoints,
            distanceMeters: trip.distanceMeters,
            consumptionPer100: 6,
            unitPrice: FuelCostCalculator.resolvedUnitPrice(vehicle: vehicle, fuelType: .petrol),
            fuelType: .petrol,
            durationSeconds: trip.duration,
            thermal: TripDerivedMetrics.thermalInput(for: trip)
        )
        let diesel = TripFuelEstimate.compute(
            points: trip.sortedPoints,
            distanceMeters: trip.distanceMeters,
            consumptionPer100: 6,
            unitPrice: FuelCostCalculator.resolvedUnitPrice(vehicle: vehicle, fuelType: .diesel),
            fuelType: .diesel,
            durationSeconds: trip.duration,
            thermal: TripDerivedMetrics.thermalInput(for: trip)
        )
        XCTAssertEqual(trip.dynamicFuelCost ?? 0, petrol.dynamicCost, accuracy: 0.01)
        XCTAssertNotEqual(petrol.dynamicCost, diesel.dynamicCost, accuracy: 0.01)
    }

    func testRecomputeFuelElectricUsesChargePriceNotPetrolLiter() {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        trip.distanceMeters = 10_000
        trip.fuelConsumptionPer100 = nil
        trip.fuelUnitPrice = nil
        let vehicle = VehicleProfile(
            name: "EV",
            fuelType: .electric,
            consumption: 18,
            chargePricePerKWh: 8.5
        )

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .petrol, vehicle: vehicle)

        let cost = trip.dynamicFuelCost ?? 0
        XCTAssertGreaterThan(cost, 0)
        let impliedKWh = cost / 8.5
        XCTAssertLessThan(impliedKWh, 10)
        let petrolLiterMistake = cost / 65
        XCTAssertGreaterThan(impliedKWh, petrolLiterMistake * 3)
    }

    func testRecomputeFuelLpgUsesLpgLiterPriceAndKeepsStoredAvg() {
        let defaults = UserDefaults(suiteName: "group.com.milehound.app") ?? .standard
        defaults.set(65, forKey: "fuelPricePerLiter")
        defaults.set(28, forKey: "lpgPricePerLiter")
        defer { defaults.removeObject(forKey: "lpgPricePerLiter") }

        let open = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        open.distanceMeters = 10_000
        open.fuelConsumptionPer100 = 10
        open.fuelUnitPrice = nil
        let vehicle = VehicleProfile(name: "LPG", fuelType: .lpg, consumption: 10)

        TripDerivedMetrics.recomputeFuel(for: open, fuelType: .petrol, vehicle: vehicle)

        XCTAssertEqual(open.fuelTypeSnapshot, .lpg)
        XCTAssertEqual(open.fuelUnitKey, "liquid")
        let expected = TripFuelEstimate.compute(
            points: open.sortedPoints,
            distanceMeters: open.distanceMeters,
            consumptionPer100: 10,
            unitPrice: 28,
            fuelType: .lpg,
            durationSeconds: open.duration,
            thermal: TripDerivedMetrics.thermalInput(for: open)
        )
        XCTAssertEqual(open.dynamicFuelCost ?? 0, expected.dynamicCost, accuracy: 0.01)
        let petrolPrice = TripFuelEstimate.compute(
            points: open.sortedPoints,
            distanceMeters: open.distanceMeters,
            consumptionPer100: 10,
            unitPrice: 65,
            fuelType: .petrol,
            durationSeconds: open.duration,
            thermal: TripDerivedMetrics.thermalInput(for: open)
        )
        XCTAssertNotEqual(open.dynamicFuelCost ?? 0, petrolPrice.dynamicCost, accuracy: 0.01)

        let stored = makeTrip(
            startedAt: Date().addingTimeInterval(-7_200),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        stored.distanceMeters = 10_000
        stored.fuelConsumptionPer100 = 10
        stored.fuelUnitPrice = 40
        stored.estimatedFuelCost = 40

        TripDerivedMetrics.recomputeFuel(for: stored, fuelType: .petrol, vehicle: vehicle)

        XCTAssertEqual(stored.estimatedFuelCost ?? 0, 40, accuracy: 0.01)
        let priced = TripFuelEstimate.compute(
            points: stored.sortedPoints,
            distanceMeters: stored.distanceMeters,
            consumptionPer100: 10,
            unitPrice: 40,
            fuelType: .lpg,
            durationSeconds: stored.duration,
            thermal: TripDerivedMetrics.thermalInput(for: stored)
        )
        XCTAssertEqual(stored.dynamicFuelCost ?? 0, priced.dynamicCost, accuracy: 0.01)
    }

    func testRecomputeClearsStoredCoordinatesWhenPointsAreEmpty() {
        let trip = Trip(startedAt: Date(), endedAt: Date())
        trip.startLatitude = 1
        trip.endLatitude = 2

        TripDerivedMetrics.recompute(for: trip)

        XCTAssertNil(trip.startLatitude)
        XCTAssertNil(trip.endLatitude)
        XCTAssertEqual(trip.trackedDistanceMeters, 0)
        XCTAssertEqual(trip.stopDurationSeconds, 0)
        XCTAssertEqual(trip.cruiseSpeedKmh, 0)
        XCTAssertEqual(trip.mostCommonSpeedKmh, 0)
    }

    func testStoredCoordinatesAvoidPointLookup() {
        let trip = Trip(startedAt: Date(), endedAt: Date())
        trip.startLatitude = 40.5
        trip.startLongitude = 28.5
        trip.endLatitude = 41.5
        trip.endLongitude = 29.5

        XCTAssertEqual(trip.startCoordinate?.latitude ?? 0, 40.5, accuracy: 0.0001)
        XCTAssertEqual(trip.endCoordinate?.longitude ?? 0, 29.5, accuracy: 0.0001)
    }

    func testSearchIndexMatchesLegacyFieldScan() {
        let trip = Trip(
            startedAt: Date(),
            endedAt: Date(),
            note: "Havalimanı transferi",
            label: "İş",
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )

        TripDerivedMetrics.refreshSearchIndex(for: trip, places: [], privacyRadius: 500)

        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "ofis"))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "havalimanı"))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "ev"))
        XCTAssertFalse(TripListViewModel.matchesSearch(trip, searchText: "bakkal"))
        XCTAssertTrue(SearchFolding.fold(try XCTUnwrap(trip.searchIndex)).contains(SearchFolding.fold("Ev")))
    }
}
