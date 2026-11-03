import CoreLocation
import MapKit
import SwiftData
import XCTest
@testable import Milehound

@MainActor
final class FrequentRouteAggregateTests: XCTestCase {
    func testTwoTripsOnSamePairIncrementCount() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-1800),
            distanceMeters: 12_000,
            estimatedFuelCost: 80,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        first.startLatitude = 41.0
        first.startLongitude = 29.0
        first.endLatitude = 41.1
        first.endLongitude = 29.1
        let second = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 11_000,
            estimatedFuelCost: 70,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        second.startLatitude = 41.0
        second.startLongitude = 29.0
        second.endLatitude = 41.1
        second.endLongitude = 29.1
        context.insert(first)
        context.insert(second)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 2)
        XCTAssertEqual(rows.first?.totalDistanceMeters ?? 0, 23_000, accuracy: 0.1)
    }

    func testPrivacyZoneUsesSavedPlaceDisplay() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let home = SavedPlace(
            name: "Ev",
            latitude: 41.008,
            longitude: 28.978,
            radiusMeters: 400,
            kind: .home,
            isPrivacyZone: true
        )
        context.insert(home)
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 8_000,
            startPlaceName: "Ev",
            endPlaceName: "Levent"
        )
        trip.startLatitude = 41.0082
        trip.startLongitude = 28.9784
        trip.endLatitude = 41.08
        trip.endLongitude = 29.01
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let row = try context.fetch(FetchDescriptor<FrequentRouteAggregate>()).first
        XCTAssertEqual(row?.startDisplay, L10n.placeNearName("Ev"))
        XCTAssertEqual(row?.startLatitude ?? 0, home.latitude, accuracy: 0.0001)
    }

    func testRemoveDeletesEmptyAggregate() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 5_000,
            startPlaceName: "A",
            endPlaceName: "B"
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        TripRollupService.remove(trip, in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<FrequentRouteAggregate>()).count, 0)
    }
}

@MainActor
final class FrequentRouteOverlayBudgetTests: XCTestCase {
    func testCapsOverlayCountAtForty() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        for index in 0..<60 {
            let row = FrequentRouteAggregate(
                pairKey: "place:a\(index)→place:b\(index)",
                startKey: "place:a\(index)",
                endKey: "place:b\(index)"
            )
            row.count = 60 - index
            row.startLatitude = 41
            row.startLongitude = 29
            row.endLatitude = 41.1
            row.endLongitude = 29.1
            context.insert(row)
        }
        try context.save()
        let all = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        let top = FrequentRouteOverlayBudget.topAggregates(all)
        XCTAssertEqual(top.count, 40)
        XCTAssertEqual(top.first?.count, 60)
        XCTAssertEqual(top.last?.count, 21)
    }

    func testHabitCorridorsKeepRepeatedNeighborhoodRoutesOnly() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        func insert(key: String, count: Int, start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
            let row = FrequentRouteAggregate(pairKey: key, startKey: key, endKey: key)
            row.count = count
            row.startLatitude = start.latitude
            row.startLongitude = start.longitude
            row.endLatitude = end.latitude
            row.endLongitude = end.longitude
            context.insert(row)
        }
        insert(
            key: "home→work",
            count: 40,
            start: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            end: CLLocationCoordinate2D(latitude: 41.080, longitude: 29.010)
        )
        insert(
            key: "home→gym",
            count: 12,
            start: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            end: CLLocationCoordinate2D(latitude: 41.050, longitude: 28.995)
        )
        insert(
            key: "mall→cafe",
            count: 4,
            start: CLLocationCoordinate2D(latitude: 41.040, longitude: 29.000),
            end: CLLocationCoordinate2D(latitude: 41.055, longitude: 29.020)
        )
        insert(
            key: "once→around",
            count: 1,
            start: CLLocationCoordinate2D(latitude: 41.010, longitude: 28.980),
            end: CLLocationCoordinate2D(latitude: 41.020, longitude: 28.990)
        )
        insert(
            key: "izmir→cesme",
            count: 18,
            start: CLLocationCoordinate2D(latitude: 38.423, longitude: 27.143),
            end: CLLocationCoordinate2D(latitude: 38.324, longitude: 26.303)
        )
        try context.save()
        let all = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        let habits = FrequentRouteOverlayBudget.habitCorridors(all)
        XCTAssertEqual(habits.map(\.pairKey), ["home→work", "home→gym", "mall→cafe"])
        XCTAssertFalse(habits.contains { $0.pairKey == "once→around" })
        XCTAssertFalse(habits.contains { $0.pairKey == "izmir→cesme" })
    }

    func testRoadPathDecimateKeepsEnds() {
        let coords = (0..<200).map { index in
            CLLocationCoordinate2D(latitude: 38.4 + Double(index) * 0.001, longitude: 27.1)
        }
        let slim = FrequentRouteRoadPathCache.decimate(coords, maxCount: 20)
        XCTAssertEqual(slim.count, 20)
        XCTAssertEqual(slim.first?.latitude ?? 0, coords.first?.latitude ?? 1, accuracy: 0.0001)
        XCTAssertEqual(slim.last?.latitude ?? 0, coords.last?.latitude ?? 1, accuracy: 0.0001)
    }
}

