import CoreLocation
import SwiftData
import SwiftUI
import XCTest
@testable import Milehound

@MainActor
final class TripRoutePathCacheTests: XCTestCase {
    private var container: ModelContainer!

    override func tearDown() {
        if let container {
            // Best-effort cleanup of any disk files written during the test.
            let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
            for trip in trips {
                TripRoutePathCache.shared.remove(for: trip.id)
            }
        }
        TripRoutePathCache.shared.clearMemory()
        TripRoutePathCache.shared.resetWorkerInvocationCount()
        container = nil
        super.tearDown()
    }

    func testMemoryHitSkipsWorkerOnSecondCall() async throws {
        let trip = try insertTrip(pointCount: 40)
        let cache = TripRoutePathCache.shared
        cache.resetWorkerInvocationCount()

        let first = await cache.path(for: trip, container: container)
        XCTAssertFalse(first.isEmpty)
        let invocationsAfterFirst = cache.workerInvocationCount

        let second = await cache.path(for: trip, container: container)
        XCTAssertEqual(cache.workerInvocationCount, invocationsAfterFirst)
        XCTAssertEqual(second.count, first.count)
        XCTAssertEqual(second.first?.count, first.first?.count)
    }

    func testDiskRoundTripRestoresCoordinates() async throws {
        let trip = try insertTrip(pointCount: 30)
        let cache = TripRoutePathCache.shared
        let fingerprint = TripRoutePathFingerprint.make(from: trip)

        let samples = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let payload = TripRoutePathPayload.from(samples: samples, fingerprint: fingerprint)
        cache.storeForTesting(payload, for: trip.id)
        cache.clearMemory()

        // Give the serial disk queue a moment to finish the atomic write.
        try await Task.sleep(for: .milliseconds(50))

        let restored = await cache.path(for: trip, container: container)
        XCTAssertEqual(restored.count, samples.count)
        XCTAssertEqual(
            restored.first?.map(\.coordinate.latitude),
            samples.first?.map(\.coordinate.latitude)
        )
    }

    func testFingerprintMismatchRejectsDiskCache() async throws {
        let trip = try insertTrip(pointCount: 20)
        let cache = TripRoutePathCache.shared
        var fingerprint = TripRoutePathFingerprint.make(from: trip)
        fingerprint = TripRoutePathFingerprint(
            distanceMeters: fingerprint.distanceMeters + 500,
            startedAt: fingerprint.startedAt,
            endedAt: fingerprint.endedAt,
            startLatitude: fingerprint.startLatitude,
            startLongitude: fingerprint.startLongitude,
            endLatitude: fingerprint.endLatitude,
            endLongitude: fingerprint.endLongitude
        )

        let stale = TripRoutePathPayload(
            fingerprint: fingerprint,
            pieces: [[
                CachedRoutePoint(latitude: 1, longitude: 2, timestamp: 0, speedMps: 1)
            ]]
        )
        cache.storeForTesting(stale, for: trip.id)
        cache.clearMemory()
        try await Task.sleep(for: .milliseconds(50))
        cache.resetWorkerInvocationCount()

        let path = await cache.path(for: trip, container: container)
        XCTAssertGreaterThan(cache.workerInvocationCount, 0)
        XCTAssertNotEqual(path.first?.first?.coordinate.latitude, 1)
    }

    func testRemoveClearsMemoryAndDisk() async throws {
        let trip = try insertTrip(pointCount: 15)
        let cache = TripRoutePathCache.shared
        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        let payload = TripRoutePathPayload(
            fingerprint: fingerprint,
            pieces: [[
                CachedRoutePoint(latitude: 41, longitude: 29, timestamp: 1, speedMps: 10),
                CachedRoutePoint(latitude: 41.01, longitude: 29.01, timestamp: 2, speedMps: 10)
            ]]
        )
        cache.storeForTesting(payload, for: trip.id)
        try await Task.sleep(for: .milliseconds(50))

        cache.remove(for: trip.id)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(cache.cachedPath(for: trip.id, fingerprint: fingerprint))
        let disk = await cache.readDiskForTesting(tripID: trip.id)
        XCTAssertNil(disk)
    }

    func testPrewarmSkipsWorkerWhenMemoryHit() async throws {
        let trip = try insertTrip(pointCount: 25)
        let cache = TripRoutePathCache.shared
        cache.resetWorkerInvocationCount()

        _ = await cache.path(for: trip, container: container)
        let invocationsAfterPath = cache.workerInvocationCount
        XCTAssertGreaterThan(invocationsAfterPath, 0)

        cache.prewarm(tripID: trip.id, container: container)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(cache.workerInvocationCount, invocationsAfterPath)
    }

