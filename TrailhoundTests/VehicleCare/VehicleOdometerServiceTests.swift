import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class VehicleOdometerServiceTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    private var container: ModelContainer?

    func testParseRejectsEmptyNegativeHugeAndNonDigits() {
        XCTAssertNil(VehicleOdometerService.parseReading(""))
        XCTAssertNil(VehicleOdometerService.parseReading("  "))
        XCTAssertNil(VehicleOdometerService.parseReading("-1"))
        XCTAssertNil(VehicleOdometerService.parseReading("12.5"))
        XCTAssertNil(VehicleOdometerService.parseReading("1 000"))
        XCTAssertNil(VehicleOdometerService.parseReading("2000001"))
        XCTAssertNil(VehicleOdometerService.parseReading("99999999"))
        XCTAssertEqual(VehicleOdometerService.parseReading("0"), 0)
        XCTAssertEqual(VehicleOdometerService.parseReading("2000000"), 2_000_000)
    }

    func testTripAfterAnchorAddsAndDeleteRemoves() throws {
        let context = try makeContext()
        let vehicle = makeVehicle(in: context)
        VehicleOdometerService.setReading(km: 10_000, at: anchor, vehicle: vehicle, in: context)

        let trip = makeTrip(meters: 2_500_000, startedAt: anchor.addingTimeInterval(3_600), vehicle: vehicle, in: context)
        VehicleOdometerService.tripAdded(trip, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, 12_500)

        let before = makeTrip(meters: 9_000_000, startedAt: anchor.addingTimeInterval(-3_600), vehicle: vehicle, in: context)
        VehicleOdometerService.tripAdded(before, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, 12_500)

        VehicleOdometerService.tripRemoved(trip, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, 10_000)
    }

    func testUpdateDistanceAndDetachVehicle() throws {
        let context = try makeContext()
        let vehicle = makeVehicle(in: context)
        let other = VehicleProfile(name: "Other")
        context.insert(other)
        VehicleOdometerService.setReading(km: 1_000, at: anchor, vehicle: vehicle, in: context)
        VehicleOdometerService.setReading(km: 50, at: anchor, vehicle: other, in: context)

        let trip = makeTrip(meters: 1_000_000, startedAt: anchor.addingTimeInterval(60), vehicle: vehicle, in: context)
        VehicleOdometerService.tripAdded(trip, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, 2_000)

        let previous = TripOdometerSnapshot(meters: trip.distanceMeters, startedAt: trip.startedAt, vehicleID: vehicle.id)
        trip.distanceMeters = 1_500_000
        VehicleOdometerService.tripUpdated(trip, previous: previous, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, 2_500)

        let moved = TripOdometerSnapshot(meters: trip.distanceMeters, startedAt: trip.startedAt, vehicleID: vehicle.id)
        trip.vehicleID = other.id
        trip.vehicle = nil
        VehicleOdometerService.tripUpdated(trip, previous: moved, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, 1_000)
        XCTAssertEqual(other.currentOdometerKm, 1_550)
    }

    func testRecomputeMatchesIncrementalAndIgnoresTripsBeforeAnchor() throws {
        let context = try makeContext()
        let vehicle = makeVehicle(in: context)
        VehicleOdometerService.setReading(km: 4_000, at: anchor, vehicle: vehicle, in: context)
        _ = makeTrip(meters: 800_000, startedAt: anchor.addingTimeInterval(-10), vehicle: vehicle, in: context)
        let counted = makeTrip(meters: 600_000, startedAt: anchor.addingTimeInterval(10), vehicle: vehicle, in: context)
        VehicleOdometerService.tripAdded(counted, in: context)
        let incremental = vehicle.currentOdometerKm
        VehicleOdometerService.recompute(vehicle, in: context)
        XCTAssertEqual(vehicle.currentOdometerKm, incremental)
        XCTAssertEqual(vehicle.currentOdometerKm, 4_600)
    }

    func testClearStopsAddingUntilANewReading() throws {
        let context = try makeContext()
        let vehicle = makeVehicle(in: context)
        VehicleOdometerService.setReading(km: 100, at: anchor, vehicle: vehicle, in: context)
        VehicleOdometerService.clearReading(vehicle)
        let trip = makeTrip(meters: 5_000_000, startedAt: anchor.addingTimeInterval(10), vehicle: vehicle, in: context)
        VehicleOdometerService.tripAdded(trip, in: context)
        XCTAssertNil(vehicle.currentOdometerKm)
    }

    func testThousandTripsStayFast() throws {
        let context = try makeContext()
        let vehicle = makeVehicle(in: context)
        VehicleOdometerService.setReading(km: 0, at: anchor, vehicle: vehicle, in: context)
        var trips: [Trip] = []
        trips.reserveCapacity(1_000)
        for index in 0..<1_000 {
            let trip = makeTrip(
                meters: 1_000,
                startedAt: anchor.addingTimeInterval(Double(index + 1)),
                vehicle: vehicle,
                in: context
            )
            trips.append(trip)
        }
        context.autosaveEnabled = false
        let started = Date()
        for trip in trips {
            VehicleOdometerService.tripAdded(trip, in: context)
        }
        VehicleOdometerService.recompute(vehicle, in: context)
        // Linear path: one increment per trip, then a single recompute.
        // A loaded GitHub runner measured this at 2.3s, so the ceiling is 5s.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(vehicle.currentOdometerKm, 1_000)
    }

    func testCompletionReadingRollsTheNextTarget() throws {
        let context = try makeContext()
        let vehicle = makeVehicle(in: context)
        let schedule = VehicleSchedule(
            kind: .service,
            intervalKind: .everyKm,
            intervalKm: 4_000,
            vehicle: vehicle
        )
        context.insert(schedule)
        _ = try VehicleScheduleCompletionService.complete(
            schedule: schedule,
            amount: 900,
            occurredAt: anchor,
            odometerKm: 1_000,
            in: context,
            rescheduleNotifications: false
        )
        XCTAssertEqual(vehicle.odometerAnchorKm, 1_000)
        XCTAssertEqual(vehicle.currentOdometerKm, 1_000)
        XCTAssertEqual(schedule.nextDueOdometerKm, 5_000)
        XCTAssertEqual(schedule.lastCompletedOdometerKm, 1_000)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeInMemory()
        self.container = container
        return container.mainContext
    }

    private func makeVehicle(in context: ModelContext) -> VehicleProfile {
        let vehicle = VehicleProfile(name: "Vespa")
        context.insert(vehicle)
        return vehicle
    }

    private func makeTrip(
        meters: Double,
        startedAt: Date,
        vehicle: VehicleProfile,
        in context: ModelContext
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distanceMeters: meters,
            vehicleID: vehicle.id
        )
        context.insert(trip)
        return trip
    }
}
