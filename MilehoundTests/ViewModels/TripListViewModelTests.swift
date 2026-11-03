import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

final class TripListViewModelTests: XCTestCase {
    func testRouteSummaryUsesPlaceNames() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1200,
            startPlaceName: "Home",
            endPlaceName: "Office"
        )

        let summary = TripListViewModel.routeSummary(for: trip)

        XCTAssertTrue(summary.contains("Home"))
        XCTAssertTrue(summary.contains("Office"))
    }

    func testStartSummaryUsesSavedPlaceName() {
        let office = SavedPlace(
            name: "Office",
            latitude: 41.05,
            longitude: 29.0,
            radiusMeters: 200,
            kind: .work
        )
        let summary = TripListViewModel.startSummary(
            coordinate: CLLocationCoordinate2D(latitude: 41.05, longitude: 29.0),
            places: [office],
            privacyRadius: 500
        )
        XCTAssertEqual(summary, "Office")
    }

    func testStartSummaryUsesNearNameForHomePrivacyZone() {
        let home = SavedPlace(
            name: "Home",
            latitude: 41.0082,
            longitude: 28.9784,
            radiusMeters: 500,
            kind: .home,
            isPrivacyZone: true
        )
        let summary = TripListViewModel.startSummary(
            coordinate: CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784),
            places: [home],
            privacyRadius: 500
        )
        XCTAssertEqual(summary, L10n.placeNearName("Home"))
    }

    func testStartSummaryFallsBackWhenNoCoordinate() {
        let summary = TripListViewModel.startSummary(
            coordinate: nil,
            places: [],
            privacyRadius: 500
        )
        XCTAssertEqual(summary, "—")
    }

    func testStartedRichBodyUsesFromPrefix() {
        let body = String(format: L10n.string("trip.started.rich.body"), "Home")
        XCTAssertTrue(body.contains("Home"))
        // EN body: "From Home" — TR body ends with " konumundan"
        XCTAssertTrue(body.hasPrefix("From ") || body.hasSuffix(" konumundan"))
    }

    func testRouteSummaryAppliesPrivacyDisplayName() {
        let home = SavedPlace(
            name: "Home",
            latitude: 41.0082,
            longitude: 28.9784,
            radiusMeters: 500,
            kind: .home,
            isPrivacyZone: true
        )
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1200,
            startPlaceName: "Exact Home",
            endPlaceName: "Office"
        )
        trip.points = [
            TripPoint(timestamp: trip.startedAt, latitude: 41.0082, longitude: 28.9784, sequence: 0, trip: trip),
            TripPoint(timestamp: trip.endedAt!, latitude: 41.05, longitude: 29.0, sequence: 1, trip: trip)
        ]

        let summary = TripListViewModel.routeSummary(for: trip, places: [home], privacyRadius: 500)

        XCTAssertFalse(summary.contains("Exact Home"))
        XCTAssertTrue(summary.contains("Office") || summary.contains("→"))
    }

    func testMatchesSearchByNote() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1000,
            note: "Commute"
        )

        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "comm"))
        XCTAssertFalse(TripListViewModel.matchesSearch(trip, searchText: "holiday"))
    }

    func testMatchesSearchEmptyQueryMatchesAll() {
        let trip = Trip(startedAt: Date(), endedAt: Date(), distanceMeters: 100)

        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: ""))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "   "))
    }

    func testSearchActivityVisibleWhileTypingOrApplying() {
        XCTAssertTrue(
            TripListViewModel.isSearchActivityVisible(
                searchText: "ev",
                debouncedSearchText: "",
                isApplying: false
            )
        )
        XCTAssertTrue(
            TripListViewModel.isSearchActivityVisible(
                searchText: "ev",
                debouncedSearchText: "ev",
                isApplying: true
            )
        )
        XCTAssertFalse(
            TripListViewModel.isSearchActivityVisible(
                searchText: "ev",
                debouncedSearchText: "ev",
                isApplying: false
            )
        )
        XCTAssertFalse(
            TripListViewModel.isSearchActivityVisible(
                searchText: "",
                debouncedSearchText: "",
                isApplying: true
            )
        )
        XCTAssertFalse(
            TripListViewModel.isSearchActivityVisible(
                searchText: "   ",
                debouncedSearchText: "",
                isApplying: false
            )
        )
    }

    func testMatchesSearchFindsPrivacyMaskedHomeName() throws {
        let home = SavedPlace(
            name: "Ev",
            latitude: 41.0082,
            longitude: 28.9784,
            radiusMeters: 300,
            kind: .home,
            isPrivacyZone: true
        )
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1200,
            startAddress: "Old Street",
            endPlaceName: "Ofis"
        )
        trip.startLatitude = 41.0082
        trip.startLongitude = 28.9784
        trip.endLatitude = 41.05
        trip.endLongitude = 29.0

        PlaceMatchingService.matchPlaces(for: trip, places: [home], privacyRadius: 500)
        TripDerivedMetrics.refreshSearchIndex(for: trip, places: [home], privacyRadius: 500)

        let summary = TripListViewModel.routeSummary(for: trip, places: [home], privacyRadius: 500)
        XCTAssertEqual(
            summary.split(separator: "→").first?.trimmingCharacters(in: .whitespaces),
            L10n.placeNearName("Ev")
        )
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "ev", places: [home], privacyRadius: 500))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "Ev", places: [home], privacyRadius: 500))
        XCTAssertTrue(SearchFolding.fold(try XCTUnwrap(trip.searchIndex)).contains(SearchFolding.fold("Ev")))
    }

    func testMatchesSearchUsesLivePlacesWhenIndexIsStale() {
        let home = SavedPlace(
            name: "Ev",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300,
            kind: .home,
            isPrivacyZone: true
        )
        let trip = Trip(
            startedAt: Date(),
            endedAt: Date(),
            startAddress: "Old Street"
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.searchIndex = "old street"

        XCTAssertTrue(
            TripListViewModel.matchesSearch(trip, searchText: "ev", places: [home], privacyRadius: 500)
        )
        XCTAssertFalse(
            TripListViewModel.matchesSearch(trip, searchText: "bakkal", places: [home], privacyRadius: 500)
        )
    }

    func testDurationAndDistanceTextForCompletedTrip() {
        let startedAt = Date().addingTimeInterval(-3900)
        let endedAt = Date()
        let trip = Trip(startedAt: startedAt, endedAt: endedAt, distanceMeters: 12_400)

        XCTAssertFalse(TripListViewModel.durationText(for: trip).isEmpty)
        XCTAssertFalse(TripListViewModel.distanceText(for: trip).isEmpty)
        XCTAssertNotNil(TripListViewModel.fuelText(for: trip))
    }

    func testFuelTextUsesAvgFuelNotEstimated() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 10_000,
            estimatedFuelCost: 40,
            dynamicFuelCost: 99
        )
        XCTAssertEqual(
            TripListViewModel.fuelText(for: trip),
            FuelCostCalculator.formatCost(40)
        )
    }
}