    func testPrewarmSkipsWorkerWhenDiskHit() async throws {
        let trip = try insertTrip(pointCount: 22)
        let cache = TripRoutePathCache.shared
        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        let samples = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let payload = TripRoutePathPayload.from(samples: samples, fingerprint: fingerprint)
        cache.storeForTesting(payload, for: trip.id)
        try await Task.sleep(for: .milliseconds(50))
        cache.clearMemory()
        cache.resetWorkerInvocationCount()

        cache.prewarm(tripID: trip.id, container: container)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(cache.workerInvocationCount, 0)
        let restored = await cache.path(for: trip, container: container)
        XCTAssertEqual(cache.workerInvocationCount, 0)
        XCTAssertEqual(restored.count, samples.count)
        XCTAssertEqual(
            restored.first?.map(\.coordinate.latitude),
            samples.first?.map(\.coordinate.latitude)
        )
    }

    func testCorruptDiskFileIsTreatedAsMiss() async throws {
        let trip = try insertTrip(pointCount: 12)
        let cache = TripRoutePathCache.shared
        cache.resetWorkerInvocationCount()

        // Write garbage into the expected file location by storing then overwriting via remove+rebuild.
        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        cache.storeForTesting(
            TripRoutePathPayload(fingerprint: fingerprint, pieces: []),
            for: trip.id
        )
        try await Task.sleep(for: .milliseconds(50))

        // Corrupt by writing truncated bytes through the public remove + direct file write.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport
            .appendingPathComponent("TripRoutePaths", isDirectory: true)
            .appendingPathComponent("\(trip.id.uuidString).bin")
        try Data([0x00, 0x01, 0x02]).write(to: url, options: .atomic)

        cache.clearMemory()
        let path = await cache.path(for: trip, container: container)
        XCTAssertGreaterThan(cache.workerInvocationCount, 0)
        XCTAssertFalse(path.isEmpty)
    }

    @discardableResult
    private func insertTrip(pointCount: Int) throws -> Trip {
        container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(pointCount) * 5),
            distanceMeters: Double(pointCount) * 12
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.endLatitude = 41.0 + Double(pointCount) * 0.0001
        trip.endLongitude = 29.0 + Double(pointCount) * 0.0001
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 5),
                latitude: 41.0 + Double(index) * 0.0001,
                longitude: 29.0 + Double(index) * 0.0001,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            context.insert(point)
        }
        try context.save()
        return trip
    }
}

