import CoreLocation
import XCTest
@testable import Milehound

final class CoordinateParsingTests: XCTestCase {
    func testParseCommaSeparated() {
        let coordinate = CoordinateParsing.parse("41.01, 28.97")
        XCTAssertEqual(coordinate?.latitude ?? 0, 41.01, accuracy: 0.0001)
        XCTAssertEqual(coordinate?.longitude ?? 0, 28.97, accuracy: 0.0001)
    }

    func testParseSemicolonSeparated() {
        let coordinate = CoordinateParsing.parse("41.0082;28.9784")
        XCTAssertEqual(coordinate?.latitude ?? 0, 41.0082, accuracy: 0.0001)
        XCTAssertEqual(coordinate?.longitude ?? 0, 28.9784, accuracy: 0.0001)
    }

    func testParseWhitespaceSeparated() {
        let coordinate = CoordinateParsing.parse("38.4192  27.1287")
        XCTAssertEqual(coordinate?.latitude ?? 0, 38.4192, accuracy: 0.0001)
        XCTAssertEqual(coordinate?.longitude ?? 0, 27.1287, accuracy: 0.0001)
    }

    func testParseRejectsOutOfRange() {
        XCTAssertNil(CoordinateParsing.parse("91.0, 28.0"))
        XCTAssertNil(CoordinateParsing.parse("41.0, 181.0"))
        XCTAssertNil(CoordinateParsing.parse("not a coordinate"))
        XCTAssertNil(CoordinateParsing.parse(""))
        XCTAssertNil(CoordinateParsing.parse("41.0"))
    }

    func testFormatRoundTripShape() {
        let coordinate = CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784)
        let formatted = CoordinateParsing.format(coordinate)
        let parsed = CoordinateParsing.parse(formatted)
        XCTAssertEqual(parsed?.latitude ?? 0, 41.0082, accuracy: 0.0001)
        XCTAssertEqual(parsed?.longitude ?? 0, 28.9784, accuracy: 0.0001)
    }
}
