import CoreLocation
import MapKit
import SwiftUI
import XCTest
@testable import Trailhound

final class PlannedRouteProgressTests: XCTestCase {
    private let line = (0...4).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.001, longitude: 29.0) }

    func testCumulativeDistancesStartAtZeroAndGrow() {
        let cumulative = PlannedRouteProgress.cumulativeDistances(line)
        XCTAssertEqual(cumulative.count, line.count)
        XCTAssertEqual(cumulative[0], 0)
        XCTAssertEqual(cumulative.last ?? 0, 444, accuracy: 5)
        XCTAssertEqual(zip(cumulative, cumulative.dropFirst()).allSatisfy { $0 < $1 }, true)
        XCTAssertEqual(PlannedRouteProgress.cumulativeDistances([]), [])
    }

    func testMeasureOnTheLine() throws {
        let cumulative = PlannedRouteProgress.cumulativeDistances(line)
        let mid = CLLocationCoordinate2D(latitude: 41.002, longitude: 29.0)
        let measure = try XCTUnwrap(PlannedRouteProgress.measure(vehicle: mid, along: line, cumulative: cumulative))
        XCTAssertEqual(measure.offRouteMeters, 0, accuracy: 1)
        XCTAssertEqual(measure.remainingMeters, (cumulative.last ?? 0) / 2, accuracy: 3)
    }

    func testMeasureBesideTheLineReportsOffset() throws {
        let cumulative = PlannedRouteProgress.cumulativeDistances(line)
        // 0.001° longitude at 41° N ≈ 84 m.
        let beside = CLLocationCoordinate2D(latitude: 41.001, longitude: 29.001)
        let measure = try XCTUnwrap(PlannedRouteProgress.measure(vehicle: beside, along: line, cumulative: cumulative))
        XCTAssertEqual(measure.offRouteMeters, 84, accuracy: 3)
        XCTAssertGreaterThan(measure.offRouteMeters, PlannedRouteProgress.offRouteMeters)
    }

    func testMeasurePastTheEndClampsToZeroRemaining() throws {
        let cumulative = PlannedRouteProgress.cumulativeDistances(line)
        let past = CLLocationCoordinate2D(latitude: 41.006, longitude: 29.0)
        let measure = try XCTUnwrap(PlannedRouteProgress.measure(vehicle: past, along: line, cumulative: cumulative))
        XCTAssertEqual(measure.remainingMeters, 0, accuracy: 0.5)
    }

    func testMeasureRejectsBadInput() {
        let cumulative = PlannedRouteProgress.cumulativeDistances(line)
        XCTAssertNil(PlannedRouteProgress.measure(vehicle: kCLLocationCoordinate2DInvalid, along: line, cumulative: cumulative))
        XCTAssertNil(PlannedRouteProgress.measure(vehicle: line[0], along: [line[0]], cumulative: [0]))
        XCTAssertNil(PlannedRouteProgress.measure(vehicle: line[0], along: line, cumulative: [0, 1]))
    }

    func testRemainingTravelTimeScalesWithShareAhead() {
        XCTAssertEqual(
            PlannedRouteProgress.remainingTravelTime(remainingMeters: 500, routeMeters: 1_000, expectedTravelTime: 600),
            300
        )
        XCTAssertEqual(
            PlannedRouteProgress.remainingTravelTime(remainingMeters: 2_000, routeMeters: 1_000, expectedTravelTime: 600),
            600
        )
        XCTAssertEqual(
            PlannedRouteProgress.remainingTravelTime(remainingMeters: 0, routeMeters: 1_000, expectedTravelTime: 600),
            0
        )
        XCTAssertEqual(
            PlannedRouteProgress.remainingTravelTime(remainingMeters: 100, routeMeters: 0, expectedTravelTime: 600),
            0
        )
    }

    func testRerouteThresholdAndThrottle() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(PlannedRouteProgress.shouldReroute(offRouteStreak: 2, lastRequestAt: nil, now: now))
        XCTAssertTrue(PlannedRouteProgress.shouldReroute(offRouteStreak: 3, lastRequestAt: nil, now: now))
        XCTAssertFalse(PlannedRouteProgress.shouldReroute(
            offRouteStreak: 3,
            lastRequestAt: now.addingTimeInterval(-29),
            now: now
        ))
        XCTAssertTrue(PlannedRouteProgress.shouldReroute(
            offRouteStreak: 3,
            lastRequestAt: now.addingTimeInterval(-30),
            now: now
        ))
    }

    func testArrivalRadius() {
        let destination = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        XCTAssertTrue(PlannedRouteProgress.hasArrived(
            vehicle: CLLocationCoordinate2D(latitude: 41.0004, longitude: 29.0),
            destination: destination
        ))
        XCTAssertFalse(PlannedRouteProgress.hasArrived(
            vehicle: CLLocationCoordinate2D(latitude: 41.0006, longitude: 29.0),
            destination: destination
        ))
        XCTAssertFalse(PlannedRouteProgress.hasArrived(vehicle: kCLLocationCoordinate2DInvalid, destination: destination))
    }
}

