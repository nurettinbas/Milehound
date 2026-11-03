import CoreLocation
import SwiftData
import XCTest
@testable import Milehound

/// Regression shield for the bug that silently destroyed long recordings: post-processing used
/// to replace a trip's points with a simplified subset, so a 1922-point drive came back as 143.
@MainActor
final class TripPostProcessorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainerFactory.makeInMemory()
    }

    func testProcessKeepsEveryRecordedPoint() async throws {
        let pointCount = 1500
        let trip = makeTrip(pointCount: pointCount)
        container.mainContext.insert(trip)
        for point in trip.points { container.mainContext.insert(point) }
        try container.mainContext.save()

        await TripPostProcessor.process(tripUUID: trip.id, container: container)

        let stored = try container.mainContext.fetch(FetchDescriptor<Trip>())
        let reloaded = try XCTUnwrap(stored.first { $0.id == trip.id })
        XCTAssertEqual(reloaded.points.count, pointCount)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TripPoint>()).count, pointCount)
    }

    func testProcessKeepsSpeedDataIntact() async throws {
        let trip = makeTrip(pointCount: 1200)
        container.mainContext.insert(trip)
        for point in trip.points { container.mainContext.insert(point) }
        try container.mainContext.save()

        await TripPostProcessor.process(tripUUID: trip.id, container: container)

        let stored = try container.mainContext.fetch(FetchDescriptor<Trip>())
        let reloaded = try XCTUnwrap(stored.first { $0.id == trip.id })
        XCTAssertEqual(reloaded.sortedPoints.filter { ($0.speedMps ?? 0) > 0 }.count, 1200)
    }

    func testProcessWritesPendingCategoryWithoutChangingCategory() async throws {
        let settings = AppSettings.shared
        let previousEnabled = settings.smartCategorySuggestionsEnabled
        settings.smartCategorySuggestionsEnabled = true
        defer { settings.smartCategorySuggestionsEnabled = previousEnabled }

        let home = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let work = CLLocationCoordinate2D(latitude: 41.1, longitude: 29.1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startedAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 11))!
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: 8_000,
            category: .personal,
            startPlaceName: "Ev",
            endPlaceName: "İş"
        )
        trip.startLatitude = home.latitude
        trip.startLongitude = home.longitude
        trip.endLatitude = work.latitude
        trip.endLongitude = work.longitude
        let points = [
            TripPoint(
                timestamp: startedAt,
                latitude: home.latitude,
                longitude: home.longitude,
                sequence: 0,
                speedMps: 10,
                trip: trip
            ),
            TripPoint(
                timestamp: startedAt.addingTimeInterval(900),
                latitude: 41.05,
                longitude: 29.05,
                sequence: 1,
                speedMps: 12,
                trip: trip
            ),
            TripPoint(
                timestamp: startedAt.addingTimeInterval(1_800),
                latitude: work.latitude,
                longitude: work.longitude,
                sequence: 2,
                speedMps: 8,
                trip: trip
            )
        ]
        trip.points = points
        container.mainContext.insert(trip)
        for point in points { container.mainContext.insert(point) }
        container.mainContext.insert(
            SavedPlace(name: "Ev", latitude: home.latitude, longitude: home.longitude, kind: .home)
        )
        container.mainContext.insert(
            SavedPlace(name: "İş", latitude: work.latitude, longitude: work.longitude, kind: .work)
        )
        try container.mainContext.save()

        await TripPostProcessor.process(tripUUID: trip.id, container: container)

        let reloaded = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<Trip>()).first { $0.id == trip.id }
        )
        XCTAssertEqual(reloaded.pendingSuggestedCategoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(reloaded.pendingSuggestionReason, .place)
        XCTAssertEqual(reloaded.categoryID, BuiltInCategory.personalID.uuidString)
        XCTAssertEqual(reloaded.categoryOrigin, .default)
        XCTAssertEqual(reloaded.points.count, 3)
    }

    private func makeTrip(pointCount: Int) -> Trip {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(startedAt: start, endedAt: start.addingTimeInterval(Double(pointCount)), distanceMeters: 24_000)

        let latitude = 38.42
        let metersPerDegreeLongitude = 111_320 * cos(latitude * .pi / 180)
        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: start.addingTimeInterval(Double(index)),
                latitude: latitude,
                longitude: 27.14 + (Double(index) * 14) / metersPerDegreeLongitude,
                sequence: index,
                speedMps: 14,
                trip: trip
            )
            trip.points.append(point)
        }
        return trip
    }
}