@MainActor
final class FrequentRouteMergeDeltaTests: XCTestCase {
    func testMergeLeavesSingleAggregate() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-1800),
            distanceMeters: 8_000,
            startPlaceName: "A",
            endPlaceName: "B"
        )
        first.startLatitude = 41
        first.startLongitude = 29
        first.endLatitude = 41.05
        first.endLongitude = 29.05
        let second = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 9_000,
            startPlaceName: "A",
            endPlaceName: "B"
        )
        second.startLatitude = 41
        second.startLongitude = 29
        second.endLatitude = 41.05
        second.endLongitude = 29.05
        context.insert(first)
        context.insert(second)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<FrequentRouteAggregate>()).first?.count, 2)

        _ = try TripMergeService.merge(trips: [first, second], into: context)
        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 1)
    }

    func testMapCameraFitsTheFeaturedCorridorNotARegionalPad() {
        let start = CLLocationCoordinate2D(latitude: 37.323, longitude: -122.032)
        let end = CLLocationCoordinate2D(latitude: 37.379, longitude: -122.118)
        let focused = FrequentRoutesMapCamera.visibleRect(start: start, end: end)
        var regional = MKMapRect.null
        for coordinate in [
            start,
            end,
            CLLocationCoordinate2D(latitude: 37.70, longitude: -122.45),
            CLLocationCoordinate2D(latitude: 37.55, longitude: -121.97)
        ] {
            let point = MKMapPoint(coordinate)
            regional = regional.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        regional = regional.insetBy(dx: -120_000, dy: -120_000)
        XCTAssertLessThan(focused.size.width, regional.size.width * 0.45)
        XCTAssertLessThan(focused.size.height, regional.size.height * 0.45)
        XCTAssertFalse(focused.isNull)
        XCTAssertFalse(focused.isEmpty)
    }

    func testMapCameraStaysCloseToTheCorridor() {
        let start = CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978)
        let end = CLLocationCoordinate2D(latitude: 41.036, longitude: 29.000)
        let focused = FrequentRoutesMapCamera.visibleRect(start: start, end: end)
        var corridor = MKMapRect.null
        for coordinate in [start, end] {
            let point = MKMapPoint(coordinate)
            corridor = corridor.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        XCTAssertLessThan(focused.size.width, corridor.size.width * 2.6 + 10_000)
        XCTAssertLessThan(focused.size.height, corridor.size.height * 2.6 + 10_000)
        XCTAssertEqual(
            FrequentRoutesMapCamera.edgePadding(for: CGSize(width: 320, height: 180)).bottom,
            FrequentRoutesMapCamera.edgePadding.bottom,
            accuracy: 0.1
        )
        XCTAssertEqual(
            FrequentRoutesMapCamera.edgePadding(for: CGSize(width: 390, height: 844)).bottom,
            FrequentRoutesMapCamera.edgePadding.bottom,
            accuracy: 0.1
        )
    }
}