final class DestinationEntryPolicyTests: XCTestCase {
    func testSearchOpensWhenStoppedOrPaused() {
        XCTAssertTrue(DestinationEntryPolicy.allowsSearch(speedMps: 0, isPaused: false))
        XCTAssertTrue(DestinationEntryPolicy.allowsSearch(speedMps: -1, isPaused: false))
        XCTAssertTrue(DestinationEntryPolicy.allowsSearch(speedMps: 2, isPaused: false))
        XCTAssertTrue(DestinationEntryPolicy.allowsSearch(speedMps: 25, isPaused: true))
    }

    func testSearchLocksWhileMoving() {
        XCTAssertFalse(DestinationEntryPolicy.allowsSearch(speedMps: 2.1, isPaused: false))
        XCTAssertFalse(DestinationEntryPolicy.allowsSearch(speedMps: 15, isPaused: false))
    }

    func testQueryIsCapped() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(DestinationEntryPolicy.sanitizedQuery(long).count, DestinationEntryPolicy.maxQueryLength)
        XCTAssertEqual(DestinationEntryPolicy.sanitizedQuery("Kadıköy"), "Kadıköy")
    }
}

final class LiveFollowPlannedRouteMapTests: XCTestCase {
    func testDestinationPinIsAppendedLast() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let target = CLLocationCoordinate2D(latitude: 41.05, longitude: 29.02)
        let pins = LiveFollowMapPinBuilder.pins(
            startCoordinate: start,
            pauseCoordinates: [],
            tripStopCoordinates: [],
            destinationCoordinate: target
        )
        XCTAssertEqual(pins.map(\.id), ["start", "destination"])
        XCTAssertEqual(pins.last?.kind, .destination)