/// One `TripDetailView` can be handed a different trip (notification deep link replacing the
/// stack, a new pane selection). Trip A's route must never be drawn under trip B's pins, and
/// switching must never touch either trip's stored GPS points.
@MainActor
final class TripDetailTripSwitchTests: XCTestCase {
    private var container: ModelContainer!
    /// The live trip page can still hold a model after the path is cleared. Releasing the
    /// in-memory container then destroys that model and crashes the next test.
    private static var keptContainers: [ModelContainer] = []

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
    }

    override func tearDown() {
        TabSelection.shared.tripsPath = NavigationPath()
        let trips = (try? container?.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
        for trip in trips {
            TripRoutePathCache.shared.remove(for: trip.id)
        }
        TripRoutePathCache.shared.clearMemory()
        if let container {
            Self.keptContainers.append(container)
        }
        container = nil
        super.tearDown()
    }

    func testModelBuiltForAnotherTripDoesNotLendItsRoute() async throws {
        let tripA = try insertTrip(startLatitude: 38.40, pointCount: 30)
        let tripB = try insertTrip(startLatitude: 38.30, pointCount: 50)
        let piecesA = await TripRoutePathCache.shared.path(for: tripA, container: container)
        let modelA = TripDetailViewModel(trip: tripA, places: [], privacyRadius: 0, displayPieces: piecesA)

        XCTAssertTrue(modelA.belongs(to: tripA))
        XCTAssertFalse(modelA.belongs(to: tripB))
        XCTAssertNil(TripDetailViewModel.reusablePieces(from: modelA, for: tripB))
        XCTAssertEqual(
            TripDetailViewModel.reusablePieces(from: modelA, for: tripA)?.first?.first?.coordinate.latitude,
            piecesA.first?.first?.coordinate.latitude
        )
        XCTAssertNil(TripDetailViewModel.reusablePieces(from: nil, for: tripA))
    }

    func testRouteIdentityLabelFlagsAForeignRoute() async throws {
        let tripA = try insertTrip(startLatitude: 38.40, pointCount: 30)
        let tripB = try insertTrip(startLatitude: 38.30, pointCount: 50)
        let piecesA = await TripRoutePathCache.shared.path(for: tripA, container: container)
        let modelA = TripDetailViewModel(trip: tripA, places: [], privacyRadius: 0, displayPieces: piecesA)
        let loadingB = TripDetailViewModel(trip: tripB, places: [], privacyRadius: 0)

        XCTAssertTrue(modelA.routeIdentityLabel(for: tripA).hasSuffix("route=match"))
        XCTAssertTrue(modelA.routeIdentityLabel(for: tripB).hasSuffix("route=mismatch"))
        XCTAssertTrue(loadingB.routeIdentityLabel(for: tripB).hasSuffix("route=loading"))
    }

    func testSwitchingTripsLoadsEachTripsOwnRoute() async throws {
        let tripA = try insertTrip(startLatitude: 38.40, pointCount: 30)
        let tripB = try insertTrip(startLatitude: 38.30, pointCount: 50)
        let cache = TripRoutePathCache.shared

        let piecesA = await cache.path(for: tripA, container: container)
        let piecesB = await cache.path(for: tripB, container: container)
        let piecesAAgain = await cache.path(for: tripA, container: container)

        XCTAssertEqual(piecesA.first?.first?.coordinate.latitude ?? 0, 38.40, accuracy: 0.000_01)
        XCTAssertEqual(piecesB.first?.first?.coordinate.latitude ?? 0, 38.30, accuracy: 0.000_01)
        XCTAssertEqual(
            piecesB.last?.last?.coordinate.latitude ?? 0,
            tripB.sortedPoints.last?.latitude ?? -1,
            accuracy: 0.000_01
        )
        XCTAssertEqual(piecesAAgain.first?.first?.coordinate.latitude, piecesA.first?.first?.coordinate.latitude)
    }

    func testSwitchingTripsNeverDeletesStoredPoints() async throws {
        let tripA = try insertTrip(startLatitude: 38.40, pointCount: 30)
        let tripB = try insertTrip(startLatitude: 38.30, pointCount: 50)
        let cache = TripRoutePathCache.shared
        let selection = TabSelection.shared

        selection.showFinishedTrip(tripA)
        let piecesA = await cache.path(for: tripA, container: container)
        var model = TripDetailViewModel(trip: tripA, places: [], privacyRadius: 0, displayPieces: piecesA)

        selection.showFinishedTrip(tripB)
        XCTAssertEqual(selection.tripsPath.count, 1)
        model = TripDetailViewModel(
            trip: tripB,
            places: [],
            privacyRadius: 0,
            displayPieces: TripDetailViewModel.reusablePieces(from: model, for: tripB)
        )
        XCTAssertNil(model.displayPieces)
        _ = TripDerivedMetrics.refreshPersistedFuel(for: tripB, in: container.mainContext)
        try container.mainContext.save()

        XCTAssertEqual(try storedPointCount(for: tripA), 30)
        XCTAssertEqual(try storedPointCount(for: tripB), 50)
        selection.tripsPath = NavigationPath()
    }

    private func storedPointCount(for trip: Trip) throws -> Int {
        let tripID = trip.id
        let descriptor = FetchDescriptor<TripPoint>(predicate: #Predicate { $0.trip?.id == tripID })
        return try container.mainContext.fetchCount(descriptor)
    }

    private func insertTrip(startLatitude: Double, pointCount: Int) throws -> Trip {
        let context = container.mainContext
        let startedAt = Date().addingTimeInterval(-Double(pointCount) * 5 - 60)
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(pointCount) * 5),
            distanceMeters: Double(pointCount) * 12
        )
        trip.startLatitude = startLatitude
        trip.startLongitude = 27.0
        trip.endLatitude = startLatitude + Double(pointCount - 1) * 0.0001
        trip.endLongitude = 27.0 + Double(pointCount - 1) * 0.0001
        context.insert(trip)
        for index in 0..<pointCount {
            context.insert(TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 5),
                latitude: startLatitude + Double(index) * 0.0001,
                longitude: 27.0 + Double(index) * 0.0001,
                sequence: index,
                speedMps: 12,
                trip: trip
            ))
        }
        try context.save()
        return trip
    }
}
