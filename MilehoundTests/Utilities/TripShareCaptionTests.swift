import CoreLocation
import XCTest
@testable import Milehound

@MainActor
final class TripShareCaptionTests: XCTestCase {
    func testWhenLineIncludesStartAndEndTimes() {
        let started = Date(timeIntervalSince1970: 1_720_000_000)
        let ended = started.addingTimeInterval(11 * 60 + 12)
        let trip = Trip(
            startedAt: started,
            endedAt: ended,
            distanceMeters: 3300,
            startPlaceName: "Opti",
            endPlaceName: "Ev"
        )

        let line = TripShareCaption.whenLine(for: trip)
        let startTime = DateFormatters.tripTime.string(from: started)
        let endTime = DateFormatters.tripTime.string(from: ended)
        let date = DateFormatters.tripDateOnly.string(from: started)

        XCTAssertTrue(line.contains(date), line)
        XCTAssertTrue(line.contains(startTime), line)
        XCTAssertTrue(line.contains(endTime), line)
    }

    func testCaptionIncludesRouteAndMetrics() {
        let started = Date(timeIntervalSince1970: 1_720_000_000)
        let ended = started.addingTimeInterval(600)
        let trip = Trip(
            startedAt: started,
            endedAt: ended,
            distanceMeters: 3300,
            estimatedFuelCost: 23,
            startPlaceName: "Opti",
            endPlaceName: "Ev"
        )
        trip.points = [
            TripPoint(
                timestamp: started,
                latitude: 38.32,
                longitude: 27.13,
                sequence: 0,
                speedMps: 10,
                trip: trip
            ),
            TripPoint(
                timestamp: started.addingTimeInterval(200),
                latitude: 38.325,
                longitude: 27.135,
                sequence: 1,
                speedMps: 14,
                trip: trip
            ),
            TripPoint(
                timestamp: ended,
                latitude: 38.33,
                longitude: 27.14,
                sequence: 2,
                speedMps: 12,
                trip: trip
            )
        ]

        let caption = TripShareCaption.build(trip: trip, places: [], privacyRadius: 0)
        let lines = caption.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3, caption)
        XCTAssertTrue(lines[0].contains("Opti"), caption)
        XCTAssertTrue(lines[0].contains("Ev"), caption)
        XCTAssertFalse(lines[2].isEmpty, caption)
    }

    func testWhenLineWithoutEndUsesStartOnly() {
        let started = Date(timeIntervalSince1970: 1_720_000_000)
        let trip = Trip(startedAt: started, distanceMeters: 100)

        let line = TripShareCaption.whenLine(for: trip)
        let endTime = DateFormatters.tripTime.string(from: started.addingTimeInterval(3600))
        XCTAssertFalse(line.contains("– \(endTime)"), line)
        XCTAssertTrue(line.contains(DateFormatters.tripTime.string(from: started)), line)
    }

    func testShareCardIsStorySized() {
        XCTAssertEqual(TripShareCardRenderer.defaultSize, RecapShareRenderer.pixelSize)
        XCTAssertEqual(
            TripShareCardRenderer.defaultSize.width / TripShareCardRenderer.defaultSize.height,
            9.0 / 16.0,
            accuracy: 0.001
        )
    }

    func testShareCardThemeFollowsPaletteInsteadOfFixedCharcoal() {
        let sand = TripShareCardTheme(palette: .sand, scheme: .light)
        let skyDark = TripShareCardTheme(palette: .sky, scheme: .dark)
        XCTAssertEqual(sand.title, UIColor.white)
        XCTAssertEqual(sand.chart, sand.atmosphere.tint.uiColor)
        XCTAssertEqual(skyDark.title, UIColor.white)
        XCTAssertGreaterThan(sand.tileFill.cgColor.alpha, skyDark.tileFill.cgColor.alpha)
    }
}