        let without = LiveFollowMapPinBuilder.pins(
            startCoordinate: start,
            pauseCoordinates: [],
            tripStopCoordinates: []
        )
        XCTAssertEqual(without.map(\.id), ["start"])
    }

    func testOverviewIncludesTheDestination() {
        let vehicle = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let target = CLLocationCoordinate2D(latitude: 41.2, longitude: 29.3)
        let rect = LiveFollowGrowingRoute.overviewMapRect(
            historyPieces: [[vehicle]],
            vehicle: vehicle,
            destination: target
        )
        XCTAssertTrue(rect.contains(MKMapPoint(target)) || rect.insetBy(dx: -1, dy: -1).contains(MKMapPoint(target)))
        let without = LiveFollowGrowingRoute.overviewMapRect(historyPieces: [[vehicle]], vehicle: vehicle)
        XCTAssertFalse(without.insetBy(dx: -1, dy: -1).contains(MKMapPoint(target)))
    }

    func testOverlayRoleKeepsTheTrailSolidAndThePlanSeeThrough() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.0)
        ]
        let planned = PlannedRoutePolyline(coordinates: coordinates, count: coordinates.count)
        let traveled = MKPolyline(coordinates: coordinates, count: coordinates.count)
        XCTAssertEqual(LiveFollowOverlayRole.of(planned), .planned)
        XCTAssertEqual(LiveFollowOverlayRole.of(traveled), .traveled)

        let plannedRenderer = MKPolylineRenderer(polyline: planned)
        LiveFollowPlannedRouteStrokeStyle.apply(to: plannedRenderer, color: .systemBlue)
        XCTAssertNil(plannedRenderer.lineDashPattern, "planned route is a solid road, not dots")
        XCTAssertEqual(plannedRenderer.lineWidth, LiveFollowRouteStrokeStyle.solidWidth)
        XCTAssertLessThan(plannedRenderer.strokeColor?.cgColor.alpha ?? 1, 0.5)
        XCTAssertEqual(plannedRenderer.lineCap, .butt, "see-through pieces must not overlap as darker dots")

        let casing = TrailCasingPolyline(coordinates: coordinates, count: coordinates.count)
        XCTAssertEqual(LiveFollowOverlayRole.of(casing), .casing)
        let casingRenderer = MKPolylineRenderer(polyline: casing)
        LiveFollowRouteStrokeStyle.apply(to: casingRenderer, for: casing, color: .systemBlue)
        XCTAssertEqual(casingRenderer.lineWidth, LiveFollowRouteStrokeStyle.casingWidth)
        XCTAssertEqual(casingRenderer.strokeColor, .white)
        XCTAssertGreaterThan(casingRenderer.lineWidth, LiveFollowRouteStrokeStyle.solidWidth)

        let traveledRenderer = MKPolylineRenderer(polyline: traveled)
        traveledRenderer.lineDashPattern = [1, 2]
        LiveFollowRouteStrokeStyle.apply(to: traveledRenderer, color: .systemBlue)
        XCTAssertNil(traveledRenderer.lineDashPattern)
    }

    func testPlannedCutFollowsTheCarSmoothly() throws {
        let coordinates = (0...10).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.001, longitude: 29.0) }
        let points = coordinates.map(MKMapPoint.init)
        let cumulative = LiveFollowPlannedAhead.cumulative(points)
        let total = try XCTUnwrap(cumulative.last)

        // A few metres beside the line (another lane) still cuts at the car.
        let car = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0025, longitude: 29.00004))
        let cut = try XCTUnwrap(LiveFollowPlannedAhead.advance(vehicle: car, points: points, cumulative: cumulative, fromSegment: 0))
        XCTAssertEqual(cut.segment, 2)
        XCTAssertEqual(cut.along / total, 0.25, accuracy: 0.005)

        let further = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0026, longitude: 29.0))
        let next = try XCTUnwrap(LiveFollowPlannedAhead.advance(
            vehicle: further, points: points, cumulative: cumulative, fromSegment: cut.segment
        ))
        XCTAssertGreaterThan(next.along, cut.along)
        XCTAssertLessThan((next.along - cut.along) * MKMetersPerMapPointAtLatitude(41), 15, "small step, no jump")

        let offRoute = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0025, longitude: 29.005))
        XCTAssertNil(LiveFollowPlannedAhead.advance(vehicle: offRoute, points: points, cumulative: cumulative, fromSegment: 2))
    }

    func testPlannedCutIgnoresALaterStretchThatRunsCloseBy() throws {
        // North 2 km, U-turn, back south 30 m to the west — the other carriageway.
        let up = (0...20).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.001, longitude: 29.0) }
        let down = (0...20).reversed().map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.001, longitude: 28.99964) }
        let points = (up + down).map(MKMapPoint.init)
        let cumulative = LiveFollowPlannedAhead.cumulative(points)

        // Car near the start, nearer to the returning stretch than the outbound one.
        let car = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0005, longitude: 28.99975))
        let cut = try XCTUnwrap(LiveFollowPlannedAhead.advance(vehicle: car, points: points, cumulative: cumulative, fromSegment: 0))
        XCTAssertLessThan(cut.segment, 2, "stays on the outbound stretch")
    }

    func testCutFindsTheCarAfterTheMapIsReopenedFarAlongTheRoute() throws {
        // 2 km north. The map reopens with the cut back at the start and the car 1.5 km in,
        // 15 m beside the line — far past the 400 m window.
        let coordinates = (0...20).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.001, longitude: 29.0) }
        let points = coordinates.map(MKMapPoint.init)
        let cumulative = LiveFollowPlannedAhead.cumulative(points)
        let car = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0135, longitude: 29.0 + 15 / 84_000))
        let cut = try XCTUnwrap(LiveFollowPlannedAhead.advance(vehicle: car, points: points, cumulative: cumulative, fromSegment: 0))
        XCTAssertEqual(cut.segment, 13)
        let total = try XCTUnwrap(cumulative.last)
        XCTAssertEqual(cut.along / total, 0.675, accuracy: 0.005)
    }

    func testLeadLeavesThePuckCentreAndEasesOntoTheRoute() throws {
        // Straight route north; the car drives 6 m east of it (another lane).
        let coordinates = (0...100).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.0002, longitude: 29.0) }
        let points = coordinates.map(MKMapPoint.init)
        let cumulative = LiveFollowPlannedAhead.cumulative(points)
        let metersPerPoint = MKMetersPerMapPointAtLatitude(41)
        let car = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0021, longitude: 29.0 + 6 / 84_000))
        let cut = try XCTUnwrap(LiveFollowPlannedAhead.advance(vehicle: car, points: points, cumulative: cumulative, fromSegment: 0))
        let firstFixed = LiveFollowPlannedAhead.firstFixedChunk(
            along: cut.along, cumulative: cumulative, metersPerPoint: metersPerPoint
        )
        let endVertex = LiveFollowPlannedAhead.chunkStartVertex(firstFixed)
        let lead = LiveFollowPlannedAhead.lead(
            vehicle: car,
            segment: cut.segment,
            along: cut.along,
            points: points,
            cumulative: cumulative,
            endVertex: endVertex,
            metersPerPoint: metersPerPoint
        )

        let start = try XCTUnwrap(lead.first)
        XCTAssertEqual(start.x, car.x, accuracy: 1e-6, "the plan leaves the puck's centre")
        XCTAssertEqual(start.y, car.y, accuracy: 1e-6)
        let end = try XCTUnwrap(lead.last)
        XCTAssertEqual(end.x, points[endVertex].x, accuracy: 1e-6, "and meets the first fixed chunk on its vertex")
        XCTAssertEqual(end.y, points[endVertex].y, accuracy: 1e-6)

        // Sideways offset only shrinks, and is gone past the blend.
        var previousOffset = Double.infinity
        for point in lead {
            let offset = abs(point.x - points[0].x) * metersPerPoint
            XCTAssertLessThanOrEqual(offset, previousOffset + 1e-6)
            previousOffset = offset
        }
        XCTAssertLessThan(previousOffset, 0.01)
        let blendEnd = cut.along + LiveFollowPlannedAhead.blendMeters / metersPerPoint
        XCTAssertGreaterThanOrEqual(cumulative[endVertex], blendEnd, "fixed chunks start after the blend")
    }

    func testFixedChunksShareBoundariesAndCoverTheRoute() {
        let coordinates = (0...100).map { CLLocationCoordinate2D(latitude: 41.0 + Double($0) * 0.0002, longitude: 29.0) }
        let points = coordinates.map(MKMapPoint.init)
        func same(_ a: MKMapPoint?, _ b: MKMapPoint?) -> Bool {
            guard let a, let b else { return false }
            return a.x == b.x && a.y == b.y
        }
        let count = LiveFollowPlannedAhead.chunkCount(pointCount: points.count)
        XCTAssertGreaterThan(count, 1)
        XCTAssertTrue(same(LiveFollowPlannedAhead.chunk(0, of: points).first, points.first))
        XCTAssertTrue(same(LiveFollowPlannedAhead.chunk(count - 1, of: points).last, points.last))
        for index in 1..<count {
            XCTAssertTrue(same(
                LiveFollowPlannedAhead.chunk(index - 1, of: points).last,
                LiveFollowPlannedAhead.chunk(index, of: points).first
            ))
        }
        let cumulative = LiveFollowPlannedAhead.cumulative(points)
        let atEnd = LiveFollowPlannedAhead.firstFixedChunk(
            along: cumulative.last ?? 0, cumulative: cumulative, metersPerPoint: MKMetersPerMapPointAtLatitude(41)
        )
        XCTAssertEqual(atEnd, count, "near the destination the lead runs to the end on its own")
    }

    func testDestinationSheetUsesFormSizingOnlyOnWideLayouts() {
        let phone = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact, vertical: .regular, size: CGSize(width: 390, height: 844), idiom: .phone
        )
        let landscape = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact, vertical: .compact, size: CGSize(width: 844, height: 390), idiom: .phone
        )
        let duoOpen = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular, vertical: .regular, size: CGSize(width: 680, height: 1100), idiom: .phone
        )
        let pad = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular, vertical: .regular, size: CGSize(width: 820, height: 1180), idiom: .pad
        )
        XCTAssertFalse(LiveFollowDestinationSheet.usesFormSizing(phone))
        XCTAssertFalse(LiveFollowDestinationSheet.usesFormSizing(landscape))
        XCTAssertTrue(LiveFollowDestinationSheet.usesFormSizing(duoOpen))
        XCTAssertTrue(LiveFollowDestinationSheet.usesFormSizing(pad))
    }
}

