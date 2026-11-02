import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

/// Counts calls and returns a canned route (or error) without MapKit or network.
private final class FakeDrivingRouteProvider: DrivingRouteProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = []
    var result: Result<DrivingRoute, Error>

    init(result: Result<DrivingRoute, Error>) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls.count
    }

    var lastOrigin: CLLocationCoordinate2D? {
        lock.lock()
        defer { lock.unlock() }
        return _calls.last?.0
    }

    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> DrivingRoute {
        let result = lock.withLock {
            _calls.append((origin, destination))
            return self.result
        }
        return try result.get()
    }
}

@MainActor
final class PlannedRouteStoreTests: XCTestCase {
    /// ~1.1 km due north of the start, 10 vertices.
    private let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
    private var northLine: [CLLocationCoordinate2D] {
        (0...10).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.001, longitude: 29.0) }
    }

    private var destination: PlannedRouteDestination {
        PlannedRouteDestination(id: "place.office", name: "Office", coordinate: northLine.last!)
    }

    private func route(travelTime: TimeInterval = 120) -> DrivingRoute {
        let length = PlannedRouteProgress.cumulativeDistances(northLine).last ?? 0
        return DrivingRoute(coordinates: northLine, distanceMeters: length, expectedTravelTime: travelTime)
    }

    private func makeStore(
        _ provider: FakeDrivingRouteProvider,
        connected: Bool = true,
        clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) -> PlannedRouteStore {
        let store = PlannedRouteStore(provider: provider, isConnected: { connected })
        store.now = clock
        return store
    }

    private func settle(_ store: PlannedRouteStore) async {
        await store.requestTask?.value
    }

    func testSetDestinationFetchesRouteAndReportsRemaining() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        let versionBefore = store.version

        store.setDestination(destination, origin: start)
        XCTAssertEqual(store.status, .loading)
        await settle(store)

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(store.status, .ready)
        XCTAssertEqual(store.route?.coordinates.count, northLine.count)
        XCTAssertGreaterThan(store.version, versionBefore)
        let remaining = try? XCTUnwrap(store.remainingMeters)
        XCTAssertEqual(remaining ?? 0, 1_110, accuracy: 20)
        XCTAssertEqual(store.remainingTravelTime ?? 0, 120, accuracy: 30)
    }

    func testFailureWhileOnlineIsFailed() async {
        let provider = FakeDrivingRouteProvider(result: .failure(DrivingRouteError.noRoute))
        let store = makeStore(provider)
        store.setDestination(destination, origin: start)
        await settle(store)
        XCTAssertEqual(store.status, .failed)
        XCTAssertNil(store.route)
        XCTAssertEqual(store.destination, destination)
    }

    func testOfflineSkipsTheRequest() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider, connected: false)
        store.setDestination(destination, origin: start)
        await settle(store)
        XCTAssertEqual(store.status, .offline)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testWithoutOriginWaitsForFirstFix() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        store.setDestination(destination, origin: nil)
        XCTAssertEqual(store.status, .loading)
        XCTAssertEqual(provider.callCount, 0)

        store.noteVehicle(start)
        await settle(store)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(store.status, .ready)
    }

    func testProgressShrinksRemainingAlongTheRoute() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        store.setDestination(destination, origin: start)
        await settle(store)
        let full = store.remainingMeters ?? 0

        store.noteVehicle(northLine[5])
        XCTAssertEqual(store.remainingMeters ?? 0, full / 2, accuracy: 20)
        XCTAssertLessThan(store.remainingTravelTime ?? .infinity, 120)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testDrivingAlongTheRouteNeverSwapsTheOverlay() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        store.setDestination(destination, origin: start)
        await settle(store)

        let version = store.version
        for index in 1...8 {
            store.noteVehicle(northLine[index])
        }
        XCTAssertEqual(store.version, version, "driving moves the lead line on the map, not the route overlays")
        XCTAssertEqual(store.route?.coordinates.count, northLine.count)
    }

    func testFirstMissReroutesImmediatelyAndTheNextOneWaits() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider, clock: { clock })
        store.setDestination(destination, origin: start)
        await settle(store)
        XCTAssertEqual(provider.callCount, 1)

        // ~400 m east of the line, a few seconds after the route was fetched.
        let off = CLLocationCoordinate2D(latitude: 41.005, longitude: 29.005)
        clock = clock.addingTimeInterval(10)
        store.noteVehicle(off)
        XCTAssertFalse(store.missedTurn, "one fix is not a miss")
        XCTAssertEqual(provider.callCount, 1)

        store.noteVehicle(off)
        XCTAssertTrue(store.missedTurn)
        XCTAssertTrue(store.isRerouting)
        await settle(store)
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(provider.lastOrigin?.longitude ?? 0, off.longitude, accuracy: 1e-9)
        XCTAssertFalse(store.isRerouting)
        XCTAssertFalse(store.missedTurn)

        // Still off the replacement. A second miss in the same departure waits out the throttle.
        store.noteVehicle(off)
        store.noteVehicle(off)
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertTrue(store.missedTurn)
        XCTAssertFalse(store.isRerouting)

        clock = clock.addingTimeInterval(7)
        store.noteVehicle(off)
        store.noteVehicle(off)
        XCTAssertEqual(provider.callCount, 2)

        clock = clock.addingTimeInterval(1)
        store.noteVehicle(off)
        store.noteVehicle(off)
        await settle(store)
        XCTAssertEqual(provider.callCount, 3)
    }

    func testWrongHeadingReroutesWhileStillNearTheJunction() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider, clock: { clock })
        store.setDestination(destination, origin: start)
        await settle(store)

        clock = clock.addingTimeInterval(20)
        let onTheLine = northLine[4]
        store.noteVehicle(onTheLine, course: 90, speed: 12)
        store.noteVehicle(onTheLine, course: 90, speed: 12)
        XCTAssertTrue(store.missedTurn)
        await settle(store)
        XCTAssertEqual(provider.callCount, 2)
    }

    func testOneOffRouteFixDoesNotReroute() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider, clock: { clock })
        store.setDestination(destination, origin: start)
        await settle(store)

        clock = clock.addingTimeInterval(60)
        let off = CLLocationCoordinate2D(latitude: 41.005, longitude: 29.005)
        store.noteVehicle(off)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertFalse(store.missedTurn)
    }

    func testOnRouteFixResetsTheStreak() async {
        var clock = Date(timeIntervalSince1970: 1_000)
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider, clock: { clock })
        store.setDestination(destination, origin: start)
        await settle(store)

        clock = clock.addingTimeInterval(60)
        let off = CLLocationCoordinate2D(latitude: 41.005, longitude: 29.005)
        store.noteVehicle(off)
        store.noteVehicle(northLine[4])
        store.noteVehicle(off)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertFalse(store.missedTurn)
    }

    func testArrivalClearsTheRoute() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        store.setDestination(destination, origin: start)
        await settle(store)

        store.noteVehicle(CLLocationCoordinate2D(latitude: northLine.last!.latitude - 0.0002, longitude: 29.0))
        XCTAssertNil(store.destination)
        XCTAssertNil(store.route)
        XCTAssertEqual(store.status, .idle)
    }

    func testClearDropsAnInFlightResult() async {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        store.setDestination(destination, origin: start)
        let task = store.requestTask
        store.clear()
        await task?.value
        XCTAssertNil(store.route)
        XCTAssertNil(store.destination)
        XCTAssertEqual(store.status, .idle)
    }

    func testInvalidDestinationIsIgnored() {
        let provider = FakeDrivingRouteProvider(result: .success(route()))
        let store = makeStore(provider)
        store.setDestination(
            PlannedRouteDestination(id: "bad", name: "Bad", coordinate: kCLLocationCoordinate2DInvalid),
            origin: start
        )
        XCTAssertNil(store.destination)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testLongRouteIsDecimatedToTheDisplayBudget() async {
        let dense = (0..<5_000).map {
            CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.00005, longitude: 29.0 + sin(Double($0) / 40) * 0.001)
        }
        let provider = FakeDrivingRouteProvider(
            result: .success(DrivingRoute(coordinates: dense, distanceMeters: 30_000, expectedTravelTime: 1_800))
        )
        let store = makeStore(provider)
        store.setDestination(
            PlannedRouteDestination(id: "far", name: "Far", coordinate: dense.last!),
            origin: dense.first!
        )
        await settle(store)
        let count = store.route?.coordinates.count ?? 0
        XCTAssertLessThanOrEqual(count, PlannedRouteStore.maxDisplayPoints)
        XCTAssertGreaterThan(count, 2)
        XCTAssertEqual(store.route?.coordinates.last?.latitude ?? 0, dense.last!.latitude, accuracy: 1e-9)
    }

    func testRecordingStopAndDiscardClearTheDestination() throws {
        let defaults = UserDefaults(suiteName: "test.trailhound.plannedRoute.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        let container = try ModelContainerFactory.makeInMemory()
        let recordingService = TripRecordingService(locationService: LocationService(), settings: settings)
        recordingService.configure(modelContext: container.mainContext)

        XCTAssertTrue(recordingService.startManualRecording())
        recordingService.plannedRoute.setDestination(destination, origin: nil)
        XCTAssertNotNil(recordingService.plannedRoute.destination)
        recordingService.stopManualRecording()
        XCTAssertNil(recordingService.plannedRoute.destination)

        XCTAssertTrue(recordingService.startManualRecording())
        recordingService.plannedRoute.setDestination(destination, origin: nil)
        recordingService.discardActiveRecordingSession()
        XCTAssertNil(recordingService.plannedRoute.destination)
        XCTAssertEqual(recordingService.plannedRoute.status, .idle)
    }
}
