import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class TripDetailViewModelRevealTests: XCTestCase {
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testRevealProgressZeroIsEmptyOrMinimal() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = makeViewModel(for: trip)

        let segments = viewModel.revealedSpeedColoredSegments(progress: 0)
        XCTAssertTrue(segments.isEmpty || segments.allSatisfy { $0.coordinates.count <= 2 })
    }

    func testRevealProgressOneMatchesFullSegments() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = makeViewModel(for: trip)

        let revealed = viewModel.revealedSpeedColoredSegments(progress: 1)
        let full = viewModel.speedColoredSegments
        XCTAssertEqual(revealed.count, full.count)
    }

    func testRevealProgressIncreasesCoordinateCoverage() throws {
        let trip = try insertTrip(pointCount: 8)
        let viewModel = makeViewModel(for: trip)

        let early = viewModel.revealedSpeedColoredSegments(progress: 0.25)
        let later = viewModel.revealedSpeedColoredSegments(progress: 0.75)

        let earlyPoints = early.reduce(0) { $0 + $1.coordinates.count }
        let laterPoints = later.reduce(0) { $0 + $1.coordinates.count }
        XCTAssertLessThanOrEqual(earlyPoints, laterPoints)
    }

    func testNilDisplayPathDoesNotCrash() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: nil
        )
        XCTAssertTrue(viewModel.revealedSpeedColoredSegments(progress: 1).isEmpty)
        XCTAssertEqual(viewModel.displayPointCount, 0)
    }

    private func makeViewModel(for trip: Trip) -> TripDetailViewModel {
        let pieces = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        return TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: pieces
        )
    }

    @discardableResult
    private func insertTrip(pointCount: Int) throws -> Trip {
        container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distanceMeters: 5_000
        )
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 30),
                latitude: 41.0 + Double(index) * 0.001,
                longitude: 29.0 + Double(index) * 0.001,
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

@MainActor
final class TripDetailViewModelSummaryTests: XCTestCase {
    func testSummaryPutsTravelTimeBesideDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            distanceMeters: 40_000
        )
        trip.cruiseDurationSeconds = 2_700
        trip.stopDurationSeconds = 900

        let ids = TripDetailViewModel(trip: trip, places: [], privacyRadius: 500)
            .summaryMetrics
            .map(\.id)
        XCTAssertEqual(ids.prefix(2).map { $0 }, ["duration", "movingDuration"])
        XCTAssertEqual(ids[2], "distance")
    }

    func testSummaryFormatsStoredMovingDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            distanceMeters: 40_000
        )
        trip.cruiseDurationSeconds = 2_700
        trip.stopDurationSeconds = 900

        let moving = TripDetailViewModel(trip: trip, places: [], privacyRadius: 500)
            .summaryMetrics
            .first { $0.id == "movingDuration" }
        XCTAssertEqual(moving?.formatted(progress: 1), DateFormatters.formatDuration(2_700))
    }

    func testSummaryOmitsTravelTimeUntilProfileExists() {
        let start = Date()
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 3_000
        )
        let ids = TripDetailViewModel(trip: trip, places: [], privacyRadius: 500)
            .summaryMetrics
            .map(\.id)
        XCTAssertFalse(ids.contains("movingDuration"))
    }

    func testSummaryFallsBackToClockMinusStopsWhenCruiseIsZeroed() {
        let start = Date()
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            distanceMeters: 400
        )
        trip.cruiseDurationSeconds = 0
        trip.stopDurationSeconds = 40

        let moving = TripDetailViewModel(trip: trip, places: [], privacyRadius: 500)
            .summaryMetrics
            .first { $0.id == "movingDuration" }
        XCTAssertEqual(moving?.formatted(progress: 1), DateFormatters.formatDuration(80))
    }

    func testSummaryFormatsAvgFuelWithVolumeLikeEstimated() {
        let start = Date()
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 5_000
        )
        trip.estimatedFuelCost = 19.5
        trip.dynamicFuelCost = 22
        trip.fuelUnitPrice = 65

        let metrics = TripDetailViewModel(trip: trip, places: [], privacyRadius: 500).summaryMetrics
        let avg = metrics.first { $0.id == "fuel" }
        let estimated = metrics.first { $0.id == "dynamicFuel" }
        let avgVolume = FuelCostCalculator.formatVolume(cost: 19.5, unitPrice: 65, isElectric: false)
        let estimatedVolume = FuelCostCalculator.formatVolume(cost: 22, unitPrice: 65, isElectric: false)

        XCTAssertEqual(
            avg?.formatted(progress: 1),
            "\(FuelCostCalculator.formatCost(19.5)) · \(avgVolume!)"
        )
        XCTAssertEqual(
            estimated?.formatted(progress: 1),
            "\(FuelCostCalculator.formatCost(22)) · \(estimatedVolume!)"
        )
    }

    func testSummaryKeepsDurationThroughFuelInOneSequence() {
        let start = Date()
        let trip = Trip(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            distanceMeters: 40_000
        )
        trip.cruiseDurationSeconds = 2_700
        trip.stopDurationSeconds = 900
        trip.maxSpeedMps = 33
        trip.estimatedFuelCost = 19
        trip.dynamicFuelCost = 22
        trip.fuelUnitPrice = 65

        let ids = TripDetailViewModel(trip: trip, places: [], privacyRadius: 500)
            .summaryMetrics
            .map(\.id)
        XCTAssertEqual(ids.prefix(4).map { $0 }, ["duration", "movingDuration", "distance", "maxSpeed"])
        XCTAssertEqual(ids.suffix(2).map { $0 }, ["fuel", "dynamicFuel"])
    }
}