@MainActor
final class LiveFollowRouteChipContentTests: XCTestCase {
    private func store(_ result: Result<DrivingRoute, Error>, connected: Bool = true) -> PlannedRouteStore {
        PlannedRouteStore(provider: StaticRouteProvider(result: result), isConnected: { connected })
    }

    private let destination = PlannedRouteDestination(
        id: "place.office",
        name: "Office",
        coordinate: CLLocationCoordinate2D(latitude: 41.01, longitude: 29.0)
    )
    private let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)

    func testChipWalksThroughEveryState() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let route = DrivingRoute(coordinates: [origin, destination.coordinate], distanceMeters: 1_200, expectedTravelTime: 600)
        let ready = store(.success(route))
        XCTAssertEqual(LiveFollowRouteChipHost.content(for: ready, now: now), .setDestination)

        ready.setDestination(destination, origin: origin)
        XCTAssertEqual(LiveFollowRouteChipHost.content(for: ready, now: now), .loading)
        await ready.requestTask?.value
        XCTAssertEqual(
            LiveFollowRouteChipHost.content(for: ready, now: now),
            .estimate(
                distance: DateFormatters.formatDistance(1_200),
                arrival: DateFormatters.tripTime.string(from: now.addingTimeInterval(600))
            )
        )

        let offline = store(.success(route), connected: false)
        offline.setDestination(destination, origin: origin)
        XCTAssertEqual(LiveFollowRouteChipHost.content(for: offline, now: now), .offline)

        let failed = store(.failure(DrivingRouteError.noRoute))
        failed.setDestination(destination, origin: origin)
        await failed.requestTask?.value
        XCTAssertEqual(LiveFollowRouteChipHost.content(for: failed, now: now), .failed)
    }
}

private struct StaticRouteProvider: DrivingRouteProviding {
    let result: Result<DrivingRoute, Error>

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> DrivingRoute {
        try result.get()
    }
}
