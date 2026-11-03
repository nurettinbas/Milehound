import CoreGraphics
import CoreLocation
import XCTest
@testable import Milehound

final class TravelJournalPanelLayoutTests: XCTestCase {
    func testCompactLeavesMostOfTheMapVisible() {
        let compact = TravelJournalPanelLayout.compactHeight(containerHeight: 852)
        XCTAssertLessThan(compact, 852 * 0.40)
        XCTAssertGreaterThanOrEqual(compact, TravelJournalPanelLayout.compactMinimum)
        XCTAssertGreaterThan(852 - compact, compact)
    }

    func testExpandedKeepsMapPeek() {
        let mapPeek: CGFloat = 120
        let expanded = TravelJournalPanelLayout.expandedHeight(containerHeight: 852, mapPeek: mapPeek)
        XCTAssertLessThanOrEqual(expanded, 852 - mapPeek)
        XCTAssertGreaterThan(expanded, TravelJournalPanelLayout.compactHeight(containerHeight: 852))
    }

    func testDragUpFromCompactGrowsTowardExpanded() {
        let height = TravelJournalPanelLayout.draggedHeight(
            detent: .compact,
            translation: -200,
            containerHeight: 852,
            mapPeek: 120
        )
        XCTAssertGreaterThan(height, TravelJournalPanelLayout.compactHeight(containerHeight: 852))
    }

    func testFlickUpSnapsToExpanded() {
        let snapped = TravelJournalPanelLayout.snappedDetent(
            predictedTranslation: -320,
            from: .compact,
            containerHeight: 852,
            mapPeek: 120
        )
        XCTAssertEqual(snapped, .expanded)
    }

    func testFlickDownSnapsToCompact() {
        let snapped = TravelJournalPanelLayout.snappedDetent(
            predictedTranslation: 320,
            from: .expanded,
            containerHeight: 852,
            mapPeek: 120
        )
        XCTAssertEqual(snapped, .compact)
    }
}

final class TravelJournalMapBudgetTests: XCTestCase {
    func testSixtyThreeTripsStayAtOrBelowCap() {
        let counts = Array(repeating: 400, count: 63)
        let allocated = TravelJournalMapBudget.allocate(pointCounts: counts, totalCap: 4000)
        XCTAssertEqual(allocated.count, 63)
        XCTAssertLessThanOrEqual(allocated.reduce(0, +), 4000)
        XCTAssertTrue(allocated.allSatisfy { $0 >= 2 })
    }

    func testDownsampleKeepsEndpoints() {
        let path = (0..<20).map {
            CLLocationCoordinate2D(latitude: Double($0), longitude: Double($0))
        }
        let sampled = TravelJournalMapBudget.downsample(path, to: 5)
        XCTAssertEqual(sampled.count, 5)
        XCTAssertEqual(sampled.first?.latitude, 0)
        XCTAssertEqual(sampled.last?.latitude, 19)
    }

    func testShortPathUnchangedWhenUnderCap() {
        XCTAssertEqual(TravelJournalMapBudget.allocate(pointCounts: [10, 20, 5], totalCap: 4000), [10, 20, 5])
    }
}

final class TravelJournalSuggesterTests: XCTestCase {
    private let home = TravelJournalHomeSnapshot(latitude: 41.0, longitude: 29.0, radiusMeters: 300)
    private let calendar = Calendar(identifier: .gregorian)

    func testWeekdayCommuteIsNotATravel() {
        let monday = date(2026, 3, 2, 8)
        let trips = [
            trip("a", start: monday, hours: 1, fromHome: true, toHome: false),
            trip("b", start: monday.addingTimeInterval(9 * 3600), hours: 1, fromHome: false, toHome: true)
        ]
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar))
    }

    func testAwayWeekendWithTwoNightsSuggests() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("fri", start: friday, hours: 3, fromHome: false, toHome: false, distance: 80_000),
            trip("sat", start: friday.addingTimeInterval(24 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000),
            trip("sun", start: friday.addingTimeInterval(48 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000)
        ]
        let suggestion = TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.tripIDs.count, 3)
    }

    func testNoHomePlaceYieldsNoSuggestion() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("fri", start: friday, hours: 3, fromHome: false, toHome: false, distance: 200_000)
        ]
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: [], calendar: calendar))
    }

    func testDismissedFingerprintIsSkipped() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("fri", start: friday, hours: 3, fromHome: false, toHome: false, distance: 80_000),
            trip("sat", start: friday.addingTimeInterval(24 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000),
            trip("sun", start: friday.addingTimeInterval(48 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000)
        ]
        let first = TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar)
        XCTAssertNotNil(first)
        let skipped = TravelJournalSuggester.suggest(
            trips: trips,
            homes: [home],
            dismissedFingerprints: [first!.fingerprint],
            calendar: calendar
        )
        XCTAssertNil(skipped)
    }

    func testLongDistanceAwayDaySuggestsWithoutTwoNights() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("km", start: friday, hours: 4, fromHome: false, toHome: false, distance: 150_000)
        ]
        let suggestion = TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.tripIDs.count, 1)
    }

    func testInProgressTripIsIgnored() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("km", start: friday, hours: 4, fromHome: false, toHome: false, distance: 150_000, isInProgress: true)
        ]
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar))
    }

    @MainActor
    func testLoaderMatchesSuggestForStoredTrips() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let friday = date(2026, 3, 6, 18)
        let trip = Trip(
            startedAt: friday,
            endedAt: friday.addingTimeInterval(4 * 3600),
            distanceMeters: 150_000,
            startPlaceName: "Away",
            endPlaceName: "Away"
        )
        trip.startLatitude = 40
        trip.startLongitude = 29
        trip.endLatitude = 40
        trip.endLongitude = 29
        context.insert(trip)
        try context.save()

        let homes = [home]
        let loader = TravelSuggestionLoader(modelContainer: container)
        let loaded = await loader.suggestion(
            homes: homes,
            existingJournalRanges: [],
            dismissedFingerprints: [],
            calendar: calendar
        )
        let direct = TravelJournalSuggester.suggest(
            trips: [TravelJournalSuggester.snapshot(from: trip)],
            homes: homes,
            calendar: calendar
        )
        XCTAssertEqual(loaded, direct)
        XCTAssertNotNil(loaded)
    }

    func testWorkOnlyPlaceYieldsNoSuggestion() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("km", start: friday, hours: 4, fromHome: false, toHome: false, distance: 200_000)
        ]
        let work = SavedPlace(name: "Office", latitude: 41.0, longitude: 29.0, kind: .work)
        let homes = TravelJournalSuggester.homeSnapshots(from: [work])
        XCTAssertTrue(homes.isEmpty)
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: homes, calendar: calendar))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func trip(
        _ id: String,
        start: Date,
        hours: Double,
        fromHome: Bool,
        toHome: Bool,
        distance: Double = 10_000,
        isInProgress: Bool = false
    ) -> TravelJournalTripSnapshot {
        let startLat = fromHome ? 41.0 : 40.0
        let endLat = toHome ? 41.0 : 40.0
        return TravelJournalTripSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(id.padding(toLength: 12, withPad: "0", startingAt: 0))") ?? UUID(),
            startedAt: start,
            endedAt: isInProgress ? nil : start.addingTimeInterval(hours * 3600),
            distanceMeters: distance,
            startLatitude: startLat,
            startLongitude: 29.0,
            endLatitude: endLat,
            endLongitude: 29.0,
            startPlaceName: fromHome ? "Home" : "Away",
            endPlaceName: toHome ? "Home" : "Away",
            journalID: nil
        )
    }
}