@MainActor
final class TripListPageVehicleFilterTests: XCTestCase {
    func testDescriptorFiltersByVehicleID() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let vehicleA = UUID()
        let vehicleB = UUID()
        let now = Date()

        let tripA = Trip(
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000),
            distanceMeters: 1_000,
            vehicleID: vehicleA
        )
        let tripB = Trip(
            startedAt: now.addingTimeInterval(-2_400),
            endedAt: now.addingTimeInterval(-1_800),
            distanceMeters: 2_000,
            vehicleID: vehicleB
        )
        let tripNone = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500
        )
        context.insert(tripA)
        context.insert(tripB)
        context.insert(tripNone)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(vehicleFilter: .vehicle(vehicleA)),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(filtered.map(\.id), [tripA.id])
    }

    func testDescriptorFiltersUnassignedVehicle() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let vehicleA = UUID()
        let now = Date()
        let tripA = Trip(
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000),
            distanceMeters: 1_000,
            vehicleID: vehicleA
        )
        let tripNone = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500
        )
        context.insert(tripA)
        context.insert(tripNone)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(vehicleFilter: .unassigned),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(filtered.map(\.id), [tripNone.id])
    }

    func testFiltersIsActiveWhenVehicleSelected() {
        XCTAssertTrue(TripListPage.Filters(vehicleFilter: .vehicle(UUID())).isActive)
        XCTAssertTrue(TripListPage.Filters(vehicleFilter: .unassigned).isActive)
        XCTAssertFalse(TripListPage.Filters().isActive)
    }
}

