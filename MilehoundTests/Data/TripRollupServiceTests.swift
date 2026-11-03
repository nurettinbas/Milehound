import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class TripRollupServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Schema(versionedSchema: MilehoundSchemaV18.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private var context: ModelContext { container.mainContext }

    @discardableResult
    private func insertTrip(
        startedAt: Date,
        distanceMeters: Double = 10_000,
        durationSeconds: TimeInterval = 1_800,
        category: TripCategory = .personal,
        nightMeters: Double = 2_000,
        trackedMeters: Double = 10_000,
        maxSpeedMps: Double = 30,
        cruiseSpeedKmh: Double = 0,
        cruiseDurationSeconds: Double = 0,
        stopDurationSeconds: Double = 0,
        mostCommonSpeedKmh: Double = 0,
        dynamicFuelCost: Double = 0
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(durationSeconds),
            distanceMeters: distanceMeters,
            category: category,
            maxSpeedMps: maxSpeedMps
        )
        trip.nightDistanceMeters = nightMeters
        trip.trackedDistanceMeters = trackedMeters
        trip.estimatedFuelCost = 50
        trip.dynamicFuelCost = dynamicFuelCost
        trip.cruiseSpeedKmh = cruiseSpeedKmh
        trip.cruiseDurationSeconds = cruiseDurationSeconds
        trip.stopDurationSeconds = stopDurationSeconds
        trip.mostCommonSpeedKmh = mostCommonSpeedKmh
        context.insert(trip)
        return trip
    }

    private func rollups() throws -> [TripDailyRollup] {
        try context.fetch(FetchDescriptor<TripDailyRollup>())
    }

    func testAddAccumulatesTripsIntoOneDailyBucket() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let first = insertTrip(startedAt: day)
        let second = insertTrip(startedAt: day.addingTimeInterval(4 * 3_600), distanceMeters: 5_000)

        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        let all = try rollups()
        XCTAssertEqual(all.count, 1, "same day, category and vehicle share one bucket")
        let rollup = try XCTUnwrap(all.first)
        XCTAssertEqual(rollup.tripCount, 2)
        XCTAssertEqual(rollup.distanceMeters, 15_000, accuracy: 0.1)
        XCTAssertEqual(rollup.nightDistanceMeters, 4_000, accuracy: 0.1)
    }

    func testSeparateBucketsPerCategory() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        TripRollupService.add(insertTrip(startedAt: day, category: .personal), in: context)
        TripRollupService.add(insertTrip(startedAt: day, category: .business), in: context)
        try context.save()

        XCTAssertEqual(try rollups().count, 2)
    }

    func testRemoveSubtractsAndDropsEmptyBucket() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let first = insertTrip(startedAt: day)
        let second = insertTrip(startedAt: day, distanceMeters: 5_000)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        TripRollupService.remove(second, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.tripCount, 1)
        XCTAssertEqual(rollup.distanceMeters, 10_000, accuracy: 0.1)

        TripRollupService.remove(first, in: context)
        try context.save()

        XCTAssertTrue(try rollups().isEmpty, "a day with no trips left keeps no row")
    }

    func testUpdateMovesContributionToNewDay() throws {
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let trip = insertTrip(startedAt: today)
        TripRollupService.add(trip, in: context)
        try context.save()

        let snapshot = TripRollupService.snapshot(of: trip)
        trip.startedAt = today.addingTimeInterval(-3 * 86_400)
        trip.endedAt = trip.startedAt.addingTimeInterval(1_800)
        TripRollupService.update(trip, from: snapshot, in: context)
        try context.save()

        let all = try rollups()
        XCTAssertEqual(all.count, 1, "the old day's bucket is emptied and removed")
        let expectedDay = Calendar.current.startOfDay(for: trip.startedAt)
        XCTAssertEqual(try XCTUnwrap(all.first).dayStart, expectedDay)
    }

    func testUpdateAdjustsAmountsWithinSameDay() throws {
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let trip = insertTrip(startedAt: today, distanceMeters: 10_000)
        TripRollupService.add(trip, in: context)
        try context.save()

        let snapshot = TripRollupService.snapshot(of: trip)
        trip.distanceMeters = 25_000
        TripRollupService.update(trip, from: snapshot, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.tripCount, 1, "an edit must not double-count the trip")
        XCTAssertEqual(rollup.distanceMeters, 25_000, accuracy: 0.1)
    }

    func testInProgressTripIsNotRolledUp() throws {
        let active = Trip(startedAt: Date(), endedAt: nil, distanceMeters: 1_000)
        context.insert(active)
        TripRollupService.add(active, in: context)
        try context.save()

        XCTAssertTrue(try rollups().isEmpty)
    }

    func testRebuildAllMatchesIncrementalDeltas() async throws {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        for index in 0..<12 {
            let trip = insertTrip(
                startedAt: base.addingTimeInterval(-Double(index) * 86_400),
                distanceMeters: Double(1_000 * (index + 1)),
                category: index.isMultiple(of: 2) ? .personal : .business
            )
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let incremental = try rollups()
            .map { [$0.dayStart, $0.categoryID, $0.distanceMeters, Double($0.tripCount)] as [AnyHashable] }
            .sorted { String(describing: $0) < String(describing: $1) }

        await TripRollupService.rebuildAll(container: container)

        let rebuilt = try context.fetch(FetchDescriptor<TripDailyRollup>())
            .map { [$0.dayStart, $0.categoryID, $0.distanceMeters, Double($0.tripCount)] as [AnyHashable] }
            .sorted { String(describing: $0) < String(describing: $1) }

        XCTAssertEqual(rebuilt.count, incremental.count)
        XCTAssertEqual(String(describing: rebuilt), String(describing: incremental))
    }

    func testRollupBackedRowsAggregateLikeTrips() throws {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        var trips: [Trip] = []
        for index in 0..<6 {
            let trip = insertTrip(
                startedAt: base.addingTimeInterval(-Double(index) * 86_400),
                distanceMeters: 8_000
            )
            trips.append(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let fromTrips = StatsViewModel.stats(for: trips.map(TripStatsRow.init(trip:)))
        let fromRollups = StatsViewModel.stats(for: try rollups().map(TripStatsRow.init(rollup:)))

        XCTAssertEqual(fromRollups.tripCount, fromTrips.tripCount)
        XCTAssertEqual(fromRollups.totalDistanceMeters, fromTrips.totalDistanceMeters, accuracy: 0.1)
        XCTAssertEqual(fromRollups.totalDuration, fromTrips.totalDuration, accuracy: 0.1)
        XCTAssertEqual(fromRollups.nightDrivingRatio, fromTrips.nightDrivingRatio, accuracy: 0.0001)
        XCTAssertEqual(fromRollups.maxSpeedKmh, fromTrips.maxSpeedKmh, accuracy: 0.1)
    }

    /// Windows past the stats tab's 92-day rollup threshold must still produce the same totals
    /// whether they are answered from trips or from daily rollups.
    func testLongWindowRollupPathMatchesTripPath() throws {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -100, to: end) ?? end
        let interval = DateInterval(start: start, end: end)

        var trips: [Trip] = []
        for index in 0..<20 {
            let trip = insertTrip(
                startedAt: end.addingTimeInterval(-Double(index) * 5 * 86_400),
                distanceMeters: Double(1_000 * (index + 1)),
                durationSeconds: 2_000,
                nightMeters: 200,
                trackedMeters: Double(1_000 * (index + 1)),
                dynamicFuelCost: Double(10 * (index + 1))
            )
            trips.append(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let periodTrips = StatsViewModel.trips(in: interval, from: trips.map(TripStatsRow.init(trip:)))
        let fromTrips = StatsViewModel.stats(for: periodTrips)

        let lowerBound = calendar.startOfDay(for: interval.start)
        let upperBound = interval.end
        let rollupsInWindow = try context.fetch(
            FetchDescriptor<TripDailyRollup>(
                predicate: #Predicate { $0.dayStart >= lowerBound && $0.dayStart <= upperBound }
            )
        )
        let fromRollups = StatsViewModel.stats(for: rollupsInWindow.map(TripStatsRow.init(rollup:)))

        XCTAssertGreaterThan(interval.duration, 92 * 86_400)
        XCTAssertEqual(fromRollups.tripCount, fromTrips.tripCount)
        XCTAssertEqual(fromRollups.totalDistanceMeters, fromTrips.totalDistanceMeters, accuracy: 0.1)
        XCTAssertEqual(fromRollups.totalDuration, fromTrips.totalDuration, accuracy: 0.1)
        XCTAssertEqual(fromRollups.estimatedFuelCost, fromTrips.estimatedFuelCost, accuracy: 0.1)
        XCTAssertEqual(fromRollups.dynamicFuelCost, fromTrips.dynamicFuelCost, accuracy: 0.1)
        XCTAssertEqual(fromRollups.nightDrivingRatio, fromTrips.nightDrivingRatio, accuracy: 0.0001)
    }

    /// A rollup keeps the highest value it ever saw and never lowers it, so one phantom maximum
    /// would poison a whole day's statistics permanently. The contribution must refuse it.
    func testRollupIgnoresAnImplausibleStoredMaximum() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let phantom = insertTrip(startedAt: day, maxSpeedMps: 56.4)
        let real = insertTrip(startedAt: day.addingTimeInterval(3_600), maxSpeedMps: 22.22)

        TripRollupService.add(phantom, in: context)
        TripRollupService.add(real, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.maxSpeedMps, 22.22, accuracy: 0.001)
    }

    func testRollupAccumulatesCruiseWeightAndStopDuration() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let city = insertTrip(
            startedAt: day,
            cruiseSpeedKmh: 30,
            cruiseDurationSeconds: 300,
            stopDurationSeconds: 120,
            mostCommonSpeedKmh: 25
        )
        let highway = insertTrip(
            startedAt: day.addingTimeInterval(3_600),
            cruiseSpeedKmh: 110,
            cruiseDurationSeconds: 7_200,
            stopDurationSeconds: 60,
            mostCommonSpeedKmh: 100
        )

        TripRollupService.add(city, in: context)
        TripRollupService.add(highway, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.stopDurationSeconds, 180, accuracy: 0.1)
        XCTAssertEqual(rollup.cruiseWeightSeconds, 7_500, accuracy: 0.1)
        XCTAssertEqual(rollup.cruiseSpeedProduct, 30 * 300 + 110 * 7_200, accuracy: 0.1)
        XCTAssertEqual(rollup.mostCommonWeightSeconds, 7_500, accuracy: 0.1)
        XCTAssertEqual(rollup.mostCommonSpeedProduct, 25 * 300 + 100 * 7_200, accuracy: 0.1)

        let row = TripStatsRow(rollup: rollup)
        XCTAssertEqual(row.resolvedCruiseSpeedKmh, 106.8, accuracy: 0.2)
        XCTAssertEqual(row.resolvedMostCommonSpeedKmh, 97.0, accuracy: 0.2)
    }

    func testRollupAccumulatesDynamicFuelCost() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let first = insertTrip(startedAt: day, dynamicFuelCost: 80)
        let second = insertTrip(startedAt: day.addingTimeInterval(3_600), dynamicFuelCost: 95)

        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.dynamicFuelCost, 175, accuracy: 0.1)
    }

    func testRebuildIfNeededSkipsWhenFuelRefreshIncomplete() async {
        let rollupKey = "milehound.rollup.rebuiltVersion"
        let fuelKey = TripDerivedBackfillService.dynamicFuelVersionKey
        let previousRollup = UserDefaults.standard.integer(forKey: rollupKey)
        let previousFuel = UserDefaults.standard.integer(forKey: fuelKey)
        UserDefaults.standard.set(10, forKey: rollupKey)
        UserDefaults.standard.set(0, forKey: fuelKey)
        defer {
            UserDefaults.standard.set(previousRollup, forKey: rollupKey)
            UserDefaults.standard.set(previousFuel, forKey: fuelKey)
        }

        await TripRollupService.rebuildIfNeeded(container: container)

        XCTAssertEqual(UserDefaults.standard.integer(forKey: rollupKey), 10)
        XCTAssertEqual(try rollups().count, 0)
    }

    func testRebuildIfNeededWritesVersionAfterFuelRefreshCompletes() async throws {
        let rollupKey = "milehound.rollup.rebuiltVersion"
        let fuelKey = TripDerivedBackfillService.dynamicFuelVersionKey
        let previousRollup = UserDefaults.standard.integer(forKey: rollupKey)
        let previousFuel = UserDefaults.standard.integer(forKey: fuelKey)
        UserDefaults.standard.set(10, forKey: rollupKey)
        UserDefaults.standard.set(TripDerivedBackfillService.dynamicFuelVersion, forKey: fuelKey)
        defer {
            UserDefaults.standard.set(previousRollup, forKey: rollupKey)
            UserDefaults.standard.set(previousFuel, forKey: fuelKey)
        }

        _ = insertTrip(startedAt: Date(), dynamicFuelCost: 42)
        try context.save()

        await TripRollupService.rebuildIfNeeded(container: container)

        XCTAssertEqual(UserDefaults.standard.integer(forKey: rollupKey), 14)
        XCTAssertEqual(try rollups().count, 1)
        XCTAssertEqual(try XCTUnwrap(try rollups().first).dynamicFuelCost, 42, accuracy: 0.1)
    }
}
