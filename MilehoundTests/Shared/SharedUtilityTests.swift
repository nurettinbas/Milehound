import CoreLocation
import XCTest
@testable import Milehound

final class SharedUtilityTests: XCTestCase {
    func testFormatDurationOmitsHoursWhenShort() {
        XCTAssertEqual(DateFormatters.formatDuration(125), "2:05")
    }

    func testFormatDurationIncludesHoursWhenNeeded() {
        XCTAssertEqual(DateFormatters.formatDuration(3661), "1:01:01")
    }

    func testFormatManeuverDistanceStaysInMetresUntilAKilometre() {
        XCTAssertEqual(DateFormatters.formatManeuverDistance(0), meters(0))
        XCTAssertEqual(DateFormatters.formatManeuverDistance(80), meters(80))
        XCTAssertEqual(DateFormatters.formatManeuverDistance(999), meters(999))
        XCTAssertEqual(DateFormatters.formatManeuverDistance(1_000), DateFormatters.formatDistance(1_000))
        XCTAssertEqual(DateFormatters.formatManeuverDistance(12_400), DateFormatters.formatDistance(12_400))
        XCTAssertFalse(DateFormatters.formatManeuverDistance(80).isEmpty)
        XCTAssertNotEqual(DateFormatters.formatManeuverDistance(80), DateFormatters.formatManeuverDistance(1_500))
    }

    private func meters(_ value: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = DateFormatters.currentLocale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: value, unit: UnitLength.meters))
    }

    func testFormatCoordinateUsesFourDecimalPlaces() {
        let text = DateFormatters.formatCoordinate(
            CLLocationCoordinate2D(latitude: 41.00824, longitude: 28.97841)
        )
        XCTAssertTrue(text.contains("41.0082"))
        XCTAssertTrue(text.contains("28.9784"))
    }

    func testRecordingControlBridgeSharedDefaultsAccessible() {
        let defaults = RecordingControlBridge.sharedDefaults()
        XCTAssertNotNil(defaults)
        XCTAssertEqual(RecordingControlBridge.appGroupSuiteName, "group.com.milehound.app")
    }
}