@MainActor
final class TripListPagePlaceFilterTests: XCTestCase {
    func testDescriptorIncludesStartOrEndPlaceMatch() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()

        let startMatch = Trip(
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000),
            distanceMeters: 1_000,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let endMatch = Trip(
            startedAt: now.addingTimeInterval(-2_400),
            endedAt: now.addingTimeInterval(-1_800),
            distanceMeters: 2_000,
            startPlaceName: "Market",
            endPlaceName: "Ev"
        )
        let neither = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500,
            startPlaceName: "Market",
            endPlaceName: "Ofis"
        )
        context.insert(startMatch)
        context.insert(endMatch)
        context.insert(neither)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(placeName: "Ev"),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(Set(filtered.map(\.id)), Set([startMatch.id, endMatch.id]))
    }

    func testDescriptorWithoutPlaceReturnsAllCompleted() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()
        let trip = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500,
            startPlaceName: "Ev"
        )
        context.insert(trip)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(filtered.map(\.id), [trip.id])
    }

    func testDescriptorSearchFindsFoldedHomeName() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()
        let home = SavedPlace(
            name: "Ev",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300,
            kind: .home,
            isPrivacyZone: true
        )
        let trip = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500,
            startAddress: "Old Street"
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        let other = Trip(
            startedAt: now.addingTimeInterval(-2_400),
            endedAt: now.addingTimeInterval(-1_800),
            distanceMeters: 400,
            startAddress: "Market"
        )
        context.insert(home)
        context.insert(trip)
        context.insert(other)
        PlaceMatchingService.matchPlaces(for: trip, places: [home], privacyRadius: 500)
        TripDerivedMetrics.refreshSearchIndex(for: trip, places: [home], privacyRadius: 500)
        TripDerivedMetrics.refreshSearchIndex(for: other, places: [home], privacyRadius: 500)
        try context.save()

        let fetched = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(searchText: "ev"),
                limit: TripListPage.pageSize
            )
        )
        let matching = fetched.filter {
            TripListViewModel.matchesSearch($0, searchText: "ev", places: [home], privacyRadius: 500)
        }

        XCTAssertEqual(matching.map(\.id), [trip.id])
    }

    func testFiltersIsActiveWhenPlaceSelected() {
        XCTAssertTrue(TripListPage.Filters(placeName: "Ev").isActive)
        XCTAssertFalse(TripListPage.Filters().isActive)
    }

    func testTripPlaceFilterMatchesStartOrEnd() {
        XCTAssertTrue(
            TripPlaceFilter.matches(
                startPlaceName: "Ev",
                endPlaceName: "Ofis",
                placeName: "Ev"
            )
        )
        XCTAssertTrue(
            TripPlaceFilter.matches(
                startPlaceName: "Market",
                endPlaceName: "Ev",
                placeName: "Ev"
            )
        )
        XCTAssertFalse(
            TripPlaceFilter.matches(
                startPlaceName: "Market",
                endPlaceName: "Ofis",
                placeName: "Ev"
            )
        )
        XCTAssertTrue(
            TripPlaceFilter.matches(
                startPlaceName: "Market",
                endPlaceName: "Ofis",
                placeName: nil
            )
        )
    }
}