@MainActor
final class FrequentRouteClusteringTests: XCTestCase {
    func testNearbyEndpointsWithDifferentNamesMerge() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = makeTrip(
            startName: "Foo Cad.",
            endName: "Bar Sk.",
            start: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            end: CLLocationCoordinate2D(latitude: 41.036, longitude: 29.000)
        )
        let second = makeTrip(
            startName: "Foo Caddesi",
            endName: "Bar Sokak",
            start: CLLocationCoordinate2D(latitude: 41.009, longitude: 28.979),
            end: CLLocationCoordinate2D(latitude: 41.037, longitude: 29.001),
            startedAt: Date().addingTimeInterval(-900)
        )
        context.insert(first)
        context.insert(second)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 2)
    }

    func testReverseDirectionMergesIntoOneCorridor() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let outbound = makeTrip(
            startName: "Ev",
            endName: "Ofis",
            start: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            end: CLLocationCoordinate2D(latitude: 41.080, longitude: 29.010)
        )
        let inbound = makeTrip(
            startName: "Ofis",
            endName: "Ev",
            start: CLLocationCoordinate2D(latitude: 41.080, longitude: 29.010),
            end: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            startedAt: Date().addingTimeInterval(-900)
        )
        context.insert(outbound)
        context.insert(inbound)
        TripRollupService.add(outbound, in: context)
        TripRollupService.add(inbound, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 2)
    }

    func testDistantSameNamesStaySplit() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let istanbul = makeTrip(
            startName: "Ev",
            endName: "Ofis",
            start: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            end: CLLocationCoordinate2D(latitude: 41.080, longitude: 29.010)
        )
        let izmir = makeTrip(
            startName: "Ev",
            endName: "Ofis",
            start: CLLocationCoordinate2D(latitude: 38.423, longitude: 27.143),
            end: CLLocationCoordinate2D(latitude: 38.462, longitude: 27.218),
            startedAt: Date().addingTimeInterval(-900)
        )
        context.insert(istanbul)
        context.insert(izmir)
        TripRollupService.add(istanbul, in: context)
        TripRollupService.add(izmir, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 2)
    }

    func testRouteRebuildMergesHistoryWithoutTouchingAchievements() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = makeTrip(
            startName: "Eski Etiket",
            endName: "Ofis A",
            start: CLLocationCoordinate2D(latitude: 41.008, longitude: 28.978),
            end: CLLocationCoordinate2D(latitude: 41.036, longitude: 29.000)
        )
        let second = makeTrip(
            startName: "Yeni Etiket",
            endName: "Ofis B",
            start: CLLocationCoordinate2D(latitude: 41.009, longitude: 28.979),
            end: CLLocationCoordinate2D(latitude: 41.037, longitude: 29.001),
            startedAt: Date().addingTimeInterval(-900)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let existing = AchievementProgress(achievementID: AchievementID.firstTrip.rawValue, currentValue: 1)
        existing.unlockedAt = first.endedAt
        context.insert(existing)
        try context.save()

        await PremiumDerivedMaintenance.rebuildRoutes(container: container)

        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 2)
        let progress = try context.fetch(FetchDescriptor<AchievementProgress>())
        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress.first?.currentValue, 1)
    }

    private func makeTrip(
        startName: String,
        endName: String,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        startedAt: Date = Date().addingTimeInterval(-1_800)
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_200),
            distanceMeters: 8_000,
            startPlaceName: startName,
            endPlaceName: endName
        )
        trip.startLatitude = start.latitude
        trip.startLongitude = start.longitude
        trip.endLatitude = end.latitude
        trip.endLongitude = end.longitude
        return trip
    }
}
