import XCTest
@testable import Milehound

@MainActor
final class ExportServiceTests: XCTestCase {
    func testCSVContainsHeader() {
        let csv = ExportService.exportCSV(trips: [])
        XCTAssertTrue(csv.contains("distanceKm"))
        XCTAssertTrue(csv.contains("dynamicFuelCost"))
        XCTAssertTrue(csv.contains("category"))
        XCTAssertFalse(csv.contains(",label,"))
        XCTAssertFalse(csv.hasPrefix("label,"))
        XCTAssertFalse(csv.contains("start,end,label,"))
    }

    func testGPXContainsTrackTag() {
        let gpx = ExportService.exportGPX(trips: [], blurCoordinates: false)
        XCTAssertTrue(gpx.contains("<gpx"))
        XCTAssertTrue(gpx.contains("</gpx>"))
    }

    func testKMLContainsDocument() {
        let kml = ExportService.exportKML(trips: [], blurCoordinates: false)
        XCTAssertTrue(kml.contains("<kml"))
        XCTAssertTrue(kml.contains("<Document>"))
    }

    func testCSVIncludesTripDataRow() {
        let trip = PreviewData.sampleTrip
        let csv = ExportService.exportCSV(trips: [trip])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(trip.id.uuidString))
        XCTAssertTrue(lines[1].contains("14.20") || lines[1].contains("14.2"))
    }

    func testCSVIncludesDynamicFuelCost() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5_000,
            estimatedFuelCost: 80,
            dynamicFuelCost: 95
        )
        let csv = ExportService.exportCSV(trips: [trip])
        let lines = csv.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(String(lines[0]).contains("dynamicFuelCost"))
        XCTAssertTrue(String(lines[1]).contains("95"))
    }

    func testGPXIncludesTrackPointsForTrip() {
        let trip = PreviewData.sampleTrip
        let gpx = ExportService.exportGPX(trips: [trip], blurCoordinates: false)

        XCTAssertTrue(gpx.contains("<trkpt"))
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt").count - 1, trip.sortedPoints.count)
    }

    func testKMLIncludesPlacemarkForTrip() {
        let trip = PreviewData.sampleTrip
        let kml = ExportService.exportKML(trips: [trip], blurCoordinates: false)

        XCTAssertTrue(kml.contains("<Placemark>"))
        XCTAssertTrue(kml.contains("<LineString>"))
        XCTAssertFalse(kml.contains("İş"), "KML name must not use retired trip labels")
    }
}
