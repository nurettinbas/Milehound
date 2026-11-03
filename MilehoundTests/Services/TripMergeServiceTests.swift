import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class TripMergeServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var storeDirectory: URL?

    override func setUpWithError() throws {
        container = try ModelContainerFactory.makeInMemory()
    }

    override func tearDownWithError() throws {
        if let storeDirectory {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        storeDirectory = nil
        container = nil
        try super.tearDownWithError()
    }

    func testMergeThrowsForSingleTrip() throws {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1000
        )
        container.mainContext.insert(trip)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try TripMergeService.merge(trips: [trip], into: container.mainContext)
        ) { error in
            XCTAssertEqual(error as? TripMergeError, .needsTwoCompletedTrips)
        }
    }

    func testMergeThrowsWhenOneLegIsUnfinished() throws {
        let completed = makeTrip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 3000
        )
        let open = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: nil,
            distanceMeters: 500
        )
        container.mainContext.insert(completed)
        container.mainContext.insert(open)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try TripMergeService.merge(trips: [completed, open], into: container.mainContext)
        ) { error in
            XCTAssertEqual(error as? TripMergeError, .needsTwoCompletedTrips)
        }
    }

    func testMergeCombinesDistanceDurationAndNotes() throws {
        let first = makeTrip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-5400),
            distanceMeters: 3000,
            note: "First leg",
            label: "Morning"
        )
        let second = makeTrip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 4500,
            note: "Second leg",
            label: "Evening"
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let expectedPointCount = first.points.count + second.points.count
        let firstStarted = first.startedAt
        let secondEnded = second.endedAt
        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertEqual(merged.distanceMeters, 7500, accuracy: 0.1)
        XCTAssertEqual(merged.startedAt, firstStarted)
        XCTAssertEqual(merged.endedAt, secondEnded)
        XCTAssertEqual(merged.points.count, expectedPointCount)
        XCTAssertTrue(merged.note?.contains("First leg") == true)
        XCTAssertTrue(merged.note?.contains("Second leg") == true)
        XCTAssertNil(merged.label, "product no longer copies labels on merge")
    }

    func testMergeRecomputesDynamicFuelFromSnapshots() throws {
        let first = makeTrip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-5400),
            distanceMeters: 3_000
        )
        first.fuelConsumptionPer100 = 7.5
        first.fuelUnitPrice = 65
        let second = makeTrip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 4_500
        )
        second.fuelConsumptionPer100 = 7.5
        second.fuelUnitPrice = 65
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertEqual(merged.distanceMeters, 7_500, accuracy: 0.1)
        XCTAssertEqual(merged.fuelConsumptionPer100 ?? 0, 7.5, accuracy: 0.01)
        XCTAssertEqual(merged.fuelUnitPrice ?? 0, 65, accuracy: 0.01)
        XCTAssertNotNil(merged.estimatedFuelCost)
        XCTAssertGreaterThan(merged.estimatedFuelCost ?? 0, 0)
        XCTAssertNotNil(merged.dynamicFuelCost)
        XCTAssertGreaterThan(merged.dynamicFuelCost ?? 0, 0)
    }

    func testMergeMarksTheGapBetweenLegsAsAStop() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let firstEnd = try XCTUnwrap(first.sortedPoints.last)
        let endLat = firstEnd.latitude
        let endLon = firstEnd.longitude
        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertEqual(merged.stops.count, 1)
        let junction = try XCTUnwrap(merged.stops.first)
        XCTAssertEqual(junction.startedAt, base.addingTimeInterval(1800))
        XCTAssertEqual(junction.durationSeconds, 1800, accuracy: 0.1)
        XCTAssertEqual(junction.latitude, endLat, accuracy: 0.000_001)
        XCTAssertEqual(junction.longitude, endLon, accuracy: 0.000_001)
    }

    func testMergeSkipsJunctionStopForBackToBackLegs() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(1805),
            endedAt: base.addingTimeInterval(3600),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertTrue(merged.stops.isEmpty)
    }

    /// A leg that was already standing still when it stopped recording must not end up with a
    /// second marker on top of the first.
    func testMergeExtendsAnExistingStopInsteadOfStackingMarkers() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let lastPoint = try XCTUnwrap(first.sortedPoints.last)
        let existing = TripStop(
            latitude: lastPoint.latitude,
            longitude: lastPoint.longitude,
            startedAt: base.addingTimeInterval(1500),
            durationSeconds: 300,
            trip: first
        )
        first.stops = [existing]

        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertEqual(merged.stops.count, 1)
        let stop = try XCTUnwrap(merged.stops.first)
        XCTAssertEqual(stop.startedAt, base.addingTimeInterval(1500))
        // 1500 s through to the moment the second leg starts at 3600 s.
        XCTAssertEqual(stop.durationSeconds, 2100, accuracy: 0.1)
    }

    /// A stop somewhere else on the route is a different standstill and must be left alone.
    func testMergeKeepsUnrelatedStopSeparateFromJunction() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let midRouteStop = TripStop(
            latitude: 40.5,
            longitude: 28.5,
            startedAt: base.addingTimeInterval(300),
            durationSeconds: 240,
            trip: first
        )
        first.stops = [midRouteStop]

        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertEqual(merged.stops.count, 2)
        XCTAssertEqual(merged.stops.filter { $0.durationSeconds == 240 }.count, 1)
        XCTAssertEqual(merged.stops.filter { $0.durationSeconds == 1800 }.count, 1)
    }

    func testMergeAddsAJunctionForEveryGapAcrossThreeLegs() throws {
        let base = Date().addingTimeInterval(-14_400)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        let third = makeTrip(
            startedAt: base.addingTimeInterval(7200),
            endedAt: base.addingTimeInterval(9000),
            distanceMeters: 1500
        )
        for trip in [first, second, third] {
            container.mainContext.insert(trip)
        }
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [third, first, second], into: container.mainContext)

        XCTAssertEqual(merged.stops.count, 2)
        XCTAssertEqual(merged.stops.filter { $0.durationSeconds == 1800 }.count, 2)
    }

    /// The legs are deleted by the merge, so a vehicle dropped here is gone for good.
    func testMergeKeepsTheVehicleAssignment() throws {
        let base = Date().addingTimeInterval(-7200)
        let vehicleID = UUID()
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        first.vehicleID = vehicleID
        let second = makeTrip(
            startedAt: base.addingTimeInterval(1800),
            endedAt: base.addingTimeInterval(3600),
            distanceMeters: 4500
        )
        second.vehicleID = vehicleID
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        XCTAssertEqual(merged.vehicleID, vehicleID)
    }

    func testMergePreservesDailyRollupTotals() throws {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let base = dayStart.addingTimeInterval(10 * 3600)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        first.nightDistanceMeters = 0
        first.trackedDistanceMeters = 3000
        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        second.nightDistanceMeters = 0
        second.trackedDistanceMeters = 4500

        container.mainContext.insert(first)
        container.mainContext.insert(second)
        TripRollupService.add(first, in: container.mainContext)
        TripRollupService.add(second, in: container.mainContext)
        try container.mainContext.save()

        let dayInterval = DateInterval(start: dayStart, duration: 24 * 3600)
        let before = TripRollupService.stats(
            in: dayInterval,
            categoryID: nil,
            vehicleID: nil,
            in: container.mainContext
        )
        XCTAssertEqual(before.tripCount, 2)
        XCTAssertEqual(before.totalDistanceMeters, 7500, accuracy: 0.1)

        _ = try TripMergeService.merge(trips: [first, second], into: container.mainContext)

        let after = TripRollupService.stats(
            in: dayInterval,
            categoryID: nil,
            vehicleID: nil,
            in: container.mainContext
        )
        XCTAssertEqual(after.tripCount, 1)
        XCTAssertEqual(after.totalDistanceMeters, 7500, accuracy: 0.1)
    }

    func testMergeOnDiskContainerPersistsCombinedTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MilehoundMergeDisk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeDirectory = directory
        let storeURL = directory.appendingPathComponent("Milehound.store")

        let diskContainer = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV11.self),
            configurations: ModelConfiguration(url: storeURL)
        )
        let context = diskContainer.mainContext
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let merged = try TripMergeService.merge(trips: [first, second], into: context)
        let mergedID = merged.id

        // Re-open the store to prove the merge survived a process-boundary-like reload.
        let reopened = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV11.self),
            configurations: ModelConfiguration(url: storeURL)
        )
        var descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == mergedID })
        descriptor.fetchLimit = 1
        let reloaded = try XCTUnwrap(try reopened.mainContext.fetch(descriptor).first)
        XCTAssertEqual(reloaded.distanceMeters, 7500, accuracy: 0.1)
        XCTAssertEqual(reloaded.points.count, 4)

        let remaining = try reopened.mainContext.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.endedAt != nil })
        )
        XCTAssertEqual(remaining.count, 1)
    }

    func testMergePerformanceWithDenseLegs() throws {
        // Keep this light enough for CI: the regression we care about is O(n) insert cost,
        // not a multi-minute soak of 20k-point legs under `measure`'s repeated iterations.
        let base = Date().addingTimeInterval(-4_000)
        measure {
            do {
                let fresh = try ModelContainerFactory.makeInMemory()
                let a = makeDenseTrip(startedAt: base, pointCount: 2_000, distanceMeters: 10_000)
                let b = makeDenseTrip(
                    startedAt: base.addingTimeInterval(2_500),
                    pointCount: 2_000,
                    distanceMeters: 10_000
                )
                fresh.mainContext.insert(a)
                fresh.mainContext.insert(b)
                try fresh.mainContext.save()
                let merged = try TripMergeService.merge(trips: [a, b], into: fresh.mainContext)
                XCTAssertEqual(merged.points.count, 4_000)
            } catch {
                XCTFail("merge failed: \(error)")
            }
        }
    }

    private func makeDenseTrip(startedAt: Date, pointCount: Int, distanceMeters: Double) -> Trip {
        let endedAt = startedAt.addingTimeInterval(Double(pointCount))
        let trip = Trip(
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            category: .personal
        )
        var points: [TripPoint] = []
        points.reserveCapacity(pointCount)
        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index)),
                latitude: 41.0 + Double(index) * 0.000_01,
                longitude: 29.0 + Double(index) * 0.000_01,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            points.append(point)
        }
        trip.points = points
        return trip
    }

    private func makeTrip(
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        note: String? = nil,
        label: String? = nil
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            note: note,
            label: label,
            category: .personal
        )
        let start = TripPoint(
            timestamp: startedAt,
            latitude: 41.0,
            longitude: 29.0,
            sequence: 0,
            trip: trip
        )
        let end = TripPoint(
            timestamp: endedAt,
            latitude: 41.01,
            longitude: 29.01,
            sequence: 1,
            trip: trip
        )
        trip.points = [start, end]
        return trip
    }
}
