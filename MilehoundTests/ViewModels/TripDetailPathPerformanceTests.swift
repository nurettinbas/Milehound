import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class TripDetailPathPerformanceTests: XCTestCase {
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// Reveal ticks must reuse prepared segments — `displaySegments` must not run per tick.
    func testRevealDoesNotReinvokeDisplaySegments() throws {
        let trip = try insertTrip(pointCount: 200)
        let samples = RouteDisplayPath.samples(from: trip.sortedPoints)
        RouteDisplayPath.testDisplaySegmentsInvocations = 0
        let pieces = RouteDisplayPath.displaySegments(samples: samples)
        let buildCount = RouteDisplayPath.testDisplaySegmentsInvocations
        XCTAssertEqual(buildCount, 1)

        let viewModel = TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: pieces
        )

        for tick in 1...12 {
            let progress = Double(tick) / 12.0
            _ = viewModel.revealedSpeedColoredSegments(progress: progress)
        }

        XCTAssertEqual(RouteDisplayPath.testDisplaySegmentsInvocations, buildCount)
    }

    func testNilDisplayPathIsSafe() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: nil
        )

        XCTAssertTrue(viewModel.speedColoredSegments.isEmpty)
        XCTAssertTrue(viewModel.revealedSpeedColoredSegments(progress: 0.5).isEmpty)
        XCTAssertTrue(viewModel.revealedFallbackCoordinates(progress: 0.5).isEmpty)
        XCTAssertEqual(viewModel.displayPointCount, 0)
        XCTAssertNotNil(viewModel.mapRegion())
    }

    func testRevealProgressOneMatchesFullSegments() throws {
        let trip = try insertTrip(pointCount: 40)
        let pieces = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let viewModel = TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: pieces
        )

        let revealed = viewModel.revealedSpeedColoredSegments(progress: 1)
        let full = viewModel.speedColoredSegments
        XCTAssertEqual(revealed.count, full.count)
        XCTAssertEqual(revealed.map(\.id), full.map(\.id))
    }

    func testRevealSegmentIdsStayStableAcrossTicks() throws {
        let trip = try insertTrip(pointCount: 60)
        let pieces = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let viewModel = TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: pieces
        )

        let early = viewModel.revealedSpeedColoredSegments(progress: 0.4)
        let later = viewModel.revealedSpeedColoredSegments(progress: 0.8)
        guard let firstEarly = early.first, let firstLater = later.first else {
            return
        }
        XCTAssertEqual(firstEarly.id, firstLater.id)
    }

    @discardableResult
    private func insertTrip(pointCount: Int) throws -> Trip {
        container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(pointCount) * 3),
            distanceMeters: Double(pointCount) * 15,
            maxSpeedMps: 20
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.endLatitude = 41.0 + Double(pointCount) * 0.0001
        trip.endLongitude = 29.0 + Double(pointCount) * 0.0001
        context.insert(trip)

        for index in 0..<pointCount {
            let kmh = index % 30 < 15 ? 40.0 : 100.0
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 3),
                latitude: 41.0 + Double(index) * 0.0001,
                longitude: 29.0 + Double(index) * 0.0001,
                sequence: index,
                speedMps: kmh / 3.6,
                trip: trip
            )
            context.insert(point)
        }
        try context.save()
        return trip
    }
}
